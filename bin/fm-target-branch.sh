#!/usr/bin/env bash
# Resolve the branch a project's pull requests target and crewmates branch off of — its
# deployable / integration branch, which is NOT always `main` (e.g. the ADMIE container-app
# repos deploy from `prd`).
#
# Resolution order:
#   1. A `+to:<branch>` token in the project's data/projects.md registry bracket
#      (e.g. `[no-mistakes +ado +to:prd]`) — explicit override.
#   2. The repo's own default branch (`origin/HEAD`) — the ADO/GitHub repo default, which is
#      the deployable branch in practice (prd for the container-app repos, main for the rest).
#   3. `main` as a last resort.
#
# Usage: fm-target-branch.sh <repo-path>
set -eu

FM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REG="$FM_ROOT/data/projects.md"
REPO=${1:?usage: fm-target-branch.sh <repo-path>}
NAME=$(basename "$(cd "$REPO" 2>/dev/null && pwd || echo "$REPO")")

# 1. registry override token
if [ -f "$REG" ]; then
  override=$(awk -v n="$NAME" '
    $1=="-" && $2==n {
      for (i=3; i<=NF; i++) if ($i ~ /^\+to:/) { t=$i; sub(/^\+to:/, "", t); sub(/]$/, "", t); print t; exit }
    }
  ' "$REG")
  if [ -n "$override" ]; then
    echo "$override"
    exit 0
  fi
fi

# 2. the repo's default branch (origin/HEAD)
if [ -d "$REPO" ]; then
  head=$(git -C "$REPO" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)
  if [ -z "$head" ]; then
    head=$(git -C "$REPO" remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p' | head -1 || true)
  fi
  if [ -n "$head" ]; then
    echo "$head"
    exit 0
  fi
fi

# 3. fallback
echo "main"
