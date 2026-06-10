# Valid Verification Docs

Verify immutable digest references for public images:

```bash
IMAGE_REF="ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18-pg18.4-ts2.27.2-20260609@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
EXPECTED_CERTIFICATE_IDENTITY="https://github.com/pnetcloud/containers/.github/workflows/build.yml@refs/heads/main"
cosign verify "$IMAGE_REF" --certificate-oidc-issuer https://token.actions.githubusercontent.com --certificate-identity "$EXPECTED_CERTIFICATE_IDENTITY"
```

For release tags, derive `EXPECTED_CERTIFICATE_IDENTITY=https://github.com/pnetcloud/containers/.github/workflows/build.yml@refs/tags/<tag>` from the exact release ref. Do not use broad certificate identity regex matching.

Release evidence includes `index_digest`, `platform_digests`, and `per_digest_evidence`. Each digest record has `sbom_ref`, `provenance_ref`, `signature_ref`, `verification_ref`, and `verified`. SBOM and provenance attestations are attached to the final multi-platform index digest and every platform digest. Missing SBOM, provenance, signature, verification evidence, or threshold-passing scan status is a release blocker.

Vulnerability policy source: `cloudnative-pg-timescaledb/config/vulnerability-policy.yaml`. Ignore policy: `cloudnative-pg-timescaledb/config/vulnerability-ignore.yaml`; undeclared ignores are rejected. Required scanner command:

```bash
trivy image --scanners vuln --severity HIGH,CRITICAL --ignorefile cloudnative-pg-timescaledb/config/vulnerability-ignore.yaml --format sarif --output <sarif> ghcr.io/pnetcloud/cloudnative-pg-timescaledb@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

The scan also produces `security-scan.json`; SARIF is surfaced as `security-scan.sarif`. Inspect `vulnerability-scan-json`, `vulnerability-scan-sarif`, `security-scan.json`, `security-scan.sarif`, `scan_result`, failure reason, and the GitHub Step Summary / `GITHUB_STEP_SUMMARY`. Any unignored `HIGH` or `CRITICAL` vulnerability fails the release gate. The scanner updates the Trivy database and must fail closed when the database or scanner metadata cannot be fetched.

Image labels map back to `cloudnative-pg-timescaledb/versions.yaml` and release metadata: `org.opencontainers.image.source` maps the source repository and source revision context through workflow identity, `org.opencontainers.image.created` maps the UTC release date, `org.pnet.postgresql.major`, `org.pnet.postgresql.version`, `org.pnet.debian.variant`, `org.pnet.cnpg.tag`, `org.pnet.cnpg.digest`, `org.pnet.timescaledb.version`, and `org.pnet.timescaledb_toolkit.version` map to the selected metadata row.
