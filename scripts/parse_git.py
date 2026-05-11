#!/usr/bin/env python3
"""Parse a local git repository and emit per-function events (JSON lines).

Usage:
  pip install -r ../requirements.txt
  python scripts/parse_git.py /path/to/repo events.jsonl

This is a light prototype using PyDriller and a heuristic function extractor.
Replace with tree-sitter for production accuracy.
"""
import sys
import pathlib
import json
import re
from datetime import datetime
from dateutil import tz
# Support both PyDriller v1 (RepositoryMining) and v2+ (Repository)
try:
    from pydriller import RepositoryMining as _RM
except Exception:
    _RM = None

try:
    from pydriller import Repository as _Repo
except Exception:
    _Repo = None

if _RM is None and _Repo is None:
    # try submodule import locations
    try:
        from pydriller.repository_mining import RepositoryMining as _RM
    except Exception:
        _RM = None
    try:
        from pydriller.repository import Repository as _Repo
    except Exception:
        _Repo = None

if _RM is None and _Repo is None:
    raise ImportError(
        "Unable to import RepositoryMining or Repository from pydriller.\n"
        "Run diagnostics in your venv to inspect the installed package and version.\n"
    )


def iter_commits_for_repo(path, file_types=None):
    """Return an iterator over commits that works with both PyDriller APIs."""
    file_types = file_types or ['.py', '.js', '.ts', '.tsx', '.go']
    # Prefer RepositoryMining when available (older API)
    if _RM is not None:
        try:
            return _RM(path, only_modifications_with_file_types=file_types).traverse_commits()
        except TypeError:
            # fallback to positional constructor
            return _RM(path).traverse_commits()
    # Otherwise use Repository (newer API)
    if _Repo is not None:
        try:
            return _Repo(path, only_modifications_with_file_types=file_types).traverse_commits()
        except TypeError:
            return _Repo(path).traverse_commits()
    raise RuntimeError('No compatible PyDriller API available')


def extract_functions_simple(file_path, content):
    funcs = []
    if not content:
        return funcs
    try:
        if file_path.endswith('.py'):
            pattern = re.compile(r'^(def|class)\s+([A-Za-z0-9_]+)\s*(\(.*\))?:', re.MULTILINE)
            for m in pattern.finditer(content):
                kind, name, sig = m.groups()
                funcs.append(f"{kind} {name}")
        else:
            # JS/TS/Go/others heuristics
            pattern1 = re.compile(r'function\s+([A-Za-z0-9_]+)\s*\(', re.MULTILINE)
            pattern2 = re.compile(r'([A-Za-z0-9_]+)\s*=\s*\(.*\)\s*=>', re.MULTILINE)
            for m in pattern1.finditer(content):
                name = m.group(1)
                funcs.append(f"func {name}")
            for m in pattern2.finditer(content):
                name = m.group(1)
                funcs.append(f"func {name}")
    except Exception:
        pass
    return list(dict.fromkeys(funcs))


def main():
    repo = sys.argv[1] if len(sys.argv) > 1 else '.'
    out = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else pathlib.Path('events.jsonl')

    out.parent.mkdir(parents=True, exist_ok=True)
    def _get_modifications(c):
        """Return an iterable of modification-like objects for a commit across PyDriller versions."""
        for attr in ('modifications', 'modified_files', 'files'):
            mods = getattr(c, attr, None)
            if mods:
                return mods
        # last-ditch: try to find any attr that's a list of objects with new_path
        for name in dir(c):
            val = getattr(c, name)
            try:
                if isinstance(val, list) and val and hasattr(val[0], 'new_path'):
                    return val
            except Exception:
                continue
        return []

    with out.open('w') as fo:
        for commit in iter_commits_for_repo(repo, file_types=['.py', '.js', '.ts', '.tsx', '.go']):
            commit_time = getattr(commit, 'author_date', None)
            if hasattr(commit_time, 'astimezone'):
                commit_time = commit_time.astimezone(tz.tzlocal()).isoformat()
            else:
                commit_time = str(commit_time)
            sha = getattr(commit, 'hash', getattr(commit, 'commit_hash', None))
            author = None
            try:
                author = commit.author.name
            except Exception:
                try:
                    author = getattr(commit, 'author', None) or getattr(commit, 'author_name', None)
                except Exception:
                    author = None

            for mod in _get_modifications(commit):
                path = getattr(mod, 'new_path', None) or getattr(mod, 'old_path', None) or ''
                new = ''
                try:
                    new = getattr(mod, 'source_code', None) or getattr(mod, 'source', None) or ''
                except Exception:
                    new = ''
                funcs = extract_functions_simple(path, new)
                # change_type may be an enum or string
                ct = getattr(mod, 'change_type', None)
                try:
                    ct_val = ct.name if hasattr(ct, 'name') else str(ct)
                except Exception:
                    ct_val = str(ct)
                for f in funcs:
                    event = {
                        'timestamp': commit_time,
                        'commit': sha,
                        'author': author,
                        'file': path,
                        'function': f,
                        'change_type': ct_val
                    }
                    fo.write(json.dumps(event) + '\n')
    print(f'Wrote events -> {out}')


if __name__ == '__main__':
    main()
