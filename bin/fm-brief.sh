#!/usr/bin/env bash
# Scaffold a crewmate brief at data/<task-id>/brief.md with the standard
# Setup/Rules/Definition-of-done contract filled in. Firstmate then replaces the
# {TASK} placeholder with the task description, acceptance criteria, and context,
# and may adjust other sections when the task genuinely deviates (e.g. working an
# existing external PR instead of shipping a new one).
# Usage: fm-brief.sh <task-id> <repo-name> [--scout]
#   --scout writes the scout contract instead: the deliverable is a report at
#   data/<task-id>/report.md (no branch, no push, no PR) and the worktree is scratch.
# For ship tasks, the definition of done is shaped by the project's delivery mode
# (data/projects.md via fm-project-mode.sh; see AGENTS.md sections 6-7):
#   no-mistakes  implement -> /no-mistakes pipeline -> PR -> captain merge (default)
#   direct-PR    implement -> push + open PR via gh-axi (no pipeline) -> captain merge
#   local-only   implement on branch, stop and report "ready in branch" (no push/PR);
#                firstmate reviews, captain approves, firstmate merges to local main
# Scout tasks ignore mode - their deliverable is a report, not a merge.
# Ship tasks include a project-memory section so durable project-intrinsic
# learnings can be committed to AGENTS.md through the project's delivery path.
# Refuses to overwrite an existing brief.
set -eu

FM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KIND=ship
POS=()
for a in "$@"; do
  case "$a" in
    --scout) KIND=scout ;;
    *) POS+=("$a") ;;
  esac
done
ID=${POS[0]}
REPO=${POS[1]}

# Forge tool: gh-axi for GitHub projects, ado-axi for Azure DevOps (+ado), gl-axi for GitLab (+gitlab).
FORGE_TOOL=$("$FM_ROOT/bin/fm-forge.sh" tool "$REPO" 2>/dev/null || echo gh-axi)
FORGE=$("$FM_ROOT/bin/fm-forge.sh" "$REPO" 2>/dev/null || echo github)
# Target/deployable branch - NOT always main (e.g. the container-app repos deploy from prd).
TARGET=$("$FM_ROOT/bin/fm-target-branch.sh" "$REPO" 2>/dev/null || echo main)
# no-mistakes steps to skip: always the upstream steps (we PR via the forge tool, not no-mistakes);
# plus any per-repo extras from a `+skip:<steps>` registry token (e.g. `+skip:test` for a repo
# with no test suite, so its gate runs review/document/lint without a failing test step).
NM_SKIP="push,pr,ci"
NM_EXTRA=$(awk -v n="$REPO" '$1=="-" && $2==n { for(i=3;i<=NF;i++) if($i ~ /^\+skip:/){t=$i; sub(/^\+skip:/,"",t); sub(/]$/,"",t); print t; exit} }' "$FM_ROOT/data/projects.md" 2>/dev/null || true)
[ -n "$NM_EXTRA" ] && NM_SKIP="$NM_SKIP,$NM_EXTRA"
# PRs target the project's deployable branch; the create command differs by forge.
case "$FORGE" in
  ado)    PR_CMD="ado-axi pr create --target $TARGET --title \"<concise title>\" --description \"<one-line summary>\"" ;;
  gitlab) PR_CMD="gl-axi mr create --target $TARGET --title \"<concise title>\" --description \"<one-line summary>\"" ;;
  *)      PR_CMD="gh-axi pr create --base $TARGET --fill" ;;
esac

BRIEF="$FM_ROOT/data/$ID/brief.md"
[ -e "$BRIEF" ] && { echo "error: $BRIEF already exists" >&2; exit 1; }
mkdir -p "$FM_ROOT/data/$ID"

if [ "$KIND" = scout ]; then
cat > "$BRIEF" <<EOF
You are a crewmate: an autonomous worker agent managed by firstmate. Work on your own; do not wait for a human.

# Task
{TASK}

# Setup
You are in a disposable git worktree of $REPO, at a detached HEAD on a clean default branch.
This is a SCOUT task: the deliverable is a written report, not a PR.
The worktree is your laboratory - install, run, edit, and make scratch commits freely; all of it is discarded at teardown.
The report is the only thing that survives, so anything worth keeping must be in it.
Create the report file early with headings, then fill it incrementally as evidence appears; do not save all writing for the final turn.

# Rules
1. Never push to any remote and never open a PR.
2. Stay inside this worktree; the only files you may write outside it are the report and the status file below.
3. Use $FORGE_TOOL for pull-request / forge operations and chrome-devtools-axi for browser operations.
4. Keep project-specific facts in the project. If you discover durable project-intrinsic knowledge, record it as a recommendation in the report; do not edit project AGENTS.md during a scout.
5. For raw user, customer, production, analytics, log, or trace data: inspect schemas, counts, and aggregate signals first. Avoid quoting raw content by default. Use redacted examples or restricted pointers unless raw content is necessary and explicitly allowed by the task.
6. Report status by appending one line:
   \`echo "{state}: {one short line}" >> $FM_ROOT/state/$ID.status\`
   States: working, needs-decision, blocked, done, failed.
   Each append wakes firstmate, so report sparingly: only phase changes a supervisor
   would act on and the needs-decision/blocked/done/failed states. No step-by-step
   FYI progress lines; firstmate reads your pane for that.
7. If you hit the same obstacle twice, append \`blocked: {why}\` and stop; firstmate will help.
8. If a decision belongs to a human (product choices, destructive actions), stop and surface it.
   For a **design choice** (architecture, approach, tradeoffs among viable options), first lay the options out with \`lavish-axi\` as a reviewable artifact — authored in the human-doc visual style (inline \`~/.agents/skills/human-doc/assets/wiki.css\`, follow \`assets/template.html\`: meta bar, TOC, tables, inline SVG, no JS) — then append \`needs-decision: {one line + the lavish link}\`. For a simple yes/no, a one-line \`needs-decision: {summary}\` is enough. Firstmate replies with the decision.

# Definition of done
Write your findings to \`$FM_ROOT/data/$ID/report.md\`.
The report must stand alone: what you did, what you found, the evidence (commands run, output, file:line references), and what you recommend.
When there are multiple findings, source records, candidate fixes, or follow-up tasks, use tables with stable identifiers so another worker can act on the report without redoing the scout.
Include a short "Next actions" section that separates project-specific recommendations from reusable workflow lessons, if any.
When the report is complete, append \`done: {one-line conclusion}\` to the status file and stop.
If your findings reveal work that should ship (e.g. you reproduced a bug and the fix is clear), say so in the report; firstmate may promote this task in place, and you would then receive mode-specific ship instructions as a follow-up message.
EOF
echo "scaffolded: $BRIEF (scout; replace {TASK})"
exit 0
fi

# Ship task: shape Setup / Rule 1 / Definition of done by the project's delivery mode.
# yolo does not affect the brief (it governs firstmate's approval behaviour), so discard it.
read -r MODE _ <<EOF
$("$FM_ROOT/bin/fm-project-mode.sh" "$REPO")
EOF

case "$MODE" in
  direct-PR)
    SETUP2=""
    RULE1='1. Never push to the default branch (push only your `fm/'"$ID"'` branch). Never merge a PR.'
    DOD=$(cat <<EOF
# Definition of done
This project ships **direct-PR**: you raise the PR yourself, without the no-mistakes pipeline.
The task is complete only when committed on your branch.
When it is implemented and committed, push your branch and open a pull request **against \`$TARGET\`**:
    $PR_CMD
Then append \`done: PR {url}\` to the status file and stop.
Do NOT run /no-mistakes. The captain reviews and merges the PR; firstmate relays it.
EOF
)
    ;;
  local-only)
    SETUP2=""
    RULE1="1. Never push to any remote and never open a PR. Work only on your \`fm/$ID\` branch; firstmate handles the merge into local \`main\`."
    DOD=$(cat <<EOF
# Definition of done
This project ships **local-only**: no remote, no PR, no pipeline.
The task is complete only when committed on your branch \`fm/$ID\`. Do NOT push, do NOT open a PR, do NOT merge.
Keep your branch a clean fast-forward onto the current default branch - if it has advanced, rebase onto it so the eventual merge stays a fast-forward.
When it is implemented and committed, append \`done: ready in branch fm/$ID\` to the status file and stop.
Firstmate then reviews your branch diff, the captain approves, and firstmate merges it into local \`main\`.
EOF
)
    ;;
  *)  # no-mistakes (default): validate locally, then open a PR against the deployable branch via the forge tool
    SETUP2="
2. Run \`no-mistakes doctor\`; if it reports the repo is not initialized here, run \`no-mistakes init\`."
    RULE1="1. Never push to \`$TARGET\` (the deployable branch) and never merge a PR. Work only on your \`fm/$ID\` branch."
    DOD=$(cat <<EOF
# Definition of done
Implement on your branch \`fm/$ID\` (off \`$TARGET\`) and commit only your task's changes.
1. **Validate** with the no-mistakes gate (review, test, document, lint — no push/PR/CI):
   \`no-mistakes axi run --intent "<what the task set out to accomplish, in plain words>" --skip=$NM_SKIP --yes\`
   Fix the actionable findings it surfaces on the same branch; for ask-user findings, append \`needs-decision\` and stop (rule 6).
2. When the gate is green, open a pull request **against \`$TARGET\`** with the forge tool:
   \`$PR_CMD\`
3. Append \`done: PR {url}\` to the status file and stop. Do NOT merge — the captain reviews and merges; firstmate relays.
EOF
)
    ;;
esac

cat > "$BRIEF" <<EOF
You are a crewmate: an autonomous worker agent managed by firstmate. Work on your own; do not wait for a human.

# Task
{TASK}

# Setup
You are in a disposable git worktree of $REPO, at a detached HEAD on a clean default branch.
1. First action: create your branch: \`git checkout -b fm/$ID\`$SETUP2

# Rules
$RULE1
2. Stay inside this worktree; modify nothing outside it.
3. Use $FORGE_TOOL for pull-request / forge operations and chrome-devtools-axi for browser operations.
4. Report status by appending one line:
   \`echo "{state}: {one short line}" >> $FM_ROOT/state/$ID.status\`
   States: working, needs-decision, blocked, done, failed.
   Each append wakes firstmate, so report sparingly: only phase changes a supervisor
   would act on (setup done, bug reproduced, fix implemented, validation passed) and the
   needs-decision/blocked/done/failed states. No step-by-step FYI progress lines;
   firstmate reads your pane for that.
5. If you hit the same obstacle twice, append \`blocked: {why}\` and stop; firstmate will help.
6. If a decision belongs to a human (product choices, destructive actions, ask-user findings), stop and surface it.
   For a **design choice** (architecture, approach, tradeoffs among viable options), first lay the options out with \`lavish-axi\` as a reviewable artifact — authored in the human-doc visual style (inline \`~/.agents/skills/human-doc/assets/wiki.css\`, follow \`assets/template.html\`: meta bar, TOC, tables, inline SVG, no JS) — then append \`needs-decision: {one line + the lavish link}\`. For a simple yes/no, a one-line \`needs-decision: {summary}\` is enough. Firstmate replies with the decision.

# Project memory
If \`AGENTS.md\` or \`CLAUDE.md\` already exists, or if this task produced durable project-intrinsic knowledge, run \`$FM_ROOT/bin/fm-ensure-agents-md.sh .\` in the worktree.
If this task produced durable project-intrinsic knowledge, record it in \`AGENTS.md\` as part of your change.
Keep it proportionate: skip \`AGENTS.md\` edits for trivial tasks that produced no durable project knowledge.

$DOD
EOF
echo "scaffolded: $BRIEF (ship, mode=$MODE; replace {TASK})"
