# Wrong Plugin Image

The CloudNativePG Barman Cloud Plugin is the supported v1 backup integration path. This PostgreSQL image family supplies PostgreSQL and extension runtime contents; backup plugin deployment is handled through CloudNativePG plugin mechanisms.

- Release: `v0.12.0`
- Manifest URL: `https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/v0.12.0/manifest.yaml`
- Plugin image: `ghcr.io/cloudnative-pg/plugin-barman-cloud:v0.11.0`
- Sidecar image: `ghcr.io/cloudnative-pg/plugin-barman-cloud-sidecar:v0.12.0`

The current generated plugin image is mentioned elsewhere: `ghcr.io/cloudnative-pg/plugin-barman-cloud:v0.12.0`.

```yaml
spec:
  imageName: ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18-pg18.4-ts2.27.2-20260609
  imageCatalogRef:
    apiGroup: postgresql.cnpg.io
    kind: ClusterImageCatalog
    name: cloudnative-pg-timescaledb-standard-trixie
    major: 18
```
