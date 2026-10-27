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
                   or {type: upstream, depends_on: <task name or list of names>}
    retry:         {max_retries: n, retry_delay_minutes: m}
    environments:  optional subset of [dev, prd] the task runs in (default both).
                   An upstream task missing from an environment is skipped over,
                   so a dev-only task can sit between two shared ones.

Nothing here is specific to an orchestrator: render.py turns the configs into
GitHub Actions workflows and run.py executes one task, so another orchestrator
only needs its own renderer.
"""

from pathlib import Path

import yaml

DAG_CONFIG_DIR = Path(__file__).parent / "dags"
ENVIRONMENTS = ["dev", "prd"]


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
        environments = cfg.setdefault("environments", ENVIRONMENTS)
        if not environments or set(environments) - set(ENVIRONMENTS):
            raise ValueError(f"{path}: environments must be a non-empty subset of {ENVIRONMENTS}")
        cfg["path"] = path
        tasks[name] = cfg

    for name, cfg in tasks.items():
        for upstream in depends_on(cfg):
            if upstream not in tasks:
                raise ValueError(f"{cfg['path']}: unknown upstream task {upstream}")

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


def depends_on(cfg):
    upstream = cfg["trigger"].get("depends_on", [])
    return [upstream] if isinstance(upstream, str) else list(upstream)


def env_depends_on(tasks, name, environment):
    """Upstream tasks of name in an environment: one missing from it is
    replaced by its own upstream tasks there."""
    result = []
    for upstream in depends_on(tasks[name]):
        if environment in tasks[upstream]["environments"]:
            result.append(upstream)
        else:
            result.extend(env_depends_on(tasks, upstream, environment))
    return list(dict.fromkeys(result))


def pipelines(tasks):
    """Group tasks into one pipeline per cron-triggered root: {root: [tasks in run order]}.
    A task runs after all its upstream tasks."""
    children = {}
    for name, cfg in tasks.items():
        for upstream in depends_on(cfg):
            children.setdefault(upstream, []).append(name)

    result = {}
    for name, cfg in tasks.items():
        if cfg["trigger"]["type"] != "cron":
            continue
        reachable, queue = set(), [name]
        while queue:
            current = queue.pop(0)
            if current not in reachable:
                reachable.add(current)
                queue.extend(children.get(current, []))
        order, ready = [], [name]
        while ready:
            current = ready.pop(0)
            order.append(current)
            for child in sorted(children.get(current, [])):
                if child not in order and all(u in order for u in depends_on(tasks[child]) if u in reachable):
                    ready.append(child)
        result[name] = order
    return result
