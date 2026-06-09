# Maintainer Guide

## Renovate Boundary

Renovate tracks reviewable dependency surfaces such as GitHub Actions and npm tooling. It must not replace the CloudNativePG, TimescaleDB, Toolkit, PostgreSQL/Debian matrix, publish policy, latest policy, or CloudNativePG Barman Cloud Plugin resolver paths.

`cloudnative-pg-timescaledb/versions.yaml` is ignored by Renovate. Resolver-owned fields are updated by `make update`, while Renovate-originated dependency changes are classified through `cloudnative-pg-timescaledb/config/change-origin-rules.json` and `cloudnative-pg-timescaledb/scripts/classify-update-origin.sh`.

Major dependency updates require manual review. Broad automerge for release-sensitive dependencies is not allowed.
