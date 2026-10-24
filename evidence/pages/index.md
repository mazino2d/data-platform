---
title: sim-split
---

How sim-split is used, from the app's usage events and Firestore copy (R-4). Refreshed daily
after the data-platform pipeline. Counts only: no account, name or email is on this site.

## Active users

```sql active_users
select day, daily_active_users, weekly_active_users, monthly_active_users
from warehouse.active_users
order by day
```

<LineChart
    data={active_users}
    x=day
    y={['daily_active_users', 'weekly_active_users', 'monthly_active_users']}
    yAxisTitle="accounts"
/>

## Sessions

```sql sessions
select day, platform, sessions, median_session_seconds, events_per_session
from warehouse.sessions
order by day
```

<BarChart data={sessions} x=day y=sessions series=platform yAxisTitle="sessions" />

<LineChart data={sessions} x=day y=median_session_seconds series=platform yAxisTitle="median session (s)" />

## Activation funnel

```sql funnel
select 'Signed up' as step, 1 as step_order, sum(signed_up) as accounts from warehouse.funnel
union all
select 'In a group', 2, sum(in_a_group) from warehouse.funnel
union all
select 'Logged an expense', 3, sum(logged_an_expense) from warehouse.funnel
union all
select 'Friend joined', 4, sum(friend_joined) from warehouse.funnel
order by step_order
```

<FunnelChart data={funnel} nameCol=step valueCol=accounts />

```sql funnel_by_week
select * from warehouse.funnel order by signup_week desc
```

<DataTable data={funnel_by_week} />

## Groups, expenses and settlements created

```sql weekly_activity
select week_start, entity, created from warehouse.weekly_activity order by week_start
```

<BarChart data={weekly_activity} x=week_start y=created series=entity />

## Most used screens and actions (last 30 days)

```sql top_events
select event_kind, event_name, sum(events) as events, max(users) as peak_daily_users
from warehouse.events
where day >= current_date - interval 30 day
group by event_kind, event_name
order by events desc
limit 50
```

<DataTable data={top_events} rows=20 search=true />
