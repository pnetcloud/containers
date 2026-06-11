# Verifying Images and Release Evidence

Use immutable digest references when verifying this public image family. Mutable tags are useful for selection, but verification must target the exact digest that release evidence covers.

```bash
IMAGE_REF="ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18-pg18.4-ts2.27.2-20260609@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
EXPECTED_CERTIFICATE_IDENTITY="https://github.com/pnetcloud/containers/.github/workflows/build.yml@refs/heads/main"
export COSIGN_REPOSITORY="ghcr.io/pnetcloud/cloudnative-pg-timescaledb-signatures"

cosign verify "$IMAGE_REF" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity "$EXPECTED_CERTIFICATE_IDENTITY"
```

For release-tagged runs, derive `EXPECTED_CERTIFICATE_IDENTITY=https://github.com/pnetcloud/containers/.github/workflows/build.yml@refs/tags/<tag>` from the exact release ref. Do not use broad certificate identity regex matching; verification must use the exact workflow identity for the release ref.

Public image verification does not require private registry credentials. Pull, inspect, cosign, and Trivy examples should work against public GHCR references. Cosign signatures are stored in `ghcr.io/pnetcloud/cloudnative-pg-timescaledb-signatures` so the main image package only carries release tags.

## Release Evidence

Release evidence is described by `cloudnative-pg-timescaledb/docs/generated/release-evidence-schema.md`. The evidence object records `index_digest`, `platform_digests`, and `per_digest_evidence`. Coverage must include the final multi-platform index digest and every platform digest.

Each `per_digest_evidence` record points at the evidence attached to that digest:

- `sbom_ref` for the BuildKit SBOM attestation.
- `provenance_ref` for the BuildKit provenance attestation.
- `signature_ref` for the keyless cosign signature.
- `verification_ref` plus `verified` for the verification result.

Missing SBOM, provenance, signature, verification evidence, or threshold-passing scan status is a release blocker. Promotion is not valid until every required digest has passing evidence and the top-level `scan_result` is `passed`.

## Vulnerability Policy

The vulnerability policy source is `cloudnative-pg-timescaledb/config/vulnerability-policy.yaml`. The ignore policy is `cloudnative-pg-timescaledb/config/vulnerability-ignore.yaml`; undeclared ignores are rejected and normal releases must not bypass the policy.

The required scanner is Trivy container image scanning. The command shape is:

```bash
trivy image --scanners vuln --severity HIGH,CRITICAL \
  --ignorefile cloudnative-pg-timescaledb/config/vulnerability-ignore.yaml \
  --format sarif --output <sarif> \
  ghcr.io/pnetcloud/cloudnative-pg-timescaledb@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

The scan also writes JSON output for the same immutable digest. Inspect `security-scan.json`, `security-scan.sarif`, `vulnerability-scan-json`, `vulnerability-scan-sarif`, `scan_result`, failure reason, and the GitHub Step Summary through `GITHUB_STEP_SUMMARY`. SARIF upload status is visible in the security scan job when code scanning upload is enabled.

Any unignored `HIGH` or `CRITICAL` vulnerability fails the release gate. The scanner updates the Trivy vulnerability database during the scan and must fail closed when the database or scanner metadata cannot be fetched.

## Image Labels

Image labels map the published image back to `cloudnative-pg-timescaledb/versions.yaml`, release metadata, and the workflow identity that produced the artifact.

| Label | Mapping |
| --- | --- |
| `org.opencontainers.image.source` | Source repository for source revision lookup and release workflow identity. |
| `org.opencontainers.image.created` | UTC release date / build date for the generated image. |
| `org.pnet.postgresql.major` | `entries[].pg_major` in `versions.yaml`. |
| `org.pnet.postgresql.version` | `entries[].pg_version` in `versions.yaml`. |
| `org.pnet.debian.variant` | `entries[].debian_variant` in `versions.yaml`. |
| `org.pnet.cnpg.tag` | `entries[].cnpg_tag` in `versions.yaml`. |
| `org.pnet.cnpg.digest` | `entries[].cnpg_digest` in `versions.yaml`. |
| `org.pnet.timescaledb.version` | `entries[].timescaledb_version` in `versions.yaml`. |
| `org.pnet.timescaledb_toolkit.version` | `entries[].toolkit_version` in `versions.yaml`. |

Use these labels with release evidence to trace PostgreSQL version, Debian variant, TimescaleDB version, Toolkit version, source revision context, and release date for the image you are adopting.
