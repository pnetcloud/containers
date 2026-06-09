#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/command.sh"
controlled_unavailable "make matrix" "Story 4.1" "Implement generated matrix output before using this target."
