# CLAUDE.md — Jaffle Shop

## Language

- **Always write code and documentation in English**, regardless of what language the user chats in.

---

## Repo Architecture

This is a demo end-to-end data pipeline using a fictional e-commerce store (Jaffle Shop).

### Stack

| Layer | Tool | Entry point |
|---|---|---|
| Ingestion | dlt | `dlt/pipeline.py`, `dlt/sources/jaffle_shop.py` |
| Warehouse | DuckDB | `jaffle_shop_dev.duckdb` (local, gitignored) |
| Transformation | dbt | `dbt/` |
| Orchestration | Dagster | `dag/definitions.py` |

### dbt model layers

```
dbt/seeds/              Static reference data (e.g. customer_id_mapping.csv)
dbt/snapshots/          SCD Type 2 snapshots for customers, orders, products
dbt/macros/             Surrogate key enrichment macros (scd_surrogate_keys, scd_sk_map,
                        fk_sk_enrich, snapshot_incremental_filter)
dbt/models/
  staging/              1:1 clean views from raw schema + seeds. Incremental for log tables.
  intermediate/         Business logic joins (int_customer_orders, int_order_payments)
                        + surrogate key lookup tables (dim_*_sk_map).
  marts/core/           Reporting tables: dim_customers, fct_orders
  marts/features/       ML feature tables: customer_features, order_features
```

### Source table types

| Type | Tables | Backend behavior | dbt strategy |
|---|---|---|---|
| SCD (slowly changing) | customers, orders, products | Updated in-place | `dbt snapshot` → SCD Type 2 |
| Log (append-only) | payments, order_items | New row per event | `incremental` model |

### Dagster layout

```
dag/
  dags/        YAML configs (one per job) — edit here to change schedules/sensors
  assets/      Dagster asset definitions (ingestion.py wraps dlt)
  loader.py    Reads YAML dags → creates Dagster jobs + schedules at startup
  definitions.py  Dagster entry point
```

Deployment: self-hosted Dagster OSS on the `mazino2d-as-se1-dev` GKE cluster (repo `everything-as-code`,
`kubernetes/clusters/mazino2d-as-se1-dev/apps/dagster/`). The root `Dockerfile` builds the code location image
(`dagster api grpc -m dag`), pushed to `ghcr.io/mazino2d/jaffle-shop` by `.github/workflows/docker-image.yml`.
Keep `dagster*` pins in `pyproject.toml` in lockstep with the Dagster Helm chart version.

Adding or reconfiguring a job: edit/add a YAML file in `dag/dags/` — no Python changes needed.

### Common commands

```bash
make install      # install all Python dependencies
make ingest       # run dlt pipeline (raw schema)
make snapshot     # run dbt snapshots (SCD Type 2)
make build        # dbt build + tests (dev)
make build-prod   # dbt build + tests (prod)
make pipeline     # ingest → snapshot → build in sequence
make freshness    # check source SLA (warn >12h, error >24h)
make docs         # generate + serve dbt lineage graph
make dagster      # start Dagster UI at http://localhost:3000
make blog         # serve MkDocs documentation site
make lint         # SQLFluff lint all SQL models
make fix          # SQLFluff auto-fix SQL style
make sync         # compile requirements.txt from pyproject.toml
```

---

## Code Style Rules

### SQL (enforced by SQLFluff + pre-commit)

Config: `.sqlfluff` (root of repo).

- Dialect: **DuckDB**
- Templater: **dbt**
- Max line length: **120**
- Keywords: **UPPERCASE** (`SELECT`, `FROM`, `WHERE`, `JOIN`, `AND`, `OR`, `CASE`, `WHEN`, `THEN`, `END`, `AS`, …)
- Identifiers: **lowercase** (column names, aliases, CTE names)
- Functions: **UPPERCASE** (`COALESCE`, `DATE_TRUNC`, `ROW_NUMBER`, …)
- Indentation: **4 spaces** (no tabs)
- Rule RF02 (reference qualification) is disabled — unqualified refs are fine

Before committing SQL, run `make lint` or `make fix`.

### Pre-commit hooks (`.pre-commit-config.yaml`)

The following hooks run automatically on `git commit`:
- `trailing-whitespace` — no trailing spaces
- `end-of-file-fixer` — files must end with a newline
- `check-yaml` — valid YAML syntax
- `check-merge-conflict` — no unresolved conflict markers
- `sqlfluff-lint` — SQL style check (DuckDB dialect)

Never skip hooks with `--no-verify`. Fix the underlying issue instead.

### Python

- Python 3.11+
- No type annotations or docstrings unless the surrounding code already uses them
- Follow existing patterns in the file you are editing

### dbt conventions

- New staging models go in `dbt/models/staging/` and must be registered in `_sources.yml` or `_schema.yml`
- New intermediate models go in `dbt/models/intermediate/`
- SCD source tables use `dbt snapshot` — do not query the raw table directly for history; use the snapshot
- Log tables (`payments`, `order_items`) use `incremental` materialization — always include an incremental filter using the `snapshot_incremental_filter` macro
- Use the `fk_sk_enrich` macro to join surrogate keys onto fact tables; do not hardcode joins to snapshot tables
- New seeds go in `dbt/seeds/` with a matching schema entry

### Dagster conventions

- New jobs are defined as YAML files in `dag/dags/` — `loader.py` picks them up automatically
- Do not hardcode job definitions in Python unless they require logic that YAML cannot express
- Assets live in `dag/assets/`

---

## Git & Pull Requests

- Never commit directly to `main` — branch as `<type>/<short-kebab-desc>` (e.g. `feat/dagster-k8s-image`)
- Commit messages and PR titles follow Conventional Commits: `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `ci:`
- PRs are squash-merged, so the PR title becomes the commit on `main`
- To open a PR, use the `write-pr` skill (`.claude/skills/write-pr/SKILL.md`)

### CI workflows (`.github/workflows/`)

Each workflow is a thin caller of a reusable workflow in [mazino2d/github-workflows](https://github.com/mazino2d/github-workflows) (`@v1`); the logic lives there.

| Workflow | Trigger | Does |
|---|---|---|
| `ci.yml` | PR + push `main` (dbt/dlt changes) | pre-commit lint, dlt ingest + `dbt build` on local DuckDB; actionlint + CodeQL on workflows |
| `docker.yml` | PR + push `main` (dag/dbt/dlt/Dockerfile changes) | build image, `dagster definitions validate`; push to GHCR on `main` and open the dev bump PR in everything-as-code |
| `docs.yml` | PR (build only) + push `main` | build MkDocs + dbt docs, deploy to GitHub Pages |

`mkdocs.yml` inherits the shared theme from `.mkdocs/base.yml` (fetched by the workflow, and by `make blog` locally).
