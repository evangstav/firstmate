#!/usr/bin/env bash
# Assign an fmw work item to a team member and mirror it to the project's external tracker
# (ADO Boards / GitHub Issues) so the assignee can see it — the captain's standing preference
# (data/captain.md). Assigning to the captain himself stays local (the mirror is a no-op).
#
# Usage: fm-assign.sh <issue-id> <repo-path> <person> [--dry-run]
#   --dry-run: still set the (local) assignee, but only PREVIEW the external mirror.
set -eu

FM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ID=${1:?usage: fm-assign.sh <issue-id> <repo-path> <person> [--dry-run]}
REPO=${2:?usage: fm-assign.sh <issue-id> <repo-path> <person> [--dry-run]}
PERSON=${3:?usage: fm-assign.sh <issue-id> <repo-path> <person> [--dry-run]}
DRY=""
[ "${4:-}" = "--dry-run" ] && DRY="--dry-run"

[ -d "$REPO" ] || { echo "fm-assign: repo path not found: $REPO" >&2; exit 1; }

# Set the assignee (local, cheap, reversible). The store resolves by walking up from the repo.
( cd "$REPO" && "$FM_ROOT/bin/fm-work.sh" update "$ID" --assignee "$PERSON" >/dev/null )

# Mirror to the external tracker (no-op for captain/unassigned/already-mirrored).
python3 "$FM_ROOT/bin/fm-mirror.py" "$ID" "$REPO" $DRY
