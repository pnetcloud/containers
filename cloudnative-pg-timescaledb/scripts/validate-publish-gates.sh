#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

release_file=""
candidate_metadata=""
release_evidence=""
scan_summary=""
output_file=""
tag_validation_status=""
release_gate_metadata=""
gate_output=""

diag() {
  printf 'command: %s\nartifact: %s\nexpected: %s\nactual: %s\nremediation: %s\n' "$@" >&2
}

require_value() {
  local option="$1"
  local value="${2:-}"
  if [[ -z "${value}" ]]; then
    diag "validate-publish-gates" "arguments" "${option} has a value" "missing" "Pass ${option} <path>."
    exit 64
  fi
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --release)
      require_value "$1" "${2:-}"
      release_file="$2"
      shift 2
      ;;
    --candidate-metadata)
      require_value "$1" "${2:-}"
      candidate_metadata="$2"
      shift 2
      ;;
    --release-evidence)
      require_value "$1" "${2:-}"
      release_evidence="$2"
      shift 2
      ;;
    --scan-summary)
      require_value "$1" "${2:-}"
      scan_summary="$2"
      shift 2
      ;;
    --tag-validation-status)
      require_value "$1" "${2:-}"
      tag_validation_status="$2"
      shift 2
      ;;
    --release-gate-metadata)
      require_value "$1" "${2:-}"
      release_gate_metadata="$2"
      shift 2
      ;;
    --gate-output)
      require_value "$1" "${2:-}"
      gate_output="$2"
      shift 2
      ;;
    --output)
      require_value "$1" "${2:-}"
      output_file="$2"
      shift 2
      ;;
    *)
      diag "validate-publish-gates" "arguments" "known option" "$1" "Use --release, --gate-output, or --candidate-metadata/--release-evidence/--scan-summary plus --release-gate-metadata."
      exit 64
      ;;
  esac
done

python3 - "${ROOT_DIR}" "${release_file}" "${candidate_metadata}" "${release_evidence}" "${scan_summary}" "${tag_validation_status}" "${output_file}" "${release_gate_metadata}" "${gate_output}" <<'PY'
import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
release_file = sys.argv[2]
candidate_metadata = sys.argv[3]
release_evidence = sys.argv[4]
scan_summary = sys.argv[5]
tag_validation_status = sys.argv[6]
output_file = sys.argv[7]
release_gate_metadata = sys.argv[8]
gate_output = sys.argv[9]

COMMAND = "validate-publish-gates"
DIGEST_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
EXPECTED_ISSUER = "https://token.actions.githubusercontent.com"


def diag(artifact, expected, actual, remediation):
    raise SystemExit(
        f"command: {COMMAND}\n"
        f"artifact: {artifact}\n"
        f"expected: {expected}\n"
        f"actual: {actual}\n"
        f"remediation: {remediation}"
    )


def require(condition, artifact, expected, actual, remediation):
    if not condition:
        diag(artifact, expected, actual, remediation)


def read_json(path):
    try:
        return json.loads(Path(path).read_text())
    except FileNotFoundError:
        diag(path, "JSON artifact exists", "missing", "Download the required same-run gate artifact before publish validation.")
    except json.JSONDecodeError as exc:
        diag(path, "valid JSON", str(exc), "Write deterministic JSON gate artifacts.")


def normalize_records(value, artifact):
    records = value if isinstance(value, list) else [value]
    require(records and all(isinstance(record, dict) for record in records), artifact, "candidate metadata is a non-empty object array", type(value).__name__, "Consume Story 4.2 release-candidate.json.")
    return records


def load_payloads():
    if release_file:
        release = read_json(release_file)
        require(isinstance(release, dict), release_file, "release fixture is an object", type(release).__name__, "Use structured publish release fixtures.")
        records = normalize_records(release.get("candidate_metadata"), release_file)
        evidence = release.get("release_evidence")
        scans = release.get("scan_summary")
        gates = release.get("gates", {})
        provided_id = release.get("release_metadata_record_id", "")
        provided_ref = release.get("release_metadata_ref", "")
        artifact = release_file
        gate_metadata = {}
    else:
        required = {
            "--candidate-metadata": candidate_metadata,
            "--release-evidence": release_evidence,
            "--scan-summary": scan_summary,
        }
        if gate_output:
            required["--tag-validation-status"] = tag_validation_status
        else:
            required["--release-gate-metadata"] = release_gate_metadata
        missing = [option for option, value in required.items() if not value]
        require(not missing, "arguments", "separate artifact mode has all required inputs", missing, "Pass candidate metadata, release evidence, scan summary, and release gate metadata; use --gate-output only from the tag_validation job.")
        records = normalize_records(read_json(candidate_metadata), candidate_metadata)
        evidence = read_json(release_evidence)
        scans = read_json(scan_summary)
        if gate_output:
            gates = {
                "candidate_build": "passed",
                "smoke_container": "passed",
                "smoke_sql": "passed",
                "tag_validation": tag_validation_status,
                "vulnerability_scan": "passed",
                "sbom": "present",
                "provenance": "present",
                "signature": "present",
                "verification": "passed",
            }
            provided_id = ""
            provided_ref = ""
            gate_metadata = {}
        else:
            gate_metadata = read_json(release_gate_metadata)
            require(isinstance(gate_metadata, dict), release_gate_metadata, "release gate metadata is an object", type(gate_metadata).__name__, "Consume the same-run tag_validation gate artifact.")
            gates = gate_metadata.get("gates", {})
            provided_id = gate_metadata.get("release_metadata_record_id", "")
            provided_ref = gate_metadata.get("release_metadata_ref", "")
        artifact = f"{candidate_metadata},{release_evidence},{scan_summary}"
    require(isinstance(evidence, dict), artifact, "release_evidence is an object", type(evidence).__name__, "Consume Story 4.4 release-evidence.json.")
    require(isinstance(scans, list) and scans, artifact, "scan_summary is a non-empty array", type(scans).__name__, "Consume Story 4.3 vulnerability-scan-summary.json.")
    require(isinstance(gates, dict), artifact, "gates is an object", type(gates).__name__, "Carry explicit publish gate statuses.")
    return artifact, records, evidence, scans, gates, provided_id, provided_ref, gate_metadata


def gate(gates, name, expected):
    actual = gates.get(name)
    require(actual == expected, "gates", f"{name} gate is {expected}", repr(actual), "Do not publish unless every same-run gate explicitly passes for the same release record.")


def expected_tag_shape(record, tags):
    pg = record["pg_major"]
    pg_version = record["pg_version"]
    debian = record["debian_variant"]
    experimental = record["experimental"]
    latest_eligible = record["latest_eligible"]
    require(isinstance(tags, list) and tags and len(tags) == len(set(tags)), "final_tags", "final_tags is a non-empty unique array", tags, "Carry exact intended tags from Story 1.4 policy.")
    require(all(isinstance(tag, str) and re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}", tag) for tag in tags), "final_tags", "all final tags use Docker tag grammar", tags, "Reject invalid Docker tag names before GHCR publish.")
    has_latest = "latest" in tags
    if has_latest:
        require(pg == "18" and debian == "trixie" and latest_eligible is True and experimental is False, "final_tags", "latest only for non-experimental PostgreSQL 18 trixie", {"pg_major": pg, "debian_variant": debian, "experimental": experimental, "latest_eligible": latest_eligible, "tags": tags}, "Keep latest pinned to the selected current primary line.")
    if debian != "trixie":
        require("latest" not in tags, "final_tags", "secondary Debian variants never receive latest", tags, "Do not publish latest for bookworm.")
    if pg == "19beta1" or experimental is True:
        normal = [tag for tag in tags if tag in {pg, f"{pg}-{debian}", "latest"}]
        require(not normal, "final_tags", "experimental PostgreSQL rows have no normal rolling/latest tags", normal, "Promote PostgreSQL preview rows only with experimental immutable tags.")
        require(all(tag.startswith(f"{pg}-pg{pg_version}-ts") for tag in tags), "final_tags", "experimental tags are immutable preview tags only", tags, "Do not create normal tags for PostgreSQL 19 preview rows.")
        return
    if debian == "trixie":
        require(pg in tags, "final_tags", f"primary trixie row includes rolling major tag {pg}", tags, "Publish the selected PostgreSQL major rolling tag for trixie.")
        immutable_re = re.compile(rf"^{re.escape(pg)}-pg{re.escape(pg_version)}-ts[^-]+-[0-9]{{8}}$")
    else:
        rolling = f"{pg}-{debian}"
        require(pg not in tags, "final_tags", "secondary Debian variants do not receive unsuffixed rolling major tags", tags, "Publish only OS-suffixed rolling tags for secondary Debian variants.")
        require(rolling in tags, "final_tags", f"secondary row includes OS-suffixed rolling tag {rolling}", tags, "Publish OS-suffixed rolling tags for secondary Debian variants.")
        immutable_re = re.compile(rf"^{re.escape(pg)}-pg{re.escape(pg_version)}-ts[^-]+-[0-9]{{8}}-{re.escape(debian)}$")
    require(any(immutable_re.fullmatch(tag) for tag in tags), "final_tags", "immutable tag matches PostgreSQL/TimescaleDB/date/OS policy", tags, "Publish the immutable tag generated by Story 1.4.")


artifact, records, evidence, scans, gates, provided_id, provided_ref, gate_metadata = load_payloads()

for name, expected in [
    ("candidate_build", "passed"),
    ("smoke_container", "passed"),
    ("smoke_sql", "passed"),
    ("tag_validation", "passed"),
    ("vulnerability_scan", "passed"),
    ("sbom", "present"),
    ("provenance", "present"),
    ("signature", "present"),
    ("verification", "passed"),
]:
    gate(gates, name, expected)

first = records[0]
same_fields = ["image", "candidate_ref", "index_digest", "platform_digests", "intended_tags", "bake_target", "pg_major", "pg_version", "debian_variant"]
for idx, record in enumerate(records):
    for field in same_fields:
        require(record.get(field) == first.get(field), artifact, f"candidate metadata record[{idx}].{field} matches release record", {"expected": first.get(field), "actual": record.get(field)}, "Do not mix candidate metadata records across image rows.")
    require(record.get("publish") is True, artifact, f"candidate metadata record[{idx}].publish is true", repr(record.get("publish")), "Publish consumes only publishable release candidate rows.")
    require(record.get("smoke_container_status") == "passed", artifact, f"candidate metadata record[{idx}] container smoke passed", record.get("smoke_container_status"), "Do not publish without container smoke.")
    require(record.get("smoke_sql_status") == "passed", artifact, f"candidate metadata record[{idx}] SQL smoke passed", record.get("smoke_sql_status"), "Do not publish without SQL smoke.")
    require(record.get("smoke_architecture_status") == "passed", artifact, f"candidate metadata record[{idx}] architecture smoke passed", record.get("smoke_architecture_status"), "Do not publish without architecture smoke.")
    require(record.get("platform_digest") == record.get("platform_digests", {}).get(record.get("platform")), artifact, f"candidate metadata record[{idx}] platform digest matches platform map", record, "Keep platform digest evidence bound to the platform smoke result.")

platforms = first.get("platforms")
platform_digests = first.get("platform_digests")
require(isinstance(platforms, list) and set(platforms) == set(platform_digests or {}), artifact, "candidate metadata platform coverage is complete", {"platforms": platforms, "platform_digests": platform_digests}, "Publish only complete multi-platform candidates.")
require({record.get("platform") for record in records} == set(platforms), artifact, "candidate records cover every platform", [record.get("platform") for record in records], "Publish only after every platform smoke record exists.")

index_digest = first.get("index_digest")
require(isinstance(index_digest, str) and DIGEST_RE.fullmatch(index_digest), artifact, "index_digest is immutable sha256 digest", repr(index_digest), "Promote by digest, not mutable tag.")
require(evidence.get("image") == first.get("image"), artifact, "release evidence image matches candidate metadata", {"candidate": first.get("image"), "evidence": evidence.get("image")}, "Do not mix evidence from another image.")
require(evidence.get("index_digest") == index_digest, artifact, "release evidence index_digest matches candidate metadata", {"candidate": index_digest, "evidence": evidence.get("index_digest")}, "Do not publish evidence for a different digest.")
require(evidence.get("platform_digests") == platform_digests, artifact, "release evidence platform_digests match candidate metadata", {"candidate": platform_digests, "evidence": evidence.get("platform_digests")}, "Do not mix platform digest evidence.")
require(evidence.get("scan_result") == "passed", artifact, "release evidence scan_result is passed", evidence.get("scan_result"), "Publish requires threshold-passing vulnerability scan evidence.")
require(evidence.get("verified") is True, artifact, "release evidence verified is true", evidence.get("verified"), "Publish requires passing cosign verification.")
require(evidence.get("cosign_certificate_issuer") == EXPECTED_ISSUER, artifact, "release evidence issuer is GitHub Actions OIDC", evidence.get("cosign_certificate_issuer"), "Reject non-GitHub OIDC signatures.")
identity = evidence.get("expected_certificate_identity")
require(
    isinstance(identity, str)
    and re.fullmatch(r"https://github.com/[^/]+/[^/]+/\.github/workflows/build\.yml@refs/(heads|tags)/.+", identity),
    artifact,
    "release evidence identity is exact repository build.yml workflow ref",
    identity,
    "Verify signatures against this repository workflow ref, not a broad identity pattern.",
)

per_digest = evidence.get("per_digest_evidence")
require(isinstance(per_digest, list) and per_digest, artifact, "release evidence per_digest_evidence exists", type(per_digest).__name__, "Carry SBOM/provenance/signature/verification refs for publish.")
by_digest = {row.get("digest"): row for row in per_digest if isinstance(row, dict)}
required_digests = {index_digest, *platform_digests.values()}
require(set(by_digest) == required_digests, artifact, "release evidence covers index digest and every platform digest", {"expected": sorted(required_digests), "actual": sorted(by_digest)}, "Do not publish with missing digest evidence.")
index_evidence = by_digest[index_digest]
for field, gate_name in [("sbom_ref", "SBOM"), ("provenance_ref", "provenance"), ("signature_ref", "signature"), ("verification_ref", "verification")]:
    value = index_evidence.get(field)
    require(isinstance(value, str) and value.startswith(f"{first['image']}@{index_digest}"), artifact, f"{gate_name} evidence is bound to published index digest", value, "Associate final published digest with its supply-chain evidence.")
require(index_evidence.get("verified") is True, artifact, "index digest verification passed", index_evidence, "Do not publish without passing index digest verification.")

expected_scans = {(record["candidate_ref"], record["platform_digest"]) for record in records}
actual_scans = {(row.get("candidate_ref"), row.get("digest")) for row in scans if isinstance(row, dict)}
require(actual_scans == expected_scans, artifact, "scan summary covers every candidate platform digest exactly", {"expected": sorted(expected_scans), "actual": sorted(actual_scans)}, "Do not publish when scan evidence belongs to another digest.")
require(all(row.get("scan_result") == "passed" for row in scans), artifact, "all scan summary rows passed", scans, "Do not publish when vulnerability policy fails.")

final_tags = first.get("intended_tags")
expected_tag_shape(first, final_tags)

record_identity = {
    "image": first["image"],
    "bake_target": first["bake_target"],
    "index_digest": index_digest,
    "platform_digests": platform_digests,
    "final_tags": final_tags,
}
record_id = "sha256:" + hashlib.sha256(json.dumps(record_identity, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
record_ref = f"{first['image']}@{index_digest}"
if provided_id:
    require(provided_id == record_id, artifact, "release_metadata_record_id matches deterministic record identity", {"expected": record_id, "actual": provided_id}, "Pass through, do not rewrite, the release metadata record identity.")
if provided_ref:
    require(provided_ref == record_ref, artifact, "release_metadata_ref matches published digest ref", {"expected": record_ref, "actual": provided_ref}, "Keep release metadata ref bound to the candidate index digest.")
elif not gate_output and not provided_id:
    require(False, artifact, "release_metadata_ref is supplied by same-run gate metadata", "missing", "Publish must consume release metadata identity from tag_validation, not synthesize it.")
if not gate_output and not (provided_id or provided_ref):
    require(False, artifact, "release_metadata_record_id or release_metadata_ref is supplied by same-run gate metadata", "missing", "Publish must consume release metadata identity from tag_validation, not synthesize it.")

if gate_metadata:
    require(provided_id, release_gate_metadata, "release gate metadata includes release_metadata_record_id", "missing", "The tag_validation job must write the release metadata record id before publish.")
    require(provided_ref, release_gate_metadata, "release gate metadata includes release_metadata_ref", "missing", "The tag_validation job must write the release metadata ref before publish.")
    expected_gate_fields = {
        "image": first["image"],
        "published_digest": index_digest,
        "final_tags": final_tags,
        "candidate_digest": first["candidate_digest"],
        "index_digest": index_digest,
        "platform_digests": platform_digests,
    }
    for key, expected in expected_gate_fields.items():
        require(gate_metadata.get(key) == expected, release_gate_metadata, f"release gate metadata {key} matches validated candidate/evidence", {"expected": expected, "actual": gate_metadata.get(key)}, "Do not consume release gate metadata from another digest or tag set.")

if gate_output:
    gate_payload = {
        "image": first["image"],
        "release_metadata_record_id": record_id,
        "release_metadata_ref": record_ref,
        "published_digest": index_digest,
        "final_tags": final_tags,
        "candidate_digest": first["candidate_digest"],
        "index_digest": index_digest,
        "platform_digests": platform_digests,
        "gates": gates,
        "promotion_status": "gates-passed",
    }
    output = Path(gate_output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(gate_payload, indent=2, sort_keys=True) + "\n")

metadata = {
    "image": first["image"],
    "release_metadata_record_id": provided_id or record_id,
    "release_metadata_ref": provided_ref or record_ref,
    "published_digest": index_digest,
    "final_tags": final_tags,
    "scan_result": "passed",
    "sbom_ref": index_evidence["sbom_ref"],
    "provenance_ref": index_evidence["provenance_ref"],
    "signature_ref": index_evidence["signature_ref"],
    "verified": True,
    "cosign_certificate_identity": identity,
    "cosign_certificate_issuer": evidence["cosign_certificate_issuer"],
    "candidate_digest": first["candidate_digest"],
    "index_digest": index_digest,
    "platform_digests": platform_digests,
    "promotion_status": "validated",
}
if output_file:
    output = Path(output_file)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")
print(f"PASS publish gates tags={len(final_tags)} digest={index_digest} record={record_id}")
PY
