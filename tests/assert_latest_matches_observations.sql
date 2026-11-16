-- fct_latest must agree with the observation fact it summarises: for every series, its
-- latest_period is the newest period in fct_observations and latest_value is that row's value.

with newest as (
    select series_id, max(period_date) as max_period
    from {{ ref('fct_observations') }}
    group by series_id
)

select l.series_id, l.latest_period, n.max_period, l.latest_value, o.value
from {{ ref('fct_latest') }} as l
join newest as n on n.series_id = l.series_id
join {{ ref('fct_observations') }} as o
    on o.series_id = l.series_id and o.period_date = n.max_period
where l.latest_period <> n.max_period
   or l.latest_value is distinct from o.value
