# ClusterImageCatalog Usage

This repository generates CloudNativePG `ClusterImageCatalog` manifests for the public image family under `ghcr.io/pnetcloud/cloudnative-pg-timescaledb`.

Use the Debian `trixie` catalog as the primary operator path:

```bash
kubectl apply -f cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml
```

Use the Debian `bookworm` catalog only when you intentionally need the secondary Debian variant:

```bash
kubectl apply -f cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm.yaml
```

The generated catalog resource names are:

| Debian variant | Role | Manifest | `ClusterImageCatalog` name |
| --- | --- | --- | --- |
| `trixie` | primary | `cloudnative-pg-timescaledb/catalog/catalog-standard-trixie.yaml` | `cloudnative-pg-timescaledb-standard-trixie` |
| `bookworm` | secondary | `cloudnative-pg-timescaledb/catalog/catalog-standard-bookworm.yaml` | `cloudnative-pg-timescaledb-standard-bookworm` |

## Cluster References

CloudNativePG clusters select an image from a catalog through `spec.imageCatalogRef`. The `major` field maps to the PostgreSQL major in the catalog entry.

Use the primary `trixie` catalog for normal PostgreSQL `18` clusters:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: app-db
spec:
  instances: 3
  storage:
    size: 100Gi
  imageCatalogRef:
    apiGroup: postgresql.cnpg.io
    kind: ClusterImageCatalog
    name: cloudnative-pg-timescaledb-standard-trixie
    major: 18
```

Use the same primary catalog with `major: 17` for PostgreSQL `17` clusters:

```yaml
spec:
  imageCatalogRef:
    apiGroup: postgresql.cnpg.io
    kind: ClusterImageCatalog
    name: cloudnative-pg-timescaledb-standard-trixie
    major: 17
```

Use the secondary `bookworm` catalog only when the cluster should run the secondary Debian image line:

```yaml
spec:
  imageCatalogRef:
    apiGroup: postgresql.cnpg.io
    kind: ClusterImageCatalog
    name: cloudnative-pg-timescaledb-standard-bookworm
    major: 18
```

Do not use `latest` as the primary CloudNativePG path. Catalog references keep PostgreSQL major selection explicit and allow generated release metadata to pin the exact published image artifact.

## Digest Policy

Release catalogs are generated from release-complete published images. When release metadata provides a published multi-platform index digest, catalog entries prefer the immutable tag plus the manifest-list digest:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: ClusterImageCatalog
metadata:
  name: cloudnative-pg-timescaledb-standard-trixie
spec:
  images:
    - major: 17
      image: ghcr.io/pnetcloud/cloudnative-pg-timescaledb:17-pg17.10-ts2.27.2-20260609@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    - major: 18
      image: ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18-pg18.4-ts2.27.2-20260609@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
```

The digest must identify the published multi-platform index, not a single per-platform digest. Catalogs must not reference unpublished images, unsigned digests, missing digests, wrong PostgreSQL majors, or wrong Debian variants.

Stable catalogs include PostgreSQL `17` and PostgreSQL `18` entries after those images have completed release publication. PostgreSQL `19beta1` is experimental; keep it out of stable catalog examples unless the example is explicitly marked experimental.

See the CloudNativePG image catalog documentation for the upstream resource behavior: <https://cloudnative-pg.io/documentation/current/image_catalog/>.
