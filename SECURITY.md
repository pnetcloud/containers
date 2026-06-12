# Security Policy

This repository publishes public container images and the automation used to build them. Security reports are welcome, especially when they affect image contents, release evidence, signing, vulnerability gates, or GitHub Actions behavior.

## Reporting A Vulnerability

If GitHub Security Advisories are enabled for this repository, please use a private advisory draft to report sensitive issues.

If private advisories are not available, open a minimal public issue asking for a private security contact. Do not include exploit details, secret values, unpublished vulnerability details, or live attack instructions in the public issue.

For non-sensitive bugs, use a normal GitHub issue and include the image tag or digest, reproduction steps, and relevant logs with secrets removed.

## Image Verification

Published images are expected to have release evidence and cosign verification material. Verification guidance lives in [docs/user-guide/verifying-images.md](docs/user-guide/verifying-images.md).

Use immutable digest references when verifying a release artifact. Mutable tags are convenient for selection, but the release evidence is tied to exact digests.

## Vulnerability Gates

Release automation is expected to fail closed for unignored `HIGH` or `CRITICAL` vulnerabilities and for scanner database or metadata failures. The current policy files are:

- `cloudnative-pg-timescaledb/config/vulnerability-policy.yaml`
- `cloudnative-pg-timescaledb/config/vulnerability-ignore.yaml`

Undeclared ignores should be treated as policy failures, not silent exceptions.
