# Documentation

This directory collects the public docs for the container image families in this repository. The root [README](../README.md) gives the short repository overview; image-specific details live near each image source.

## Using Images

- [CloudNativePG TimescaleDB image overview](../cloudnative-pg-timescaledb/README.md) - supported lines, image contents, catalogs, backup boundary, and local commands.
- [Image tags](image-tags.md) - immutable tags, rolling tags, and examples for CloudNativePG manifests.
- [Generated compatibility overview](../cloudnative-pg-timescaledb/docs/generated/compatibility.md) - metadata-rendered publishable and experimental image lines.
- [Generated compatibility table](../cloudnative-pg-timescaledb/docs/generated/compatibility-table.md) - compact table generated from image metadata.

## Operating With CloudNativePG

- [ClusterImageCatalog usage](catalog.md) - generated catalog manifests and recommended cluster references.
- [CloudNativePG Barman Cloud Plugin boundary](barman-plugin.md) - backup integration scope for the image family.
- [Troubleshooting](troubleshooting.md) - common failures and where to inspect evidence.

## Maintaining Images

- [Maintainer guide](maintainer-guide.md) - update, generate, validate, release rehearsal, and GHCR cleanup workflow.
- [Generated files](generated-files.md) - which files are generated and how to refresh them.
- [Generator contracts](generator-contracts.md) - deterministic generator behavior expected by validation.
- [Generated matrix schema](../cloudnative-pg-timescaledb/docs/generated/matrix-schema.md) - CI matrix contract.
- [Generated release candidate schema](../cloudnative-pg-timescaledb/docs/generated/release-candidate-schema.md) - release candidate metadata contract.
- [Generated release evidence schema](../cloudnative-pg-timescaledb/docs/generated/release-evidence-schema.md) - release evidence contract.
- [Generated failure reason catalog](../cloudnative-pg-timescaledb/docs/generated/failure-reason-catalog.md) - standard failure reasons used by automation.
- [Generated release rehearsal report](../cloudnative-pg-timescaledb/docs/generated/release-rehearsal-report.md) - dry-run release rehearsal output.

## Security And Verification

- [Verifying images and release evidence](user-guide/verifying-images.md) - cosign verification, release evidence, vulnerability policy, and image labels.
- [Security policy](../SECURITY.md) - how to report sensitive security issues.

## Contributing

- [Contribution guide](../CONTRIBUTING.md) - practical notes for changes, validation, generated files, and pull requests.
