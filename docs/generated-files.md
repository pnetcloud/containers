# Generated Files

`cloudnative-pg-timescaledb/versions.yaml` is the only hand-edited source of truth for the image family.

The following outputs are generated or validated from that metadata as later stories are implemented:

- generated Dockerfiles
- Docker Bake definitions
- GitHub Actions matrix data
- CloudNativePG `ClusterImageCatalog` manifests
- generated documentation tables
- README compatibility tables

Generated outputs are committed only after their owning generator and validation checks pass. They must not become independent hand-edited sources of truth.

The `vendor/` tree is reference-only. It provides implementation examples for humans, but project build and runtime paths must rely on the source files generated from this repository's metadata.
