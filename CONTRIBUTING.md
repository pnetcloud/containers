# Contributing

Thanks for taking a look at this repository. The goal is to keep the container images boring, reproducible, and easy to inspect.

## Before You Start

- Use `make help` to see the supported command surface.
- Keep secrets, credentials, private tokens, and local `.env` files out of commits.
- For the CloudNativePG TimescaleDB image family, `cloudnative-pg-timescaledb/versions.yaml` is the hand-edited image metadata source.

## Making Changes

For documentation-only changes, keep the root README short and link to the detailed docs instead of duplicating image-specific policy.

For image line changes:

1. Edit `cloudnative-pg-timescaledb/versions.yaml`.
2. Run `make generate`.
3. Review generated Dockerfiles, matrices, catalogs, and docs.
4. Run `make validate`.

For local image checks:

```bash
make build PG=18 DEBIAN=trixie
make smoke PG=18 DEBIAN=trixie
```

Use `DEBIAN=bookworm` when you are intentionally checking the secondary Debian variant.

## Pull Requests

A useful pull request usually includes:

- A short explanation of the change and why it is needed.
- The validation commands you ran.
- Any known limitation, skipped check, or follow-up that should be visible to maintainers.

Generated files are committed when their source metadata changes. If validation reports generated drift, regenerate rather than editing generated outputs by hand.

## Bugs And Support

Open an issue with:

- The image tag or digest involved.
- The command or CloudNativePG manifest fragment that reproduces the problem.
- Relevant logs, with secrets removed.
- The host architecture and Debian/PostgreSQL line if it matters.

Security-sensitive reports should follow [SECURITY.md](SECURITY.md) instead of a public issue with exploit details.
