"""
Entry point for running a dlt ingestion pipeline.

Usage:
    python dlt/pipeline.py <source>        e.g. python dlt/pipeline.py jaffle_shop
    sources: jaffle_shop (Faker demo), simsplit (sim-split's Firestore),
             simsplit_fake (fake sim-split data; dev project only, after simsplit)

Loads the source into BigQuery, in the dataset dbt reads it from (see
dbt/macros/generate_schema_name.sql):
    DBT_TARGET=prod  → <source>_raw
    DBT_TARGET=ci    → $DBT_CI_DATASET_<source>_raw
    DBT_TARGET=dev   → dev_$USER_<source>_raw

simsplit_fake writes into simsplit's dataset (same tables); with
DBT_TARGET=prod (the DAG) it also appends fake telemetry to simsplit_raw, which
every target reads. It refuses any project not ending in "-dev".

Credentials come from Application Default Credentials; the project from
GCP_PROJECT_ID.
"""

import os
import re
import sys
from pathlib import Path

# Add dlt/ directory to path so 'sources' can be imported without
# conflicting with the installed dlt package's own dlt.sources module.
sys.path.insert(0, str(Path(__file__).parent))

import dlt
from dotenv import load_dotenv

from sources.jaffle_shop import jaffle_shop
from sources.simsplit import simsplit
from sources.simsplit_fake import load_telemetry, simsplit_fake

load_dotenv()

SOURCES = {
    "jaffle_shop": jaffle_shop,
    "simsplit": simsplit,
    "simsplit_fake": simsplit_fake,
}

# Sources that write into another source's dataset.
DATASET_OF = {"simsplit_fake": "simsplit"}

LOCATION = "asia-southeast1"


def dataset_name(source_name):
    target = os.getenv("DBT_TARGET", "dev")
    if target == "prod":
        return f"{source_name}_raw"
    if target == "ci":
        return f"{os.environ['DBT_CI_DATASET']}_{source_name}_raw"
    # Same rule as the dev dataset in dbt/profiles.yml.
    user = re.sub(r"[^A-Za-z0-9_]", "_", os.getenv("USER", "local"))
    return f"dev_{user}_{source_name}_raw"


def run(source_name):
    project_id = os.getenv("GCP_PROJECT_ID", "dataplatform-as-se1-prd")
    if source_name == "simsplit_fake" and not project_id.endswith("-dev"):
        sys.exit(f"simsplit_fake writes fake data: refusing project {project_id} (only *-dev)")

    pipeline = dlt.pipeline(
        pipeline_name=source_name,
        destination=dlt.destinations.bigquery(location=LOCATION, project_id=project_id),
        dataset_name=dataset_name(DATASET_OF.get(source_name, source_name)),
    )

    load_info = pipeline.run(SOURCES[source_name]())
    print(load_info)

    if source_name == "simsplit_fake" and os.getenv("DBT_TARGET", "dev") == "prod":
        load_telemetry(project_id)


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in SOURCES:
        sys.exit(f"usage: python dlt/pipeline.py {{{'|'.join(SOURCES)}}}")
    run(sys.argv[1])
