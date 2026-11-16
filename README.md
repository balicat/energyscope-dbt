# energyscope-dbt

[![dbt CI](https://github.com/balicat/energyscope-dbt/actions/workflows/dbt-ci.yml/badge.svg)](https://github.com/balicat/energyscope-dbt/actions/workflows/dbt-ci.yml)

A dbt project over the [EnergyScope](https://energyscope.io) market-data lake: 17 datasets,
**18.9M observations across 204,544 series**, read in place from Parquet by DuckDB
(dbt-duckdb). Sources include EIA petroleum and natural gas, the EIA Short-Term Energy
Outlook, JODI, CFTC and ICE positioning, NOAA degree days, IMF PortWatch, GIE gas storage,
the EU Weekly Oil Bulletin, FRED, Baker Hughes, and OPEC and IEA report tables.

The lake itself is built by Dagster pipelines and served by an Arrow Flight server; this project
is the modelling and testing layer on top of it. Everything below ran against the live lake on
16 Nov 2026.

## Layers

```
sources (Parquet, read in place)          seeds
  lake_observations.<DATASET>               frequency_cadence    (spacing, lateness, revision window)
  lake_series_meta.<DATASET>                dataset_publication  (publication-rhythm overrides)
            |                               key_series           (which series feed the weekly mart)
staging     stg_observations   stg_series_meta
            |                        |
            |                  snapshots: snp_series_meta (SCD2, hard deletes recorded)
intermediate int_series_profile (span, count, gaps against cadence)
            |
marts       fct_observations (incremental)  dim_series  fct_latest  mart_us_crude_weekly
            |
exposure    scripts/weekly_balance.py
```

Marts are `public` and carry **enforced contracts** (names, types, not-null, primary keys);
staging and intermediate are `protected`.

## Design decisions

**Revision-aware incremental model.** Publishers revise recent history: EIA revises weekly and
monthly figures, and annual benchmarks reach back further. `fct_observations` re-reads, per
series, every period inside a lookback window behind that series' own newest period, and
`delete+insert` replaces what it re-read. The window depends on frequency (45 days for daily,
120 for weekly, 400 for monthly, 1,100 for annual). The watermark is per series, not per table:
STEO's forecasts run to December 2027, and a table-wide watermark would have pushed every other
dataset's window past its revisions. A unit test pins exactly this. Deletions upstream are not
caught incrementally; a periodic `--full-refresh` handles them.

**Periods parsed here, then reconciled with upstream.** The cook step writes a normalised
period; staging parses the raw string independently (`YYYYMMDD`, `YYYYMM`, `YYYYQn`, `YYYY`;
anything else becomes NULL and fails a test) and a singular test compares the two.

**"Late" follows the publication rhythm, not the data frequency.** EIA monthly data appears about
two months after the month, and PortWatch publishes daily data once a week. `dim_series.status`
(current / late / discontinued / forecast / no_data) uses seed thresholds that include the normal
lag, with per-dataset overrides. The first version used plain frequency and called 98,006 series
late; with publication lags it is 22,855, and those are worth a look.

**Freshness on data time.** Source freshness uses the newest period in each dataset, not file
timestamps: a file rewritten today with last month's data is not fresh. Forecast datasets have
no freshness rule.

## Tests

| Kind | Count | What they hold |
|---|---|---|
| Unit tests | 3 | period parsing for every format; the incremental window (revision picked up, old history skipped, new series loaded in full, a forecast series does not move anyone else's window); latest/previous/change |
| Data tests | 36 | keys and composite keys, relationships (facts to dimension, seeds to dimension), accepted values, ranges, no future periods in actuals datasets, orphan series |
| Singular | 2 | `fct_latest` agrees with the facts; dbt's period parsing agrees with the upstream cook step |
| Source freshness | 14 | newest period per dataset within its publication rhythm |

## What the first run found

- **STEO quarterly periods were malformed upstream.** 177,245 rows had a normalised period like
  `2003-Q1-01`, which is not a date. OPEC and IEA quarterlies were fine. The reconciliation test
  flags it as a warning; this project's own parsing gives 2003-01-01, so the marts are correct.
- **CFTC and ICE positioning stopped at Tuesday 3 November**, 13 days before the run date, and both
  sources warned on freshness. Possibly a holiday-week release delay (Veterans Day fell on 11
  November); not yet confirmed.
- **Series status:** 70,195 current, 22,855 late, 102,712 discontinued, 8,782 forecast, and 6,391
  with metadata but no observations (EIA catalogue entries with no data).
- **Gaps against cadence** in current series: every current EU Weekly Oil Bulletin series has at
  least one gap longer than two weeks (publication pauses), and 273 of 456 NOAA degree-day series
  do (seasonal).

## Measured (MS-02: Intel Core Ultra 5 235HX, 64 GB, NVMe)

| Run | Time |
|---|---|
| `dbt build`, 54 nodes, from empty | 7.6 s wall (5.0 s in dbt), 3.7 GB peak |
| `fct_observations`, full refresh, 18.9M rows | 1.1 s |
| `fct_observations`, incremental | 0.7 s, row count unchanged |
| CI build on the fixture lake | under 1 s |

At this size on DuckDB a full refresh is already cheap; the incremental model is there for the
revision semantics and for warehouses that bill by bytes scanned.

## Run it

CI runs on a small fixture lake committed under `fixtures/` (US-government public-domain data
only: EIA, CFTC, NOAA), so the project runs without access to the real lake:

```bash
pip install -r requirements.txt
export ENERGYSCOPE_LAKE=fixtures/lake DBT_PROFILES_DIR=.
dbt deps
dbt build --target ci --vars '{datasets: [PET, NG, STEO, CFTC, WEATHER], as_of_date: "2026-11-16"}'
python scripts/weekly_balance.py ci.duckdb
```

Against the real lake: `ENERGYSCOPE_LAKE=/path/to/lake dbt build` (target `lake`).
`scripts/make_fixtures.py` rebuilds the fixtures from a lake.

## Not done

- `parse_period` is dispatched so another adapter can supply its own date functions, but only
  DuckDB is tested here. An earlier version of these marts ran on Snowflake.
- Thresholds in the seeds are judgement calls about each publisher's rhythm; they live in data so
  they can be argued with.
