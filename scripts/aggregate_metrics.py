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
    df['timestamp'] = pd.to_datetime(df['timestamp'], utc=True)
    df = df.sort_values('timestamp')

    # First introduction of each (file, function)
    first = df.groupby(['file', 'function']).first().reset_index()
    first = first.rename(columns={'commit': 'created_commit', 'author': 'creator', 'timestamp': 'created_at'})

    # Merge introduction time back onto all events
    merged = df.merge(first[['file', 'function', 'created_at']], on=['file', 'function'])
    merged['days_after'] = (merged['timestamp'] - merged['created_at']).dt.days

    # Only events that came after the introduction
    subsequent = merged[merged['days_after'] > 0].copy()

    # Future distinct commits within 90 days
    mods_90d = (
        subsequent[subsequent['days_after'] <= 90]
        .groupby(['file', 'function'])['commit']
        .nunique()
        .reset_index()
        .rename(columns={'commit': 'future_mods_90d'})
    )

    # Survivability: days until first modification (capped at 90 if never touched)
    surv = (
        subsequent.sort_values('days_after')
        .groupby(['file', 'function'])['days_after']
        .first()
        .reset_index()
        .rename(columns={'days_after': 'survivability_days'})
    )

    first = first.merge(mods_90d, on=['file', 'function'], how='left')
    first = first.merge(surv, on=['file', 'function'], how='left')
    first['future_mods_90d'] = first['future_mods_90d'].fillna(0).astype(int)
    first['survivability_days'] = first['survivability_days'].fillna(90)

    # Aggregate per author
    agg = first.groupby('creator').agg(
        introduced_functions=('function', 'count'),
        total_future_mods_90d=('future_mods_90d', 'sum'),
        median_survivability=('survivability_days', 'median')
    ).reset_index()

    # Impact score: downstream mods scaled by breadth of authorship + survivability bonus
    agg['impact_score'] = (
        agg['total_future_mods_90d'] * np.log1p(agg['introduced_functions'])
        + agg['median_survivability'] / 90.0
    )

    agg = agg.sort_values('impact_score', ascending=False)
    out.parent.mkdir(parents=True, exist_ok=True)
    agg.to_csv(out, index=False)
    print('Wrote metrics ->', out)


if __name__ == '__main__':
    main()
