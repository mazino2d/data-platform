# Data Engineering: Principles & Patterns

A series on the foundational ideas behind modern data pipelines — how to think about them, design them, and operate them reliably. Each post focuses on a principle rather than a tool. Code examples are drawn from the [data-platform](https://github.com/mazino2d/data-platform) repository, starting from its Jaffle Shop demo.

---

## Module 1 — Foundations & Philosophy

The mental models that underpin everything else. Start here.

| # | Post | What it covers |
|---|---|---|
| 1.1 | [Two Mental Models: Mutable Entities vs. Immutable Events](blog/mutable-vs-immutable/) | The most fundamental split in data engineering — how you classify data determines every design decision |
| 1.2 | [ELT vs. ETL: A Paradigm Shift, Not Just a Letter Swap](blog/elt-vs-etl/) | Why modern stacks load raw first and transform inside the warehouse |
| 1.3 | [Layered Pipeline Architecture: Why Not One Script?](blog/layered-pipeline-architecture/) | Separation of concerns across ingestion, staging, intermediate, and marts |
| 1.4 | [Batch vs. Streaming vs. Micro-batch](blog/batch-vs-streaming/) | Choosing the right processing model — and why real-time is often the wrong answer |
| 1.5 | [Data Warehouse vs. Data Lake vs. Lakehouse](blog/warehouse-lake-lakehouse/) | A tradeoff between structure, cost, and flexibility — not a tool war |

---

## Module 2 — Ingestion

Getting data in reliably, at scale, without surprises.

| # | Post | What it covers |
|---|---|---|
| 2.1 | [Three Ingestion Patterns: Full Refresh, Incremental, CDC](blog/ingestion-patterns/) | Choosing by data nature, not tool capability |
| 2.2 | [Schema Evolution: When Your Source Changes Without Warning](blog/schema-evolution/) | The most underestimated operational challenge — breaking vs. non-breaking changes |
| 2.3 | [Idempotency: Pipelines That Are Safe to Run Twice](blog/idempotency/) | Why retries are inevitable and how to design for them |

---

## Module 3 — Storage

How data is stored affects every query that runs against it.

| # | Post | What it covers |
|---|---|---|
| 3.1 | [Storage Formats: Why Parquet Is Not Just "Smaller CSV"](blog/storage-formats/) | Row vs. column orientation, file format tradeoffs, compression |
| 3.2 | [Partitioning and Clustering: Designing for Query Patterns](blog/partitioning-and-clustering/) | Partition pruning, the small files problem, clustering as a complement |

---

## Module 4 — Data Modeling

Structuring data for how analysts actually query it.

| # | Post | What it covers |
|---|---|---|
| 4.1 | [Dimensional Modeling: Facts, Dimensions, and Star Schema](blog/dimensional-modeling/) | Why denormalization is correct in analytics |
| 4.2 | [Surrogate Keys vs. Natural Keys](blog/surrogate-vs-natural-keys/) | Stability over intuition — why business keys are fragile |
| 4.3 | [Slowly Changing Dimensions: When History Matters](blog/slowly-changing-dimensions/) | SCD Type 1/2/6 — the business question determines the approach |
| 4.4 | [Fact Table Patterns: Transactional, Periodic Snapshot, Accumulating Snapshot](blog/fact-table-patterns/) | Three distinct patterns for three types of measurements |

---

## Module 5 — Transformation

Building the logic that turns raw data into trusted analytics.

| # | Post | What it covers |
|---|---|---|
| 5.1 | [Staging → Intermediate → Marts: The Case for Layered Transforms](blog/staging-intermediate-marts/) | One responsibility per layer, clear boundaries, controlled blast radius |
| 5.2 | [Incremental Processing and Late-Arriving Data](blog/incremental-processing/) | Lookback windows, deduplication, and when to trigger a full rebuild |
| 5.3 | [The Semantic Layer: Define Metrics Once, Use Everywhere](blog/semantic-layer/) | Centralizing metric definitions to eliminate inconsistency at scale |

---

## Module 6 — Quality & Reliability

Trustworthy data doesn't happen by accident.

| # | Post | What it covers |
|---|---|---|
| 6.1 | [Data Quality as Code: Tests That Ship With the Pipeline](blog/data-quality-as-code/) | Schema tests, business logic tests, freshness SLAs — fail fast, fail early |
| 6.2 | [Data Contracts: The Agreement Between Producers and Consumers](blog/data-contracts/) | Making implicit dependencies explicit before they break silently |
| 6.3 | [Data Observability: Beyond "Did the Job Succeed?"](blog/data-observability/) | Freshness, volume, schema, distribution — and why pipeline success ≠ data correctness |

---

## Module 7 — Orchestration

Coordinating pipelines that run reliably, recover gracefully, and scale.

| # | Post | What it covers |
|---|---|---|
| 7.1 | [DAGs: The Right Mental Model for Pipeline Dependencies](blog/dag-fundamentals/) | Directed, acyclic, graph — why each property matters |
| 7.2 | [Trigger Patterns: Cron, Sensors, and Event-Driven Pipelines](blog/trigger-patterns/) | Schedule-based vs. data-aware triggering — the coupling tradeoff |
| 7.3 | [Backfilling and Catchup: Reprocessing Historical Data](blog/backfilling-and-catchup/) | Idempotency as a prerequisite, partitioned backfill, blast radius control |
| 7.4 | [Pipeline as Code: Configuration Over Imperative DAG Definitions](blog/pipeline-as-code/) | Separating pipeline behavior from pipeline logic for maintainability |

---

## Module 8 — Serving

Delivering data to the consumers who depend on it.

| # | Post | What it covers |
|---|---|---|
| 8.1 | [Designing the Serving Layer for Different Consumers](blog/serving-layer/) | BI vs. ML vs. operational — different requirements, different designs |
| 8.2 | [Feature Engineering: Bridging Analytics and Machine Learning](blog/feature-engineering/) | Point-in-time correctness, RFM framework, when you need a feature store |

---

*All examples reference the [data-platform](https://github.com/mazino2d/data-platform) repository — its Jaffle Shop demo pipeline was built with dlt, dbt, DuckDB and Dagster, and now runs on BigQuery with GitHub Actions.*
