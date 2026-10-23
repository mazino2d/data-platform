"""
Drops every BigQuery dataset whose name starts with the given prefix, with its
tables. CI uses it to clean up its ci_<run>_* datasets.

Usage:
    python scripts/drop_datasets.py <prefix>
"""

import os
import sys

from google.cloud import bigquery


def main(prefix):
    if not prefix.startswith(("ci_", "dev_")):
        sys.exit(f"refusing to drop datasets with prefix {prefix!r}: only ci_ and dev_ prefixes")
    client = bigquery.Client(project=os.getenv("GCP_PROJECT_ID", "dataplatform-as-se1-prd"))
    for dataset in client.list_datasets():
        if dataset.dataset_id.startswith(prefix):
            print(f"dropping {dataset.dataset_id}")
            client.delete_dataset(dataset.reference, delete_contents=True, not_found_ok=True)


if __name__ == "__main__":
    main(sys.argv[1])
