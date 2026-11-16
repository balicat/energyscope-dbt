-- Series metadata from every modelled dataset, with empty strings turned into NULLs.

{% for ds in var('datasets') %}
select
    '{{ ds }}'                                       as dataset,
    cast(series_id as varchar)                       as series_id,
    nullif(trim(name), '')                           as series_name,
    nullif(trim(units), '')                          as units,
    nullif(upper(trim(f)), '')                       as frequency_code,
    nullif(trim(description), '')                    as description,
    nullif(trim(source), '')                         as source_org
from {{ source('lake_series_meta', ds) }}
{% if not loop.last %}
union all
{% endif %}
{% endfor %}
