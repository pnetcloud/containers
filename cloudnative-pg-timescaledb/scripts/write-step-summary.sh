#!/usr/bin/env bash
set -Eeuo pipefail

template=""
output="${GITHUB_STEP_SUMMARY:-}"
required=()
required_success=()
require_failure_reason=false

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

while (($#)); do
  case "$1" in
    --template)
      [[ $# -ge 2 ]] || { diag write-step-summary arguments '--template has a value' missing 'Pass --template <path>.'; exit 64; }
      template="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || { diag write-step-summary arguments '--output has a value' missing 'Pass --output <path>.'; exit 64; }
      output="$2"
      shift 2
      ;;
    --require)
      [[ $# -ge 2 ]] || { diag write-step-summary arguments '--require has a value' missing 'Pass --require <ENV_NAME>.'; exit 64; }
      required+=("$2")
      shift 2
      ;;
    --require-success)
      [[ $# -ge 2 ]] || { diag write-step-summary arguments '--require-success has a value' missing 'Pass --require-success <ENV_NAME>.'; exit 64; }
      required_success+=("$2")
      shift 2
      ;;
    --require-failure-reason)
      require_failure_reason=true
      shift
      ;;
    *)
      diag write-step-summary arguments 'known option' "$1" 'Use --template, --output, --require, --require-success, or --require-failure-reason.'
      exit 64
      ;;
  esac
done

[[ -n "${template}" && -f "${template}" ]] || { diag write-step-summary "${template:-template}" 'summary template exists' missing 'Create the summary template before wiring workflows.'; exit 1; }
[[ -n "${output}" ]] || { diag write-step-summary GITHUB_STEP_SUMMARY 'summary output path is set' missing 'Run inside GitHub Actions or pass --output.'; exit 1; }

for key in "${required[@]}"; do
  value="${!key:-}"
  if [[ -z "${value}" ]]; then
    diag write-step-summary "${template}" "required summary field ${key} is set" missing "Populate ${key} before writing the workflow summary."
    exit 1
  fi
done

status="${SUMMARY_STATUS:-success}"
failure_reason="${FAILURE_REASON:-}"
if [[ "${status}" == "success" ]]; then
  for key in "${required_success[@]}"; do
    value="${!key:-}"
    if [[ -z "${value}" || "${value}" == "n/a" ]]; then
      diag write-step-summary "${template}" "successful summary field ${key} is set and not n/a" "${value:-missing}" "Populate ${key} before writing a successful workflow summary."
      exit 1
    fi
  done
fi
if [[ "${require_failure_reason}" == "true" && "${status}" != "success" && -z "${failure_reason}" ]]; then
  diag write-step-summary "${template}" 'failed summaries include FAILURE_REASON' missing 'Set FAILURE_REASON when SUMMARY_STATUS is not success.'
  exit 1
fi

python3 - "${template}" "${output}" <<'PY'
import os
import re
import sys
from pathlib import Path

template = Path(sys.argv[1])
output = Path(sys.argv[2])
text = template.read_text()

def repl(match):
    key = match.group(1)
    return os.environ.get(key, "n/a") or "n/a"

rendered = re.sub(r"\{\{([A-Z0-9_]+)\}\}", repl, text)
output.parent.mkdir(parents=True, exist_ok=True)
with output.open("a", encoding="utf-8") as handle:
    handle.write(rendered)
    if not rendered.endswith("\n"):
        handle.write("\n")
PY
