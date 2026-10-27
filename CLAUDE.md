# CLAUDE.md — data-platform

## Language

- **Always write code and documentation in English**, regardless of what language the user chats in.

---

## Repo Architecture

The data pipeline for all mazino2d projects: one BigQuery warehouse, dbt models per project,
YAML DAG configs rendered into GitHub Actions workflows. Projects so far: `jaffle_shop`
(Faker demo) and `simsplit` (the sim-split app: a daily dlt copy of its Firestore, plus the
error reports and usage events its telemetry endpoint writes to `simsplit_raw`).

### Stack

| Layer | Tool | Entry point |
|---|---|---|
| Ingestion | dlt | `dlt/pipeline.py <source>`, `dlt/sources/<source>.py` |
| Warehouse | BigQuery | projects `dataplatform-as-se1-dev` (main) and `dataplatform-as-se1-prd` (release tags), location `asia-southeast1` |
| Transformation | dbt (dbt-bigquery) | `dbt/` |
| Orchestration | YAML DAGs → GitHub Actions | `dag/dags/`, `dag/render.py` |
| Dashboard | Evidence → Cloudflare Pages (behind Access) | `evidence/` |

Infrastructure (GCP projects, Workload Identity Federation, the `dev` and `prd` GitHub
Environments with `GCP_PROJECT_ID`, `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT`,
`SIMSPLIT_FIREBASE_PROJECT` and `DASHBOARD_PROJECT`) lives in everything-as-code,
`terraform/gcp/dataplatform-as-se1-{dev,prd}` and `terraform/github`.

### Environments

- **dev** (`dataplatform-as-se1-dev`): PR CI, and the DAGs on every push to `main` and daily.
  Reads `simsplit-as-se1-dev`'s Firestore and the dev telemetry endpoint's tables, plus fake
  data (`dlt/sources/simsplit_fake.py`, IDs prefixed `fake-`, task `simsplit_fake_ingestion`,
  dev only).
- **prd** (`dataplatform-as-se1-prd`): the DAGs on a `vYYYY.M.D` tag push and daily, always
  from the latest release tag. A merge to `main` reaches prd only once tagged.
- Every BigQuery job checks that its environment's variables name its own projects, since
  missing environment variables would fall back to repo-level ones. Never point fake data at
  prd: `dlt/pipeline.py` refuses projects not ending in `-dev`.

### Datasets

`dbt/macros/generate_schema_name.sql` maps each model's `+schema` (`<project>_<layer>`) to a dataset:

- `prod` → `<project>_<layer>` (only the DAG workflows use prod, in each environment's project)
- `ci` → `$DBT_CI_DATASET_<project>_<layer>`, dropped by `scripts/drop_datasets.py` after the run
- `dev` → `dev_$USER_<project>_<layer>`

dlt writes raw data to `<source>_raw` with the same prefixes; the project's `_sources.yml`
computes the same name. Exception: sim-split's `error_reports` and `usage_events` are written
by its telemetry endpoint (one per environment) to the project's `simsplit_raw` only, so the
`simsplit_telemetry` source reads `simsplit_raw` from every target.

sim-split data is personal (names, emails, amounts): `dim_user` is rebuilt from a replaced
`users` load and never snapshotted, so a deleted account leaves the warehouse with the next
daily run, while facts keep only its uid.

### dbt layout

```
dbt/macros/             generate_schema_name + surrogate key macros (scd_surrogate_keys,
                        scd_sk_map, fk_sk_enrich, snapshot_incremental_filter)
dbt/seeds/<project>/
dbt/snapshots/<project>/
dbt/models/<project>/
  staging/              1:1 clean views from raw + seeds. Incremental for log tables.
  intermediate/         Business logic joins + surrogate key lookup tables (dim_*_sk_map).
  marts/core/           Reporting tables
  marts/features/       ML feature tables
```

### Jaffle Shop source table types

| Type | Tables | Backend behavior | dbt strategy |
|---|---|---|---|
| SCD (slowly changing) | customers, orders, products | Updated in-place | `dbt snapshot` → SCD Type 2 |
| Log (append-only) | payments, order_items | New row per event | `incremental` model |

### DAG layout

```
dag/
  dags/<project>/*.yml  One YAML per task: command or dbt_command + dbt_selector,
                        trigger (cron | upstream), retry
  config.py             Loads/validates the YAML, groups tasks into pipelines
  run.py                python -m dag.run <task> — runs one task with retries
  render.py             python -m dag.render — writes .github/workflows/dag-<root>.yml
```

The YAML is orchestrator-neutral; GitHub Actions is the current target. After editing
`dag/dags/`, run `make dags` and commit the generated workflows — CI fails on drift
(`python -m dag.render --check`). Never edit `dag-<root>.yml` by hand.

### Common commands

```bash
make install      # install all Python dependencies
make ingest       # run a dlt pipeline (SOURCE=jaffle_shop)
make snapshot     # run dbt snapshots (SCD Type 2)
make build        # dbt build + tests (dev datasets)
make build-prod   # dbt build + tests (prod datasets) — normally only the DAG workflows do this
make pipeline     # ingest → snapshot → build in sequence
make freshness    # check source SLA (warn >12h, error >24h)
make docs         # generate + serve dbt lineage graph
make dags         # render dag/dags/ into GitHub Actions workflows
make blog         # serve MkDocs documentation site
make lint         # SQLFluff lint all SQL models
make fix          # SQLFluff auto-fix SQL style
make sync         # compile requirements.txt from pyproject.toml
```

Local runs need `gcloud auth application-default login`.

---

## Code Style Rules

### SQL (enforced by SQLFluff + pre-commit)

Config: `.sqlfluff` (root of repo).

- Dialect: **BigQuery** — use `CAST(x AS TIMESTAMP)` (no `::`), `* EXCEPT (...)`,
  `TIMESTAMP_DIFF`, `QUALIFY` (with a `WHERE` clause)
- Templater: **jinja** with dbt builtins (no warehouse connection); only `dbt/models/` is linted
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
- `sqlfluff-lint` — SQL style check (BigQuery dialect, `dbt/models/` only)

Never skip hooks with `--no-verify`. Fix the underlying issue instead.

### Python

- Python 3.11+
- No type annotations or docstrings unless the surrounding code already uses them
- Follow existing patterns in the file you are editing

### dbt conventions

- A new project gets its own folders under `models/`, `snapshots/` and `seeds/`, a project tag,
  and `+schema: <project>_<layer>` per layer in `dbt_project.yml`
- New staging models go in `dbt/models/<project>/staging/` and must be registered in `_sources.yml` or `_schema.yml`
- New intermediate models go in `dbt/models/<project>/intermediate/`
- SCD source tables use `dbt snapshot` — do not query the raw table directly for history; use the snapshot
- Log tables (`payments`, `order_items`) use `incremental` materialization — always include an incremental filter using the `snapshot_incremental_filter` macro
- Use the `fk_sk_enrich` macro to join surrogate keys onto fact tables; do not hardcode joins to snapshot tables
- New seeds go in `dbt/seeds/<project>/` with a matching schema entry

### DAG conventions

- New tasks are YAML files in `dag/dags/<project>/`, named `<project>_<task>`
- dbt tasks select on the project tag plus the layer tag
- Do not add orchestrator-specific fields; extend `dag/config.py` and every renderer instead

### Data privacy

The repo is public. Never commit credentials, `.env`, `gha-creds-*.json`, extracted data or
dashboard data files. Personal data from app projects (names, emails, amounts) stays in
BigQuery; models that feed public outputs (dbt docs) must not expose it. The Evidence
dashboard reads only aggregate models (`<project>_metrics`, no uid, name or email) and is
deployed only to its Access-protected Cloudflare Pages project.

---

## Git & Pull Requests

- Never commit directly to `main` — branch as `<type>/<short-kebab-desc>` (e.g. `feat/simsplit-events`)
- Commit messages and PR titles follow Conventional Commits: `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `ci:`
- PRs are squash-merged, so the PR title becomes the commit on `main`
- To open a PR, use the `write-pr` skill (`.claude/skills/write-pr/SKILL.md`)

### CI workflows (`.github/workflows/`)

Workflows are thin callers of reusable workflows in [mazino2d/github-workflows](https://github.com/mazino2d/github-workflows) (`@v1`), except the ones that need `id-token: write` for BigQuery, which are local.

| Workflow | Trigger | Does |
|---|---|---|
| `ci.yml` | PR + push `main` | `lint`: pre-commit + `dag.render --check`; `dbt` (local, dev environment): dlt ingest + `dbt build` into `ci_<run>_*` datasets in the dev project, then drops them; actionlint + CodeQL |
| `docs.yml` | PR (build only) + push `main` | build MkDocs + dbt docs (`--no-compile --empty-catalog`: lineage and YAML docs only, no BigQuery access), deploy to GitHub Pages |
| `dag-task.yml` | called by `dag-*.yml` | run one DAG task in one environment at one ref |
| `dag-*.yml` | cron + push `main` (dev) + push `v*` tag (prd) + manual (generated) | one pipeline per cron task, a job chain per environment |
| `dashboard.yml` | after `DAG simsplit_raw_ingestion` + manual | build the Evidence dashboard per environment from `simsplit_metrics` and deploy it to that environment's Cloudflare Pages project behind Access |

`mkdocs.yml` inherits the shared theme from `.mkdocs/base.yml` (fetched by the workflow, and by `make blog` locally).
