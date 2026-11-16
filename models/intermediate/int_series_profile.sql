-- Per-series coverage profile: span, count, and gaps measured against the series' own cadence.
-- A gap is a step between consecutive observations longer than twice the nominal spacing.
-- Daily series skip weekends and holidays, so a daily gap is anything over 5 days.

with meta as (
    select
        dataset,
        series_id,
        coalesce(frequency_code, {{ frequency_from_suffix('series_id') }}) as frequency_code
    from {{ ref('stg_series_meta') }}
),

obs as (
    select
        dataset,
        series_id,
        period_date,
        lag(period_date) over (partition by series_id order by period_date) as prev_period
    from {{ ref('fct_observations') }}
),

flagged as (
    select
        o.dataset,
        o.series_id,
        o.period_date,
        coalesce(m.frequency_code, {{ frequency_from_suffix('o.series_id') }}) as frequency_code,
        case
            when o.prev_period is null then false
            when coalesce(m.frequency_code, {{ frequency_from_suffix('o.series_id') }}) = 'D'
                then date_diff('day', o.prev_period, o.period_date) > 5
            else date_diff('day', o.prev_period, o.period_date) > 2 * coalesce(c.nominal_days, 31)
        end as is_gap
    from obs as o
    left join meta as m
        on m.dataset = o.dataset and m.series_id = o.series_id
    left join {{ ref('frequency_cadence') }} as c
        on c.frequency_code = coalesce(m.frequency_code, {{ frequency_from_suffix('o.series_id') }})
)

select
    series_id,
    any_value(dataset)              as dataset,
    any_value(frequency_code)       as frequency_code,
    min(period_date)                as first_period,
    max(period_date)                as last_period,
    count(*)                        as n_obs,
    count(*) filter (where is_gap)  as n_gaps
from flagged
group by series_id
