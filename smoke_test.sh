#!/usr/bin/env bash
set -euo pipefail

# run.sh — create a richer local git history in local_testrepo and run the analyzer
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

REPO_DIR="local_testrepo"
rm -rf "$REPO_DIR"
mkdir -p "$REPO_DIR"
cd "$REPO_DIR"
git init -q

echo "Creating richer commit history in $PWD"

# Commit 1: Alice adds a Python file
cat > a.py <<'PY'
def foo(x):
        return x + 1
PY
git add a.py
GIT_AUTHOR_NAME="Alice" GIT_AUTHOR_EMAIL="alice@example.com" git commit -m "add a.py" --author="Alice <alice@example.com>" -q

# Commit 2: Alice adds a utility file
cat > util.py <<'PY'
def helper(y):
        return y * 2
PY
git add util.py
GIT_AUTHOR_NAME="Alice" GIT_AUTHOR_EMAIL="alice@example.com" git commit -m "add util.py" --author="Alice <alice@example.com>" -q

# Branch: feature/add-js - Bob works on a feature with JS file
git checkout -b feature/add-js
cat > b.js <<'JS'
function greet(name) {
    return `hello ${name}`
}
JS
git add b.js
GIT_AUTHOR_NAME="Bob" GIT_AUTHOR_EMAIL="bob@example.com" git commit -m "add b.js (greet)" --author="Bob <bob@example.com>" -q

# Bob tweaks Python file too (portable in-place edit)
python3 - <<'PY'
from pathlib import Path
p = Path('a.py')
if p.exists():
        s = p.read_text()
        s = s.replace('x + 1', 'x + 2')
        p.write_text(s)
PY
git add a.py
GIT_AUTHOR_NAME="Bob" GIT_AUTHOR_EMAIL="bob@example.com" git commit -m "tweak foo to +2" --author="Bob <bob@example.com>" -q
# determine default branch name (after initial commits)
MAIN_BRANCH=$(git branch --show-current 2>/dev/null || echo main)

# Back to main and merge feature as Carol (simulate PR merge)
git checkout "$MAIN_BRANCH"
GIT_AUTHOR_NAME="Carol" GIT_AUTHOR_EMAIL="carol@example.com" GIT_COMMITTER_NAME="Carol" GIT_COMMITTER_EMAIL="carol@example.com" git merge --no-ff feature/add-js -m "Merge feature/add-js" -q || true

# Dave performs a refactor: move function to a_refactor.py and remove original
git checkout -b refactor/move-foo
git mv a.py a_refactor.py
cat > a_refactor.py <<'PY'
def foo(x):
        # refactored implementation
        return (x or 0) + 2
PY
git add a_refactor.py
GIT_AUTHOR_NAME="Dave" GIT_AUTHOR_EMAIL="dave@example.com" git commit -m "move foo to a_refactor and refactor" --author="Dave <dave@example.com>" -q

# Merge refactor back to main via merge commit
git checkout "$MAIN_BRANCH"
GIT_AUTHOR_NAME="Carol" GIT_AUTHOR_EMAIL="carol@example.com" GIT_COMMITTER_NAME="Carol" GIT_COMMITTER_EMAIL="carol@example.com" git merge --no-ff refactor/move-foo -m "Merge refactor/move-foo" -q || true

# Tag a release
git tag -a v0.1 -m "release v0.1"

# Eve adds a TypeScript file and modifies util
cat > c.ts <<'TS'
export function compute(n: number) {
    return n * n
}
TS
git add c.ts
GIT_AUTHOR_NAME="Eve" GIT_AUTHOR_EMAIL="eve@example.com" git commit -m "add c.ts (compute)" --author="Eve <eve@example.com>" -q

python3 - <<'PY' || true
from pathlib import Path
p = Path('util.py')
if p.exists():
        s = p.read_text()
        s = s.replace('y * 2', 'y * 3')
        p.write_text(s)
PY
git add util.py || true
GIT_AUTHOR_NAME="Eve" GIT_AUTHOR_EMAIL="eve@example.com" git commit -m "adjust util.helper multiplier" --author="Eve <eve@example.com>" -q || true

# Simulate a bugfix by Frank (write the corrected file to avoid shell-quoting fragility)
cat > b.js <<'JS'
function greet(name) {
        return 'hello ' + name
}
JS
git add b.js
GIT_AUTHOR_NAME="Frank" GIT_AUTHOR_EMAIL="frank@example.com" git commit -m "fix greeting string in b.js" --author="Frank <frank@example.com>" -q || true

# Add a deletion
git rm util.py || true
GIT_AUTHOR_NAME="Grace" GIT_AUTHOR_EMAIL="grace@example.com" git commit -m "remove util (no longer needed)" --author="Grace <grace@example.com>" -q || true

# Create a small merge conflict scenario: feature/experimental
git checkout -b feature/experimental
echo "// experimental" > experimental.js
git add experimental.js
GIT_AUTHOR_NAME="Heidi" GIT_AUTHOR_EMAIL="heidi@example.com" git commit -m "add experimental file" --author="Heidi <heidi@example.com>" -q

git checkout "$MAIN_BRANCH"
GIT_AUTHOR_NAME="Carol" GIT_AUTHOR_EMAIL="carol@example.com" GIT_COMMITTER_NAME="Carol" GIT_COMMITTER_EMAIL="carol@example.com" git merge --no-ff feature/experimental -m "Merge experimental feature" -q || true

cd "$ROOT_DIR"

# Run parser and aggregator against this richer repo
echo "Running parser and aggregator on $ROOT_DIR/$REPO_DIR"
python3 scripts/parse_git.py "$REPO_DIR" "$REPO_DIR/events.jsonl"
python3 scripts/aggregate_metrics.py "$REPO_DIR/events.jsonl" "$REPO_DIR/metrics.csv"

echo "Outputs:"
ls -lh "$REPO_DIR/events.jsonl" "$REPO_DIR/metrics.csv" || true
echo "--- events (tail) ---"
tail -n 200 "$REPO_DIR/events.jsonl" || true
echo "--- metrics ---"
cat "$REPO_DIR/metrics.csv" || true

echo "Done. To run the dashboard use: source .venv/bin/activate && streamlit run dashboard/app.py"

### Additional complex history (appended) ###
echo "--- Creating extra complex history: conflicts, cherry-picks, revert ---"
cd "$REPO_DIR"

# Create a perf branch and some micro-optimizations by Ivan
git checkout -b perf/opt
python3 - <<'PY'
from pathlib import Path
p=Path('a_refactor.py')
if p.exists():
        s=p.read_text()
        s=s.replace('return (x or 0) + 2', 'return (x or 0) + 2  # micro-opt')
        p.write_text(s)
PY
git add a_refactor.py || true
GIT_AUTHOR_NAME="Ivan" GIT_AUTHOR_EMAIL="ivan@example.com" git commit -m "micro-optimize foo" --author="Ivan <ivan@example.com>" -q || true

# Create hotfix branch from main and cherry-pick later
git checkout "$MAIN_BRANCH"
git checkout -b hotfix/fix-compute
python3 - <<'PY'
from pathlib import Path
p=Path('c.ts')
if p.exists():
                s=p.read_text()
                s=s.replace('return n * n','return Math.abs(n) * Math.abs(n)')
                p.write_text(s)
PY
git add c.ts || true
GIT_AUTHOR_NAME="Judy" GIT_AUTHOR_EMAIL="judy@example.com" git commit -m "hotfix: ensure compute handles negatives" --author="Judy <judy@example.com>" -q || true

# Cherry-pick Judy's hotfix onto main via a temporary branch
git checkout "$MAIN_BRANCH"
CHERRY_COMMIT=$(git rev-parse hotfix/fix-compute)
git checkout -b integrate/hotfix
git cherry-pick "$CHERRY_COMMIT" -x || true
GIT_AUTHOR_NAME="Kurt" GIT_AUTHOR_EMAIL="kurt@example.com" git commit --amend --no-edit --author="Kurt <kurt@example.com>" -q || true
git checkout "$MAIN_BRANCH"
git merge --no-ff integrate/hotfix -m "merge hotfix" -q || true

# Create two conflicting branches editing b.js to simulate a merge conflict
git checkout -b conflict/one
cat > b.js <<'JS'
function greet(name) {
        return 'hello ' + name + '!!'
}
JS
git add b.js
GIT_AUTHOR_NAME="Kevin" GIT_AUTHOR_EMAIL="kevin@example.com" git commit -m "enthusiastic greeting" --author="Kevin <kevin@example.com>" -q

git checkout "$MAIN_BRANCH"
git checkout -b conflict/two
cat > b.js <<'JS'
function greet(name) {
        return 'hi ' + name
}
JS
git add b.js
GIT_AUTHOR_NAME="Laura" GIT_AUTHOR_EMAIL="laura@example.com" git commit -m "alternate greeting" --author="Laura <laura@example.com>" -q

# Attempt merge of conflict/two into main, detect conflict and resolve programmatically
git checkout "$MAIN_BRANCH"
git merge --no-ff conflict/one -m "merge conflict/one" -q || true
set +e
git merge --no-ff conflict/two -m "merge conflict/two" 2> merge.err
MERGE_EXIT=$?
set -e
if [ $MERGE_EXIT -ne 0 ]; then
        echo "Merge produced conflicts; resolving by choosing a combined greeting"
        # write resolved file
        cat > b.js <<'JS'
function greet(name) {
        return 'hello ' + name + ' (resolved)'
}
JS
        git add b.js
        GIT_AUTHOR_NAME="Mallory" GIT_AUTHOR_EMAIL="mallory@example.com" git commit -m "resolve merge conflict: b.js" --author="Mallory <mallory@example.com>" -q || true
fi

# Create a revert of a previous commit (revert Ivan's micro-opt)
IVAN_COMMIT=$(git log --author=Ivan --pretty=format:%H -n 1 || true)
if [ -n "$IVAN_COMMIT" ]; then
        git revert --no-edit "$IVAN_COMMIT" || true
fi

# Create an experimental branch and squash-merge it
git checkout -b feature/squash-me
echo "// temp" > temp.txt
git add temp.txt
GIT_AUTHOR_NAME="Nina" GIT_AUTHOR_EMAIL="nina@example.com" git commit -m "temp file" --author="Nina <nina@example.com>" -q
git checkout "$MAIN_BRANCH"
git merge --squash feature/squash-me || true
GIT_AUTHOR_NAME="Oscar" GIT_AUTHOR_EMAIL="oscar@example.com" git commit -m "squash-merge feature/squash-me" --author="Oscar <oscar@example.com>" -q || true

# Final tag
git tag -a v0.2 -m "release v0.2" || true

cd "$ROOT_DIR"

echo "Running parser and aggregator again on $ROOT_DIR/$REPO_DIR"
python3 scripts/parse_git.py "$REPO_DIR" "$REPO_DIR/events.jsonl"
python3 scripts/aggregate_metrics.py "$REPO_DIR/events.jsonl" "$REPO_DIR/metrics.csv"

echo "Final outputs:"
ls -lh "$REPO_DIR/events.jsonl" "$REPO_DIR/metrics.csv" || true
echo "--- events (tail) ---"
tail -n 300 "$REPO_DIR/events.jsonl" || true
echo "--- metrics ---"
cat "$REPO_DIR/metrics.csv" || true