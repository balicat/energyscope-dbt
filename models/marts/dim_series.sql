-- One row per series: what it is, how often it should arrive, what we actually hold,
-- and whether it is late. Built from metadata AND observations, so a series that has data
-- but no metadata (or metadata but no data) still appears, flagged.

with meta as (
    select * from {{ ref('stg_series_meta') }}
),

profile as (
    select * from {{ ref('int_series_profile') }}
),

joined as (
    select
        coalesce(p.series_id, m.series_id)                                     as series_id,
        coalesce(p.dataset, m.dataset)                                         as dataset,
        m.series_name,
        m.units,
        coalesce(m.frequency_code, p.frequency_code,
                 {{ frequency_from_suffix('coalesce(p.series_id, m.series_id)') }}) as frequency_code,
        m.source_org,
        p.first_period,
        p.last_period,
        coalesce(p.n_obs, 0)                                                   as n_obs,
        coalesce(p.n_gaps, 0)                                                  as n_gaps,
        m.series_id is not null                                                as has_metadata
    from profile as p
    full outer join meta as m
        on m.series_id = p.series_id and m.dataset = p.dataset
)

select
    cast(j.series_id as varchar)                    as series_id,
    cast(j.dataset as varchar)                      as dataset,
    cast(j.series_name as varchar)                  as series_name,
    cast(j.units as varchar)                        as units,
    cast(j.frequency_code as varchar)               as frequency_code,
    cast(c.frequency_name as varchar)               as frequency_name,
    cast(j.source_org as varchar)                   as source_org,
    cast(j.first_period as date)                    as first_period,
    cast(j.last_period as date)                     as last_period,
    cast(j.n_obs as bigint)                         as n_obs,
    cast(j.n_gaps as bigint)                        as n_gaps,
    cast(j.has_metadata as boolean)                 as has_metadata,
    cast(j.dataset in (
        {%- for ds in var('forecast_datasets') %}'{{ ds }}'{% if not loop.last %}, {% endif %}{% endfor -%}
    ) as boolean)                                   as is_forecast_dataset,
    cast(coalesce(p.stale_after_days, c.stale_after_days) as integer) as stale_after_days,
    cast(
        case
            when j.last_period is null then 'no_data'
            when j.dataset in (
                {%- for ds in var('forecast_datasets') %}'{{ ds }}'{% if not loop.last %}, {% endif %}{% endfor -%}
            ) then 'forecast'
            when date_diff('day', j.last_period, {{ as_of_date() }})
                 <= coalesce(p.stale_after_days, c.stale_after_days, 150) then 'current'
            when date_diff('day', j.last_period, {{ as_of_date() }})
                 <= greatest(2 * coalesce(p.stale_after_days, c.stale_after_days, 150), 365) then 'late'
            else 'discontinued'
        end
    as varchar)                                     as status
from joined as j
left join {{ ref('frequency_cadence') }} as c
    on c.frequency_code = j.frequency_code
left join {{ ref('dataset_publication') }} as p
    on p.dataset = j.dataset
