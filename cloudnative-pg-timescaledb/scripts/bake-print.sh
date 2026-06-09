#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/command.sh"
controlled_unavailable "make bake-print" "Story 3.3" "Implement local build and Bake execution before using this target."
