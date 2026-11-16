{% docs __overview__ %}
# EnergyScope market data, modelled in dbt

Seventeen market datasets from the EnergyScope lake (EIA petroleum and natural gas, STEO, JODI,
CFTC and ICE positioning, NOAA degree days, IMF PortWatch, GIE gas storage, the EU Weekly Oil
Bulletin, FRED, Baker Hughes, OPEC and IEA report tables, freight and macro series), read in
place from Parquet by DuckDB.

**Layers**
- `staging`: one view per entity, unioned across datasets; periods parsed from the raw strings.
- `intermediate`: per-series coverage profile (span, count, gaps against the series' cadence).
- `marts`: `fct_observations` (incremental, revision-aware), `dim_series` (status per series),
  `fct_latest`, `mart_us_crude_weekly`. Marts have enforced contracts.
- `snapshots`: Type 2 history of series metadata.

**Tests** run at three levels: unit tests on the transformation logic (period parsing, the
incremental revision window, latest/change), data tests on every run (keys, relationships,
accepted values, ranges, future dates in actuals), and singular reconciliation tests (latest vs
facts; dbt's period parsing vs the upstream cook step).
{% enddocs %}
