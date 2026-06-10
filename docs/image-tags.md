# Image Tags

This image family publishes tags under `ghcr.io/pnetcloud/cloudnative-pg-timescaledb` from the metadata in `cloudnative-pg-timescaledb/versions.yaml`.

Use immutable or major-prefixed tags in CloudNativePG `imageName` fields. Prefer immutable tags for production rollouts and rollback plans; use rolling major tags only when you intentionally want the current patched image for one PostgreSQL major and Debian variant. Prefer digest-pinned references after release evidence is available and you need exact artifact identity.

## Immutable Tags

Primary Debian `trixie` immutable tags use `{major}-pg{pg_version}-ts{timescaledb_version}-{yyyymmdd}`:

```text
18-pg18.4-ts2.27.2-20260609
```

Secondary Debian `bookworm` immutable tags append the `-bookworm` suffix:

```text
18-pg18.4-ts2.27.2-20260609-bookworm
```

## Rolling Tags

Primary rolling major tags such as `17` and `18` are for Debian `trixie` only. Secondary Debian `bookworm` rolling tags must include the OS suffix, for example `18-bookworm`.

`latest` is convenience-only in v1. It points only to PostgreSQL `18` on Debian `trixie`; it is never assigned to Debian `bookworm`, PostgreSQL `17`, or experimental PostgreSQL `19beta1`.

PostgreSQL `19beta1` is experimental. It never receives `latest` or normal rolling tags such as `19beta1`; use only experimental immutable tags such as `19beta1-pg19beta1-ts2.27.2-20260609` or `19beta1-pg19beta1-ts2.27.2-20260609-bookworm`.

## CloudNativePG Examples

Use a major-prefixed immutable tag when you want a fixed release:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: app-db
spec:
  imageName: ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18-pg18.4-ts2.27.2-20260609
```

Use a rolling major tag only when that is an explicit operations choice:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: app-db-bookworm
spec:
  imageName: ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18-bookworm
```

Do not use `latest` as a CloudNativePG `imageName` example. It is a convenience tag for discovery and manual pulls, not the primary operator manifest pattern.
