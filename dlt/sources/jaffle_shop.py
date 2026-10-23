"""
Jaffle Shop dlt source.

Simulates a backend database with daily ingest. Tables are split into two categories:
- SCD tables (customers, orders, products): write_disposition='replace'
  Full table replace each run; dbt snapshot captures history of changes.
- Log tables (payments, order_items): write_disposition='append'
  Immutable event log; only new records are emitted each run.

State (stored in dlt pipeline state):
  source_state["customer_count"]           — total customers after last run
  source_state["product_count"]            — total products after last run
  source_state["order_count"]              — total orders after last run
  payments resource_state["last_order_id"] — last order_id with payments emitted
  order_items resource_state["last_order_id"] — last order_id with items emitted

First run: generates ~1 year of historical data.
Subsequent runs: adds ≤ NEW_PER_RUN new records per table; mutates ~MUTATION_RATE of existing.
"""

import hashlib
import random
import uuid
from datetime import datetime, timedelta

import dlt
from faker import Faker

# ── Base counts (first run) ────────────────────────────────────────────────
CUSTOMER_COUNT = 200
PRODUCT_COUNT = 30
ORDER_COUNT = 800

NEW_PER_RUN = 20        # max new records added per table per run
MUTATION_RATE = 0.075   # 7.5% of existing records mutated each run

SEED = 42

# ── Time anchors (fixed for the duration of this pipeline run) ─────────────
_NOW = datetime.now()
_ONE_YEAR_AGO = _NOW - timedelta(days=365)
_SIX_MONTHS_AGO = _NOW - timedelta(days=180)
_ONE_MONTH_AGO = _NOW - timedelta(days=30)

# ── Seeded Faker instance ──────────────────────────────────────────────────
# seed_instance ensures the same call sequence produces the same values
# across runs, so existing record names/emails never change.
fake = Faker()
fake.seed_instance(SEED)


# ── Helpers ────────────────────────────────────────────────────────────────

def _rng(offset: int) -> random.Random:
    """Return a deterministic RNG seeded from SEED + offset."""
    return random.Random(SEED + offset)


def _seeded_date(rng: random.Random, start: datetime, end: datetime) -> datetime:
    """Random date from a seeded RNG — produces the same value every run."""
    delta = end - start
    return start + timedelta(seconds=rng.randint(0, int(delta.total_seconds())))


def _rand_date(start: datetime, end: datetime) -> datetime:
    """Random date from the un-seeded module RNG — varies each run."""
    delta = end - start
    return start + timedelta(seconds=random.randint(0, int(delta.total_seconds())))


def _order_placed_at(order_id: int) -> datetime:
    """Stable placed_at for historical orders (id <= ORDER_COUNT)."""
    return _seeded_date(_rng(2000 + order_id), _ONE_YEAR_AGO, _ONE_MONTH_AGO)


def _stable_items(order_id: int) -> list[tuple[int, int, float]]:
    """Return [(product_id, quantity, unit_price), ...] stable per order_id.

    Used by both orders (to compute amount) and order_items (to emit line items),
    guaranteeing that SUM(quantity * unit_price) == orders.amount.
    """
    rng = _rng(3000 + order_id)
    return [
        (rng.randint(1, PRODUCT_COUNT), rng.randint(1, 4), round(rng.uniform(3.0, 25.0), 2))
        for _ in range(rng.randint(1, 5))
    ]


def _timestamp_columns(*names):
    """Column hints so ISO strings load as TIMESTAMP, not STRING."""
    return {n: {"data_type": "timestamp"} for n in names}


# ── SCD resources ──────────────────────────────────────────────────────────

@dlt.resource(name="customers", write_disposition="replace", primary_key="id", columns=_timestamp_columns("created_at", "updated_at"))
def customers():
    """Customer master data — updated in-place on the backend (SCD source)."""
    state = dlt.current.source_state()
    prev_count = state.get("customer_count", 0)
    is_first_run = prev_count == 0

    total = CUSTOMER_COUNT if is_first_run else prev_count + random.randint(1, NEW_PER_RUN)
    state["customer_count"] = total

    statuses = ["active", "churned", "at_risk"]

    for i in range(1, total + 1):
        rng = _rng(i)
        is_new = i > prev_count
        is_changed = (not is_new) and (random.random() < MUTATION_RATE)

        # Stable identity — same across all runs (Faker globally seeded,
        # called in fixed order so customer i always gets the same values).
        name = fake.name()
        email = fake.email()
        country = fake.country_code()
        created_at = _seeded_date(rng, _ONE_YEAR_AGO, _SIX_MONTHS_AGO)

        if is_new:
            # Brand-new customer created today.
            created_at = _NOW
            updated_at = _NOW
            status = random.choices(statuses, weights=[70, 15, 15])[0]
        elif is_changed:
            # Existing customer updated this run.
            updated_at = _NOW
            status = random.choices(statuses, weights=[70, 15, 15])[0]
        else:
            # Unchanged. 50% never changed (created_at == updated_at);
            # 50% changed once somewhere in the past.
            status = rng.choices(statuses, weights=[70, 15, 15])[0]
            if rng.random() < 0.5:
                updated_at = _seeded_date(rng, created_at, _ONE_MONTH_AGO)
            else:
                updated_at = created_at

        yield {
            "id": i,
            "name": name,
            "email": email,
            "country": country,
            "status": status,
            "created_at": created_at.isoformat(),
            "updated_at": updated_at.isoformat(),
        }


@dlt.resource(name="products", write_disposition="replace", primary_key="id", columns=_timestamp_columns("created_at", "updated_at"))
def products():
    """Product catalog — prices and availability can change (SCD source)."""
    state = dlt.current.source_state()
    prev_count = state.get("product_count", 0)
    is_first_run = prev_count == 0

    total = PRODUCT_COUNT if is_first_run else prev_count + random.randint(1, NEW_PER_RUN)
    state["product_count"] = total

    categories = ["Food", "Beverage", "Merchandise"]

    for i in range(1, total + 1):
        rng = _rng(100 + i)  # offset to avoid seed collision with customers
        is_new = i > prev_count
        is_changed = (not is_new) and (random.random() < MUTATION_RATE)

        created_at = _seeded_date(rng, _ONE_YEAR_AGO, _SIX_MONTHS_AGO)

        if is_new:
            created_at = _NOW
            updated_at = _NOW
            price = round(random.uniform(3.0, 25.0), 2)
            is_active = True
        elif is_changed:
            updated_at = _NOW
            price = round(random.uniform(3.0, 25.0), 2)
            is_active = random.random() > 0.1
        else:
            price = round(rng.uniform(3.0, 25.0), 2)
            is_active = rng.random() > 0.1
            if rng.random() < 0.5:
                updated_at = _seeded_date(rng, created_at, _ONE_MONTH_AGO)
            else:
                updated_at = created_at

        yield {
            "id": i,
            "name": fake.bs().title()[:40],
            "category": rng.choice(categories),
            "price": price,
            "is_active": is_active,
            "created_at": created_at.isoformat(),
            "updated_at": updated_at.isoformat(),
        }


@dlt.resource(name="orders", write_disposition="replace", primary_key="id", columns=_timestamp_columns("placed_at", "updated_at"))
def orders():
    """Order records — status transitions over time (SCD source)."""
    state = dlt.current.source_state()
    prev_count = state.get("order_count", 0)
    is_first_run = prev_count == 0

    total = ORDER_COUNT if is_first_run else prev_count + random.randint(1, NEW_PER_RUN)
    state["order_count"] = total

    statuses = ["placed", "shipped", "completed", "returned"]

    for i in range(1, total + 1):
        rng = _rng(200 + i)  # offset to avoid seed collision
        is_new = i > prev_count
        is_changed = (not is_new) and (random.random() < MUTATION_RATE)

        # Stable: customer assignment and line items never change.
        customer_id = rng.randint(1, CUSTOMER_COUNT)
        items = _stable_items(i)
        amount = round(sum(qty * price for _, qty, price in items), 2)

        if is_new:
            # New order just placed.
            placed_at = _NOW
            updated_at = _NOW
            status = "placed"
        else:
            placed_at = _order_placed_at(i)
            if is_changed:
                updated_at = _NOW
                status = random.choices(statuses, weights=[5, 10, 75, 10])[0]
            else:
                status = rng.choices(statuses, weights=[5, 10, 75, 10])[0]
                if rng.random() < 0.5:
                    updated_at = _seeded_date(rng, placed_at, _ONE_MONTH_AGO)
                else:
                    updated_at = placed_at

        yield {
            "id": i,
            "customer_id": customer_id,
            "status": status,
            "amount": amount,
            "placed_at": placed_at.isoformat(),
            "updated_at": updated_at.isoformat(),
        }


# ── Append-only resources ──────────────────────────────────────────────────

@dlt.resource(name="payments", write_disposition="append", primary_key="id", columns=_timestamp_columns("created_at"))
def payments():
    """Payment events — immutable log, append-only.

    Only emits records for order_ids not yet seen (tracked via resource state).
    UUIDs are hash-based so a re-run of the same batch is idempotent.
    """
    res_state = dlt.current.resource_state()
    src_state = dlt.current.source_state()
    last_order_id = res_state.get("last_order_id", 0)
    total_orders = src_state.get("order_count", ORDER_COUNT)

    methods = ["credit_card", "debit_card", "bank_transfer", "gift_card"]
    statuses = ["success", "failed", "refunded"]

    for order_id in range(last_order_id + 1, total_orders + 1):
        # Historical orders use their stable placed_at; new orders use _NOW.
        placed_at = _order_placed_at(order_id) if order_id <= ORDER_COUNT else _NOW
        pay_end = min(placed_at + timedelta(days=3), _NOW)

        for idx in range(random.randint(1, 2)):
            pay_id = uuid.UUID(hashlib.md5(f"pay-{order_id}-{idx}".encode()).hexdigest())
            yield {
                "id": str(pay_id),
                "order_id": order_id,
                "method": random.choice(methods),
                "status": random.choices(statuses, weights=[85, 10, 5])[0],
                "amount": round(random.uniform(5.0, 120.0), 2),
                "created_at": _rand_date(placed_at, pay_end).isoformat(),
            }

    res_state["last_order_id"] = total_orders


@dlt.resource(name="order_items", write_disposition="append", primary_key="id", columns=_timestamp_columns("created_at"))
def order_items():
    """Line items per order — immutable log, append-only.

    Uses _stable_items() so that SUM(quantity * unit_price) == orders.amount.
    Only emits records for order_ids not yet seen (tracked via resource state).
    """
    res_state = dlt.current.resource_state()
    src_state = dlt.current.source_state()
    last_order_id = res_state.get("last_order_id", 0)
    total_orders = src_state.get("order_count", ORDER_COUNT)

    for order_id in range(last_order_id + 1, total_orders + 1):
        placed_at = _order_placed_at(order_id) if order_id <= ORDER_COUNT else _NOW
        item_end = min(placed_at + timedelta(hours=1), _NOW)

        for idx, (product_id, quantity, unit_price) in enumerate(_stable_items(order_id)):
            item_id = uuid.UUID(hashlib.md5(f"item-{order_id}-{idx}".encode()).hexdigest())
            yield {
                "id": str(item_id),
                "order_id": order_id,
                "product_id": product_id,
                "quantity": quantity,
                "unit_price": unit_price,
                "created_at": _rand_date(placed_at, item_end).isoformat(),
            }

    res_state["last_order_id"] = total_orders


@dlt.source
def jaffle_shop():
    """All Jaffle Shop tables as a single dlt source."""
    return [customers(), products(), orders(), payments(), order_items()]
