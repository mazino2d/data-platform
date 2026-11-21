---
title: Notifications
---

Pushes the crm service sent (R-9), and how many were opened. Opens come from the app's usage
events and count on the day they happen; opens from builds that only logged the category are
under source `unknown`.

## Sends and opens

```sql daily
select day, sum(sent) as sent, sum(opens) as opens
from warehouse.notifications
where day is not null
group by day
order by day
```

<LineChart emptySet="pass" emptyMessage="No data yet" data={daily} x=day y={['sent', 'opens']} yAxisTitle="pushes" />

```sql sent_by_source
select day, source, sum(sent) as sent
from warehouse.notifications
where day is not null and sent > 0
group by day, source
order by day
```

<BarChart emptySet="pass" emptyMessage="No data yet" data={sent_by_source} x=day y=sent series=source yAxisTitle="sent" />

## Per source (last 30 days)

```sql by_source
select source, source_id,
    sum(sends) as sends, sum(sent) as sent, sum(invalid_token) as invalid_token, sum(failed) as failed,
    sum(opens) as opens,
    sum(opens) / nullif(sum(sent), 0) as open_rate,
    sum(invalid_token) / nullif(sum(sends), 0) as invalid_token_rate
from warehouse.notifications
where day >= current_date - interval 30 day and source is not null
group by source, source_id
order by sends desc
```

<DataTable emptySet="pass" emptyMessage="No data yet" data={by_source} rows=30>
    <Column id=source />
    <Column id=source_id />
    <Column id=sends />
    <Column id=sent />
    <Column id=invalid_token />
    <Column id=failed />
    <Column id=opens />
    <Column id=open_rate fmt=pct1 />
    <Column id=invalid_token_rate fmt=pct1 />
</DataTable>

## Invalid-token rate

Share of send attempts rejected because the device token is no longer valid.

```sql invalid_tokens
select day, sum(invalid_token) / nullif(sum(sends), 0) as invalid_token_rate
from warehouse.notifications
where day is not null
group by day
order by day
```

<LineChart emptySet="pass" emptyMessage="No data yet" data={invalid_tokens} x=day y=invalid_token_rate yFmt=pct1 yAxisTitle="invalid-token rate" />
