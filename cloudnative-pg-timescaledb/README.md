# CloudNativePG TimescaleDB Images

This directory contains the source for CloudNativePG-compatible PostgreSQL images published under GHCR namespace `ghcr.io/pnetcloud/cloudnative-pg-timescaledb`.

The image family layers TimescaleDB, TimescaleDB Toolkit when available, pgvector, and PGAudit onto CloudNativePG standard PostgreSQL images. Barman-related backup support is intentionally outside the image filesystem: use the CloudNativePG Barman Cloud Plugin path for backup integration, and legacy in-image `barman-cloud` binaries are not part of v1 images.

`cloudnative-pg-timescaledb/versions.yaml` is the only hand-edited source of truth for image lines. Generated Dockerfiles, workflow matrices, catalog manifests, generated documentation, and README tables must be derived from that metadata instead of maintained as competing sources.

Initial metadata covers PostgreSQL `17`, PostgreSQL `18`, and experimental PostgreSQL `19beta1` across Debian `trixie` and `bookworm`. Debian `trixie` is the primary recommended variant, and Debian `bookworm` is the secondary variant. PostgreSQL `19beta1` is experimental everywhere it appears.

Alpine, Debian `bullseye`, legacy PostgreSQL majors outside `17`, `18`, and experimental `19beta1`, and Artifact Hub metadata are out of scope for v1.

Use PostgreSQL major tags in CloudNativePG manifests and automation, for example:

```text
ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18
```

`latest` is convenience-only in v1 and points to PostgreSQL `18` on Debian `trixie`. Prefer explicit PostgreSQL major tags over `latest` in operator-managed manifests.

## Image Tags

Immutable `trixie` tags use `{major}-pg{pg_version}-ts{timescaledb_version}-{yyyymmdd}`, for example `18-pg18.4-ts2.27.2-20260609`. Secondary Debian `bookworm` tags append `-bookworm`, for example `18-pg18.4-ts2.27.2-20260609-bookworm`; rolling secondary tags also keep the OS suffix, such as `18-bookworm`.

CloudNativePG `imageName` examples should use immutable or major-prefixed tags, not `latest`. `latest` is convenience-only for PostgreSQL `18` on Debian `trixie`; PostgreSQL `19beta1` is experimental and never receives `latest` or normal rolling tags. Experimental preview examples use immutable tags such as `19beta1-pg19beta1-ts2.27.2-20260609`.

```yaml
spec:
  imageName: ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18-pg18.4-ts2.27.2-20260609
```

See `docs/image-tags.md` in the repository root for detailed tag policy and CloudNativePG examples.

## ClusterImageCatalog

The generated CloudNativePG `ClusterImageCatalog` manifests live in `cloudnative-pg-timescaledb/catalog/`. Apply `cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml` as the primary Debian `trixie` catalog:

```bash
kubectl apply -f cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml
```

Apply `cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm.yaml` only for the secondary Debian `bookworm` variant:

```bash
kubectl apply -f cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm.yaml
```

The generated `ClusterImageCatalog` resource names are `cloudnative-pg-timescaledb-standard-trixie` and `cloudnative-pg-timescaledb-standard-bookworm`. PostgreSQL `17` maps to catalog `major: 17`; PostgreSQL `18` maps to catalog `major: 18`.

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

Release catalogs are generated from release-complete published images. When release metadata provides a digest, catalog entries prefer the published multi-platform index or manifest-list digest, for example `ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18-pg18.4-ts2.27.2-20260609@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb`. Catalogs must not reference unpublished images, unsigned digests, missing digests, wrong PostgreSQL majors, or wrong Debian variants. Do not use `latest` as the primary CloudNativePG catalog path. PostgreSQL `19beta1` is experimental and regular catalog examples omit it unless explicitly marked experimental.

See the root `docs/catalog.md` for full catalog usage guidance.

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

See the root `docs/barman-plugin.md` for the backup integration boundary.

## Security Verification

Verify public images by immutable digest, not mutable tags alone:

```bash
IMAGE_REF="ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18-pg18.4-ts2.27.2-20260609@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
EXPECTED_CERTIFICATE_IDENTITY="https://github.com/pnetcloud/containers/.github/workflows/build.yml@refs/heads/main"
export COSIGN_REPOSITORY="ghcr.io/pnetcloud/cloudnative-pg-timescaledb-signatures"
cosign verify "$IMAGE_REF" --certificate-oidc-issuer https://token.actions.githubusercontent.com --certificate-identity "$EXPECTED_CERTIFICATE_IDENTITY"
```

For release refs, derive `EXPECTED_CERTIFICATE_IDENTITY=https://github.com/pnetcloud/containers/.github/workflows/build.yml@refs/tags/<tag>`. Do not use broad certificate identity regex matching. Public verification does not need private registry credentials.

Cosign signatures are stored in `ghcr.io/pnetcloud/cloudnative-pg-timescaledb-signatures` so the main image package only carries release tags. Release evidence covers `index_digest`, `platform_digests`, and `per_digest_evidence` with `sbom_ref`, `provenance_ref`, `signature_ref`, `verification_ref`, and `verified` for the final multi-platform index digest and every platform digest. Missing SBOM, provenance, signature, verification evidence, or threshold-passing scan status is a release blocker.

Vulnerability policy lives in `cloudnative-pg-timescaledb/config/vulnerability-policy.yaml`; ignores live in `cloudnative-pg-timescaledb/config/vulnerability-ignore.yaml`, and undeclared ignores are rejected. Required scan command shape: `trivy image --scanners vuln --severity HIGH,CRITICAL --ignorefile cloudnative-pg-timescaledb/config/vulnerability-ignore.yaml --format sarif --output <sarif> ghcr.io/pnetcloud/cloudnative-pg-timescaledb@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa`. Inspect `security-scan.json`, `security-scan.sarif`, `vulnerability-scan-json`, `vulnerability-scan-sarif`, `scan_result`, failure reason, Step Summary, and `GITHUB_STEP_SUMMARY`. Any unignored `HIGH` or `CRITICAL` vulnerability fails the release gate, and scanner database failures fail closed.

Labels map release images back to `cloudnative-pg-timescaledb/versions.yaml`: `org.opencontainers.image.source` for source revision context, `org.opencontainers.image.created` for release date, `org.pnet.postgresql.major`, `org.pnet.postgresql.version`, `org.pnet.debian.variant`, `org.pnet.cnpg.tag`, `org.pnet.cnpg.digest`, `org.pnet.timescaledb.version`, and `org.pnet.timescaledb_toolkit.version`.

See the root `docs/user-guide/verifying-images.md` for full verification guidance.

The compatibility overview is generated from `cloudnative-pg-timescaledb/versions.yaml`:

- `cloudnative-pg-timescaledb/docs/generated/compatibility.md`
- `cloudnative-pg-timescaledb/docs/generated/compatibility-table.md`

The current metadata enables publishable stable PostgreSQL `17` and `18` image lines for Debian `trixie` and `bookworm`. PostgreSQL `19beta1` remains experimental with `publish: false` and a non-empty `skip_reason`; generated Dockerfiles and Bake targets are emitted only for publishable entries.

## Command Surface

Use the root `Makefile` for local development and CI entry points. The stable targets are `help`, `update`, `generate`, `validate`, `matrix`, `bake-print`, `catalog`, `build`, and `smoke`.

`make bake-print` prints the generated Docker Buildx Bake plan from `cloudnative-pg-timescaledb/docker-bake.hcl`. The plan uses checkout/path context and contains no registry push output.

`make build` and `make smoke` require `PG=<17|18|19beta1>` and `DEBIAN=<trixie|bookworm>`. `make build PG=<major> DEBIAN=<variant>` invokes the selected local Bake target with `output=type=docker` and a single local `PLATFORM` override, defaulting to `linux/amd64`. If the selected row is still `publish: false`, the command exits non-zero with the target name, Dockerfile path, context, platform, and `skip_reason`.

`make smoke PG=<major> DEBIAN=<variant> CHECKS=container` runs container-level smoke checks for a locally built image line. It verifies Debian release, PostgreSQL version, required extension control files, image labels, CNPG runtime binaries, the `postgres` user, data directory permissions, and temporary PostgreSQL startup.

`make smoke PG=<major> DEBIAN=<variant> CHECKS=sql` runs SQL extension smoke checks for a locally built image line. It verifies basic SQL execution, server version, canonical `shared_preload_libraries=timescaledb,pgaudit`, TimescaleDB and Toolkit extension versions, TimescaleDB library availability, pgvector/PGAudit creation or explicitly documented validation-only policy, and deterministic diagnostics for publish-blocking failures.
