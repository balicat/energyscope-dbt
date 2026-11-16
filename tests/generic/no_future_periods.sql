{#
  Fails for any row dated after the as-of date, except in datasets that publish forecasts
  (var forecast_datasets) when exclude_forecast_datasets is true. A future date in an actuals
  dataset almost always means a parsing or unit error upstream.
#}
{% test no_future_periods(model, column_name, dataset_column='dataset', exclude_forecast_datasets=true) %}

select {{ dataset_column }}, {{ column_name }}
from {{ model }}
where {{ column_name }} > {{ as_of_date() }}
{%- if exclude_forecast_datasets and var('forecast_datasets') %}
  and {{ dataset_column }} not in (
    {%- for ds in var('forecast_datasets') %}'{{ ds }}'{% if not loop.last %}, {% endif %}{% endfor -%}
  )
{%- endif %}

{% endtest %}
