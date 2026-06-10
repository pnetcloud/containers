# CloudNativePG TimescaleDB Containers

This repository builds public CloudNativePG-compatible PostgreSQL images for GHCR namespace `ghcr.io/pnetcloud/cloudnative-pg-timescaledb`.

The image family adds TimescaleDB, TimescaleDB Toolkit when available, pgvector, and PGAudit on top of CloudNativePG standard PostgreSQL images. Backup integration for v1 is through the CloudNativePG Barman Cloud Plugin path; legacy in-image `barman-cloud` binaries are not part of the image scope.

Supported PostgreSQL majors are PostgreSQL `17`, PostgreSQL `18`, and experimental PostgreSQL `19beta1`. Debian `trixie` is the primary recommended variant, and Debian `bookworm` is the secondary variant. Alpine, Debian `bullseye`, legacy PostgreSQL majors, and Artifact Hub metadata are out of scope for v1.

Use PostgreSQL major tags for examples and automation, such as:

```text
ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18
```

`latest` is convenience-only in v1 and points to PostgreSQL `18` on Debian `trixie`. Prefer explicit PostgreSQL major tags for production manifests.

## Image Tags

Immutable `trixie` tags use the form `{major}-pg{pg_version}-ts{timescaledb_version}-{yyyymmdd}`, for example `18-pg18.4-ts2.27.2-20260609`. Debian `bookworm` tags append `-bookworm`, for example `18-pg18.4-ts2.27.2-20260609-bookworm` and rolling `18-bookworm`.

Use major-prefixed tags in CloudNativePG `imageName` fields. `latest` is convenience-only for PostgreSQL `18` on Debian `trixie`; PostgreSQL `19beta1` is experimental and never receives `latest` or normal rolling tags. Experimental preview examples use immutable tags such as `19beta1-pg19beta1-ts2.27.2-20260609`.

```yaml
spec:
  imageName: ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18-pg18.4-ts2.27.2-20260609
```

See [docs/image-tags.md](docs/image-tags.md) for CloudNativePG image examples and tag selection guidance.

## ClusterImageCatalog

CloudNativePG operators should consume generated catalog resources instead of using `latest` as the primary operator path. Apply `cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml` as the primary Debian `trixie` catalog:

```bash
kubectl apply -f cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml
```

Apply `cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm.yaml` only when you need the secondary Debian `bookworm` variant:

```bash
kubectl apply -f cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm.yaml
```

The generated `ClusterImageCatalog` names are `cloudnative-pg-timescaledb-standard-trixie` and `cloudnative-pg-timescaledb-standard-bookworm`. PostgreSQL `17` maps to catalog `major: 17`; PostgreSQL `18` maps to catalog `major: 18`.

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: app-db
spec:
  imageCatalogRef:
    apiGroup: postgresql.cnpg.io
    kind: ClusterImageCatalog
    name: cloudnative-pg-timescaledb-standard-trixie
    major: 18
```

Release catalogs are generated from release-complete published images and prefer published multi-platform index digest references, for example `ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18-pg18.4-ts2.27.2-20260609@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb`. Catalogs must not reference unpublished images, unsigned digests, missing digests, wrong PostgreSQL majors, or wrong Debian variants. PostgreSQL `19beta1` is experimental and regular catalog examples omit it unless explicitly marked experimental.

See [docs/catalog.md](docs/catalog.md) for full CloudNativePG `ClusterImageCatalog` usage guidance.

## Backup Boundary

The CloudNativePG Barman Cloud Plugin is the supported v1 backup integration path. This image family supplies PostgreSQL and extension runtime contents; backup plugin deployment is handled through CloudNativePG plugin mechanisms, not through legacy in-image `barman-cloud` binaries.

Current generated Barman plugin reference values from `cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md`:

- Release: `v0.13.0`
- Manifest URL: `https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/v0.13.0/manifest.yaml`
- Plugin image: `ghcr.io/cloudnative-pg/plugin-barman-cloud:v0.13.0`
- Sidecar image: `ghcr.io/cloudnative-pg/plugin-barman-cloud-sidecar:v0.13.0`

Backup guidance remains compatible with direct image tags:

```yaml
spec:
  imageName: ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18-pg18.4-ts2.27.2-20260609
```

It also remains compatible with generated catalogs:

```yaml
spec:
  imageCatalogRef:
    apiGroup: postgresql.cnpg.io
    kind: ClusterImageCatalog
    name: cloudnative-pg-timescaledb-standard-trixie
    major: 18
```

See [docs/barman-plugin.md](docs/barman-plugin.md) for the backup integration boundary.

## Security Verification

Verify public images by immutable digest, not mutable tags alone:

```bash
IMAGE_REF="ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18-pg18.4-ts2.27.2-20260609@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
EXPECTED_CERTIFICATE_IDENTITY="https://github.com/pnetcloud/containers/.github/workflows/build.yml@refs/heads/main"
cosign verify "$IMAGE_REF" --certificate-oidc-issuer https://token.actions.githubusercontent.com --certificate-identity "$EXPECTED_CERTIFICATE_IDENTITY"
```

For release refs, derive `EXPECTED_CERTIFICATE_IDENTITY=https://github.com/pnetcloud/containers/.github/workflows/build.yml@refs/tags/<tag>`. Do not use broad certificate identity regex matching. Public verification does not need private registry credentials.

Release evidence covers `index_digest`, `platform_digests`, and `per_digest_evidence` with `sbom_ref`, `provenance_ref`, `signature_ref`, `verification_ref`, and `verified` for the final multi-platform index digest and every platform digest. Missing SBOM, provenance, signature, verification evidence, or threshold-passing scan status is a release blocker.

Vulnerability policy lives in `cloudnative-pg-timescaledb/config/vulnerability-policy.yaml`; ignores live in `cloudnative-pg-timescaledb/config/vulnerability-ignore.yaml`, and undeclared ignores are rejected. Required scan command shape: `trivy image --scanners vuln --severity HIGH,CRITICAL --ignorefile cloudnative-pg-timescaledb/config/vulnerability-ignore.yaml --format sarif --output <sarif> ghcr.io/pnetcloud/cloudnative-pg-timescaledb@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa`. Inspect `security-scan.json`, `security-scan.sarif`, `vulnerability-scan-json`, `vulnerability-scan-sarif`, `scan_result`, failure reason, Step Summary, and `GITHUB_STEP_SUMMARY`. Any unignored `HIGH` or `CRITICAL` vulnerability fails the release gate, and scanner database failures fail closed.

Labels map release images back to `cloudnative-pg-timescaledb/versions.yaml`: `org.opencontainers.image.source` for source revision context, `org.opencontainers.image.created` for release date, `org.pnet.postgresql.major`, `org.pnet.postgresql.version`, `org.pnet.debian.variant`, `org.pnet.cnpg.tag`, `org.pnet.cnpg.digest`, `org.pnet.timescaledb.version`, and `org.pnet.timescaledb_toolkit.version`.

See [docs/user-guide/verifying-images.md](docs/user-guide/verifying-images.md) for full verification guidance.

See [cloudnative-pg-timescaledb/README.md](cloudnative-pg-timescaledb/README.md) for the package overview and [cloudnative-pg-timescaledb/docs/generated/compatibility-table.md](cloudnative-pg-timescaledb/docs/generated/compatibility-table.md) for the generated compatibility table.
