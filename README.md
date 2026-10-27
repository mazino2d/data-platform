# data-platform

The data pipeline for mazino2d projects: every project's data is loaded into one BigQuery
warehouse, modelled with dbt and scheduled from YAML DAG configs. The first project is the
Jaffle Shop demo, a fictional e-commerce store; SimSplit follows.

## Stack

| Layer | Tool | Role |
|---|---|---|
| Ingestion | [dlt](https://dlthub.com) | Load raw data from a backend into BigQuery |
| Warehouse | [BigQuery](https://cloud.google.com/bigquery) | Projects `dataplatform-as-se1-dev` and `dataplatform-as-se1-prd`, location `asia-southeast1` |
| Transformation | [dbt](https://www.getdbt.com) | Build and test data models in layers |
| Orchestration | YAML DAGs → GitHub Actions | `dag/dags/` rendered into scheduled workflows (any orchestrator can read the same YAML) |

The GCP projects, the Workload Identity Federation for this repo's workflows and the
`dev` and `prd` GitHub Environments are managed in
[everything-as-code](https://github.com/mazino2d/everything-as-code)
(`terraform/gcp/dataplatform-as-se1-{dev,prd}`, `terraform/github`).

---

## Environments and release

| | dev | prd |
|---|---|---|
| BigQuery project | `dataplatform-as-se1-dev` | `dataplatform-as-se1-prd` |
| sim-split Firestore | `simsplit-as-se1-dev` | `simsplit-as-se1-prd` |
| sim-split telemetry | dev builds, via the dev endpoint | released builds |
| Fake data (`fake-` IDs) | `simsplit_fake_ingestion`, daily | never: `dlt/pipeline.py` refuses |
| Code it runs | `main` | the latest `vYYYY.M.D` tag |
| Dashboard | `data-platform-dashboard-dev.pages.dev` | `data-platform-dashboard.pages.dev` |

Each is a GitHub Environment with the same variable names (`GCP_PROJECT_ID`,
`GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT`, `SIMSPLIT_FIREBASE_PROJECT`,
`DASHBOARD_PROJECT`), and every job checks that they name its own projects.

```
feature branch ──PR──► CI (dev env): dlt + dbt build into ci_<run>_* in the dev project, dropped after
      │
      ▼ squash-merge
main ──push──► DAG workflows run in dev ──► dev dashboard
      │        check the models and charts on dev and fake data
      ▼ git tag vYYYY.M.D && git push origin vYYYY.M.D
tag  ──push──► DAG workflows run in prd from the tag ──► prd dashboard
```

The daily schedule runs both: dev from `main`, prd from the latest release tag. So a
merge never reaches prd until it is tagged. To roll back prd, delete the bad tag, or tag
the last good commit again with a newer version, then run the DAG workflow with
`environment: prd`.

Fake data rebuilds the same world from a fixed start date (`START` in
`dlt/sources/simsplit_fake.py`) up to yesterday on every run, so runs are idempotent and
each day only adds that day's rows. To clear it, delete the rows whose ID starts with
`fake-` from `simsplit_raw`.

---

## Datasets

Each project and layer gets its own dataset, named by `dbt/macros/generate_schema_name.sql`:

| Target | Dataset | Example |
|---|---|---|
| `prod` (scheduled DAGs, in each environment's project) | `<project>_<layer>` | `jaffle_shop_staging` |
| `ci` (pull requests) | `ci_<run>_<project>_<layer>`, dropped after the run | `ci_123_1_jaffle_shop_staging` |
| `dev` (local) | `dev_<user>_<project>_<layer>` | `dev_alice_jaffle_shop_staging` |

dlt writes raw data to `<project>_raw` with the same prefixes (`dlt/pipeline.py`).

---

## Jaffle Shop

```
Backend (simulated by Faker)
    │
    ▼  dlt — daily sync
jaffle_shop_raw
    │   ├── customers     (replace — SCD source)
    │   ├── orders        (replace — SCD source)
    │   ├── products      (replace — SCD source)
    │   ├── payments      (append — event log)
    │   └── order_items   (append — event log)
    │
    ▼  dbt snapshot — SCD Type 2
jaffle_shop_snapshots
    │   ├── customers_snapshot  (tracks customer status/profile changes)
    │   ├── orders_snapshot     (tracks order status transitions)
    │   └── products_snapshot   (tracks price/catalog changes)
    │
    ▼  dbt build
jaffle_shop_staging      → clean 1:1 views from raw + snapshots + seeds
jaffle_shop_intermediate → business logic joins + surrogate key maps
jaffle_shop_marts        → dim_customers, fct_orders
jaffle_shop_features     → customer_features (RFM), order_features (AOV, return risk)
```

### Why two types of source tables?

| Type | Tables | Backend behavior | dbt approach |
|---|---|---|---|
| **SCD** (slowly changing) | customers, orders, products | Record updated in-place | `dbt snapshot` → captures history |
| **Log** (append-only) | payments, order_items | New row per event | `incremental` model → process new rows only |

### Ingestion — `dlt/`

`dlt/sources/jaffle_shop.py` defines five resources using Faker to simulate a backend
database. `dlt/pipeline.py <source>` loads a source into its raw dataset.

```bash
make ingest                  # SOURCE=jaffle_shop by default
```

### Snapshots — `dbt/snapshots/jaffle_shop/`

SCD tables change in-place on the backend (e.g. an order's status moves from `placed` →
`shipped` → `completed`). dbt snapshots use the `timestamp` strategy on `updated_at` to
capture each version with `dbt_valid_from` / `dbt_valid_to` columns.

```bash
make snapshot
```

### Transformations — `dbt/models/jaffle_shop/`

```
staging/          Clean and rename raw columns. Incremental for log tables.
                  Includes stg_customer_id_mapping from seed data.
intermediate/     Business logic joins + surrogate key maps for SCD entities.
marts/
  core/           Reporting tables: dim_customers, fct_orders
  features/       ML feature tables: customer_features, order_features
```

Every model carries the project tag (`jaffle_shop`) and its layer tag (`staging`,
`intermediate`, `core`, `features`); the DAG configs select on both.

`dbt/macros/` provides macros that precompute surrogate key mappings from snapshots, and an
enrichment macro to join them onto fact tables (`dim_customer_sk_map`, `dim_order_sk_map`,
`dim_product_sk_map`).

```bash
make build        # full build + tests (dev datasets)
make freshness    # check source SLA (warn >12h, error >24h)
make docs         # generate + serve lineage graph
```

### ML features

**`customer_features`** — one row per customer (RFM model):
- `days_since_last_order` — recency
- `order_frequency` — frequency (completed orders)
- `lifetime_value` — monetary
- `return_rate`, `avg_order_value`, `avg_days_between_orders`

**`order_features`** — one row per order:
- `payment_failure_rate`, `item_count`, `unique_products`
- `customer_ltv_at_order`, `customer_return_rate` — customer context at order time

Downstream consumers are documented in `dbt/models/jaffle_shop/marts/features/_exposures.yml`.

---

## Orchestration — `dag/`

One YAML file per task in `dag/dags/<project>/`:

```yaml
name: jaffle_shop_staging
description: "Clean and normalize raw source data into staging views."
dbt_command: build                       # or `command: <shell command>`
dbt_selector: "+tag:staging,tag:jaffle_shop"
dbt_exclude: "resource_type:snapshot"    # optional
trigger:
  type: upstream                         # or `cron` with `cron_schedule` (UTC)
  depends_on: jaffle_shop_snapshots
retry:
  max_retries: 2
  retry_delay_minutes: 5
```

The configs say nothing about the orchestrator:

- `dag/config.py` loads and validates them and groups each cron task with everything
  downstream of it into a pipeline.
- `dag/run.py <task>` runs one task with its retries.
- `dag/render.py` writes one GitHub Actions workflow per pipeline,
  `.github/workflows/dag-<root task>.yml`, where each task is a job calling
  `dag-task.yml` and upstream triggers become `needs`. Each task is rendered once per
  environment it runs in (`environments:`, default `[dev, prd]`); a `plan` job picks
  the environments and the ref (see [Environments and release](#environments-and-release)).
  `depends_on` can list several tasks; one missing from an environment is skipped over.

```bash
make dags                    # re-render the workflows after editing dag/dags/
python -m dag.render --check # what CI runs
```

Moving to another orchestrator means writing another renderer; the YAML stays.

Jaffle Shop runs daily at 06:00 UTC:
`raw_ingestion → snapshots → staging → intermediate → core → features`.

---

## Project Structure

```
data-platform/
├── Makefile
├── pyproject.toml
├── mkdocs.yml                      # blog + dbt docs site
├── dlt/
│   ├── sources/jaffle_shop.py      # Faker-based source (5 tables)
│   └── pipeline.py                 # python dlt/pipeline.py <source>
├── dbt/
│   ├── dbt_project.yml             # per-project datasets, tags, materializations
│   ├── profiles.yml                # BigQuery: dev / ci / prod
│   ├── macros/                     # generate_schema_name, surrogate key macros
│   ├── seeds/jaffle_shop/
│   ├── snapshots/jaffle_shop/
│   └── models/jaffle_shop/         # staging, intermediate, marts/{core,features}
├── dag/
│   ├── dags/jaffle_shop/           # one YAML per task
│   ├── config.py · run.py · render.py
├── scripts/drop_datasets.py        # CI cleanup of ci_* datasets
└── .github/workflows/
    ├── ci.yml · docs.yml
    ├── dag-task.yml                # runs one task (reusable)
    └── dag-*.yml                   # generated, one per pipeline
```

---

## Quickstart

### Prerequisites

- Python 3.11+
- `gcloud` with access to the `dataplatform-as-se1-dev` project (local runs belong in dev)

### Setup

```bash
make install
cp .env.example .env
gcloud auth application-default login
cd dbt && dbt deps --profiles-dir . && cd ..
pre-commit install
```

### Run the pipeline into your dev datasets

```bash
make pipeline     # ingest → snapshot → build
make freshness
make docs
python scripts/drop_datasets.py dev_$USER_   # clean up when done
```

---

## Code Quality

```bash
make lint         # SQLFluff: lint all SQL models
make fix          # SQLFluff: auto-fix style issues
```

SQLFluff config: `.sqlfluff` (dialect: BigQuery, templater: jinja with dbt builtins, so no
warehouse connection is needed).

---

## Documentation

```bash
make blog         # serve MkDocs documentation site locally
```
