#!/usr/bin/env bash
# Locate and run the fmw work-store CLI, so the rest of firstmate doesn't care where
# it's installed. Resolution order: $FM_WORK_BIN, `fmw` on PATH, then the standard
# checkout at ~/workspace/fmw/fmw.
# Usage: fm-work.sh <fmw args...>   (e.g. fm-work.sh ready --project admie-project)
set -eu

BIN="${FM_WORK_BIN:-}"
[ -n "$BIN" ] || BIN=$(command -v fmw 2>/dev/null || true)
if [ -z "$BIN" ]; then
  for c in "$HOME/workspace/fmw/fmw" "$HOME/.local/bin/fmw"; do
    [ -x "$c" ] && BIN="$c" && break
  done
fi
[ -n "$BIN" ] || { echo "fm-work: fmw not found (set FM_WORK_BIN, put fmw on PATH, or install at ~/workspace/fmw)" >&2; exit 127; }

exec "$BIN" "$@"
