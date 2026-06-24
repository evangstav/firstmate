#!/usr/bin/env bash
# Behavior tests for the forge resolver. These tests do not touch the live fleet;
# they point fm-forge.sh at a fixture registry via FM_ROOT_OVERRIDE and assert the
# pure resolver contract: which forge a registry bracket selects and which AXI tool
# drives it. data/projects.md is gitignored, so the fixture is built here, not read.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORGE="$ROOT/bin/fm-forge.sh"
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

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-forge-tests.XXXXXX")
mkdir -p "$TMP_ROOT/data"
cat > "$TMP_ROOT/data/projects.md" <<'EOF'
## Fleet
- plainapp [no-mistakes] - a github-default project (added 2026-06-22)
- adoapp [direct-PR +ado] - an azure devops project (added 2026-06-22)
- taxis [no-mistakes +gitlab +to:develop] - a gitlab project (added 2026-06-22)
- yoloapp [direct-PR +yolo] - yolo is orthogonal; forge stays github (added 2026-06-22)
EOF

forge() {
  FM_ROOT_OVERRIDE="$TMP_ROOT" "$FORGE" "$@"
}

test_github_is_the_default() {
  [ "$(forge plainapp)" = "github" ] || fail "plain project should resolve to github, got: $(forge plainapp)"
  [ "$(forge tool plainapp)" = "gh-axi" ] || fail "plain project tool should be gh-axi, got: $(forge tool plainapp)"
  pass "github is the default forge (gh-axi)"
}

test_unknown_project_falls_back_to_github() {
  [ "$(forge nonesuch)" = "github" ] || fail "unknown project should fall back to github, got: $(forge nonesuch)"
  [ "$(forge tool nonesuch)" = "gh-axi" ] || fail "unknown project tool should be gh-axi, got: $(forge tool nonesuch)"
  pass "unknown project falls back to github"
}

test_ado_token_selects_ado_axi() {
  [ "$(forge adoapp)" = "ado" ] || fail "+ado project should resolve to ado, got: $(forge adoapp)"
  [ "$(forge tool adoapp)" = "ado-axi" ] || fail "+ado project tool should be ado-axi, got: $(forge tool adoapp)"
  pass "+ado token selects ado-axi"
}

test_gitlab_token_selects_gl_axi() {
  [ "$(forge taxis)" = "gitlab" ] || fail "+gitlab project should resolve to gitlab, got: $(forge taxis)"
  [ "$(forge tool taxis)" = "gl-axi" ] || fail "+gitlab project tool should be gl-axi, got: $(forge tool taxis)"
  pass "+gitlab token selects gl-axi"
}

test_yolo_does_not_change_forge() {
  [ "$(forge yoloapp)" = "github" ] || fail "+yolo should not change forge, got: $(forge yoloapp)"
  pass "+yolo is orthogonal; forge stays github"
}

test_github_is_the_default
test_unknown_project_falls_back_to_github
test_ado_token_selects_ado_axi
test_gitlab_token_selects_gl_axi
test_yolo_does_not_change_forge
