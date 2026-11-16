-- The newest observation of every series, with the one before it and the change between them.
-- This is what an analyst's "latest" formula and the agent's latest-value tool should agree with.

with ranked as (
    select
        series_id,
        dataset,
        period_date,
        value,
        row_number() over (partition by series_id order by period_date desc) as rn
    from {{ ref('fct_observations') }}
),

latest as (select * from ranked where rn = 1),
previous as (select * from ranked where rn = 2)

select
    cast(l.series_id as varchar)        as series_id,
    cast(l.dataset as varchar)          as dataset,
    cast(l.period_date as date)         as latest_period,
    cast(l.value as double)             as latest_value,
    cast(p.period_date as date)         as previous_period,
    cast(p.value as double)             as previous_value,
    cast(l.value - p.value as double)   as change,
    cast(
        case when p.value is null or p.value = 0 then null
             else (l.value - p.value) / abs(p.value) end
    as double)                          as pct_change
from latest as l
left join previous as p on p.series_id = l.series_id
