#!/usr/bin/env bash
# Dispatch an fmw work item as a firstmate task: the work store is the durable source
# of work; this bridges one ready issue into the spawn machinery.
#
# It reads the issue from the work store (resolved by walking up from the repo path),
# scaffolds a brief seeded with the issue's title + body, spawns a crewmate against the
# repo, marks the issue in_progress, and records work=<id> in the task meta so the issue
# is closed automatically when the task lands (fm-teardown).
#
# The fmw issue id doubles as the firstmate task id, so window/brief/state all trace
# back to one id.
#
# Usage: fm-dispatch.sh <issue-id> <repo-path> [harness] [--scout]
set -eu

FM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$FM_ROOT/bin/fm-work.sh"

ID=${1:?usage: fm-dispatch.sh <issue-id> <repo-path> [harness] [--scout]}
REPO=${2:?usage: fm-dispatch.sh <issue-id> <repo-path> [harness] [--scout]}
shift 2
PASS=("$@")  # harness and/or --scout, forwarded to brief/spawn

[ -d "$REPO" ] || { echo "fm-dispatch: repo path not found: $REPO" >&2; exit 1; }

SCOUT=""
for a in ${PASS[@]+"${PASS[@]}"}; do [ "$a" = "--scout" ] && SCOUT=1; done

# Pull the issue (store resolves by walking up from the repo to the project's .work).
ISSUE_JSON=$( cd "$REPO" && "$WORK" show "$ID" --json ) || {
  echo "fm-dispatch: no work item '$ID' in the store for $REPO" >&2; exit 1; }

IFS=$'\t' read -r TITLE BODY < <(printf '%s' "$ISSUE_JSON" | python3 -c '
import sys, json
d = json.load(sys.stdin)
# title on first line, body (newlines escaped) after a tab
print(d.get("title","").replace("\n"," "), (d.get("body","") or "").replace("\n","\\n"), sep="\t")
')

# Scaffold the standard brief, then replace {TASK} with the issue content.
REPO_NAME=$(basename "$REPO")
"$FM_ROOT/bin/fm-brief.sh" "$ID" "$REPO_NAME" ${PASS[@]+"${PASS[@]}"} >/dev/null
BRIEF="$FM_ROOT/data/$ID/brief.md"
TASK_TEXT="Implement work item \`$ID\`: $TITLE

$(printf '%b' "$BODY")

When this lands, firstmate marks \`$ID\` done in the work store."
python3 - "$BRIEF" <<PYEOF
import sys
p = sys.argv[1]
task = """$TASK_TEXT"""
s = open(p).read().replace("{TASK}", task, 1)
open(p, "w").write(s)
PYEOF

# Spawn against the repo (forge/mode resolved per-project inside fm-spawn).
"$FM_ROOT/bin/fm-spawn.sh" "$ID" "$REPO" ${PASS[@]+"${PASS[@]}"}

# Record the work-store link and flip the issue to in_progress.
echo "work=$ID" >> "$FM_ROOT/state/$ID.meta"
[ -n "$SCOUT" ] || ( cd "$REPO" && "$WORK" update "$ID" --status in_progress >/dev/null 2>&1 || true )

echo "dispatched work item $ID -> $REPO_NAME"
