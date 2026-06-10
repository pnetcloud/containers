# Missing Labels

```bash
IMAGE_REF="ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18-pg18.4-ts2.27.2-20260609@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
EXPECTED_CERTIFICATE_IDENTITY="https://github.com/pnetcloud/containers/.github/workflows/build.yml@refs/heads/main"
cosign verify "$IMAGE_REF" --certificate-oidc-issuer https://token.actions.githubusercontent.com --certificate-identity "$EXPECTED_CERTIFICATE_IDENTITY"
```

Use `EXPECTED_CERTIFICATE_IDENTITY=https://github.com/pnetcloud/containers/.github/workflows/build.yml@refs/tags/<tag>`. Release evidence includes SBOM, provenance, `index_digest`, `platform_digests`, `per_digest_evidence`, `sbom_ref`, `provenance_ref`, `signature_ref`, `verification_ref`, and `verified`. Missing SBOM, provenance, signature, or threshold-passing scan status is a release blocker. Use `cloudnative-pg-timescaledb/config/vulnerability-policy.yaml` and `cloudnative-pg-timescaledb/config/vulnerability-ignore.yaml`; undeclared ignores are rejected. `trivy image --scanners vuln --severity HIGH,CRITICAL --ignorefile cloudnative-pg-timescaledb/config/vulnerability-ignore.yaml --format sarif --output <sarif> ghcr.io/pnetcloud/cloudnative-pg-timescaledb@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa`. Inspect `security-scan.json`, `security-scan.sarif`, `vulnerability-scan-json`, `vulnerability-scan-sarif`, `scan_result`, failure reason, Step Summary, and `GITHUB_STEP_SUMMARY`. Unignored `HIGH` or `CRITICAL` fails; scanner database failures fail closed.
