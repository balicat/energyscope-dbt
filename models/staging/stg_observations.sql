-- One row per (dataset, series, period) across every modelled dataset.
-- period_date is parsed here from the raw period string, independently of the
-- period_norm column the Python cook step writes; the two are compared in tests.

{% for ds in var('datasets') %}
select
    '{{ ds }}'                                as dataset,
    cast(series_id as varchar)                as series_id,
    cast(period as varchar)                   as period_raw,
    {{ parse_period('cast(period as varchar)') }} as period_date,
    cast(period_norm as varchar)              as period_norm_upstream,
    cast(value as double)                     as value
from {{ source('lake_observations', ds) }}
where value is not null
{% if not loop.last %}
union all
{% endif %}
{% endfor %}
