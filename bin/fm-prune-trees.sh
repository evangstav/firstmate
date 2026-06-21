#!/usr/bin/env bash
# Reclaim treehouse pool slots firstmate no longer needs - the gap fm-fleet-sync leaves
# (it prunes git clones and branches, not treehouse pools). Two kinds of slot:
#
#   stale  - a returned worktree with no running process / owner reservation, no
#            uncommitted changes, and a HEAD already merged into the default branch.
#            Fully verifiable as safe; pruned automatically.
#   orphan - a slot whose backing repository was deleted (e.g. a project removed from
#            disk). treehouse cannot verify these (the repo is gone, so it cannot check
#            for unmerged/uncommitted work), so they are REPORTED, never auto-removed.
#            Pass --orphans to delete them deliberately.
#
# Everything leans on `treehouse prune`, which owns the safety checks: it never removes a
# slot with a running process, an owner reservation, uncommitted changes, or an unmerged
# HEAD (verified live - it correctly skips an in-flight crewmate's worktree). Best-effort
# and non-fatal, like fm-fleet-sync.
#
# Usage:
#   fm-prune-trees.sh              prune stale slots; report orphans (do not delete)
#   fm-prune-trees.sh --orphans    prune stale AND deleted-repo orphans
#   fm-prune-trees.sh --dry-run    list all candidates, delete nothing
#   fm-prune-trees.sh --bootstrap  quiet; auto-prune stale, emit one TREE_ORPHAN: line iff orphans exist
set -u

command -v treehouse >/dev/null 2>&1 || exit 0

# --all sweeps every managed pool under the user-level treehouse root. treehouse requires
# the configured root to be unset or absolute for a global sweep; a pool with a relative
# custom root is simply skipped, and any error is swallowed (best-effort).
orphans_exist() {
  # An orphan shows up only when --prune-orphans is added, so the two candidate listings
  # differ exactly when deleted-repo slots exist - no dependence on treehouse's wording.
  local base orph
  base=$(treehouse prune --all 2>&1 || true)
  orph=$(treehouse prune --all --prune-orphans 2>&1 || true)
  [ "$base" != "$orph" ]
}

case "${1:-}" in
  --bootstrap)
    treehouse prune --all --yes >/dev/null 2>&1 || true
    if orphans_exist; then
      echo "TREE_ORPHAN: treehouse has worktree slots whose backing repo was deleted; run bin/fm-prune-trees.sh --orphans to reclaim them"
    fi
    ;;
  --orphans)
    treehouse prune --all --prune-orphans --yes 2>&1 || true
    ;;
  --dry-run)
    treehouse prune --all --prune-orphans 2>&1 || true
    ;;
  "")
    echo "== stale worktree slots (auto-pruned) =="
    treehouse prune --all --yes 2>&1 || true
    echo "== orphan slots (backing repo deleted; NOT auto-removed) =="
    if orphans_exist; then
      treehouse prune --all --prune-orphans 2>&1 || true
      echo "  run 'bin/fm-prune-trees.sh --orphans' to remove them"
    else
      echo "  none"
    fi
    ;;
  *)
    echo "usage: fm-prune-trees.sh [--orphans|--dry-run|--bootstrap]" >&2
    exit 2
    ;;
esac
exit 0
