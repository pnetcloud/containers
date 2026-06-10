# Invalid README

CloudNativePG-compatible PostgreSQL images are published at `ghcr.io/pnetcloud/cloudnative-pg-timescaledb` with TimescaleDB, TimescaleDB Toolkit, pgvector, and PGAudit.

Barman support uses the CloudNativePG Barman Cloud Plugin path; legacy in-image `barman-cloud` binaries are not part of v1. Supported PostgreSQL majors are PostgreSQL `17`, PostgreSQL `18`, and experimental PostgreSQL `19beta1`. Debian `trixie` is the primary recommended variant, and Debian `bookworm` is the secondary variant.

`latest` is convenience-only and points to PostgreSQL `18` on Debian `trixie`. Alpine is supported in v1. Debian `bullseye`, legacy PostgreSQL majors, and Artifact Hub metadata are out of scope for v1.
