#!/usr/bin/env bash
# Deterministically choose a crewmate harness for one task.
# Prints: <harness><TAB><reason>
# Usage: fm-route-harness.sh <task-id> <repo-path> <ship|scout> [explicit-harness]
set -eu

FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

ID=${1:?usage: fm-route-harness.sh <task-id> <repo-path> <kind> [explicit-harness]}
REPO=${2:?usage: fm-route-harness.sh <task-id> <repo-path> <kind> [explicit-harness]}
KIND=${3:?usage: fm-route-harness.sh <task-id> <repo-path> <kind> [explicit-harness]}
EXPLICIT=${4:-}

if [ -n "$EXPLICIT" ]; then
  printf '%s\t%s\n' "$EXPLICIT" "explicit harness override"
  exit 0
fi

BRIEF="$FM_ROOT/data/$ID/brief.md"
TEXT="$ID $KIND $(basename "$REPO")"
if [ -f "$BRIEF" ]; then
  TEXT="$TEXT $(tr '\n' ' ' < "$BRIEF")"
fi
TEXT=$(printf '%s' "$TEXT" | tr '[:upper:]' '[:lower:]')

contains_any() {
  local needle
  for needle in "$@"; do
    case "$TEXT" in
      *"$needle"*) return 0 ;;
    esac
  done
  return 1
}

if contains_any auth jwt credential secret destructive "delete" "external tracker" "security" "rbac"; then
  printf '%s\t%s\n' claude "sensitive task"
elif [ "$KIND" = scout ] && contains_any "grep-heavy" "inventory" "search files" "where feature" "broad exploration" "mechanical cleanup"; then
  printf '%s\t%s\n' opencode "low-risk exploration; deepseek adapter unverified"
elif [ "$KIND" = scout ] && contains_any document deliverable reconcile "review copy" changelog architecture audit report stakeholder "long-context"; then
  printf '%s\t%s\n' claude "long-context scout"
elif contains_any implement bugfix "bug fix" regression test tests "no-mistakes" debug parser code lint shellcheck; then
  printf '%s\t%s\n' codex "code/test task"
elif [ "$KIND" = ship ]; then
  printf '%s\t%s\n' codex "default ship task"
else
  printf '%s\t%s\n' claude "default scout task"
fi
