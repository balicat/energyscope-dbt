{{ config(severity = 'warn', store_failures = true) }}

-- The Python cook step writes period_norm; staging parses the raw period independently.
-- Where they disagree, one of them is wrong. Grouped so the failure reads as a list of
-- formats, not a list of rows.

select
    dataset,
    regexp_replace(period_raw, '\d', '9', 'g')     as raw_format,
    any_value(period_raw)                           as example_raw,
    any_value(period_norm_upstream)                 as example_upstream,
    any_value(period_date)                          as example_parsed,
    count(*)                                        as n_rows
from {{ ref('stg_observations') }}
where try_cast(period_norm_upstream as date) is distinct from period_date
group by dataset, raw_format
