# Update Process

`make update` is the local update contract used before scheduled automation is added.

The command runs `cloudnative-pg-timescaledb/scripts/resolve-versions.sh update`, updates only resolver-owned metadata fields in `cloudnative-pg-timescaledb/versions.yaml`, and then regenerates committed outputs through the project generators.

Resolver-owned fields are PostgreSQL base image version/tag/digest fields and TimescaleDB/Toolkit version fields. Maintainer policy fields remain owned by maintainers: `publish`, `experimental`, `latest_eligible`, and non-prefixed `skip_reason` values are preserved. Resolver-generated skip reasons use the reserved `resolver:<code>:` prefix and may be updated by `make update`.

Machine output is available with:

```bash
make update UPDATE_ARGS=--json
```

Successful JSON contains `changed`, `updated_entries`, `old`, `new`, `generated`, `summary_path`, `exit_code`, and `failure_reason`. Human diagnostics are written to stderr. A no-op update exits successfully and leaves the working tree clean.

For deterministic tests or scheduled automation rehearsals, pass fixture inventories:

```bash
make update UPDATE_ARGS="--fixtures /path/to/upstream --json"
```

The fixture root must contain `cnpg/` and `packages/` directories compatible with the Story 2.1 and Story 2.2 resolver fixtures.

Update invariants:

- Supported rows remain exactly PostgreSQL `17`, `18`, and experimental `19beta1` across Debian `trixie` and `bookworm`.
- `latest_eligible` remains assigned only to PostgreSQL `18` on `trixie`.
- Publishable rows fail if resolver-owned CNPG or package data cannot satisfy required platforms.
- Legacy in-image Barman tooling such as `barman-cloud` must not appear in metadata or generated image artifacts; Barman support is reserved for the CloudNativePG Barman Cloud Plugin story.
