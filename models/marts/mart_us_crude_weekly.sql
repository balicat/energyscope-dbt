-- The US weekly crude balance as one row per week, the shape an analyst charts.
-- Which series feed which column is data (seed key_series), not code.

with obs as (
    select
        k.metric,
        f.period_date,
        f.value
    from {{ ref('fct_observations') }} as f
    inner join {{ ref('key_series') }} as k
        on k.series_id = f.series_id
),

pivoted as (
    select
        period_date as week_ending,
        {%- for m in ['crude_stocks_ex_spr', 'crude_stocks_spr', 'cushing_stocks', 'crude_production',
                      'crude_imports', 'crude_exports', 'refinery_crude_inputs'] %}
        max(value) filter (where metric = '{{ m }}') as {{ m }}{{ ',' if not loop.last }}
        {%- endfor %}
    from obs
    group by period_date
)

select
    cast(week_ending as date)                                           as week_ending,
    crude_stocks_ex_spr,
    crude_stocks_spr,
    cushing_stocks,
    crude_production,
    crude_imports,
    crude_exports,
    crude_imports - crude_exports                                       as net_crude_imports,
    refinery_crude_inputs,
    crude_stocks_ex_spr
        - lag(crude_stocks_ex_spr) over (order by week_ending)          as crude_stocks_ex_spr_wow
from pivoted
