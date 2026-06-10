# Valid Barman Plugin Docs

The CloudNativePG Barman Cloud Plugin is the supported v1 backup integration path. This PostgreSQL image family supplies PostgreSQL and extension runtime contents; backup plugin deployment is handled through CloudNativePG plugin mechanisms.

- Release: `v0.13.0`
- Manifest URL: `https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/v0.13.0/manifest.yaml`
- Plugin image: `ghcr.io/cloudnative-pg/plugin-barman-cloud:v0.13.0`
- Sidecar image: `ghcr.io/cloudnative-pg/plugin-barman-cloud-sidecar:v0.13.0`

Direct image tag example:

```yaml
spec:
  imageName: ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18-pg18.4-ts2.27.2-20260609
```

Generated catalog example:

```yaml
spec:
  imageCatalogRef:
    apiGroup: postgresql.cnpg.io
    kind: ClusterImageCatalog
    name: cloudnative-pg-timescaledb-standard-trixie
    major: 18
```

Legacy in-image `barman-cloud` binaries are not supported; use the plugin path instead.
