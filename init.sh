#!/usr/bin/env bash
#set -euo pipefail

# init.sh — bootstrap and run the engineer-impact prototype
# Usage: ./init.sh [<path-to-repo> [<git-clone-url>]]
# Examples:
#   ./init.sh /tmp/posthog
#   ./init.sh            # uses /tmp/posthog

# Notes:
# - This script creates a local virtualenv (.venv) in the workspace and uses that
#   Python to run the scripts. Activating the venv in your interactive shell
#   is optional — the script runs inside the venv directly.
# - Running this script will clone the repo to the path you provide if it
#   doesn't already exist. Be cautious with the target path.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

REPO_PATH="${1:-/tmp/posthog}"
CLONE_URL="${2:-https://github.com/PostHog/posthog.git}"
VENV_DIR="$ROOT_DIR/.venv"

echo "Workspace root: $ROOT_DIR"
echo "Using repo path: $REPO_PATH"

# 1) ensure python3 exists
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 not found on PATH. Install python3 before continuing." >&2
  exit 1
fi

# 2) create venv if missing
if [ ! -d "$VENV_DIR" ]; then
  echo "Creating venv at $VENV_DIR"
  python3 -m venv "$VENV_DIR"
fi

PIP="$VENV_DIR/bin/pip"
PY="$VENV_DIR/bin/python"

# 3) install requirements
if [ -f "$ROOT_DIR/requirements.txt" ]; then
  echo "Installing Python dependencies into venv..."
  "$PIP" install --upgrade pip
  "$PIP" install -r "$ROOT_DIR/requirements.txt"
else
  echo "requirements.txt not found in $ROOT_DIR. Please add it or install deps manually." >&2
  exit 1
fi

# 4) clone repo if needed
if [ ! -d "$REPO_PATH/.git" ]; then
  echo "Cloning $CLONE_URL -> $REPO_PATH (shallow)..."
  git clone "$CLONE_URL" "$REPO_PATH"
else
  echo "Repo already exists at $REPO_PATH"
fi

# 5) run parser and aggregator
EVENTS="$ROOT_DIR/events.jsonl"
METRICS="$ROOT_DIR/metrics.csv"

echo "Parsing repository (this may take a while) ..."
"$PY" "$ROOT_DIR/scripts/parse_git.py" "$REPO_PATH" "$EVENTS"

echo "Aggregating metrics ..."
"$PY" "$ROOT_DIR/scripts/aggregate_metrics.py" "$EVENTS" "$METRICS"

echo "Finished. Metrics written to: $METRICS"

echo "To view the dashboard locally, run:"
echo "  source $VENV_DIR/bin/activate   # optional interactive activation"
echo "  streamlit run $ROOT_DIR/dashboard/app.py"

echo "Note: activating the venv in this script would not persist in your shell;"
echo "the script used the venv's python directly to run the steps."
