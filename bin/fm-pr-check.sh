#!/usr/bin/env bash
# Record a PR-ready task: appends pr=<url> to state/<id>.meta and arms the
# watcher's merge poll by writing state/<id>.check.sh, which prints one line iff
# the PR is merged (the watcher's check contract: output = wake firstmate,
# silence = keep sleeping).
#
# The watcher runs the generated check.sh from the firstmate repo root with no
# cd, but the GitLab (gl-axi) and Azure DevOps (ado-axi) CLIs resolve the
# host/project from the origin of the current directory. So those branches cd
# into the task's project clone (the project= line in state/<id>.meta) before
# invoking the forge CLI; if that path is gone (e.g. a torn-down task left a
# stray poll), the generated script exits quietly. The GitHub branch uses
# `gh pr view <full-url>`, which is self-contained and needs no cwd.
# Usage: fm-pr-check.sh <task-id> <pr-url>
set -eu

FM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$FM_ROOT/bin/fm-guard.sh" || true
ID=$1
URL=$2

META="$FM_ROOT/state/$ID.meta"
if [ -f "$META" ] && ! grep -qxF "pr=$URL" "$META"; then
  echo "pr=$URL" >> "$META"
fi

# Project clone path, for forge CLIs (gl-axi/ado-axi) that resolve the
# host/project from the cwd's origin.
PROJ=""
[ -f "$META" ] && PROJ=$(sed -n 's/^project=//p' "$META" | head -1)

# Forge-aware merge poll: GitHub PRs report state=MERGED; Azure DevOps PRs report
# status=completed; GitLab MRs report state=merged. The URL shape tells them apart
# (no registry lookup needed here).
case "$URL" in
  *dev.azure.com*|*visualstudio.com*)
    PRID="${URL##*/}"
    cat > "$FM_ROOT/state/$ID.check.sh" <<EOF
[ -n "$PROJ" ] && cd "$PROJ" 2>/dev/null || exit 0
status=\$(ado-axi pr show "$PRID" 2>/dev/null | sed -n 's/^[[:space:]]*status:[[:space:]]*//p' | head -1)
[ "\$status" = "completed" ] && echo "merged"
EOF
    ;;
  */-/merge_requests/*)
    MRID="${URL##*/}"
    cat > "$FM_ROOT/state/$ID.check.sh" <<EOF
[ -n "$PROJ" ] && cd "$PROJ" 2>/dev/null || exit 0
state=\$(gl-axi mr show "$MRID" 2>/dev/null | sed -n 's/^[[:space:]]*state:[[:space:]]*//p' | head -1)
[ "\$state" = "merged" ] && echo "merged"
EOF
    ;;
  *)
    cat > "$FM_ROOT/state/$ID.check.sh" <<EOF
state=\$(gh pr view "$URL" --json state -q .state 2>/dev/null)
[ "\$state" = "MERGED" ] && echo "merged"
EOF
    ;;
esac
echo "armed: state/$ID.check.sh polls $URL"
