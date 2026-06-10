#!/usr/bin/env python3
import argparse
import difflib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from tag_policy import generated_tags, resolve_release_date


ROOT = Path(__file__).resolve().parents[3]
DEFAULT_METADATA = ROOT / "cloudnative-pg-timescaledb" / "versions.yaml"
DOCKERFILE_TEMPLATE = ROOT / "cloudnative-pg-timescaledb" / "templates" / "Dockerfile.tmpl"
CNPG_IMAGE = "ghcr.io/cloudnative-pg/postgresql"
SOURCE_REPOSITORY = "https://github.com/pnetcloud/containers"
DIGEST_RE = re.compile(r"^sha256:[0-9a-f]{64}$")


FAILURE_REASON_CATALOG = [
    {
        "reason_id": "metadata.invalid",
        "category": "invalid metadata",
        "applies_to": "versions.yaml validation and update resolver input",
        "gate_or_command": "cloudnative-pg-timescaledb/scripts/validate-metadata.sh",
        "hard_fail": True,
        "publish_false_skip_reason_allowed": "No. Invalid metadata must be fixed before any publish decision is made.",
        "local_command": "make validate or bash cloudnative-pg-timescaledb/scripts/validate-metadata.sh",
        "remediation": "Fix cloudnative-pg-timescaledb/versions.yaml so allowed PostgreSQL majors, Debian variants, platforms, Barman plugin metadata, and every entry field match the schema.",
        "trixie_bookworm_notes": "same",
    },
    {
        "reason_id": "generated.stale",
        "category": "stale generated files",
        "applies_to": "generated Dockerfiles, Bake, matrix, catalogs, and docs",
        "gate_or_command": "cloudnative-pg-timescaledb/scripts/validate-generated.sh",
        "hard_fail": True,
        "publish_false_skip_reason_allowed": "No. Regenerate committed outputs instead of marking rows unpublished.",
        "local_command": "make generate && make validate",
        "remediation": "Regenerate outputs from versions.yaml, templates, and generators; commit the generated diff rather than hand-editing generated files.",
        "trixie_bookworm_notes": "same",
    },
    {
        "reason_id": "package.unsupported-combination",
        "category": "unsupported package combinations",
        "applies_to": "TimescaleDB and Toolkit package resolver output",
        "gate_or_command": "make update and cloudnative-pg-timescaledb/scripts/resolve-versions.sh --check-packages",
        "hard_fail": False,
        "publish_false_skip_reason_allowed": "Yes, when upstream packages do not exist for a supported row; keep publish: false with a clear skip_reason until packages resolve.",
        "local_command": "make update UPDATE_ARGS=--json",
        "remediation": "Confirm package availability for the PostgreSQL/Debian row. Keep unsupported rows skipped with skip_reason, or update exact package versions once upstream support exists.",
        "trixie_bookworm_notes": "trixie uses debian13 package builds and is primary; bookworm uses debian12 package builds and may lag as the secondary variant.",
    },
    {
        "reason_id": "tag.policy-invalid",
        "category": "wrong tag policy",
        "applies_to": "final tag generation and publish metadata",
        "gate_or_command": "cloudnative-pg-timescaledb/scripts/validate-tags.sh",
        "hard_fail": True,
        "publish_false_skip_reason_allowed": "No. A tag policy violation means the candidate identity is unsafe to publish.",
        "local_command": "make validate or bash cloudnative-pg-timescaledb/scripts/validate-tags.sh --metadata cloudnative-pg-timescaledb/versions.yaml --date 20260609",
        "remediation": "Regenerate tags from metadata and TAG_VALIDATION_DATE. Primary trixie tags omit the Debian suffix; secondary bookworm tags include -bookworm.",
        "trixie_bookworm_notes": "trixie is the primary suffixless tag line; bookworm must include the -bookworm suffix on immutable and rolling tags.",
    },
    {
        "reason_id": "tag.latest-invalid",
        "category": "wrong latest",
        "applies_to": "matrix, publish metadata, and docs examples",
        "gate_or_command": "validate_latest in generators and docs validation",
        "hard_fail": True,
        "publish_false_skip_reason_allowed": "No. Wrong latest assignment must be fixed in metadata or tag generation before release.",
        "local_command": "make matrix && make validate",
        "remediation": "Keep latest_eligible true only for PostgreSQL 18 on trixie. Do not assign latest to PostgreSQL 17, bookworm, or experimental 19beta1 rows.",
        "trixie_bookworm_notes": "trixie PostgreSQL 18 is the only latest target; bookworm never receives latest.",
    },
    {
        "reason_id": "postgresql.pg19-experimental-policy",
        "category": "PostgreSQL 19beta1 experimental failures",
        "applies_to": "metadata, matrix, tag, catalog, and publish gates",
        "gate_or_command": "make validate and release promotion gates",
        "hard_fail": False,
        "publish_false_skip_reason_allowed": "Yes. PostgreSQL 19beta1 should remain experimental and publish: false until upstream package and release policy explicitly allow it.",
        "local_command": "make matrix && make validate",
        "remediation": "Keep experimental: true, latest_eligible: false, no normal rolling tag, and a skip_reason explaining the upstream support gap.",
        "trixie_bookworm_notes": "same",
    },
    {
        "reason_id": "build.docker-failed",
        "category": "Docker build failures",
        "applies_to": "candidate build workflow and local Bake targets",
        "gate_or_command": ".github/workflows/build.yml and make build",
        "hard_fail": True,
        "publish_false_skip_reason_allowed": "No. A Docker build failure for a publishable row must be fixed; rows intentionally disabled before build should use a metadata or package skip_reason instead.",
        "local_command": "make build PG=18 DEBIAN=trixie",
        "remediation": "Inspect the generated Dockerfile, CNPG base digest, package install output, and platform list; regenerate after metadata or template fixes.",
        "trixie_bookworm_notes": "trixie package names use debian13 versions; bookworm package names use debian12 versions and may fail for different repository availability reasons.",
    },
    {
        "reason_id": "runtime.postgresql-startup-failed",
        "category": "PostgreSQL startup failures",
        "applies_to": "container smoke tests and CloudNativePG candidate runtime",
        "gate_or_command": "cloudnative-pg-timescaledb/tests/smoke/container/run.sh and make smoke",
        "hard_fail": True,
        "publish_false_skip_reason_allowed": "No for publishable rows. Runtime startup failure means the image must not be promoted.",
        "local_command": "make smoke PG=18 DEBIAN=trixie CHECKS=container",
        "remediation": "Run the container smoke test locally, inspect PostgreSQL logs, base image labels, extension library paths, and architecture mapping.",
        "trixie_bookworm_notes": "same unless the log points to Debian-specific package files; then compare trixie debian13 and bookworm debian12 package versions.",
    },
    {
        "reason_id": "smoke.sql-extension-failed",
        "category": "SQL smoke failures",
        "applies_to": "extension CREATE EXTENSION and version checks",
        "gate_or_command": "cloudnative-pg-timescaledb/tests/smoke/sql/run.sh and make smoke",
        "hard_fail": True,
        "publish_false_skip_reason_allowed": "No for publishable rows. Extension SQL failure blocks promotion.",
        "local_command": "make smoke PG=18 DEBIAN=trixie CHECKS=sql",
        "remediation": "Verify TimescaleDB, Toolkit, pgvector, and pgaudit availability inside the image; fix package metadata or Dockerfile install steps and regenerate.",
        "trixie_bookworm_notes": "trixie and bookworm can differ by package repository build; confirm the variant-specific package version in versions.yaml.",
    },
    {
        "reason_id": "evidence.sbom-missing",
        "category": "missing SBOM",
        "applies_to": "release evidence and publish promotion",
        "gate_or_command": "release evidence verification gate",
        "hard_fail": True,
        "publish_false_skip_reason_allowed": "No. Missing SBOM evidence blocks normal release promotion.",
        "local_command": "make validate and inspect release-evidence.json for sbom_ref coverage",
        "remediation": "Re-run the candidate build with BuildKit SBOM attestations enabled and verify every index and platform digest has sbom_ref evidence.",
        "trixie_bookworm_notes": "same",
    },
    {
        "reason_id": "evidence.provenance-missing",
        "category": "missing provenance",
        "applies_to": "release evidence and publish promotion",
        "gate_or_command": "release evidence verification gate",
        "hard_fail": True,
        "publish_false_skip_reason_allowed": "No. Missing provenance evidence blocks normal release promotion.",
        "local_command": "make validate and inspect release-evidence.json for provenance_ref coverage",
        "remediation": "Re-run the candidate build with provenance attestations enabled and verify every index and platform digest has provenance_ref evidence.",
        "trixie_bookworm_notes": "same",
    },
    {
        "reason_id": "evidence.signature-missing",
        "category": "missing signature",
        "applies_to": "cosign signing and release evidence verification",
        "gate_or_command": "cosign sign and release evidence verification gate",
        "hard_fail": True,
        "publish_false_skip_reason_allowed": "No. Missing signature evidence blocks normal release promotion.",
        "local_command": "make validate and inspect release-evidence.json for signature_ref coverage",
        "remediation": "Re-run keyless cosign signing from the build workflow identity and verify signature_ref plus verification_ref for every digest.",
        "trixie_bookworm_notes": "same",
    },
    {
        "reason_id": "scan.vulnerability-threshold-failed",
        "category": "vulnerability threshold failures",
        "applies_to": "Trivy vulnerability gate and SARIF evidence",
        "gate_or_command": ".github/workflows/security-scan.yml",
        "hard_fail": True,
        "publish_false_skip_reason_allowed": "No for normal releases. Unignored HIGH or CRITICAL findings, scanner database failures, or undeclared ignores block promotion.",
        "local_command": "trivy image --scanners vuln --severity HIGH,CRITICAL --ignorefile cloudnative-pg-timescaledb/config/vulnerability-ignore.yaml <image-ref>",
        "remediation": "Update base/package metadata to a fixed version or add a reviewed explicit ignore in the committed vulnerability ignore policy when justified.",
        "trixie_bookworm_notes": "trixie and bookworm may have different Debian package CVE status; treat each variant's scan result independently.",
    },
    {
        "reason_id": "catalog.reference-invalid",
        "category": "catalog reference failures",
        "applies_to": "CloudNativePG ClusterImageCatalog generation and validation",
        "gate_or_command": "cloudnative-pg-timescaledb/scripts/generate-catalog.sh --validate-catalog",
        "hard_fail": True,
        "publish_false_skip_reason_allowed": "No. Catalogs must reference only release-complete published image refs with digest, signature, SBOM, provenance, and scan evidence.",
        "local_command": "make catalog && make validate",
        "remediation": "Regenerate catalogs from release metadata; remove unpublished refs, tag-only refs, per-platform digests, experimental rows, and wrong Debian variant entries.",
        "trixie_bookworm_notes": "trixie catalog is primary and bookworm catalog is secondary; both must contain only matching variant release metadata.",
    },
]


def diag(command, artifact, expected, actual, remediation):
    raise SystemExit(
        f"command: {command}\n"
        f"artifact: {artifact}\n"
        f"expected: {expected}\n"
        f"actual: {actual}\n"
        f"remediation: {remediation}"
    )


def parse_scalar(raw):
    value = raw.strip()
    if value == "":
        return ""
    if value.startswith("[") and value.endswith("]"):
        inner = value[1:-1].strip()
        if not inner:
            return []
        return [parse_scalar(part.strip()) for part in inner.split(",")]
    if value == "true":
        return True
    if value == "false":
        return False
    if value in {"null", "~"}:
        return None
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        return value[1:-1]
    if re.fullmatch(r"-?(0|[1-9][0-9]*)", value):
        return int(value)
    return value


def parse_mapping_item(text, line_no, command, path):
    if ":" not in text:
        diag(command, path, "parseable metadata YAML subset", f"line {line_no}: {text!r}", "Use simple key/value YAML for generator metadata.")
    key, raw_value = text.split(":", 1)
    return key.strip(), parse_scalar(raw_value)


def assign_mapping(target, key, value, line_no, scope, command, path):
    if key in target:
        diag(command, path, "unique YAML mapping keys", f"duplicate key {key!r} at line {line_no} in {scope}", "Remove duplicate metadata keys.")
    target[key] = value


def parse_metadata(path, command):
    data = {}
    current_top = None
    current_entry = None
    try:
        text = path.read_text()
    except FileNotFoundError:
        diag(command, path, "metadata file exists", str(path), "Create metadata before running generators.")
    for line_no, raw_line in enumerate(text.splitlines(), start=1):
        line = raw_line.rstrip()
        if line.strip() == "" or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip(" "))
        item = line.lstrip(" ")
        if indent == 0:
            key, value = parse_mapping_item(item, line_no, command, path)
            if item.endswith(":"):
                value = [] if key == "entries" else {}
            assign_mapping(data, key, value, line_no, "top-level metadata", command, path)
            current_top = key if isinstance(value, (dict, list)) else None
            current_entry = None
            continue
        if indent == 2 and current_top == "entries":
            if not item.startswith("- "):
                diag(command, path, "entries list item", f"line {line_no}: {item!r}", "Use '- key: value' entry mappings.")
            current_entry = {}
            data["entries"].append(current_entry)
            key, value = parse_mapping_item(item[2:].strip(), line_no, command, path)
            assign_mapping(current_entry, key, value, line_no, "entries[] item", command, path)
            continue
        if indent == 2 and isinstance(data.get(current_top), dict):
            key, value = parse_mapping_item(item, line_no, command, path)
            assign_mapping(data[current_top], key, value, line_no, current_top, command, path)
            continue
        if indent == 4 and current_top == "entries" and isinstance(current_entry, dict):
            key, value = parse_mapping_item(item, line_no, command, path)
            assign_mapping(current_entry, key, value, line_no, "entries[] item", command, path)
            continue
        diag(command, path, "parseable metadata YAML subset", f"line {line_no}: {line!r}", "Use the versions.yaml schema indentation.")
    return data


def validate_metadata_shape(data, command, artifact):
    required_top = {"schema_version", "image", "allowed", "entries"}
    optional_top = {"barman_plugin"}
    if not required_top.issubset(data) or set(data) - required_top - optional_top:
        diag(command, artifact, f"top-level keys include {sorted(required_top)} and optional {sorted(optional_top)}", f"actual {sorted(data)}", "Use the versions.yaml metadata contract.")
    allowed = data["allowed"]
    expected_allowed = {
        "postgres_majors": ["17", "18", "19beta1"],
        "debian_variants": ["trixie", "bookworm"],
        "platforms": ["linux/amd64", "linux/arm64"],
    }
    if not isinstance(allowed, dict) or set(allowed) != set(expected_allowed):
        diag(command, artifact, f"allowed keys exactly {sorted(expected_allowed)}", repr(allowed), "Keep generator dimensions explicit.")
    for key, expected in expected_allowed.items():
        if allowed[key] != expected:
            diag(command, artifact, f"allowed.{key} exactly {expected!r}", repr(allowed[key]), "Do not broaden generator scope outside planning.")
    if not isinstance(data["entries"], list) or not data["entries"]:
        diag(command, artifact, "entries is non-empty list", type(data["entries"]).__name__, "Define image entries before generation.")


def row_id(entry):
    return f"{entry['pg_major']}-{entry['debian_variant']}"


def dockerfile_path(entry, output_root="cloudnative-pg-timescaledb/generated"):
    return f"{output_root.rstrip('/')}/{entry['pg_major']}/{entry['debian_variant']}/Dockerfile"


def skipped_marker_path(entry, output_root="cloudnative-pg-timescaledb/generated"):
    return f"{output_root.rstrip('/')}/{entry['pg_major']}/{entry['debian_variant']}/Dockerfile.skipped.json"


def generated_date():
    value = os.environ.get("DOCKERFILE_GENERATED_DATE", "2026-06-09")
    if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", value):
        diag("generate-dockerfiles", "DOCKERFILE_GENERATED_DATE", "UTC YYYY-MM-DD", value, "Set DOCKERFILE_GENERATED_DATE to a deterministic UTC date.")
    return value


def bake_target(entry):
    return f"pg{entry['pg_major']}-{entry['debian_variant']}"


def bake_context_path():
    return "cloudnative-pg-timescaledb"


def bake_hcl_dockerfile_path(entry):
    return f"generated/{entry['pg_major']}/{entry['debian_variant']}/Dockerfile"


def image_ref(data, entry):
    registry = data["image"]["registry"]
    repo = data["image"]["repository"]
    tag = f"{entry['pg_major']}-pg{entry['pg_version']}-ts{entry['timescaledb_version'] or 'unresolved'}-00000000"
    if entry["debian_variant"] != "trixie":
        tag = f"{tag}-{entry['debian_variant']}"
    return f"{registry}/{repo}:{tag}"


def release_date(command="generate-matrix"):
    value = os.environ.get("TAG_VALIDATION_DATE") or os.environ.get("DATE") or "20260609"
    try:
        return resolve_release_date(os.environ)
    except ValueError as exc:
        diag(command, "TAG_VALIDATION_DATE/DATE", "valid UTC YYYYMMDD", value, f"{exc}. Set TAG_VALIDATION_DATE or DATE to a deterministic UTC release date.")


def validate_latest(entries, command, artifact):
    latest = [(entry["pg_major"], entry["debian_variant"]) for entry in entries if entry["latest_eligible"]]
    if latest != [("18", "trixie")]:
        diag(command, artifact, "18-trixie is the sole latest_eligible row", repr(latest), "Preserve latest eligibility exactly from metadata.")


def dockerfiles_summary(entries, output_root="cloudnative-pg-timescaledb/generated"):
    return {
        "dockerfiles": [
            {
                "pg_major": entry["pg_major"],
                "debian_variant": entry["debian_variant"],
                "dockerfile": dockerfile_path(entry, output_root) if entry["publish"] else "",
                "skipped_marker": "" if entry["publish"] else skipped_marker_path(entry, output_root),
                "source_entry": row_id(entry),
                "publish": entry["publish"],
                "experimental": entry["experimental"],
                "skip_reason": entry["skip_reason"],
                "base_image": f"{CNPG_IMAGE}:{entry['cnpg_tag']}@{entry['cnpg_digest']}" if entry["publish"] else "",
            }
            for entry in entries
        ]
    }


def bake_summary(entries, bake_file="cloudnative-pg-timescaledb/docker-bake.hcl"):
    return {
        "bake_file": bake_file,
        "targets": [
            {
                "name": bake_target(entry),
                "context": bake_context_path(),
                "dockerfile": bake_hcl_dockerfile_path(entry),
                "platforms": entry["platforms"],
                "publish": entry["publish"],
                "experimental": entry["experimental"],
            }
            for entry in entries if entry["publish"]
        ],
        "skipped": [
            {
                "pg_major": entry["pg_major"],
                "debian_variant": entry["debian_variant"],
                "name": bake_target(entry),
                "dockerfile": dockerfile_path(entry),
                "publish": entry["publish"],
                "experimental": entry["experimental"],
                "skip_reason": entry["skip_reason"],
            }
            for entry in entries if not entry["publish"]
        ],
    }


def matrix_schema_doc():
    return """# Generated Matrix Schema

<!-- Generated by cloudnative-pg-timescaledb/scripts/generate-matrix.sh from cloudnative-pg-timescaledb/versions.yaml. -->

`generate-matrix.sh --json` emits compact JSON with top-level `include[]` and `skipped[]` arrays.

Required `include[]` keys:

| Key | Meaning |
| --- | --- |
| `pg_major` | PostgreSQL major from metadata, including experimental `19beta1`. |
| `pg_version` | PostgreSQL version from metadata. |
| `timescaledb_version` | TimescaleDB version used in immutable tags. |
| `debian_variant` | Debian variant, with `trixie` primary and `bookworm` secondary. |
| `image` | Registry/repository from metadata. |
| `candidate_ref` | Candidate image reference using the immutable intended tag. |
| `digest` | Produced image digest; empty until release jobs populate it. |
| `platforms` | Required build platforms. |
| `bake_target` | Generated Docker Bake target. |
| `dockerfile` | Generated Dockerfile path. |
| `intended_tags` | Tag-policy output generated from metadata and `TAG_VALIDATION_DATE`. |
| `publish` | Always `true` for `include[]`. |
| `experimental` | Experimental release marker; `19beta1` rows stay `true`. |
| `latest_eligible` | `true` only for PostgreSQL `18` on `trixie`. |
| `scan_result` | Vulnerability scan result placeholder; empty until later release gates. |
| `sbom_ref` | SBOM artifact reference placeholder. |
| `provenance_ref` | Provenance artifact reference placeholder. |
| `signature_ref` | Signature artifact reference placeholder. |

`skipped[]` entries retain `publish: false`, PostgreSQL/Debian identity fields, `platforms`, `experimental`, `latest_eligible`, and `skip_reason` for workflow summaries.
"""


def release_candidate_schema_doc():
    return """# Release Candidate Metadata Schema

<!-- Generated by cloudnative-pg-timescaledb/scripts/generate-docs.sh from cloudnative-pg-timescaledb/versions.yaml. -->

Story 4.2 emits one JSON object per smoked platform candidate. Downstream release gates must consume this immutable metadata instead of recomputing release state.

Required keys:

| Key | Meaning |
| --- | --- |
| `image` | Registry and repository, without tag. |
| `candidate_ref` | Candidate-only image reference pushed by the candidate build job. It must not be a final release tag or `latest`. |
| `candidate_digest` | Immutable digest addressed by this candidate record. |
| `platform_digest` | Single-platform digest for the record's `platform`. |
| `index_digest` | Multi-platform candidate index digest created only after every listed platform smoke gate passes. |
| `platform_digests` | Object keyed by platform string with one immutable digest per publishable platform. Keys must exactly match `platforms`. |
| `platform` | Platform smoked by this record, such as `linux/amd64` or `linux/arm64`. |
| `platforms` | Full publishable platform set for the image row. |
| `expected_platform` | Expected runtime platform for `dpkg --print-architecture` mapping. |
| `runtime_architecture` | Raw architecture reported by `dpkg --print-architecture` inside the candidate image. |
| `smoke_architecture_status` | `passed` only after runtime architecture maps to `expected_platform`. |
| `bake_target` | Generated Docker Bake target. |
| `dockerfile` | Generated Dockerfile path used by the Bake target. |
| `pg_major` | PostgreSQL major from metadata. |
| `pg_version` | PostgreSQL version from metadata. |
| `debian_variant` | Debian variant from metadata. |
| `intended_tags` | Final tags that later stories may promote after all gates pass; Story 4.2 must not push them. |
| `publish` | Must be `true` for candidate publish-path records. |
| `experimental` | Must be `false` for candidate publish-path records. |
| `latest_eligible` | Metadata marker for later tag promotion decisions. |
| `smoke_container_status` | `passed` only after container smoke succeeds for this platform candidate. |
| `smoke_sql_status` | `passed` only after SQL smoke succeeds for this platform candidate. |

Digest rules:

- `candidate_digest`, `platform_digest`, `index_digest`, and every `platform_digests` value must use `sha256:<64 lowercase hex>`.
- `platform_digest` must equal `platform_digests[platform]`.
- `index_digest` must be distinct from all per-platform digests.
- `platform_digests` keys must exactly match `platforms`; missing, extra, or duplicate platform coverage is invalid.
- Candidate metadata is valid only after container, SQL, and architecture smoke statuses are all `passed`.
"""


def release_evidence_schema_doc():
    return """# Release Evidence Schema

<!-- Generated by cloudnative-pg-timescaledb/scripts/generate-docs.sh from cloudnative-pg-timescaledb/versions.yaml. -->

Story 4.4 emits one JSON object per release candidate image row after build, smoke, vulnerability scan, SBOM/provenance attestation, keyless cosign signing, and exact identity verification pass.

Required top-level keys:

| Key | Meaning |
| --- | --- |
| `image` | Registry and repository, without tag. |
| `candidate_digest` | Immutable candidate platform digest carried from Story 4.2 metadata. |
| `index_digest` | Final multi-platform candidate index digest that later tag promotion will reference. |
| `platform_digests` | Object keyed by platform string with every required platform digest. |
| `per_digest_evidence` | Array containing one evidence record for `index_digest` and one record for every `platform_digests` value. |
| `scan_result` | Must be `passed` from the same-run Story 4.3 vulnerability gate. |
| `expected_certificate_identity` | Exact workflow identity used for cosign verification: `https://github.com/pnetcloud/containers/.github/workflows/build.yml@<ref>`. |
| `cosign_certificate_issuer` | Must be `https://token.actions.githubusercontent.com`. |
| `verified` | Must be `true` only after every digest has passing verification. |

Required `per_digest_evidence[]` keys:

| Key | Meaning |
| --- | --- |
| `digest` | The index or platform digest covered by this evidence record. |
| `sbom_ref` | Immutable GHCR subject reference for the BuildKit SBOM attestation. |
| `provenance_ref` | Immutable GHCR subject reference for the BuildKit provenance attestation. |
| `signature_ref` | Immutable GHCR subject reference for the keyless cosign signature. |
| `verification_ref` | Immutable GHCR subject reference for the verification result. |
| `verification_path` | Relative path inside the release evidence artifact containing raw `cosign verify` JSON output. |
| `attestation_path` | Relative path inside the release evidence artifact containing raw BuildKit attestation index inspection output. |
| `signed_digest` | Digest passed to `cosign sign`; must equal `digest`. |
| `verification_identity` | Exact certificate identity used by `cosign verify`. |
| `verification_issuer` | OIDC issuer used by `cosign verify`; must be GitHub Actions. |
| `verified` | Must be `true` for this digest. |

Digest and verification rules:

- `candidate_digest`, `index_digest`, every `platform_digests` value, `digest`, and `signed_digest` must use `sha256:<64 lowercase hex>`.
- `per_digest_evidence` coverage must exactly equal `index_digest` plus every platform digest; missing, duplicate, or extra digest records are invalid.
- `sbom_ref`, `provenance_ref`, `signature_ref`, and `verification_ref` must be immutable `ghcr.io/...@sha256:<digest>` references bound to the same `image` and `digest` as the record.
- `verification_path` and `attestation_path` must resolve to files inside the uploaded evidence artifact; validators must parse those files instead of trusting self-asserted booleans.
- `scan_result`, top-level `verified`, and every per-digest `verified` value must be passing before later stories may publish final tags.
- Verification must use exact `--certificate-identity` and `--certificate-oidc-issuer https://token.actions.githubusercontent.com`; broad identity regexes are not valid release evidence.
"""


def matrix_schema_path(matrix_output):
    if not matrix_output:
        return "cloudnative-pg-timescaledb/docs/generated/matrix-schema.md"
    output_path = Path(matrix_output)
    return (output_path.parent / "docs" / "generated" / "matrix-schema.md").as_posix()


def matrix_summary(data, entries):
    date = release_date()
    registry = data["image"]["registry"]
    repo = data["image"]["repository"]
    image = f"{registry}/{repo}"
    include = []
    skipped = []
    for entry in entries:
        if entry["publish"]:
            try:
                tags = generated_tags(entry, date)
            except ValueError as exc:
                diag("generate-matrix", row_id(entry), "generated tags use valid Docker tag grammar", str(exc), "Fix metadata values used in tag policy before generating matrix rows.")
            immutable_tag = next((tag for tag in tags if "-pg" in tag and "-ts" in tag), tags[0])
            include.append(
                {
                    "pg_major": entry["pg_major"],
                    "pg_version": entry["pg_version"],
                    "timescaledb_version": entry["timescaledb_version"],
                    "debian_variant": entry["debian_variant"],
                    "image": image,
                    "candidate_ref": f"{image}:{immutable_tag}",
                    "digest": "",
                    "platforms": entry["platforms"],
                    "bake_target": bake_target(entry),
                    "dockerfile": dockerfile_path(entry),
                    "intended_tags": tags,
                    "publish": True,
                    "experimental": entry["experimental"],
                    "latest_eligible": entry["latest_eligible"],
                    "scan_result": "pending",
                    "sbom_ref": "",
                    "provenance_ref": "",
                    "signature_ref": "",
                }
            )
        else:
            skipped.append(
                {
                    "pg_major": entry["pg_major"],
                    "pg_version": entry["pg_version"],
                    "debian_variant": entry["debian_variant"],
                    "platforms": entry["platforms"],
                    "publish": False,
                    "experimental": entry["experimental"],
                    "latest_eligible": entry["latest_eligible"],
                    "skip_reason": entry["skip_reason"],
                }
            )
    return {
        "include": include,
        "skipped": skipped,
    }


def digest_ref(image, tag, digest):
    return f"{image}:{tag}@{digest}"


def numeric_pg_major(pg_major):
    match = re.match(r"^([0-9]+)", str(pg_major))
    return match.group(1) if match else str(pg_major)


def immutable_release_tag(entry, tags, command, artifact):
    tags = tags if isinstance(tags, list) else []
    suffix = "" if entry["debian_variant"] == "trixie" else f"-{entry['debian_variant']}"
    prefix = f"{entry['pg_major']}-pg{entry['pg_version']}-ts{entry['timescaledb_version'] or 'unresolved'}-"
    candidates = []
    for tag in tags:
        if not isinstance(tag, str) or not tag.startswith(prefix) or not tag.endswith(suffix):
            continue
        if entry["debian_variant"] == "trixie" and any(tag.endswith(f"-{variant}") for variant in ["bookworm"]):
            continue
        candidates.append(tag)
    if len(candidates) != 1:
        diag(command, artifact, f"one immutable final tag for {row_id(entry)} with prefix {prefix!r} and suffix {suffix!r}", tags, "Publish metadata must include the exact immutable release tag before catalog generation.")
    return candidates[0]


def release_metadata_paths(paths):
    result = []
    for raw in paths or []:
        path = Path(raw)
        if path.is_dir():
            result.extend(sorted(child for child in path.rglob("*.json") if child.is_file()))
        else:
            result.append(path)
    return result


def release_entry_match(entry, payload, command, artifact):
    tags = payload.get("final_tags")
    if not isinstance(tags, list):
        diag(command, artifact, "release metadata final_tags is a list", repr(tags), "Use Story 4.5 ghcr-release-metadata.json artifacts.")
    try:
        immutable_release_tag(entry, tags, command, artifact)
    except SystemExit:
        return False
    return True


def load_release_records(data, entries, release_metadata, command):
    records = {}
    artifacts = {}
    paths = release_metadata_paths(release_metadata)
    for path in paths:
        try:
            payload = json.loads(path.read_text())
        except FileNotFoundError:
            diag(command, path, "release metadata file exists", str(path), "Pass a Story 4.5 ghcr-release-metadata.json file or a directory containing those files.")
        except json.JSONDecodeError as exc:
            diag(command, path, "release metadata is JSON", str(exc), "Use the Story 4.5 release metadata JSON artifact.")
        if isinstance(payload, list):
            for index, row in enumerate(payload):
                if not isinstance(row, dict):
                    diag(command, path, "release metadata list contains objects", f"index {index}: {type(row).__name__}", "Use release metadata JSON objects.")
                key, record = normalize_release_record(data, entries, row, command, f"{path}#{index}")
                if key in records and records[key] != record:
                    duplicate_release_record_diag(command, key, artifacts[key], f"{path}#{index}", records[key], record)
                records[key] = record
                artifacts[key] = f"{path}#{index}"
        elif isinstance(payload, dict):
            key, record = normalize_release_record(data, entries, payload, command, str(path))
            if key in records and records[key] != record:
                duplicate_release_record_diag(command, key, artifacts[key], str(path), records[key], record)
            records[key] = record
            artifacts[key] = str(path)
        else:
            diag(command, path, "release metadata is an object or list of objects", type(payload).__name__, "Use Story 4.5 ghcr-release-metadata.json artifacts.")
    return records


def duplicate_release_record_diag(command, key, first_artifact, second_artifact, first, second):
    diag(
        command,
        second_artifact,
        "one release metadata record per PostgreSQL/Debian entry",
        {
            "duplicate_key": f"{key[0]}-{key[1]}",
            "first_artifact": first_artifact,
            "second_artifact": second_artifact,
            "first_release_metadata_record_id": first.get("release_metadata_record_id"),
            "second_release_metadata_record_id": second.get("release_metadata_record_id"),
            "first_digest": first.get("digest"),
            "second_digest": second.get("digest"),
        },
        "Keep only one release-complete metadata record for each catalog row before generating catalogs.",
    )


def normalize_release_record(data, entries, payload, command, artifact):
    image = f"{data['image']['registry']}/{data['image']['repository']}"
    required = {
        "image", "release_metadata_record_id", "release_metadata_ref", "published_digest",
        "final_tags", "scan_result", "sbom_ref", "provenance_ref", "signature_ref",
        "verified", "index_digest", "platform_digests", "promotion_status",
        "candidate_digest", "cosign_certificate_identity", "cosign_certificate_issuer",
    }
    missing = sorted(required - set(payload))
    if missing:
        diag(command, artifact, f"release metadata includes {sorted(required)}", f"missing {missing}", "Use release-complete metadata emitted by the publish job.")
    if payload.get("image") != image:
        diag(command, artifact, f"release metadata image is {image}", payload.get("image"), "Do not mix catalogs with another image repository.")
    published_digest = payload.get("published_digest")
    index_digest = payload.get("index_digest")
    if not isinstance(published_digest, str) or not DIGEST_RE.fullmatch(published_digest):
        diag(command, artifact, "published_digest is sha256:<64 lowercase hex>", repr(published_digest), "Catalogs must pin the manifest-list digest.")
    candidate_digest = payload.get("candidate_digest")
    if not isinstance(candidate_digest, str) or not DIGEST_RE.fullmatch(candidate_digest):
        diag(command, artifact, "candidate_digest is sha256:<64 lowercase hex>", repr(candidate_digest), "Carry candidate digest lineage from Story 4.5 release metadata.")
    if candidate_digest == published_digest:
        diag(command, artifact, "candidate_digest is distinct from published index digest", candidate_digest, "Keep platform candidate lineage separate from the manifest-list digest.")
    if index_digest != published_digest:
        diag(command, artifact, "published_digest equals index_digest", {"published_digest": published_digest, "index_digest": index_digest}, "Use the published multi-platform manifest-list digest, not a platform digest.")
    platform_digests = payload.get("platform_digests")
    if not isinstance(platform_digests, dict) or not platform_digests:
        diag(command, artifact, "platform_digests is a non-empty object", repr(platform_digests), "Carry every publishable platform digest into release metadata.")
    if published_digest in set(platform_digests.values()):
        diag(command, artifact, "published_digest is distinct from per-platform digests", published_digest, "Use the manifest-list digest in catalogs.")
    if payload.get("scan_result") != "passed" or payload.get("verified") is not True or payload.get("promotion_status") != "validated":
        diag(command, artifact, "release metadata is scan-passed, verified, and promotion_status validated", {"scan_result": payload.get("scan_result"), "verified": payload.get("verified"), "promotion_status": payload.get("promotion_status")}, "Catalog generation requires release-complete publish metadata.")
    for key in ["sbom_ref", "provenance_ref", "signature_ref"]:
        value = payload.get(key)
        if not isinstance(value, str) or not value.startswith(f"{image}@{published_digest}"):
            diag(command, artifact, f"{key} is bound to the published digest", value, "Do not catalog unsigned or unprovenanced digests.")
    identity = payload.get("cosign_certificate_identity")
    issuer = payload.get("cosign_certificate_issuer")
    if not isinstance(identity, str) or not re.fullmatch(r"https://github.com/[^/]+/[^/]+/\.github/workflows/build\.yml@refs/(heads|tags)/.+", identity):
        diag(command, artifact, "cosign_certificate_identity is exact build.yml workflow ref", identity, "Carry signer identity from Story 4.5 release metadata.")
    if issuer != "https://token.actions.githubusercontent.com":
        diag(command, artifact, "cosign_certificate_issuer is GitHub Actions OIDC", issuer, "Carry signer issuer from Story 4.5 release metadata.")
    if payload.get("release_metadata_ref") != f"{image}@{published_digest}":
        diag(command, artifact, "release_metadata_ref is bound to published digest", payload.get("release_metadata_ref"), "Keep release metadata identity tied to the digest being cataloged.")
    matches = [entry for entry in entries if release_entry_match(entry, payload, command, artifact)]
    if len(matches) != 1:
        diag(command, artifact, "release metadata final_tags match exactly one versions.yaml entry", [row_id(entry) for entry in matches], "Keep final tag policy unambiguous across PostgreSQL and Debian variants.")
    entry = matches[0]
    if set(platform_digests) != set(entry["platforms"]):
        diag(command, artifact, f"platform_digests covers every publishable platform for {row_id(entry)}", {"expected": entry["platforms"], "actual": sorted(platform_digests)}, "Regenerate release metadata only after every publishable platform has completed.")
    for platform, digest in platform_digests.items():
        if not isinstance(digest, str) or not DIGEST_RE.fullmatch(digest):
            diag(command, artifact, f"platform digest for {platform} is sha256:<64 lowercase hex>", repr(digest), "Use immutable platform digests from candidate metadata.")
    tag = immutable_release_tag(entry, payload["final_tags"], command, artifact)
    record = {
        "entry": entry,
        "image": image,
        "tag": tag,
        "digest": published_digest,
        "image_ref": digest_ref(image, tag, published_digest),
        "final_tags": payload["final_tags"],
        "platform_digests": platform_digests,
        "release_metadata_record_id": payload["release_metadata_record_id"],
        "release_metadata_ref": payload["release_metadata_ref"],
    }
    return (entry["pg_major"], entry["debian_variant"]), record


def catalog_summary(data, entries, output_root="cloudnative-pg-timescaledb/catalog", release_metadata=None):
    release_records = load_release_records(data, entries, release_metadata or [], "generate-catalog")
    catalogs = []
    for debian in ["trixie", "bookworm"]:
        rows = []
        for entry in entries:
            if entry["debian_variant"] != debian or entry["experimental"]:
                continue
            record = release_records.get((entry["pg_major"], debian))
            if record:
                rows.append(record)
        catalogs.append(
            {
                "debian_variant": debian,
                "catalog_path": f"{output_root.rstrip('/')}/catalog-standard-{debian}.yaml",
                "entries": [
                    {
                        "pg_major": record["entry"]["pg_major"],
                        "major": int(numeric_pg_major(record["entry"]["pg_major"])),
                        "debian_variant": debian,
                        "image": record["image_ref"],
                        "tag": record["tag"],
                        "digest": record["digest"],
                        "source_entry": row_id(record["entry"]),
                        "platforms": record["entry"]["platforms"],
                        "release_metadata_record_id": record["release_metadata_record_id"],
                    }
                    for record in rows
                ],
            }
        )
    return {"catalogs": catalogs}


def docs_summary(entries, doc_path="cloudnative-pg-timescaledb/docs/generated/compatibility.md", has_barman_plugin=False):
    docs_dir = Path(doc_path).parent
    table_path = (Path(doc_path).parent / "compatibility-table.md").as_posix()
    manifest_paths = [
        (doc_path, "cloudnative-pg-timescaledb/scripts/generate-docs.sh", "1.5", "metadata-rendered compatibility skeleton"),
        (table_path, "cloudnative-pg-timescaledb/scripts/generate-docs.sh", "5.1", "metadata-rendered compatibility table"),
        ((docs_dir / "release-candidate-schema.md").as_posix(), "cloudnative-pg-timescaledb/scripts/generate-docs.sh", "4.2", "static generated schema documentation"),
        ((docs_dir / "release-evidence-schema.md").as_posix(), "cloudnative-pg-timescaledb/scripts/generate-docs.sh", "4.4", "static generated schema documentation"),
        ((docs_dir / "failure-reason-catalog.md").as_posix(), "cloudnative-pg-timescaledb/scripts/generate-docs.sh", "5.8", "static generated failure reason catalog"),
        ((docs_dir / "release-rehearsal-report.md").as_posix(), "cloudnative-pg-timescaledb/scripts/release-rehearsal.sh", "5.9", "dry-run release rehearsal report"),
        ((docs_dir / "matrix-schema.md").as_posix(), "cloudnative-pg-timescaledb/scripts/generate-matrix.sh", "4.1", "static generated matrix schema documentation"),
    ]
    metadata_path = "cloudnative-pg-timescaledb/versions.yaml"
    if has_barman_plugin:
        manifest_paths.append(((docs_dir / "barman-plugin-reference.md").as_posix(), "cloudnative-pg-timescaledb/scripts/generate-docs.sh", "2.7", "metadata-rendered Barman Cloud Plugin reference"))
    return {
        "docs": [
            {
                "doc_path": doc_path,
                "companion_paths": [table_path],
                "source": "cloudnative-pg-timescaledb/versions.yaml",
                "sections": ["compatibility"],
                "publishable_entries": sum(1 for entry in entries if entry["publish"]),
                "experimental_entries": sum(1 for entry in entries if entry["experimental"]),
            }
        ],
        "generated_docs_manifest": [
            {
                "path": path,
                "generator_input": metadata_path,
                "generator_command": command,
                "owner_story": owner_story,
                "deterministic_generation_mode": mode,
            }
            for path, command, owner_story, mode in manifest_paths
        ],
    }


def render_dockerfile(entry):
    template = DOCKERFILE_TEMPLATE.read_text()
    values = {
        "source_entry": row_id(entry),
        "source_repository": SOURCE_REPOSITORY,
        "generated_date": generated_date(),
        "pg_major": entry["pg_major"],
        "pg_version": entry["pg_version"],
        "debian_variant": entry["debian_variant"],
        "cnpg_tag": entry["cnpg_tag"],
        "cnpg_digest": entry["cnpg_digest"],
        "timescaledb_version": entry["timescaledb_version"],
        "timescaledb_package_name": entry["timescaledb_package_name"],
        "timescaledb_package_version": entry["timescaledb_package_version"],
        "toolkit_version": entry["toolkit_version"],
        "toolkit_package_name": entry["toolkit_package_name"],
        "toolkit_package_version": entry["toolkit_package_version"],
        "pgvector_source": entry["pgvector_source"],
        "pgvector_package_version": entry["pgvector_package_version"],
        "pgaudit_source": entry["pgaudit_source"],
        "pgaudit_package_version": entry["pgaudit_package_version"],
    }
    rendered = template
    for key, value in values.items():
        rendered = rendered.replace("{{" + key + "}}", str(value))
    unresolved = re.findall(r"{{[^}]+}}", rendered)
    if unresolved:
        diag("generate-dockerfiles", DOCKERFILE_TEMPLATE, "all Dockerfile template variables resolved", unresolved, "Update template variables and generator values together.")
    forbidden_reference_tree = "vendor" + "/"
    if forbidden_reference_tree in rendered:
        diag("generate-dockerfiles", DOCKERFILE_TEMPLATE, "generated Dockerfile contains no reference-tree build or runtime input", forbidden_reference_tree, "Do not use vendored trees as build context or runtime input.")
    return rendered


def render_skipped_marker(entry):
    payload = {
        "pg_major": entry["pg_major"],
        "debian_variant": entry["debian_variant"],
        "source_entry": row_id(entry),
        "publish": False,
        "buildable": False,
        "skip_reason": entry["skip_reason"],
    }
    return json.dumps(payload, indent=2, sort_keys=True) + "\n"


def cnpg_reference(entry):
    return f"{CNPG_IMAGE}:{entry['cnpg_tag']}@{entry['cnpg_digest']}"


def manifest_platforms_from_fixture(entry, reference, fixture):
    payload = json.loads(Path(fixture).read_text())
    if "refs" in payload:
        ref_payload = payload["refs"].get(reference)
        return None if ref_payload is None else ref_payload.get("platforms", [])
    for manifest in payload.get("manifests", []):
        if manifest.get("tag") == entry["cnpg_tag"] and manifest.get("digest") == entry["cnpg_digest"]:
            return manifest.get("platforms", [])
    return None


def manifest_platforms_live(reference, command, artifact):
    attempts = []
    raw = ""
    if shutil.which("docker"):
        docker = subprocess.run(["docker", "buildx", "imagetools", "inspect", reference, "--raw"], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        attempts.append(f"docker buildx imagetools inspect: exit {docker.returncode}; stderr {docker.stderr.strip()[:300]}")
        raw = docker.stdout if docker.returncode == 0 else ""
    else:
        attempts.append("docker: executable not found")
    if not raw and shutil.which("skopeo"):
        skopeo = subprocess.run(["skopeo", "inspect", "--raw", f"docker://{reference}"], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        attempts.append(f"skopeo inspect: exit {skopeo.returncode}; stderr {skopeo.stderr.strip()[:300]}")
        raw = skopeo.stdout if skopeo.returncode == 0 else ""
    elif not raw:
        attempts.append("skopeo: executable not found")
    if not raw:
        diag(command, artifact, f"CNPG manifest resolves for {reference}", "; ".join(attempts), "Install docker buildx or skopeo, or set CNPG_MANIFEST_FIXTURE for deterministic tests.")
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as exc:
        diag(command, artifact, f"CNPG manifest inspection returns JSON for {reference}", str(exc), "Use docker buildx imagetools or skopeo with raw manifest JSON output.")
    platforms = []
    for manifest in payload.get("manifests", []):
        platform = manifest.get("platform", {})
        if platform.get("os") and platform.get("architecture"):
            platforms.append(f"{platform['os']}/{platform['architecture']}")
    if not platforms and payload.get("os") and payload.get("architecture"):
        platforms.append(f"{payload['os']}/{payload['architecture']}")
    return platforms


def validate_publishable_dockerfile_entry(entry, command, artifact):
    if entry["debian_variant"] not in {"trixie", "bookworm"}:
        diag(command, artifact, "publishable debian_variant is trixie or bookworm", entry["debian_variant"], "Use only supported Debian variants before generating install logic.")
    platform_set = set(entry["platforms"])
    if platform_set != {"linux/amd64", "linux/arm64"} or len(entry["platforms"]) != 2:
        diag(command, artifact, "publishable platforms exactly linux/amd64 and linux/arm64", entry["platforms"], "Validate apt architecture mappings before publishing.")
    if "-standard-" not in entry["cnpg_tag"] or "-system-" in entry["cnpg_tag"]:
        diag(command, artifact, "publishable cnpg_tag uses standard-* and never system-*", entry["cnpg_tag"], "Use CloudNativePG standard image tags only.")
    if not DIGEST_RE.fullmatch(entry["cnpg_digest"]):
        diag(command, artifact, "publishable cnpg_digest matches sha256:<64 lowercase hex>", entry["cnpg_digest"], "Resolve and store a digest-pinned CNPG base image before publishing.")
    required_package_fields = ["timescaledb_package_name", "timescaledb_package_version", "toolkit_package_name", "toolkit_package_version"]
    missing_package_fields = [field for field in required_package_fields if not str(entry.get(field, "")).strip()]
    if missing_package_fields:
        diag(command, artifact, "publishable TimescaleDB and Toolkit package names/versions are resolved in metadata", missing_package_fields, "Run package resolution before setting publish: true.")
    for extension in ["pgvector", "pgaudit"]:
        source = entry.get(f"{extension}_source", "")
        version = entry.get(f"{extension}_package_version", "")
        if source not in {"base", "package"}:
            diag(command, artifact, f"publishable {extension}_source is base or package", repr(source), "Set explicit extension source metadata before publishing.")
        if source == "package" and not str(version).strip():
            diag(command, artifact, f"publishable {extension} package source has exact package version", repr(version), "Resolve package version metadata for package-sourced extensions.")
        if source == "base" and str(version).strip():
            diag(command, artifact, f"publishable {extension} base source has empty package version", repr(version), "Base-sourced extensions are verified from the CNPG standard image, not package-installed.")
    reference = cnpg_reference(entry)
    fixture = os.environ.get("CNPG_MANIFEST_FIXTURE", "")
    platforms = manifest_platforms_from_fixture(entry, reference, fixture) if fixture else manifest_platforms_live(reference, command, artifact)
    if platforms is None:
        diag(command, artifact, f"CNPG manifest fixture resolves {reference}", "missing reference", "Add the publishable CNPG reference and platform list to the fixture.")
    missing = sorted(set(entry["platforms"]) - set(platforms))
    if missing:
        diag(command, artifact, f"CNPG manifest for {reference} includes metadata platforms {entry['platforms']}", f"actual platforms {platforms}; missing {missing}", "Use a CNPG digest that resolves for every metadata platform.")


def render_bake(entries):
    lines = [
        "# Generated by cloudnative-pg-timescaledb/scripts/generate-bake.sh",
        "# Local build targets are generated from versions.yaml publishable entries.",
        "group \"default\" {",
        "  targets = [",
    ]
    for entry in [row for row in entries if row["publish"]]:
        lines.append(f"    \"{bake_target(entry)}\",")
    lines.extend(["  ]", "}", ""])
    for entry in [row for row in entries if row["publish"]]:
        lines.extend(
            [
                f"target \"{bake_target(entry)}\" {{",
                f"  context = \"{bake_context_path()}\"",
                f"  dockerfile = \"{bake_hcl_dockerfile_path(entry)}\"",
                "  platforms = [" + ", ".join(json.dumps(platform) for platform in entry["platforms"]) + "]",
                f"  tags = [\"local/{bake_target(entry)}:skeleton\"]",
                "  labels = {",
                f"    \"org.opencontainers.image.version\" = \"{entry['pg_major']}\"",
                f"    \"io.pnet.pg-major\" = \"{entry['pg_major']}\"",
                f"    \"io.pnet.debian-variant\" = \"{entry['debian_variant']}\"",
                f"    \"io.pnet.publish\" = \"{str(entry['publish']).lower()}\"",
                "  }",
                "}",
                "",
            ]
        )
    return "\n".join(lines)


def render_catalog(debian, records):
    lines = [
        "# Generated by cloudnative-pg-timescaledb/scripts/generate-catalog.sh",
        "apiVersion: postgresql.cnpg.io/v1",
        "kind: ClusterImageCatalog",
        "metadata:",
        f"  name: cloudnative-pg-timescaledb-standard-{debian}",
        "spec:",
        "  images:" if records else "  images: []",
    ]
    for record in records:
        entry = record["entry"]
        lines.extend(
            [
                f"    - major: {numeric_pg_major(entry['pg_major'])}",
                f"      image: {record['image_ref']}",
            ]
        )
    return "\n".join(lines) + "\n"


def parse_catalog_yaml(path, command):
    try:
        import yaml
    except ImportError as exc:
        diag(command, path, "PyYAML is installed for catalog validation", str(exc), "Install PyYAML or run validation in the project CI image.")
    try:
        payload = yaml.safe_load(Path(path).read_text())
    except FileNotFoundError:
        diag(command, path, "catalog YAML exists", "missing", "Generate catalogs before validation.")
    except Exception as exc:
        diag(command, path, "catalog YAML parses", str(exc), "Keep generated catalog manifests valid YAML.")
    if not isinstance(payload, dict):
        diag(command, path, "catalog YAML is a mapping", type(payload).__name__, "Use a CloudNativePG ClusterImageCatalog manifest.")
    return payload


def catalog_variant(payload, path, command):
    name = payload.get("metadata", {}).get("name") if isinstance(payload.get("metadata"), dict) else ""
    file_match = re.fullmatch(r"catalog-standard-(trixie|bookworm)\.yaml", Path(path).name)
    name_match = re.fullmatch(r"cloudnative-pg-timescaledb-standard-(trixie|bookworm)", str(name))
    if not file_match or not name_match:
        diag(command, path, "catalog file and metadata.name encode supported matching variants", {"file": Path(path).name, "metadata.name": name}, "Use catalog-standard-<debian>.yaml and cloudnative-pg-timescaledb-standard-<debian>.")
    if file_match.group(1) != name_match.group(1):
        diag(command, path, "catalog file variant matches metadata.name variant", {"file_variant": file_match.group(1), "metadata_name_variant": name_match.group(1)}, "Regenerate the catalog so the Kubernetes object identity matches the catalog file.")
    return file_match.group(1)


def split_catalog_image_ref(value, image, release_records):
    if not isinstance(value, str):
        return None, None, "catalog image is a string"
    if "@" not in value:
        return None, None, "missing digest"
    left, digest = value.rsplit("@", 1)
    if not DIGEST_RE.fullmatch(digest):
        return None, digest, "missing digest"
    if not left.startswith(f"{image}:"):
        return None, digest, "wrong image repository"
    tag = left[len(image) + 1:]
    if not tag:
        return None, digest, "missing tag"
    for record in release_records.values():
        if digest in set(record["platform_digests"].values()):
            return tag, digest, "per-platform digest"
    return tag, digest, ""


def validate_catalog_file(data, entries, release_metadata, catalog_path):
    command = "validate-catalog"
    release_records = load_release_records(data, entries, release_metadata, command)
    if not release_records:
        diag(command, catalog_path, "at least one release metadata record", "none", "Pass --release-metadata from Story 4.5 publish output before validating release catalogs.")
    image = f"{data['image']['registry']}/{data['image']['repository']}"
    payload = parse_catalog_yaml(catalog_path, command)
    if payload.get("apiVersion") != "postgresql.cnpg.io/v1" or payload.get("kind") != "ClusterImageCatalog":
        diag(command, catalog_path, "CloudNativePG ClusterImageCatalog apiVersion/kind", {"apiVersion": payload.get("apiVersion"), "kind": payload.get("kind")}, "Generate catalogs with generate-catalog.sh.")
    variant = catalog_variant(payload, catalog_path, command)
    spec = payload.get("spec")
    images = spec.get("images") if isinstance(spec, dict) else None
    if images is None:
        images = []
    if not isinstance(images, list):
        diag(command, catalog_path, "spec.images is a list", type(images).__name__, "Use CloudNativePG catalog image entries.")
    expected = {
        key: record for key, record in release_records.items()
        if key[1] == variant and not record["entry"]["experimental"]
    }
    seen = set()
    for index, row in enumerate(images):
        artifact = f"{catalog_path}#spec.images[{index}]"
        if not isinstance(row, dict):
            diag(command, artifact, "catalog image row is an object", type(row).__name__, "Use major/image mappings.")
        tag, digest, ref_error = split_catalog_image_ref(row.get("image"), image, release_records)
        if ref_error == "missing digest":
            diag(command, artifact, "catalog image uses repo:published-tag@sha256 manifest-list digest", row.get("image"), "Pin every catalog image to a digest.")
        if ref_error == "per-platform digest":
            diag(command, artifact, "catalog digest is the published manifest-list digest", row.get("image"), "Do not use per-platform image digests in ClusterImageCatalog.")
        if ref_error:
            diag(command, artifact, "catalog image reference is a published repo:tag@digest ref", row.get("image"), "Use a final GHCR tag and published digest from release metadata.")
        matches = [key for key, record in release_records.items() if record["digest"] == digest and tag in record["final_tags"]]
        if not matches:
            diag(command, artifact, "catalog tag is present in release metadata final_tags", {"tag": tag, "digest": digest}, "Do not reference unpublished tags in catalogs.")
        if len(matches) != 1:
            diag(command, artifact, "catalog ref maps to exactly one release metadata record", matches, "Keep tag/digest identities unique.")
        key = matches[0]
        record = release_records[key]
        entry = record["entry"]
        if entry["experimental"]:
            diag(command, artifact, "stable catalog excludes experimental PostgreSQL entries", entry["pg_major"], "Emit experimental entries only in an explicitly named experimental catalog.")
        if key[1] != variant:
            diag(command, artifact, f"catalog entry Debian variant is {variant}", key[1], "Keep trixie and bookworm catalogs separated.")
        expected_major = int(numeric_pg_major(entry["pg_major"]))
        if row.get("major") != expected_major:
            diag(command, artifact, f"catalog major is PostgreSQL numeric major {expected_major}", row.get("major"), "Map catalog major from the release metadata PostgreSQL row.")
        seen.add(key)
    if seen != set(expected):
        diag(command, catalog_path, f"catalog includes every stable release metadata record for {variant} and no extras", {"expected": sorted(f"{k[0]}-{k[1]}" for k in expected), "actual": sorted(f"{k[0]}-{k[1]}" for k in seen)}, "Regenerate the catalog from the complete release metadata set.")


def render_docs(entries):
    lines = [
        "# Generated Compatibility",
        "",
        "<!-- Generated by cloudnative-pg-timescaledb/scripts/generate-docs.sh from cloudnative-pg-timescaledb/versions.yaml. -->",
        "",
        "The compatibility table is emitted as `compatibility-table.md` for README inclusion and public documentation validation.",
    ]
    return "\n".join(lines) + "\n"


def render_compatibility_table(entries):
    lines = [
        "# Generated Compatibility Table",
        "",
        "<!-- Generated by cloudnative-pg-timescaledb/scripts/generate-docs.sh from cloudnative-pg-timescaledb/versions.yaml. -->",
        "",
        "| PostgreSQL | Debian | Publish | Experimental | Latest Eligible | Platforms | Skip Reason |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for entry in entries:
        lines.append(
            "| {pg_major} | {debian_variant} | {publish} | {experimental} | {latest_eligible} | {platforms} | {skip_reason} |".format(
                pg_major=entry["pg_major"],
                debian_variant=entry["debian_variant"],
                publish=str(entry["publish"]).lower(),
                experimental=str(entry["experimental"]).lower(),
                latest_eligible=str(entry["latest_eligible"]).lower(),
                platforms=", ".join(entry["platforms"]),
                skip_reason=entry["skip_reason"],
            )
        )
    return "\n".join(lines) + "\n"


def render_barman_plugin_reference(plugin):
    lines = [
        "# CloudNativePG Barman Cloud Plugin Reference",
        "",
        "<!-- Generated by cloudnative-pg-timescaledb/scripts/generate-docs.sh from cloudnative-pg-timescaledb/versions.yaml. -->",
        "",
        f"Release: `{plugin['release']}`",
        f"Manifest URL: `{plugin['manifest_url']}`",
        f"Plugin image: `{plugin['plugin_image']}`",
        f"Sidecar image: `{plugin['sidecar_image']}`",
        f"Source URL: `{plugin['source_url']}`",
        f"Last checked UTC date: `{plugin['updated_at_utc']}`",
        "",
        "PostgreSQL images remain backup-tooling-free for v1; use the CloudNativePG Barman Cloud Plugin path for backup integration.",
    ]
    return "\n".join(lines) + "\n"


def render_failure_reason_catalog():
    lines = [
        "# Failure Reason Catalog",
        "",
        "<!-- Generated by cloudnative-pg-timescaledb/scripts/generate-docs.sh from maintained repository failure reason definitions. -->",
        "",
        "This catalog defines the structured failure reasons surfaced by validation, update, build, publish, catalog, and security gates.",
        "Barman-related metadata in this repository refers to the CloudNativePG Barman Cloud Plugin integration path, not legacy in-image backup binaries.",
        "",
    ]
    for entry in FAILURE_REASON_CATALOG:
        lines.extend(
            [
                f"## `{entry['reason_id']}`",
                "",
                f"- `reason_id`: `{entry['reason_id']}`",
                f"- `category`: {entry['category']}",
                f"- `applies_to`: {entry['applies_to']}",
                f"- `gate_or_command`: `{entry['gate_or_command']}`",
                f"- `hard_fail`: `{str(entry['hard_fail']).lower()}`",
                f"- `publish_false_skip_reason_allowed`: {entry['publish_false_skip_reason_allowed']}",
                f"- `local_command`: `{entry['local_command']}`",
                f"- `remediation`: {entry['remediation']}",
                f"- `trixie_bookworm_notes`: {entry['trixie_bookworm_notes']}",
                "",
            ]
        )
    return "\n".join(lines)


def write_or_check(path, content, check, command):
    path = ROOT / path if not Path(path).is_absolute() else Path(path)
    if check:
        actual = path.read_text() if path.exists() else None
        if actual != content:
            diff = "missing file" if actual is None else "".join(difflib.unified_diff(actual.splitlines(True), content.splitlines(True), fromfile=str(path), tofile="generated"))
            diag(command, path, "committed output matches generated content", diff[:1200], "Run make generate and commit the regenerated skeleton output.")
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)


def remove_or_check_absent(path, check, command):
    path = ROOT / path if not Path(path).is_absolute() else Path(path)
    if check:
        if path.exists():
            diag(command, path, "stale alternate generated artifact is absent", "present", "Run make generate to remove stale Dockerfile/skipped marker output.")
    elif path.exists():
        path.unlink()


def run(kind, metadata, output, check, as_json, release_metadata=None, validate_catalog=None):
    command = f"generate-{kind}"
    data = parse_metadata(metadata, command)
    validate_metadata_shape(data, command, metadata)
    entries = data["entries"]
    validate_latest(entries, command, metadata)
    if kind == "dockerfiles":
        root = output or "cloudnative-pg-timescaledb/generated"
        for entry in entries:
            if entry["publish"]:
                validate_publishable_dockerfile_entry(entry, command, metadata)
                render_dockerfile(entry)
        summary = dockerfiles_summary(entries, root)
        if check or not as_json:
            for entry in entries:
                if entry["publish"]:
                    write_or_check(dockerfile_path(entry, root), render_dockerfile(entry), check, command)
                    remove_or_check_absent(skipped_marker_path(entry, root), check, command)
                else:
                    if not str(entry["skip_reason"]).strip():
                        diag(command, metadata, "skipped non-publish entries have non-empty skip_reason", row_id(entry), "Populate skip_reason before skipping a Dockerfile.")
                    write_or_check(skipped_marker_path(entry, root), render_skipped_marker(entry), check, command)
                    remove_or_check_absent(dockerfile_path(entry, root), check, command)
        if not as_json:
            print(f"generated dockerfile outputs: buildable={sum(1 for entry in entries if entry['publish'])} skipped={sum(1 for entry in entries if not entry['publish'])}", file=sys.stderr)
    elif kind == "bake":
        bake_file = output or "cloudnative-pg-timescaledb/docker-bake.hcl"
        summary = bake_summary(entries, bake_file)
        if check or not as_json:
            write_or_check(bake_file, render_bake(entries), check, command)
        if not as_json:
            print(f"generated bake targets: buildable={sum(1 for entry in entries if entry['publish'])} skipped={sum(1 for entry in entries if not entry['publish'])} artifact={bake_file}", file=sys.stderr)
    elif kind == "matrix":
        summary = matrix_summary(data, entries)
        if check or not as_json:
            content = json.dumps(summary, indent=2, sort_keys=True) + "\n"
            write_or_check(output or "cloudnative-pg-timescaledb/matrix.json", content, check, command)
            write_or_check(matrix_schema_path(output), matrix_schema_doc(), check, command)
        if not as_json:
            print(f"generated matrix entries: publishable={len(summary['include'])} skipped={len(summary['skipped'])}", file=sys.stderr)
    elif kind == "catalog":
        if validate_catalog:
            for catalog_path in validate_catalog:
                validate_catalog_file(data, entries, release_metadata or [], catalog_path)
            summary = {"validated_catalogs": [str(path) for path in validate_catalog]}
            if not as_json:
                print(f"PASS validate-catalog files={len(validate_catalog)}", file=sys.stderr)
        else:
            summary = catalog_summary(data, entries, output or "cloudnative-pg-timescaledb/catalog", release_metadata or [])
        if check or not as_json:
            for catalog in summary.get("catalogs", []):
                records = [load_release_records(data, entries, release_metadata or [], command)[(row["pg_major"], catalog["debian_variant"])] for row in catalog["entries"]]
                write_or_check(catalog["catalog_path"], render_catalog(catalog["debian_variant"], records), check, command)
        if not as_json and not validate_catalog:
            print(f"generated release catalogs: {len(summary['catalogs'])}", file=sys.stderr)
    elif kind == "docs":
        doc_path = output or "cloudnative-pg-timescaledb/docs/generated/compatibility.md"
        summary = docs_summary(entries, doc_path, "barman_plugin" in data)
        if check or not as_json:
            write_or_check(doc_path, render_docs(entries), check, command)
            table_path = (Path(doc_path).parent / "compatibility-table.md").as_posix()
            write_or_check(table_path, render_compatibility_table(entries), check, command)
            candidate_schema_path = (Path(doc_path).parent / "release-candidate-schema.md").as_posix()
            write_or_check(candidate_schema_path, release_candidate_schema_doc(), check, command)
            evidence_schema_path = (Path(doc_path).parent / "release-evidence-schema.md").as_posix()
            write_or_check(evidence_schema_path, release_evidence_schema_doc(), check, command)
            failure_catalog_path = (Path(doc_path).parent / "failure-reason-catalog.md").as_posix()
            write_or_check(failure_catalog_path, render_failure_reason_catalog(), check, command)
            if "barman_plugin" in data:
                barman_doc_path = (Path(doc_path).parent / "barman-plugin-reference.md").as_posix()
                write_or_check(barman_doc_path, render_barman_plugin_reference(data["barman_plugin"]), check, command)
        if not as_json:
            print(f"generated compatibility docs skeleton: {doc_path}", file=sys.stderr)
            table_path = (Path(doc_path).parent / "compatibility-table.md").as_posix()
            print(f"generated compatibility table docs: {table_path}", file=sys.stderr)
            candidate_schema_path = (Path(doc_path).parent / "release-candidate-schema.md").as_posix()
            print(f"generated release candidate schema docs: {candidate_schema_path}", file=sys.stderr)
            evidence_schema_path = (Path(doc_path).parent / "release-evidence-schema.md").as_posix()
            print(f"generated release evidence schema docs: {evidence_schema_path}", file=sys.stderr)
            failure_catalog_path = (Path(doc_path).parent / "failure-reason-catalog.md").as_posix()
            print(f"generated failure reason catalog docs: {failure_catalog_path}", file=sys.stderr)
            if "barman_plugin" in data:
                barman_doc_path = (Path(doc_path).parent / "barman-plugin-reference.md").as_posix()
                print(f"generated Barman plugin reference docs: {barman_doc_path}", file=sys.stderr)
    else:
        raise AssertionError(kind)
    if as_json:
        sys.stdout.write(json.dumps(summary, separators=(",", ":"), sort_keys=True) + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("kind", choices=["dockerfiles", "bake", "matrix", "catalog", "docs"])
    parser.add_argument("--metadata", type=Path, default=DEFAULT_METADATA)
    parser.add_argument("--output", default="")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--release-metadata", action="append", default=[])
    parser.add_argument("--validate-catalog", action="append", default=[])
    args = parser.parse_args()
    if args.kind != "catalog" and (args.release_metadata or args.validate_catalog):
        diag(f"generate-{args.kind}", "arguments", "catalog-only options omitted", {"release_metadata": args.release_metadata, "validate_catalog": args.validate_catalog}, "Use --release-metadata and --validate-catalog only with generate-catalog.sh.")
    run(args.kind, args.metadata, args.output, args.check, args.json, args.release_metadata, args.validate_catalog)


if __name__ == "__main__":
    main()
