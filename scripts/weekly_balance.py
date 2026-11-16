"""Print the latest weeks of the US crude balance from mart_us_crude_weekly.

Usage: python scripts/weekly_balance.py [path/to/energyscope.duckdb] [weeks]
"""
import sys

import duckdb

db = sys.argv[1] if len(sys.argv) > 1 else "energyscope.duckdb"
weeks = int(sys.argv[2]) if len(sys.argv) > 2 else 6

con = duckdb.connect(db, read_only=True)
schema = con.execute(
    "select table_schema from information_schema.tables where table_name = 'mart_us_crude_weekly' limit 1"
).fetchone()[0]
rows = con.execute(
    f"""
    select week_ending, crude_stocks_ex_spr, crude_stocks_ex_spr_wow, cushing_stocks,
           crude_production, net_crude_imports, refinery_crude_inputs
    from "{schema}".mart_us_crude_weekly
    where crude_stocks_ex_spr is not null
    order by week_ending desc
    limit ?
    """,
    [weeks],
).fetchall()

head = f"{'week':<12}{'stocks ex-SPR':>15}{'w/w':>10}{'Cushing':>10}{'prod':>9}{'net imp':>9}{'runs':>9}"
print(head)
print("-" * len(head))
for wk, stocks, wow, cushing, prod, netimp, runs in rows:
    fmt = lambda v, w: f"{v:>{w},.0f}" if v is not None else f"{'-':>{w}}"
    print(f"{str(wk):<12}{fmt(stocks, 15)}{fmt(wow, 10)}{fmt(cushing, 10)}{fmt(prod, 9)}{fmt(netimp, 9)}{fmt(runs, 9)}")
print("\nStocks in thousand barrels; flows in thousand barrels per day. Source: EIA Weekly Petroleum Status Report.")
