#!/usr/bin/env python3
"""Aggregate events.jsonl into per-author impact metrics.

Usage:
  python scripts/aggregate_metrics.py events.jsonl metrics.csv
"""
import sys
import pathlib
import json
import pandas as pd
import numpy as np


def main():
    inp = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path('events.jsonl')
    out = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else pathlib.Path('metrics.csv')
    rows = []
    for line in inp.read_text().splitlines():
        if not line.strip():
            continue
        rows.append(json.loads(line))
    if not rows:
        print('No events found in', inp)
        return
    df = pd.DataFrame(rows)
    df['timestamp'] = pd.to_datetime(df['timestamp'])

    # Identify first introduction of each (file,function)
    first = df.sort_values('timestamp').groupby(['file', 'function']).first().reset_index()
    first = first.rename(columns={'commit': 'created_commit', 'author': 'creator', 'timestamp': 'created_at'})

    # Count future distinct commits that modify the same function within 90 days
    def future_mod_count(row):
        mask = (
            (df['file'] == row['file']) &
            (df['function'] == row['function']) &
            (df['timestamp'] > row['created_at']) &
            (df['timestamp'] <= row['created_at'] + pd.Timedelta(days=90))
        )
        return df[mask]['commit'].nunique()

    first['future_mods_90d'] = first.apply(future_mod_count, axis=1)

    # Survivability = days until first modification (or capped at 90)
    def survivability_days(row):
        mask = (
            (df['file'] == row['file']) &
            (df['function'] == row['function']) &
            (df['timestamp'] > row['created_at'])
        )
        sub = df[mask].sort_values('timestamp')
        if sub.empty:
            return 90
        return (sub.iloc[0]['timestamp'] - row['created_at']).days

    first['survivability_days'] = first.apply(survivability_days, axis=1)

    # Aggregate per creator
    agg = first.groupby('creator').agg(
        introduced_functions=('function', 'count'),
        total_future_mods_90d=('future_mods_90d', 'sum'),
        median_survivability=('survivability_days', 'median')
    ).reset_index()

    # Impact score: downstream mods scaled by introduced functions and survivability
    agg['impact_score'] = agg['total_future_mods_90d'] * np.log1p(agg['introduced_functions']) + agg['median_survivability'] / 90.0

    agg = agg.sort_values('impact_score', ascending=False)
    out.parent.mkdir(parents=True, exist_ok=True)
    agg.to_csv(out, index=False)
    print('Wrote metrics ->', out)


if __name__ == '__main__':
    main()
