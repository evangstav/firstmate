#!/usr/bin/env bash
# Record a PR-ready task: appends pr=<url> to state/<id>.meta and arms the
# watcher's merge poll by writing state/<id>.check.sh, which prints one line iff
# the PR is merged (the watcher's check contract: output = wake firstmate,
# silence = keep sleeping).
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

# Forge-aware merge poll: GitHub PRs report state=MERGED; Azure DevOps PRs report
# status=completed; GitLab MRs report state=merged. The URL shape tells them apart
# (no registry lookup needed here).
case "$URL" in
  *dev.azure.com*|*visualstudio.com*)
    PRID="${URL##*/}"
    cat > "$FM_ROOT/state/$ID.check.sh" <<EOF
status=\$(ado-axi pr show "$PRID" 2>/dev/null | sed -n 's/^[[:space:]]*status:[[:space:]]*//p' | head -1)
[ "\$status" = "completed" ] && echo "merged"
EOF
    ;;
  */-/merge_requests/*)
    MRID="${URL##*/}"
    cat > "$FM_ROOT/state/$ID.check.sh" <<EOF
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
