#!/usr/bin/env bash
set -Eeuo pipefail

diag() {
  local command="$1"
  local artifact="$2"
  local expected="$3"
  local actual="$4"
  local remediation="$5"
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' \
    "$command" "$artifact" "$expected" "$actual" "$remediation" >&2
}
