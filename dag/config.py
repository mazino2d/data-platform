"""
Loads the orchestrator-neutral DAG configs in dag/dags/**/*.yml.

One YAML file is one task:
    name:          unique task name, prefixed with its project (jaffle_shop_staging)
    description:   one line
    command:       shell command to run, or
    dbt_command:   dbt sub-command (build, snapshot, ...) with
    dbt_selector:  --select value and optional
    dbt_exclude:   --exclude value
    trigger:       {type: cron, cron_schedule: "<UTC cron>"}
                   or {type: upstream, depends_on: <task name>}
    retry:         {max_retries: n, retry_delay_minutes: m}

Nothing here is specific to an orchestrator: render.py turns the configs into
GitHub Actions workflows and run.py executes one task, so another orchestrator
only needs its own renderer.
"""

from pathlib import Path

import yaml

DAG_CONFIG_DIR = Path(__file__).parent / "dags"


def load_tasks():
    tasks = {}
    for path in sorted(DAG_CONFIG_DIR.glob("**/*.yml")):
        cfg = yaml.safe_load(path.read_text())
        name = cfg["name"]
        if name in tasks:
            raise ValueError(f"{path}: duplicate task name {name}")
        if ("command" in cfg) == ("dbt_command" in cfg):
            raise ValueError(f"{path}: set exactly one of command and dbt_command")
        trigger = cfg.get("trigger", {})
        if trigger.get("type") not in ("cron", "upstream"):
            raise ValueError(f"{path}: trigger.type must be cron or upstream")
        cfg["path"] = path
        tasks[name] = cfg

    for name, cfg in tasks.items():
        trigger = cfg["trigger"]
        if trigger["type"] == "upstream" and trigger["depends_on"] not in tasks:
            raise ValueError(f"{cfg['path']}: unknown upstream task {trigger['depends_on']}")

    # A task that no cron root reaches (a depends_on cycle) would never be scheduled.
    scheduled = {name for order in pipelines(tasks).values() for name in order}
    for name, cfg in tasks.items():
        if name not in scheduled:
            raise ValueError(f"{cfg['path']}: {name} is not reachable from a cron task (depends_on cycle?)")
    return tasks


def task_command(cfg):
    if "command" in cfg:
        return cfg["command"]
    cmd = f"cd dbt && dbt {cfg['dbt_command']} --profiles-dir . --select '{cfg['dbt_selector']}'"
    if "dbt_exclude" in cfg:
        cmd += f" --exclude '{cfg['dbt_exclude']}'"
    return cmd


def pipelines(tasks):
    """Group tasks into one pipeline per cron-triggered root: {root: [tasks in run order]}."""
    children = {}
    for name, cfg in tasks.items():
        if cfg["trigger"]["type"] == "upstream":
            children.setdefault(cfg["trigger"]["depends_on"], []).append(name)

    result = {}
    for name, cfg in tasks.items():
        if cfg["trigger"]["type"] != "cron":
            continue
        order, queue = [], [name]
        while queue:
            current = queue.pop(0)
            order.append(current)
            queue.extend(sorted(children.get(current, [])))
        result[name] = order
    return result
