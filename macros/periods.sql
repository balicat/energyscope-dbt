{#
  parse_period: turn the raw period string the sources publish into the first day of the period.
    YYYYMMDD -> that day          (daily, weekly: week-ending or week-start date as published)
    YYYYMM   -> first of month
    YYYYQn   -> first day of the quarter
    YYYY     -> 1 January
  Anything else returns NULL, so a new format shows up in tests instead of being guessed.
  Dispatched, so another adapter can supply its own date functions.
#}
{% macro parse_period(column) -%}
  {{ return(adapter.dispatch('parse_period', 'energyscope')(column)) }}
{%- endmacro %}

{% macro default__parse_period(column) -%}
  case
    when regexp_full_match({{ column }}, '\d{8}')
      then try_strptime({{ column }}, '%Y%m%d')::date
    when regexp_full_match({{ column }}, '\d{6}')
      then try_strptime({{ column }} || '01', '%Y%m%d')::date
    when regexp_full_match({{ column }}, '\d{4}Q[1-4]')
      then make_date(
             cast(substr({{ column }}, 1, 4) as integer),
             (cast(substr({{ column }}, 6, 1) as integer) - 1) * 3 + 1,
             1)
    when regexp_full_match({{ column }}, '\d{4}')
      then make_date(cast({{ column }} as integer), 1, 1)
    else null
  end
{%- endmacro %}

{#
  frequency_from_suffix: the series ID convention puts the frequency after the last dot
  (PET.RWTC.D, STEO.PAPR_WORLD.M). IDs without that convention return NULL.
#}
{% macro frequency_from_suffix(series_id) -%}
  case
    when regexp_full_match({{ series_id }}, '.*\.[DWMQA4]')
      then right({{ series_id }}, 1)
    else null
  end
{%- endmacro %}

{# as_of_date: the date staleness is judged against; var('as_of_date') when set, else today. #}
{% macro as_of_date() -%}
  {%- if var('as_of_date', '') -%}
    cast('{{ var("as_of_date") }}' as date)
  {%- else -%}
    current_date
  {%- endif -%}
{%- endmacro %}
