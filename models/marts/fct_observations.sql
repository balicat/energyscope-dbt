-- depends_on: {{ ref('stg_series_meta') }}
-- depends_on: {{ ref('frequency_cadence') }}
{# Both are only referenced inside is_incremental(); the hints register them at parse time. #}
{{
  config(
    materialized = 'incremental',
    unique_key = ['series_id', 'period_date'],
    incremental_strategy = 'delete+insert',
    on_schema_change = 'fail'
  )
}}

-- The observation fact. Incremental, and revision-aware.
--
-- Publishers revise recent history (EIA revises weekly and monthly figures; monthly
-- benchmarks reach back a year or more). An incremental run therefore re-reads, for each
-- series, every period inside a lookback window behind that series' own newest period,
-- and delete+insert replaces whatever it re-read. The window depends on the frequency
-- (seed frequency_cadence). The watermark is per series, not per table: a forecast
-- dataset whose newest period is in 2027 must not push the window past everyone else's
-- revisions.
--
-- Not handled incrementally: an observation the publisher deletes outright. A periodic
-- --full-refresh removes those.

with source_rows as (
    select
        o.dataset,
        o.series_id,
        o.period_date,
        o.value
    from {{ ref('stg_observations') }} as o
),

{% if is_incremental() %}
series_watermark as (
    select series_id, max(period_date) as max_period
    from {{ this }}
    group by series_id
),

series_lookback as (
    select
        m.dataset,
        m.series_id,
        c.revision_lookback_days as lookback_days
    from {{ ref('stg_series_meta') }} as m
    left join {{ ref('frequency_cadence') }} as c
        on c.frequency_code = coalesce(m.frequency_code, {{ frequency_from_suffix('m.series_id') }})
),
{% endif %}

selected as (
    select s.*
    from source_rows as s
    {% if is_incremental() %}
    left join series_watermark as w
        on w.series_id = s.series_id
    left join series_lookback as l
        on l.dataset = s.dataset and l.series_id = s.series_id
    where w.max_period is null
       or s.period_date >= w.max_period
            - cast(coalesce(l.lookback_days, {{ var('default_revision_lookback_days', 400) }}) as integer)
    {% endif %}
)

select
    cast(series_id as varchar)   as series_id,
    cast(dataset as varchar)     as dataset,
    cast(period_date as date)    as period_date,
    cast(value as double)        as value,
    cast(current_timestamp as timestamp) as loaded_at
from selected
