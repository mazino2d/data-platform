"""
Fake sim-split data for the dev warehouse (dataplatform-as-se1-dev), so the
dashboard has something to draw before the dev app has real users.

Every ID starts with "fake-", so fake rows are easy to tell apart from what
the dev app and its Firestore send, and to delete:
    DELETE FROM simsplit_raw.<table> WHERE STARTS_WITH(<id column>, 'fake-')

The data is a deterministic function of the day: every run rebuilds the same
world for the last SIMSPLIT_FAKE_DAYS days (default 90), so runs are
idempotent and each new day adds that day's rows.

- Firestore-shaped tables (users, groups, members, expenses, settlements,
  activity): this dlt source, merged on the document path into the same
  dataset as the real copy (dlt/pipeline.py simsplit). The real users load
  replaces its table, so this must run after it.
- Telemetry tables (usage_events, error_reports): load_telemetry(), which
  appends whole days that hold no fake rows yet. They are Terraform-managed
  tables, so they go through plain BigQuery load jobs: dlt would add its own
  columns to them.

pipeline.py refuses to run this against any project not ending in "-dev".
"""

import hashlib
import os
import random
from datetime import date, datetime, time, timedelta, timezone

import dlt
from faker import Faker
from google.cloud import bigquery

from sources.simsplit import AUDIT, _columns

SEED = 7
DAYS = int(os.getenv("SIMSPLIT_FAKE_DAYS", "90"))
TODAY = datetime.now(timezone.utc).date()
START = TODAY - timedelta(days=DAYS - 1)

CURRENCIES = ["VND", "VND", "VND", "USD", "EUR"]
CATEGORIES = ["food", "transport", "lodging", "shopping", "entertainment", "other"]
LANGUAGES = ["vi", "vi", "en"]
PLATFORMS = ["android", "android", "android", "web"]
GROUP_EMOJIS = ["🏖️", "🍜", "🏠", "🎉", "✈️", "⚽"]

# One release every two weeks, counted back from today.
RELEASES = [TODAY - timedelta(days=14 * i) for i in range(DAYS // 14 + 1)][::-1]

SCREENS = [
    "/", "/groups/:groupId", "/groups/:groupId/expenses/add", "/groups/:groupId/expenses/:expenseId",
    "/groups/:groupId/debts", "/groups/:groupId/activity", "/groups/form", "/settings",
]
TAPS = [
    "tap_open_group", "tap_add_expense", "tap_save_expense", "tap_pick_payer", "tap_toggle_participant",
    "tap_pick_category", "tap_settle_debt", "tap_save_settlement", "tap_share_group", "tap_open_settings",
]
FORMS = [("form_expense_submitted", 0.8), ("form_expense_abandoned", 0.2), ("form_group_submitted", 0.7),
         ("form_group_abandoned", 0.3), ("form_settlement_submitted", 0.9)]
OPS = [("op_add_expense", 450), ("op_edit_expense", 380), ("op_create_group", 600),
       ("op_add_member", 300), ("op_add_settlement", 420), ("op_sign_in_with_google", 1800)]
ERRORS = [
    ("FirebaseException", "permission-denied on groups/{id}", 5),
    ("shown:SocketException", "Failed host lookup", 4),
    ("TimeoutException", "Future not completed after 0:00:10", 3),
    ("shown:FormatException", "Invalid amount", 2),
    ("StateError", "Bad state: No element", 1),
]


def _rng(*key):
    digest = hashlib.sha256(repr((SEED, *key)).encode()).digest()
    return random.Random(int.from_bytes(digest[:8], "big"))


def _id(kind, *key):
    return f"fake-{kind}-" + hashlib.sha256(repr(key).encode()).hexdigest()[:12]


def _at(day, rng, start_hour=7, end_hour=23):
    seconds = rng.randint(start_hour * 3600, end_hour * 3600 - 1)
    return datetime.combine(day, time(), tzinfo=timezone.utc) + timedelta(seconds=seconds)


def _ms(ts):
    return int(ts.timestamp() * 1000)


def _days():
    return [START + timedelta(days=i) for i in range(DAYS)]


def _version(day):
    released = [r for r in RELEASES if r <= day]
    return (released[-1] if released else RELEASES[0]).strftime("%Y.%-m.%-d")


# ── The world: who signed up when, and who is active on a day ──────────────

def _signups(day):
    """Accounts created on a day: slow growth, more at weekends."""
    rng = _rng("signups", day)
    age = (day - START).days
    base = 1 + age / 30 + (1.5 if day.weekday() >= 5 else 0)
    return [
        {"uid": _id("u", day, i), "created_at": _at(day, rng), "rng": _rng("user", day, i)}
        for i in range(max(0, round(rng.gauss(base, 1))))
    ]


def _users():
    return [u for day in _days() for u in _signups(day)]


def _active(user, day):
    """Retention decays with account age; weekends are busier."""
    age = (day - user["created_at"].date()).days
    if age < 0:
        return False
    p = 0.9 if age == 0 else 0.15 + 0.45 * 0.93 ** age
    p *= 1.2 if day.weekday() >= 5 else 1
    return _rng("active", user["uid"], day).random() < p


def _world():
    """Groups with members, expenses, settlements and activity, built from the users."""
    users = _users()
    fake = Faker()
    fake.seed_instance(SEED)
    names = {u["uid"]: fake.name() for u in users}
    groups = []
    for owner in users:
        rng = owner["rng"]
        if rng.random() > 0.55:
            continue
        created = owner["created_at"] + timedelta(minutes=rng.randint(1, 600))
        if created.date() > TODAY:
            continue
        gid = _id("g", owner["uid"])
        # Friends who join later, from accounts that exist by then.
        joined = [u for u in users if u is not owner and u["created_at"] <= created + timedelta(days=3)]
        friends = rng.sample(joined, k=min(len(joined), rng.randint(0, 3)))
        groups.append({
            "id": gid, "owner": owner, "created": created, "rng": _rng("group", gid),
            "name": rng.choice(["Trip to ", "Dinner with ", "Flat ", "Team "]) + fake.city(),
            "currency": rng.choice(CURRENCIES), "friends": friends, "names": names,
        })
    return users, names, groups


@dlt.source(name="simsplit_fake")
def simsplit_fake():
    users, names, groups = _world()

    def audit(uid, created, updated, deleted=False):
        return {"created_by": uid, "updated_by": uid, "deleted": deleted,
                "created_at": _ms(created), "updated_at": updated}

    @dlt.resource(
        name="users", write_disposition="merge", primary_key="path",
        columns=_columns(
            display_name="text", email="text", created_at="timestamp",
            consent__agreed_at="timestamp", consent__policy_version="text",
        ),
    )
    def users_():
        for u in users:
            yield {
                "path": f"users/{u['uid']}", "doc_id": u["uid"], "display_name": names[u["uid"]],
                "email": f"{u['uid']}@example.com", "created_at": u["created_at"],
                "consent": {"agreed_at": u["created_at"], "policy_version": "2026-10-24"},
            }

    group_rows, member_rows, expense_rows, settlement_rows, activity_rows = [], [], [], [], []
    for g in groups:
        rng, owner, created = g["rng"], g["owner"]["uid"], g["created"]
        base = f"groups/{g['id']}"
        accounts = [owner] + [f["uid"] for f in g["friends"]]
        group_rows.append({
            "path": base, "doc_id": g["id"], "name": g["name"], "emoji": rng.choice(GROUP_EMOJIS),
            "color_value": rng.randint(0, 2**31), "currency_code": g["currency"], "is_archived": False,
            "owner_uid": owner, "member_uids": accounts, **audit(owner, created, created),
        })

        def activity(actor, action, entity_type, entity_id, at):
            aid = _id("a", g["id"], action, entity_id)
            activity_rows.append({
                "path": f"{base}/activity/{aid}", "doc_id": aid, "group_id": g["id"], "actor_uid": actor,
                "action": action, "entity_type": entity_type, "entity_id": entity_id,
                "client_time": _ms(at), "synced_at": at, "before": None, "after": None,
            })

        activity(owner, "create", "group", g["id"], created)
        members = []
        for i, uid in enumerate(accounts + [None] * rng.randint(0, 2)):
            mid = _id("m", g["id"], i)
            joined = created if uid in (owner, None) else created + timedelta(hours=rng.randint(1, 72))
            if joined.date() > TODAY:
                continue
            members.append(mid)
            member_rows.append({
                "path": f"{base}/members/{mid}", "doc_id": mid, "group_id": g["id"],
                "name": g["names"][uid] if uid else f"Guest {i}", "emoji": None,
                "avatar_color_value": rng.randint(0, 2**31), "linked_uid": uid, **audit(owner, joined, joined),
            })
            if uid and uid != owner:
                activity(uid, "join", "member", mid, joined)

        # Expenses until the group goes quiet; the busiest in its first weeks.
        life = rng.randint(3, 60)
        day = created.date()
        while day <= min(TODAY, created.date() + timedelta(days=life)):
            for n in range(rng.choice([0, 0, 0, 1, 1, 2, 3])):
                at = _at(day, rng)
                if at < created:
                    continue
                eid = _id("e", g["id"], day, n)
                payer = rng.choice(members)
                amount = rng.randint(20, 800) * (1000 if g["currency"] == "VND" else 100)
                share = amount // len(members)
                splits = [
                    {"id": _id("s", eid, m), "memberId": m, "value": 1,
                     "amountCents": share + (amount - share * len(members) if m == members[0] else 0)}
                    for m in members
                ]
                author = rng.choice(accounts)
                deleted = rng.random() < 0.03
                expense_rows.append({
                    "path": f"{base}/expenses/{eid}", "doc_id": eid, "group_id": g["id"],
                    "title": rng.choice(["Lunch", "Taxi", "Hotel", "Groceries", "Coffee", "Tickets"]),
                    "amount_cents": amount, "currency_code": g["currency"], "paid_by_member_id": payer,
                    "split_type": "equal", "category": rng.choice(CATEGORIES), "note": None,
                    "expense_date": _ms(at), "edited_at": None, "splits": splits,
                    **audit(author, at, at, deleted),
                })
                activity(author, "create", "expense", eid, at)
            day += timedelta(days=1)

        for n in range(rng.randint(0, 2)):
            at = created + timedelta(days=rng.randint(1, life + 1), hours=rng.randint(0, 12))
            if at.date() > TODAY or len(members) < 2:
                continue
            sid = _id("t", g["id"], n)
            src, dst = rng.sample(members, 2)
            settlement_rows.append({
                "path": f"{base}/settlements/{sid}", "doc_id": sid, "group_id": g["id"],
                "from_member_id": src, "to_member_id": dst, "amount_cents": rng.randint(50, 500) * 1000,
                "currency_code": g["currency"], "note": None, "settled_at": _ms(at), **audit(owner, at, at),
            })
            activity(owner, "create", "settlement", sid, at)

    # Positional-only: "name" is also a column.
    def resource(table, rows, /, **types):
        return dlt.resource(rows, name=table, write_disposition="merge", primary_key="path",
                            columns=_columns(**types))

    activity_ = dlt.resource(
        activity_rows, name="activity", write_disposition="merge", primary_key="path",
        columns={
            **_columns(actor_uid="text", action="text", entity_type="text", entity_id="text",
                       client_time="bigint", group_id="text", synced_at="timestamp"),
            "before": {"data_type": "json", "nullable": True},
            "after": {"data_type": "json", "nullable": True},
        },
    )
    return (
        users_,
        resource("groups", group_rows, name="text", emoji="text", color_value="bigint", currency_code="text",
                 is_archived="bool", owner_uid="text", updated_at="timestamp", member_uids="json", **AUDIT),
        resource("members", member_rows, name="text", emoji="text", avatar_color_value="bigint",
                 linked_uid="text", group_id="text", updated_at="timestamp", **AUDIT),
        resource("expenses", expense_rows, title="text", amount_cents="bigint", currency_code="text",
                 paid_by_member_id="text", split_type="text", category="text", note="text",
                 expense_date="bigint", edited_at="bigint", group_id="text", updated_at="timestamp",
                 splits="json", **AUDIT),
        resource("settlements", settlement_rows, from_member_id="text", to_member_id="text",
                 amount_cents="bigint", currency_code="text", note="text", settled_at="bigint",
                 group_id="text", updated_at="timestamp", **AUDIT),
        activity_,
    )


# ── Telemetry ──────────────────────────────────────────────────────────────

def _sessions(user, day):
    rng = _rng("sessions", user["uid"], day)
    platform = PLATFORMS[int(user["uid"][-1], 16) % len(PLATFORMS)]
    language = LANGUAGES[int(user["uid"][-2], 16) % len(LANGUAGES)]
    for s in range(rng.choice([1, 1, 2, 3])):
        yield {
            "id": _id("sess", user["uid"], day, s), "at": _at(day, rng), "rng": _rng("session", user["uid"], day, s),
            "platform": platform, "language": language, "version": _version(day),
        }


def _events(user, session):
    rng, at = session["rng"], session["at"]
    rows = []

    def add(kind, name, screen=None, result=None, duration_ms=None):
        nonlocal at
        at += timedelta(seconds=rng.randint(1, 40))
        rows.append({
            "received_at": (at + timedelta(seconds=rng.randint(0, 90))).isoformat(),
            "uid": user["uid"], "session_id": session["id"], "client_time": at.isoformat(),
            "kind": kind, "name": name, "screen": screen, "result": result, "duration_ms": duration_ms,
            "platform": session["platform"], "app_version": session["version"],
            "language": session["language"], "online": rng.random() > 0.05,
        })

    for _ in range(rng.randint(2, 8)):
        screen = rng.choice(SCREENS)
        add("screen", screen)
        for _ in range(rng.randint(0, 4)):
            add("tap", rng.choice(TAPS), screen=screen)
        if rng.random() < 0.4:
            name, p = rng.choice(FORMS)
            add("form", name if rng.random() < p else name.replace("submitted", "abandoned"), screen=screen)
        if rng.random() < 0.15:
            add("dialog", "dialog_opened", screen=screen)
            add("dialog", "dialog_closed", screen=screen)
        if rng.random() < 0.05:
            add("gesture", "gesture_swipe_delete_expense", screen=screen)
        if rng.random() < 0.5:
            name, median = rng.choice(OPS)
            failed = rng.random() < 0.04
            add("op", name, screen=screen, result="error" if failed else "success",
                duration_ms=int(rng.lognormvariate(0, 0.5) * median))
    return rows


def _error_reports(user, session):
    rng = _rng("errors", session["id"])
    if rng.random() > 0.06:
        return []
    error_type, message, _ = rng.choices(ERRORS, weights=[w for *_, w in ERRORS])[0]
    at = session["at"] + timedelta(minutes=rng.randint(0, 20))
    return [{
        "received_at": at.isoformat(), "report_id": _id("r", user["uid"]), "session_id": session["id"],
        "client_time": at.isoformat(), "platform": session["platform"],
        "os": "Android 15" if session["platform"] == "android" else "Chrome 141",
        "app_version": session["version"], "language": session["language"], "signed_in": True,
        "online": rng.random() > 0.3, "error_type": error_type, "message": message,
        "stack": f"#0 {error_type.removeprefix('shown:')} (package:simsplit/fake.dart:1)",
        "count": rng.choice([1, 1, 1, 2, 5]),
        "breadcrumbs": [{"time": at.isoformat(), "kind": "screen", "name": rng.choice(SCREENS)}],
    }]


def load_telemetry(project_id, dataset="simsplit_raw"):
    """Appends fake usage events and error reports for each day in the window
    that has none yet. Telemetry always lands in simsplit_raw, which every dbt
    target reads (dbt/models/simsplit/staging/_sources.yml)."""
    client = bigquery.Client(project=project_id)
    users = _users()
    for table, id_column, build in (
        ("usage_events", "uid", _events),
        ("error_reports", "report_id", _error_reports),
    ):
        ref = f"{project_id}.{dataset}.{table}"
        query = (
            f"SELECT DISTINCT DATE(received_at) AS day FROM `{ref}` "
            f"WHERE STARTS_WITH({id_column}, 'fake-') AND DATE(received_at) >= @start"
        )
        params = [bigquery.ScalarQueryParameter("start", "DATE", START.isoformat())]
        done = {r.day for r in client.query(query, job_config=bigquery.QueryJobConfig(query_parameters=params))}
        rows = [
            row
            for day in _days() if day not in done
            for user in users if _active(user, day)
            for session in _sessions(user, day)
            for row in build(user, session)
        ]
        if not rows:
            print(f"{ref}: nothing to add")
            continue
        schema = client.get_table(ref).schema
        job = client.load_table_from_json(
            rows, ref,
            job_config=bigquery.LoadJobConfig(schema=schema, write_disposition="WRITE_APPEND"),
        )
        job.result()
        print(f"{ref}: added {len(rows)} fake rows for {len({r['received_at'][:10] for r in rows})} days")
