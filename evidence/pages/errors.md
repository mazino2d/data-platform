---
title: Errors and operations
---

## Errors per 100 sessions

```sql errors
select day, platform, sum(errors) as errors, sum(sessions) as sessions,
    100.0 * sum(errors) / nullif(sum(sessions), 0) as errors_per_100_sessions
from warehouse.errors
group by day, platform
order by day
```

<LineChart data={errors} x=day y=errors_per_100_sessions series=platform yAxisTitle="errors / 100 sessions" />

```sql errors_by_version
select app_version, platform, sum(errors) as errors, sum(sessions) as sessions,
    100.0 * sum(errors) / nullif(sum(sessions), 0) as errors_per_100_sessions
from warehouse.errors
group by app_version, platform
order by app_version desc
```

<DataTable data={errors_by_version} />

## Top error types

```sql top_errors
select error_type, platform, shown_to_user, reports, occurrences, installs, first_seen, last_seen
from warehouse.top_errors
order by occurrences desc
limit 50
```

<DataTable data={top_errors} rows=20 search=true />

## Operations (last 30 days)

```sql operations
select operation, sum(runs) as runs, sum(failures) as failures,
    sum(failures) / nullif(sum(runs), 0) as failure_rate,
    median(median_duration_ms) as median_duration_ms
from warehouse.operations
where day >= current_date - interval 30 day
group by operation
order by runs desc
```

<DataTable data={operations} rows=30>
    <Column id=operation />
    <Column id=runs />
    <Column id=failures />
    <Column id=failure_rate fmt=pct1 />
    <Column id=median_duration_ms />
</DataTable>
