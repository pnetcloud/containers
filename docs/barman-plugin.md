# Barman Cloud Plugin Boundary

The CloudNativePG Barman Cloud Plugin is the supported v1 backup integration path for this image family.

This repository builds PostgreSQL images with TimescaleDB, TimescaleDB Toolkit, pgvector, and PGAudit extension runtime contents. Backup plugin deployment is handled through CloudNativePG plugin mechanisms, not by adding backup binaries to the PostgreSQL image filesystem.

## Current Plugin Reference

The generated reference artifact is `cloudnative-pg-timescaledb/docs/generated/barman-plugin-reference.md`. Public backup docs must match that generated Story 2.7 reference.

Current generated values:

| Field | Value |
| --- | --- |
| Release | `v0.13.0` |
| Manifest URL | `https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/v0.13.0/manifest.yaml` |
| Plugin image | `ghcr.io/cloudnative-pg/plugin-barman-cloud:v0.13.0` |
| Sidecar image | `ghcr.io/cloudnative-pg/plugin-barman-cloud-sidecar:v0.13.0` |

Use the manifest and images above through the CloudNativePG plugin deployment path. The CloudNativePG Barman Cloud Plugin path does not install, require, or validate legacy in-image `barman-cloud` binaries in v1 images.

## Image Boundary

The database image remains focused on PostgreSQL and extension runtime contents:

- PostgreSQL and CloudNativePG standard image runtime compatibility.
- TimescaleDB and TimescaleDB Toolkit when available for the selected PostgreSQL and Debian variant.
- pgvector and PGAudit extension availability.
- No legacy in-image `barman-cloud` backup binaries.

The backup plugin owns backup and restore sidecar behavior through CloudNativePG plugin mechanisms. This separation keeps the database image smaller, easier to smoke test, and aligned with modern CloudNativePG backup integration.

## Compatible Database Image Examples

Backup guidance must not change how the database image is selected. Direct image tag examples remain valid:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: app-db
spec:
  imageName: ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18-pg18.4-ts2.27.2-20260609
```

Generated catalog examples remain valid as well:

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

The plugin image and sidecar image are plugin deployment references. They must not be used as the PostgreSQL `spec.imageName` value for the database cluster.
