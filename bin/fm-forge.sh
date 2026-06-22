#!/usr/bin/env bash
# Resolve a project's forge (where pull requests live) and the AXI tool that drives it.
# Forge is orthogonal to delivery mode: it answers "GitHub, Azure DevOps, or GitLab?", not
# "PR or local merge?". A project hosted on Azure DevOps marks itself with a +ado token, one
# hosted on GitLab with a +gitlab token, in its data/projects.md registry bracket; the
# default is github.
#
# Registry bracket examples (data/projects.md):
#   - app [direct-PR]          -> github  (default)
#   - app [direct-PR +ado]     -> ado
#   - app [no-mistakes +gitlab]-> gitlab
#   - app [no-mistakes +yolo]  -> github  (+yolo is unrelated; forge stays github)
#
# Usage:
#   fm-forge.sh <project-name>        -> prints "github" | "ado" | "gitlab"
#   fm-forge.sh tool <project-name>   -> prints the CLI: "gh-axi" | "ado-axi" | "gl-axi"
#
# An unknown/missing project falls back to github, matching the no-mistakes default.
set -eu

FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
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
        if (s ~ /(^| )\+ado( |$)/) f="ado";       # a +ado token flips the forge to Azure DevOps
        if (s ~ /(^| )\+gitlab( |$)/) f="gitlab"; # a +gitlab token flips the forge to GitLab
      }
      print f; exit
    }
  ' "$REG")
  [ -n "$parsed" ] && forge="$parsed"
fi

if [ -n "$WANT_TOOL" ]; then
  case "$forge" in
    ado) echo "ado-axi" ;;
    gitlab) echo "gl-axi" ;;
    *) echo "gh-axi" ;;
  esac
else
  echo "$forge"
fi
