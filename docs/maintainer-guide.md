# Maintainer Guide

This guide is for maintainers changing the CloudNativePG TimescaleDB image family. The image metadata model is intentionally narrow: `cloudnative-pg-timescaledb/versions.yaml` is the only hand-edited source of truth and the only hand-edited image source of truth. Do not treat generated Dockerfiles, Bake files, matrix files, catalogs, or generated docs as independent sources of truth.

## Source Of Truth

Edit `cloudnative-pg-timescaledb/versions.yaml` for supported PostgreSQL lines, Debian variants, publish policy, experimental policy, `latest` eligibility, CloudNativePG base references, TimescaleDB references, TimescaleDB Toolkit references, pgvector and PGAudit package expectations, and the CloudNativePG Barman Cloud Plugin reference.

Generated outputs are committed so a clean checkout is reviewable and CI can detect drift. They must not be hand-edited as final fixes. If a generated output is wrong, edit `versions.yaml`, the owning template, or the owning generator, then run the generator again and validate the diff.

The `vendor/` tree is reference-only. Vendor projects and examples can inform implementation, but repository builds, workflow contexts, runtime image contents, and generated outputs must come from this repository's metadata, templates, scripts, and committed generated artifacts.

## Command Surface

Use the root `Makefile` as the stable maintainer interface:

| Target | Maintainer use |
| --- | --- |
| `make help` | Print the supported command surface and parameter names. |
| `make update` | Refresh resolver-owned CloudNativePG base image, TimescaleDB, TimescaleDB Toolkit, CloudNativePG Barman Cloud Plugin references, and regenerated outputs. |
| `make generate` | Regenerate Dockerfiles, Docker Buildx Bake definitions, matrix JSON, generated documentation, and other metadata-derived outputs. |
| `make validate` | Run repository gates for metadata, generated drift, workflows, docs, tags, catalogs, security policy, release evidence, and autocommit safety. |
| `make matrix` | Print the generated CI matrix from `versions.yaml`. |
| `make bake-print` | Print the generated Docker Buildx Bake plan and inspect resolved targets, platforms, and tags before building. |
| `make catalog` | Generate CloudNativePG `ClusterImageCatalog` manifests from release-complete published digest metadata. |
| `make build PG=<major> DEBIAN=<variant>` | Build one PostgreSQL/Debian image line from generated files, for example `PG=18 DEBIAN=trixie`. |
| `make smoke PG=<major> DEBIAN=<variant>` | Run smoke checks for one built image line; set `CHECKS=container` or `CHECKS=sql` when narrowing the check type. |

## Renovate Boundary

Renovate tracks reviewable dependency surfaces such as GitHub Actions and static helper dependencies. It must not replace the CloudNativePG, TimescaleDB, TimescaleDB Toolkit, PostgreSQL/Debian matrix, publish policy, latest policy, or CloudNativePG Barman Cloud Plugin resolver paths.

`cloudnative-pg-timescaledb/versions.yaml` is ignored by Renovate. Resolver-owned fields are updated by `make update`, while Renovate-originated dependency changes are classified through `cloudnative-pg-timescaledb/config/change-origin-rules.json` and `cloudnative-pg-timescaledb/scripts/classify-update-origin.sh`.

Major dependency updates require manual review. Broad automerge for release-sensitive dependencies is not allowed.

## Generated Files

Generated outputs are committed after validation so review diffs show the exact image, workflow, catalog, and documentation consequences of a metadata change. They are regenerated, not patched by hand as final fixes.

The generated file ownership matrix is maintained in [Generated Files](generated-files.md). Use it to identify the source of truth, generator command, commit policy, and hand-edit policy for each generated path.

Before committing generated diffs, run `make generate` and `make validate`. When release catalog metadata is involved, run `make catalog` after publish evidence is available and review only the catalog diffs allowed by `cloudnative-pg-timescaledb/config/catalog-autocommit-allowlist.txt`.

## Scheduled Updates And Autocommit

The scheduled update workflow runs `make update`, validates with `make validate`, stages only paths from `cloudnative-pg-timescaledb/config/autocommit-allowlist.txt`, and commits only when the staged diff is non-empty. A scheduled update no-op must create no commit and leave the resolver-owned generated paths unchanged.

Release catalog autocommit is separate. It first checks whether release metadata exists. If no release metadata is available, catalog autocommit is a no-op and must not generate empty catalogs. When release metadata is available, it runs `make catalog`, stages only paths from `cloudnative-pg-timescaledb/config/catalog-autocommit-allowlist.txt`, validates the staged paths, and commits only changed catalog manifests.

Autocommit path allowlists are security boundaries, not convenience lists. `cloudnative-pg-timescaledb/scripts/autocommit-stage.sh` must be the only staging path in update automation, and `cloudnative-pg-timescaledb/scripts/validate-autocommit-staging.sh` must reject vendor changes, runtime artifacts, `.env` files, credentials, tokens, passwords, signing secrets, registry passwords, and other secret-like paths.

Loop prevention is required for generated commits. Update and catalog workflows must avoid recursively creating new generated commits from bot/generated commits, and catalog autocommit must refresh the branch tip after resolver autocommit to avoid racing on stale branch state.

## Token Policy

Use `GITHUB_TOKEN` through `actions/checkout` persisted credentials as the default autocommit mechanism. The workflow grants `contents: write` only to the known autocommit jobs that need to push allowlisted generated changes.

A personal access token fallback is allowed only as a branch-protection exception when repository policy prevents `GITHUB_TOKEN` from pushing the required generated update branch. That fallback has a security tradeoff: a broader token increases blast radius if misconfigured, exposed, or granted more scopes than the workflow needs. Prefer adjusting branch protection for the automation path before adding a PAT.

Never commit `.env` files, credentials, tokens, signing secrets, registry passwords, private keys, or secret-like values. Do not print secrets into workflow summaries, generated docs, fixtures, release evidence, or logs.

## Release Process

1. Edit only `cloudnative-pg-timescaledb/versions.yaml` for image metadata and policy changes.
2. Run `make update` to refresh resolver-owned CloudNativePG base image, TimescaleDB, TimescaleDB Toolkit, CloudNativePG Barman Cloud Plugin references, and regenerated outputs. Do not describe `make update` as updating GitHub Actions or static helper dependencies; those are Renovate-managed through the Renovate boundary.
3. Run `make generate` to regenerate Dockerfiles, Bake definitions, matrix JSON, catalogs, docs tables, and generated docs from metadata.
4. Run `make validate` and fix drift, metadata, workflow, shell, docs, tag, catalog, and security policy failures before build or publish.
5. Inspect `make bake-print` output for the resolved PostgreSQL/Debian/platform matrix and tag set.
6. Run `make build PG=<major> DEBIAN=<variant>` and `make smoke PG=<major> DEBIAN=<variant>` for the target line, or use the release rehearsal when validating the full publishable matrix.
7. Run `make catalog` after publish metadata is available and review generated catalog diffs.
8. Review scheduled update no-op and autocommit runs: no-op runs must create no commits; changed runs must commit only allowlisted generated paths and must not recurse on bot/generated commits.
9. Use `GITHUB_TOKEN` as the default automation credential. PAT fallback is documented only as a branch-protection exception with the risk that a broader token increases blast radius.
10. Keep Artifact Hub metadata out of v1 and never commit `.env`, credentials, tokens, signing secrets, registry passwords, private keys, or secret-like values.
