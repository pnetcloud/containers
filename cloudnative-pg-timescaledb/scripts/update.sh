#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/command.sh"
controlled_unavailable "make update" "Story 2.3" "Implement deterministic resolver update orchestration before using this target."
