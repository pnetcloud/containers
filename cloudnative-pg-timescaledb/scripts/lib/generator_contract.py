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
from tag_policy import generated_tags


ROOT = Path(__file__).resolve().parents[3]
DEFAULT_METADATA = ROOT / "cloudnative-pg-timescaledb" / "versions.yaml"
DOCKERFILE_TEMPLATE = ROOT / "cloudnative-pg-timescaledb" / "templates" / "Dockerfile.tmpl"
CNPG_IMAGE = "ghcr.io/cloudnative-pg/postgresql"
SOURCE_REPOSITORY = "https://github.com/pnetcloud/containers"
DIGEST_RE = re.compile(r"^sha256:[0-9a-f]{64}$")


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


def image_ref(data, entry):
    registry = data["image"]["registry"]
    repo = data["image"]["repository"]
    tag = f"{entry['pg_major']}-pg{entry['pg_version']}-ts{entry['timescaledb_version'] or 'unresolved'}-00000000"
    if entry["debian_variant"] != "trixie":
        tag = f"{tag}-{entry['debian_variant']}"
    return f"{registry}/{repo}:{tag}"


def release_date(command="generate-matrix"):
    value = os.environ.get("TAG_VALIDATION_DATE", "20260609")
    if not re.fullmatch(r"[0-9]{8}", value):
        diag(command, "TAG_VALIDATION_DATE", "UTC YYYYMMDD", value, "Set TAG_VALIDATION_DATE to a deterministic UTC release date.")
    return value


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
                "context": ".",
                "dockerfile": dockerfile_path(entry),
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
            tags = generated_tags(entry, date)
            immutable_tag = next((tag for tag in tags if "-pg" in tag and "-ts" in tag), tags[0])
            include.append(
                {
                    "pg_major": entry["pg_major"],
                    "pg_version": entry["pg_version"],
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


def catalog_summary(data, entries, output_root="cloudnative-pg-timescaledb/catalog"):
    catalogs = []
    for debian in ["trixie", "bookworm"]:
        rows = [entry for entry in entries if entry["debian_variant"] == debian]
        catalogs.append(
            {
                "debian_variant": debian,
                "catalog_path": f"{output_root.rstrip('/')}/catalog-standard-{debian}.yaml",
                "entries": [
                    {
                        "pg_major": entry["pg_major"],
                        "image": image_ref(data, entry),
                        "digest": entry["cnpg_digest"] if entry["publish"] else "",
                        "publish": entry["publish"],
                        "experimental": entry["experimental"],
                        "latest_eligible": entry["latest_eligible"],
                        "skip_reason": entry["skip_reason"],
                    }
                    for entry in rows
                ],
            }
        )
    return {"catalogs": catalogs}


def docs_summary(entries, doc_path="cloudnative-pg-timescaledb/docs/generated/compatibility.md"):
    return {
        "docs": [
            {
                "doc_path": doc_path,
                "source": "cloudnative-pg-timescaledb/versions.yaml",
                "sections": ["compatibility"],
                "publishable_entries": sum(1 for entry in entries if entry["publish"]),
                "experimental_entries": sum(1 for entry in entries if entry["experimental"]),
            }
        ]
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
                "  context = \".\"",
                f"  dockerfile = \"{dockerfile_path(entry)}\"",
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


def render_catalog(data, debian, entries):
    lines = [
        "# Generated by cloudnative-pg-timescaledb/scripts/generate-catalog.sh",
        "apiVersion: postgresql.cnpg.io/v1",
        "kind: ClusterImageCatalog",
        "metadata:",
        f"  name: cloudnative-pg-timescaledb-standard-{debian}",
        "spec:",
        "  images:",
    ]
    for entry in [row for row in entries if row["debian_variant"] == debian]:
        lines.extend(
            [
                f"    - major: {entry['pg_major'].replace('beta1', '')}",
                f"      image: {image_ref(data, entry)}",
                f"      sourceEntry: {row_id(entry)}",
                f"      publish: {str(entry['publish']).lower()}",
                f"      experimental: {str(entry['experimental']).lower()}",
                f"      latestEligible: {str(entry['latest_eligible']).lower()}",
                f"      skipReason: {json.dumps(entry['skip_reason'])}",
            ]
        )
    return "\n".join(lines) + "\n"


def render_docs(entries):
    lines = [
        "# Generated Compatibility",
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


def run(kind, metadata, output, check, as_json):
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
        summary = catalog_summary(data, entries, output or "cloudnative-pg-timescaledb/catalog")
        if check or not as_json:
            for catalog in summary["catalogs"]:
                write_or_check(catalog["catalog_path"], render_catalog(data, catalog["debian_variant"], entries), check, command)
        if not as_json:
            print(f"generated catalog skeletons: {len(summary['catalogs'])}", file=sys.stderr)
    elif kind == "docs":
        doc_path = output or "cloudnative-pg-timescaledb/docs/generated/compatibility.md"
        summary = docs_summary(entries, doc_path)
        if check or not as_json:
            write_or_check(doc_path, render_docs(entries), check, command)
            candidate_schema_path = (Path(doc_path).parent / "release-candidate-schema.md").as_posix()
            write_or_check(candidate_schema_path, release_candidate_schema_doc(), check, command)
            evidence_schema_path = (Path(doc_path).parent / "release-evidence-schema.md").as_posix()
            write_or_check(evidence_schema_path, release_evidence_schema_doc(), check, command)
            if "barman_plugin" in data:
                barman_doc_path = (Path(doc_path).parent / "barman-plugin-reference.md").as_posix()
                write_or_check(barman_doc_path, render_barman_plugin_reference(data["barman_plugin"]), check, command)
        if not as_json:
            print(f"generated compatibility docs skeleton: {doc_path}", file=sys.stderr)
            candidate_schema_path = (Path(doc_path).parent / "release-candidate-schema.md").as_posix()
            print(f"generated release candidate schema docs: {candidate_schema_path}", file=sys.stderr)
            evidence_schema_path = (Path(doc_path).parent / "release-evidence-schema.md").as_posix()
            print(f"generated release evidence schema docs: {evidence_schema_path}", file=sys.stderr)
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
    args = parser.parse_args()
    run(args.kind, args.metadata, args.output, args.check, args.json)


if __name__ == "__main__":
    main()
