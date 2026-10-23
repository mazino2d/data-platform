"""
Runs one DAG task with the retries its config asks for.

Usage:
    python -m dag.run <task name>
"""

import subprocess
import sys
import time

from dag.config import load_tasks, task_command


def run(name):
    cfg = load_tasks()[name]
    retry = cfg.get("retry", {})
    attempts = retry.get("max_retries", 0) + 1
    delay = retry.get("retry_delay_minutes", 0) * 60
    cmd = task_command(cfg)

    for attempt in range(1, attempts + 1):
        print(f"[{name}] attempt {attempt}/{attempts}: {cmd}", flush=True)
        if subprocess.run(cmd, shell=True).returncode == 0:
            return 0
        if attempt < attempts:
            time.sleep(delay)
    return 1


if __name__ == "__main__":
    sys.exit(run(sys.argv[1]))
