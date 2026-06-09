#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/command.sh"
controlled_unavailable "make catalog" "Story 4.6" "Implement digest-aware catalog generation before using this target."
