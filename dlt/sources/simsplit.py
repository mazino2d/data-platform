"""
sim-split dlt source: copies the app's Firestore data into the warehouse
(sim-split R-4). The app's error reports and usage events do not come through
here: its telemetry endpoint writes them straight to simsplit_raw.

Tables:
- users (write_disposition='replace'): one row per account, with the privacy
  policy agreement. Replaced on every run, so a deleted account leaves the
  warehouse with the next load (R-4 AC11); never snapshotted.
- groups, members, expenses, settlements (merge on the document path):
  incremental on the server's updatedAt. Soft deletes arrive as deleted=true;
  hard deletes (a group removed with its last member's account) are not
  propagated — the facts stay.
- activity (merge): the audit history, incremental on syncedAt.

Subcollections are read across all groups with collection-group queries,
which need the COLLECTION_GROUP indexes in sim-split's firestore.indexes.json.
Invite tokens are never copied.

Credentials come from Application Default Credentials (the CI and DAG service
account has datastore.viewer on the project); the project from
SIMSPLIT_FIREBASE_PROJECT.
"""

import os
from datetime import datetime, timezone

import dlt
from google.cloud import firestore
from google.cloud.firestore_v1.base_query import FieldFilter

EPOCH = datetime(2020, 1, 1, tzinfo=timezone.utc)

# Fields the warehouse must never hold.
SECRET_FIELDS = {"inviteToken", "joinToken"}


def _timestamps(*names):
    return {n: {"data_type": "timestamp"} for n in names}


def _columns(**types):
    """Explicit column types, so sparse fields (all null so far) still exist.
    Lists (expense splits, member uids) stay JSON columns rather than child
    tables, so every table exists from the first run; dbt unnests them.
    The key and IDs every row carries are typed too, so an empty table can be
    created before any document exists."""
    columns = {name: {"data_type": t, "nullable": True} for name, t in types.items()}
    columns["path"] = {"data_type": "text", "nullable": False, "primary_key": True}
    columns["doc_id"] = {"data_type": "text", "nullable": False}
    return columns


AUDIT = dict(created_by="text", updated_by="text", deleted="bool", created_at="bigint")


def _client():
    return firestore.Client(project=os.getenv("SIMSPLIT_FIREBASE_PROJECT", "simsplit-as-se1-prd"))


def _row(doc):
    row = {k: v for k, v in doc.to_dict().items() if k not in SECRET_FIELDS}
    row["path"] = doc.reference.path
    row["doc_id"] = doc.id
    group = doc.reference.parent.parent
    if group is not None:
        row["group_id"] = group.id
    return row


# Every resource first yields materialize_table_schema(), so its table exists
# (with the hinted columns) even before Firestore holds any such document.
def _changed(query, field, cursor):
    return query.where(filter=FieldFilter(field, ">", cursor.last_value)).order_by(field).stream()


@dlt.source(name="simsplit")
def simsplit():
    client = _client()

    @dlt.resource(
        name="users",
        write_disposition="replace",
        primary_key="path",
        columns=_columns(
            display_name="text", email="text", created_at="timestamp",
            consent__agreed_at="timestamp", consent__policy_version="text",
        ),
    )
    def users():
        yield dlt.mark.materialize_table_schema()
        for doc in client.collection("users").stream():
            yield _row(doc)

    @dlt.resource(
        name="groups",
        write_disposition="merge",
        primary_key="path",
        columns=_columns(
            name="text", emoji="text", color_value="bigint", currency_code="text",
            is_archived="bool", owner_uid="text", updated_at="timestamp",
            member_uids="json", **AUDIT,
        ),
    )
    def groups(updated_at=dlt.sources.incremental("updatedAt", initial_value=EPOCH)):
        yield dlt.mark.materialize_table_schema()
        yield from (_row(d) for d in _changed(client.collection("groups"), "updatedAt", updated_at))

    @dlt.resource(
        name="members",
        write_disposition="merge",
        primary_key="path",
        columns=_columns(
            name="text", emoji="text", avatar_color_value="bigint", linked_uid="text",
            group_id="text", updated_at="timestamp", **AUDIT,
        ),
    )
    def members(updated_at=dlt.sources.incremental("updatedAt", initial_value=EPOCH)):
        yield dlt.mark.materialize_table_schema()
        yield from (_row(d) for d in _changed(client.collection_group("members"), "updatedAt", updated_at))

    @dlt.resource(
        name="expenses",
        write_disposition="merge",
        primary_key="path",
        columns=_columns(
            title="text", amount_cents="bigint", currency_code="text", paid_by_member_id="text",
            split_type="text", category="text", note="text", expense_date="bigint",
            edited_at="bigint", group_id="text", updated_at="timestamp",
            splits="json", **AUDIT,
        ),
    )
    def expenses(updated_at=dlt.sources.incremental("updatedAt", initial_value=EPOCH)):
        yield dlt.mark.materialize_table_schema()
        yield from (_row(d) for d in _changed(client.collection_group("expenses"), "updatedAt", updated_at))

    @dlt.resource(
        name="settlements",
        write_disposition="merge",
        primary_key="path",
        columns=_columns(
            from_member_id="text", to_member_id="text", amount_cents="bigint", currency_code="text",
            note="text", settled_at="bigint", group_id="text", updated_at="timestamp", **AUDIT,
        ),
    )
    def settlements(updated_at=dlt.sources.incremental("updatedAt", initial_value=EPOCH)):
        yield dlt.mark.materialize_table_schema()
        yield from (_row(d) for d in _changed(client.collection_group("settlements"), "updatedAt", updated_at))

    @dlt.resource(
        name="activity",
        write_disposition="merge",
        primary_key="path",
        columns={
            **_columns(
                actor_uid="text", action="text", entity_type="text", entity_id="text",
                client_time="bigint", group_id="text", synced_at="timestamp",
            ),
            # Before/after snapshots stay whole, as JSON, instead of one column per field.
            "before": {"data_type": "json", "nullable": True},
            "after": {"data_type": "json", "nullable": True},
        },
    )
    def activity(synced_at=dlt.sources.incremental("syncedAt", initial_value=EPOCH)):
        yield dlt.mark.materialize_table_schema()
        yield from (_row(d) for d in _changed(client.collection_group("activity"), "syncedAt", synced_at))

    return users, groups, members, expenses, settlements, activity
