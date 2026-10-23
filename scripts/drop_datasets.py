"""
Drops every BigQuery dataset named <prefix> or <prefix>_*, with its tables. CI
uses it to clean up its ci_<run>_<attempt>_* datasets.

Usage:
    python scripts/drop_datasets.py <prefix>    e.g. ci_123_1 or dev_alice
"""

import os
import re
import sys

from google.cloud import bigquery


def main(prefix):
    # One CI run (ci_<run>_<attempt>) or one developer (dev_<user>), never all of them.
    if not re.fullmatch(r"ci_\d+_\d+|dev_\w+", prefix):
        sys.exit(f"refusing to drop datasets with prefix {prefix!r}: expected ci_<run>_<attempt> or dev_<user>")
    client = bigquery.Client(project=os.getenv("GCP_PROJECT_ID", "dataplatform-as-se1-prd"))
    for dataset in client.list_datasets():
        if dataset.dataset_id == prefix or dataset.dataset_id.startswith(prefix + "_"):
            print(f"dropping {dataset.dataset_id}")
            client.delete_dataset(dataset.reference, delete_contents=True, not_found_ok=True)


if __name__ == "__main__":
    main(sys.argv[1])
