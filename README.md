# Engineer Impact Prototype

This prototype computes a heuristic "impact" score for engineers by treating functions as the unit of work and measuring downstream modifications (within 90 days) and survivability.

Files added:
- `scripts/parse_git.py` — parse a local git repo and emit `events.jsonl` (per-function events).
- `scripts/aggregate_metrics.py` — aggregate events into `metrics.csv` with an `impact_score` per author.
- `dashboard/app.py` — minimal Streamlit dashboard showing top 5 engineers.
- `requirements.txt` — Python dependencies.

Quick start (macOS / zsh):

```bash
# create a venv
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# clone PostHog (example) and run on a small subset or a full clone
git clone https://github.com/PostHog/posthog.git /tmp/posthog
python3 scripts/parse_git.py /tmp/posthog events.jsonl
python3 scripts/aggregate_metrics.py events.jsonl metrics.csv
streamlit run dashboard/app.py
```

Notes and next steps:
- Replace regex-based extractor with tree-sitter for accurate function identities.
- Handle renames/moves and semantic diffs to attribute authorship across file moves.
- Add tests and sample data; integrate with PostHog ingestion API to send metrics as events.
