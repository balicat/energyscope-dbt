"""Build the small fixture lake used by CI from the real lake.

Only US-government public-domain sources go into the fixtures (EIA, CFTC, NOAA), so the
repository can carry them. Same layout and schema as the real lake:
  fixtures/lake/<DATASET>/year=<YYYY>/data.parquet   (series_id, period, value, period_norm, year)
  fixtures/lake/<DATASET>/series_meta.parquet

Usage: python scripts/make_fixtures.py /opt/energyscope/data fixtures/lake
"""
import shutil
import sys
from pathlib import Path

import duckdb

src = Path(sys.argv[1])
dst = Path(sys.argv[2])

# the most-populated series of one frequency since 2022
RECENT = ("series_id in (select series_id from read_parquet('{root}/{ds}/year=*/data.parquet', union_by_name = true) "
          "where cast(period as varchar) >= '2022' and series_id like '%.{freq}' group by series_id "
          "order by count(*) desc, series_id limit {n})")

# dataset -> SQL predicate choosing a handful of series
PICK = {
    "PET": """series_id in ('PET.WCESTUS1.W','PET.WCSSTUS1.W','PET.W_EPC0_SAX_YCUOK_MBBL.W','PET.WCRFPUS2.W',
                            'PET.WCRIMUS2.W','PET.WCREXUS2.W','PET.WCRRIUS2.W','PET.RWTC.D','PET.RBRTE.D',
                            'PET.MCRFPUS2.M','PET.MCRFPUS1.A')""",
    "NG": RECENT.format(root="{root}", ds="NG", freq="W", n=6),
    "STEO": "(" + RECENT.format(root="{root}", ds="STEO", freq="M", n=4) + " or "
            + RECENT.format(root="{root}", ds="STEO", freq="Q", n=4) + ")",
    "CFTC": "series_id like 'CFTC.WTI.%'",
    "WEATHER": "series_id like 'WEATHER.HDD.POP.US.%'",
}
SINCE = 2022

if dst.exists():
    shutil.rmtree(dst)
con = duckdb.connect()
for ds, pred in PICK.items():
    pred = pred.format(root=src)
    out = dst / ds
    out.mkdir(parents=True)
    data = f"read_parquet('{src}/{ds}/year=*/data.parquet', union_by_name = true)"
    con.execute(f"""
        copy (
            select cast(series_id as varchar) as series_id, cast(period as varchar) as period, value,
                   cast(period_norm as varchar) as period_norm,
                   cast(substr(cast(period as varchar), 1, 4) as integer) as year
            from {data}
            where ({pred}) and cast(substr(cast(period as varchar), 1, 4) as integer) >= {SINCE}
        ) to '{out}' (format parquet, partition_by (year), filename_pattern 'data', overwrite_or_ignore)
    """)
    for part in out.glob("year=*"):
        files = list(part.glob("*.parquet"))
        if len(files) == 1 and files[0].name != "data.parquet":
            files[0].rename(part / "data.parquet")
    con.execute(f"""
        copy (select * from read_parquet('{src}/{ds}/series_meta.parquet') where {pred})
        to '{out}/series_meta.parquet' (format parquet)
    """)
    n = con.execute(f"select count(*) from read_parquet('{out}/year=*/data.parquet')").fetchone()[0]
    print(f"{ds}: {n} rows")
