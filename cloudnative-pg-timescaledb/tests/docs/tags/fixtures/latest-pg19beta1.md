# Invalid Tag Docs

Primary Debian `trixie` immutable tags use `18-pg18.4-ts2.27.2-20260609`. Secondary Debian `bookworm` immutable tags use `18-pg18.4-ts2.27.2-20260609-bookworm`, and the secondary rolling tag is `18-bookworm`. Primary rolling major tags `17` and `18` are for trixie only. `latest` is convenience-only and points only to PostgreSQL `18` Debian `trixie`; `latest` is published for PostgreSQL `19beta1` preview images. PostgreSQL `19beta1` is experimental and uses immutable preview tags such as `19beta1-pg19beta1-ts2.27.2-20260609`.

```yaml
spec:
  imageName: ghcr.io/pnetcloud/cloudnative-pg-timescaledb:18
```
