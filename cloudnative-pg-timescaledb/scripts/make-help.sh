#!/usr/bin/env bash
set -Eeuo pipefail

cat <<'HELP'
CloudNativePG TimescaleDB command surface

Targets:
  help                         Show this command list.
  update                       Refresh resolver-owned metadata and generated outputs.
  generate                     Regenerate committed generated outputs.
  validate                     Run available repository validation gates.
  matrix                       Print the generated CI matrix.
  bake-print                   Print the generated Docker Bake plan.
  catalog                      Generate catalog manifests.
  build PG=<major> DEBIAN=<variant>
                               Build one PostgreSQL/Debian image line.
  smoke PG=<major> DEBIAN=<variant>
                               Run smoke checks for one image line.

Supported parameters:
  PG:     17, 18, 19beta1
  DEBIAN: trixie, bookworm
  CHECKS: container, sql

Controlled exit codes:
  64 missing required PG/DEBIAN parameters
  65 unsupported PG or DEBIAN value
  69 target behavior is owned by a later story
HELP
