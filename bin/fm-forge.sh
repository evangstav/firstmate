#!/usr/bin/env bash
# Resolve a project's forge (where pull requests live) and the AXI tool that drives it.
# Forge is orthogonal to delivery mode: it answers "GitHub or Azure DevOps?", not
# "PR or local merge?". A project hosted on Azure DevOps marks itself with a +ado token
# in its data/projects.md registry bracket; the default is github.
#
# Registry bracket examples (data/projects.md):
#   - app [direct-PR]          -> github  (default)
#   - app [direct-PR +ado]     -> ado
#   - app [no-mistakes +yolo]  -> github  (+yolo is unrelated; forge stays github)
#
# Usage:
#   fm-forge.sh <project-name>        -> prints "github" | "ado"
#   fm-forge.sh tool <project-name>   -> prints the CLI: "gh-axi" | "ado-axi"
#
# An unknown/missing project falls back to github, matching the no-mistakes default.
set -eu

FM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REG="$FM_ROOT/data/projects.md"

WANT_TOOL=""
if [ "${1:-}" = "tool" ]; then
  WANT_TOOL=1
  shift
fi
NAME=${1:?usage: fm-forge.sh [tool] <project-name>}

forge=github
if [ -f "$REG" ]; then
  parsed=$(awk -v n="$NAME" '
    $1=="-" && $2==n {
      f="github";
      if ($3 ~ /^\[/) {
        s="";
        for (i=3; i<=NF; i++) { s = s (s==""?"":" ") $i; if ($i ~ /\]$/) break }
        gsub(/^\[|\]$/, "", s);             # strip the surrounding brackets
        if (s ~ /(^| )\+ado( |$)/) f="ado"; # a +ado token flips the forge
      }
      print f; exit
    }
  ' "$REG")
  [ -n "$parsed" ] && forge="$parsed"
fi

if [ -n "$WANT_TOOL" ]; then
  case "$forge" in
    ado) echo "ado-axi" ;;
    *) echo "gh-axi" ;;
  esac
else
  echo "$forge"
fi
