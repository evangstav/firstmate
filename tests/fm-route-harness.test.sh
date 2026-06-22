#!/usr/bin/env bash
# Behavior tests for deterministic harness routing. These tests do not spawn
# tmux/treehouse; they exercise the pure router contract used by fm-spawn.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROUTE="$ROOT/bin/fm-route-harness.sh"
TMP_ROOT=

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

cleanup() {
  if [ -n "${TMP_ROOT:-}" ]; then
    rm -rf "$TMP_ROOT"
  fi
}

trap cleanup EXIT

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-route-tests.XXXXXX")

write_brief() {
  local id=$1 text=$2 dir
  dir="$TMP_ROOT/data/$id"
  mkdir -p "$dir"
  printf '%s\n' "$text" > "$dir/brief.md"
}

route() {
  FM_ROOT_OVERRIDE="$TMP_ROOT" "$ROUTE" "$@"
}

test_document_scout_routes_to_claude() {
  local out
  write_brief p1doc-techsol-m3 'Reconcile P1 Technical Solution deliverable to as-built; produce Greek review copy and changelog.'
  out=$(route p1doc-techsol-m3 /repo/asset-mgmt-assistant-backend scout)
  [ "${out%%	*}" = "claude" ] || fail "document scout should route to claude, got: $out"
  printf '%s\n' "$out" | grep -F 'long-context scout' >/dev/null || fail "document scout reason missing"
  pass "document scout routes to claude"
}

test_code_ship_routes_to_codex() {
  local out
  write_brief fix-parser-k3 'Implement parser bugfix with regression tests and run no-mistakes follow-through.'
  out=$(route fix-parser-k3 /repo/ado-axi ship)
  [ "${out%%	*}" = "codex" ] || fail "code ship should route to codex, got: $out"
  printf '%s\n' "$out" | grep -F 'code/test task' >/dev/null || fail "code ship reason missing"
  pass "code ship routes to codex"
}

test_low_risk_exploration_does_not_use_unverified_deepseek() {
  local out
  write_brief inventory-a1 'Broad grep-heavy inventory: search files and summarize where feature flags are defined.'
  out=$(route inventory-a1 /repo/tooling scout)
  [ "${out%%	*}" = "opencode" ] || fail "low-risk exploration should route to verified opencode fallback, got: $out"
  printf '%s\n' "$out" | grep -F 'deepseek adapter unverified' >/dev/null || fail "DeepSeek fallback reason missing"
  pass "low-risk exploration uses verified opencode fallback"
}

test_security_sensitive_routes_to_claude() {
  local out
  write_brief auth-audit-b2 'Review auth, JWT, credentials, and destructive delete behavior before merge.'
  out=$(route auth-audit-b2 /repo/backend ship)
  [ "${out%%	*}" = "claude" ] || fail "security-sensitive task should route to claude, got: $out"
  printf '%s\n' "$out" | grep -F 'sensitive' >/dev/null || fail "security-sensitive reason missing"
  pass "security-sensitive task routes to claude"
}

test_explicit_harness_is_not_routed() {
  local out
  write_brief force-codex-z9 'Investigate long document.'
  out=$(route force-codex-z9 /repo/docs scout codex)
  [ "$out" = "codex	explicit harness override" ] || fail "explicit harness should win, got: $out"
  pass "explicit harness override wins"
}

test_document_scout_routes_to_claude
test_code_ship_routes_to_codex
test_low_risk_exploration_does_not_use_unverified_deepseek
test_security_sensitive_routes_to_claude
test_explicit_harness_is_not_routed
