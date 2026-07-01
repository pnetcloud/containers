#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import re
import sys


REQUIRED_INCLUDE = {
    "pg_major", "pg_version", "timescaledb_version", "debian_variant", "image", "candidate_ref", "digest",
    "release_date", "platforms", "bake_target", "dockerfile", "intended_tags", "publish", "experimental",
    "latest_eligible", "scan_result", "sbom_ref", "provenance_ref", "signature_ref",
}
REQUIRED_SKIPPED = {
    "pg_major", "pg_version", "debian_variant", "platforms", "bake_target", "skipped_marker",
    "publish", "experimental", "latest_eligible", "skip_reason",
}
DOCKER_TAG_RE = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}")
ALLOWED_PG_MAJORS = {"17", "18", "19beta1"}
ALLOWED_DEBIAN_VARIANTS = {"trixie", "bookworm"}
REQUIRED_PLATFORMS = ["linux/amd64", "linux/arm64"]


def fail(artifact, expected, actual, remediation):
    raise SystemExit(
        f"command: validate-matrix-json\n"
        f"artifact: {artifact}\n"
        f"expected: {expected}\n"
        f"actual: {actual}\n"
        f"remediation: {remediation}"
    )


def load_payload(args):
    if args.file:
        path = Path(args.file)
        try:
            return json.loads(path.read_text()), path
        except FileNotFoundError:
            fail(path, "matrix JSON file exists", "missing", "Generate matrix JSON before validating it.")
    if args.json:
        return json.loads(args.json), "--json"
    fail("arguments", "--file <path> or --json <payload>", "missing", "Pass matrix JSON as a file or compact argument.")


def validate(payload, artifact):
    if not isinstance(payload, dict):
        fail(artifact, "matrix payload is object", type(payload).__name__, "Emit a JSON object with include[] and skipped[].")
    if set(payload) != {"include", "skipped"}:
        fail(artifact, "top-level keys exactly include and skipped", sorted(payload), "Emit the Story 4.1 matrix schema only.")
    include = payload.get("include")
    if not isinstance(include, list):
        fail(artifact, "include is array", repr(include), "Emit include[] for GitHub Actions strategy matrix rows.")
    skipped = payload.get("skipped")
    if not isinstance(skipped, list):
        fail(artifact, "skipped is array", repr(skipped), "Emit skipped[] for non-publishable matrix summary rows.")
    seen_identities = set()
    seen_bake_targets = set()
    for idx, row in enumerate(include):
        if not isinstance(row, dict):
            fail(artifact, f"include[{idx}] is object", type(row).__name__, "Emit object rows for matrix include[].")
        missing = sorted(REQUIRED_INCLUDE - set(row))
        extra = sorted(set(row) - REQUIRED_INCLUDE)
        if missing or extra:
            fail(artifact, f"include[{idx}] required keys exactly", f"missing {missing}, extra {extra}", "Keep downstream workflow keys explicit; do not recompute release fields.")
        if row["pg_major"] not in ALLOWED_PG_MAJORS:
            fail(artifact, f"include[{idx}].pg_major is supported", repr(row["pg_major"]), "Use only PostgreSQL 17, 18, or experimental 19beta1 matrix rows.")
        if row["debian_variant"] not in ALLOWED_DEBIAN_VARIANTS:
            fail(artifact, f"include[{idx}].debian_variant is supported", repr(row["debian_variant"]), "Use only trixie or bookworm matrix rows.")
        identity = (row["pg_major"], row["debian_variant"])
        if identity in seen_identities:
            fail(artifact, f"include[{idx}] identity is unique across include and skipped", repr(row), "Emit one matrix row per PostgreSQL/Debian pair.")
        seen_identities.add(identity)
        if row["bake_target"] in seen_bake_targets:
            fail(artifact, f"include[{idx}].bake_target is unique across include and skipped", repr(row), "Emit one Bake target per PostgreSQL/Debian pair.")
        seen_bake_targets.add(row["bake_target"])
        if row["platforms"] != REQUIRED_PLATFORMS:
            fail(artifact, f"include[{idx}].platforms exactly {REQUIRED_PLATFORMS}", repr(row["platforms"]), "Publishable matrix rows must target both supported platforms in deterministic order.")
        for key in ["publish", "experimental", "latest_eligible"]:
            if not isinstance(row[key], bool):
                fail(artifact, f"include[{idx}].{key} is boolean", repr(row[key]), "Use JSON booleans for matrix control fields.")
        if row["publish"] is not True:
            fail(artifact, f"include[{idx}].publish is true", repr(row), "Only publishable rows may enter the workflow build matrix.")
        expected_target = f"pg{row['pg_major']}-{row['debian_variant']}"
        expected_dockerfile = f"cloudnative-pg-timescaledb/generated/{row['pg_major']}/{row['debian_variant']}/Dockerfile"
        if row["bake_target"] != expected_target or row["dockerfile"] != expected_dockerfile:
            fail(artifact, f"include[{idx}] exposes metadata-derived Dockerfile and target", repr(row), f"Use bake_target={expected_target!r} and dockerfile={expected_dockerfile!r}.")
        intended_tags = row["intended_tags"]
        if not isinstance(intended_tags, list) or not intended_tags:
            fail(artifact, f"include[{idx}].intended_tags is non-empty array", repr(intended_tags), "Emit deterministic tag-policy output for every publishable matrix row.")
        for tag in intended_tags:
            if not isinstance(tag, str) or not DOCKER_TAG_RE.fullmatch(tag):
                fail(artifact, f"include[{idx}].intended_tags use Docker tag grammar", repr(tag), "Regenerate matrix tags from validated tag policy output.")
        candidate_ref = row["candidate_ref"]
        suffix = "" if row["debian_variant"] == "trixie" else f"-{row['debian_variant']}"
        immutable_re = re.compile(
            rf"{re.escape(str(row['pg_major']))}-pg{re.escape(str(row['pg_version']))}-ts{re.escape(str(row['timescaledb_version']))}-[0-9]{{8}}{re.escape(suffix)}"
        )
        immutable_tags = [tag for tag in intended_tags if isinstance(tag, str) and immutable_re.fullmatch(tag)]
        if len(immutable_tags) != 1:
            fail(artifact, f"include[{idx}].intended_tags include exactly one policy immutable tag", repr(intended_tags), "Emit one immutable candidate tag matching the row PostgreSQL, Debian variant, TimescaleDB version, and release date.")
        tag_date = re.search(r"-([0-9]{8})(?:-[A-Za-z0-9_.-]+)?$", immutable_tags[0]).group(1)
        if row["release_date"] != tag_date:
            fail(artifact, f"include[{idx}].release_date matches immutable tag date", repr(row["release_date"]), "Carry the metadata-derived release date through the matrix instead of hard-coding it in workflow steps.")
        expected_candidate_ref = f"{row['image']}:{immutable_tags[0]}"
        if not isinstance(candidate_ref, str) or "@" in candidate_ref or candidate_ref != expected_candidate_ref:
            fail(artifact, f"include[{idx}].candidate_ref equals image:immutable-tag", repr(candidate_ref), f"Use {expected_candidate_ref!r}; digest refs and recomputed tags are not valid candidate refs.")
        if not DOCKER_TAG_RE.fullmatch(immutable_tags[0]):
            fail(artifact, f"include[{idx}].candidate_ref tag uses Docker tag grammar", repr(candidate_ref), "Use a Docker tag-safe immutable candidate reference.")
        is_latest_owner = row["pg_major"] == "18" and row["debian_variant"] == "trixie" and row["experimental"] is False
        if is_latest_owner and row["latest_eligible"] is not True:
            fail(artifact, f"include[{idx}].latest_eligible true for non-experimental 18 trixie", repr(row), "Keep exactly one publishable latest owner in the matrix.")
        if row["latest_eligible"] is True and not is_latest_owner:
            fail(artifact, f"include[{idx}].latest_eligible only for non-experimental 18 trixie", repr(row), "Do not promote bookworm, PostgreSQL 17, or PostgreSQL 19 preview rows to latest.")
        has_latest = "latest" in intended_tags
        if has_latest != (row["latest_eligible"] is True):
            fail(artifact, f"include[{idx}].latest tag matches latest_eligible", repr(row), "Emit latest exactly when the row is latest_eligible.")
        if row["debian_variant"] == "trixie" and immutable_tags[0].endswith("-bookworm"):
            fail(artifact, f"include[{idx}].trixie immutable tag has no Debian suffix", repr(immutable_tags[0]), "Primary trixie immutable tags omit the Debian suffix.")
        if row["debian_variant"] != "trixie" and not immutable_tags[0].endswith(f"-{row['debian_variant']}"):
            fail(artifact, f"include[{idx}].secondary immutable tag has Debian suffix", repr(immutable_tags[0]), "Secondary Debian variants must carry their suffix.")
    for idx, row in enumerate(skipped):
        if not isinstance(row, dict):
            fail(artifact, f"skipped[{idx}] is object", type(row).__name__, "Emit object rows for matrix skipped[].")
        missing = sorted(REQUIRED_SKIPPED - set(row))
        extra = sorted(set(row) - REQUIRED_SKIPPED)
        if missing or extra:
            fail(artifact, f"skipped[{idx}] required keys exactly", f"missing {missing}, extra {extra}", "Keep skipped row marker, target, and policy fields explicit; do not expose publishable build fields.")
        if row["pg_major"] not in ALLOWED_PG_MAJORS:
            fail(artifact, f"skipped[{idx}].pg_major is supported", repr(row["pg_major"]), "Use only PostgreSQL 17, 18, or experimental 19beta1 matrix rows.")
        expected_pg_version = row["pg_major"] if row["pg_major"] == "19beta1" else rf"{re.escape(str(row['pg_major']))}\.[0-9]+"
        if row["pg_major"] == "19beta1" and row["pg_version"] != expected_pg_version:
            fail(artifact, f"skipped[{idx}].pg_version matches pg_major", repr(row), "Skipped matrix rows must keep PostgreSQL identity unambiguous.")
        if row["pg_major"] != "19beta1" and not re.fullmatch(expected_pg_version, str(row["pg_version"])):
            fail(artifact, f"skipped[{idx}].pg_version matches pg_major version pattern", repr(row), "Skipped matrix rows must keep PostgreSQL identity unambiguous.")
        if row["debian_variant"] not in ALLOWED_DEBIAN_VARIANTS:
            fail(artifact, f"skipped[{idx}].debian_variant is supported", repr(row["debian_variant"]), "Use only trixie or bookworm matrix rows.")
        identity = (row["pg_major"], row["debian_variant"])
        if identity in seen_identities:
            fail(artifact, f"skipped[{idx}] identity is unique across include and skipped", repr(row), "Emit one matrix row per PostgreSQL/Debian pair.")
        seen_identities.add(identity)
        if row["bake_target"] in seen_bake_targets:
            fail(artifact, f"skipped[{idx}].bake_target is unique across include and skipped", repr(row), "Emit one Bake target per PostgreSQL/Debian pair.")
        seen_bake_targets.add(row["bake_target"])
        if row["platforms"] != REQUIRED_PLATFORMS:
            fail(artifact, f"skipped[{idx}].platforms exactly {REQUIRED_PLATFORMS}", repr(row["platforms"]), "Skipped matrix rows must retain deterministic platform scope for summaries.")
        for key in ["publish", "experimental", "latest_eligible"]:
            if not isinstance(row[key], bool):
                fail(artifact, f"skipped[{idx}].{key} is boolean", repr(row[key]), "Use JSON booleans for skipped matrix control fields.")
        if not isinstance(row["skip_reason"], str) or not row["skip_reason"].strip():
            fail(artifact, f"skipped[{idx}].skip_reason is non-empty string", repr(row["skip_reason"]), "Keep skipped summary entries actionable.")
        if row["publish"] is not False:
            fail(artifact, f"skipped[{idx}] publish false with skip_reason", repr(row), "Keep skipped summary entries actionable.")
        expected_target = f"pg{row['pg_major']}-{row['debian_variant']}"
        expected_marker = f"cloudnative-pg-timescaledb/generated/{row['pg_major']}/{row['debian_variant']}/Dockerfile.skipped.json"
        if row["bake_target"] != expected_target or row["skipped_marker"] != expected_marker:
            fail(artifact, f"skipped[{idx}] exposes metadata-derived marker and target", repr(row), f"Use bake_target={expected_target!r} and skipped_marker={expected_marker!r}.")
        if row["latest_eligible"] is not False:
            fail(artifact, f"skipped[{idx}].latest_eligible is false", repr(row), "Only publishable include[] rows may own latest; skipped rows are not built or promoted.")
        if row["pg_major"] == "19beta1" and row["experimental"] is not True:
            fail(artifact, f"skipped[{idx}].19beta1 rows are experimental", repr(row), "Keep PostgreSQL 19 preview rows experimental.")
    latest_rows = [(row["pg_major"], row["debian_variant"]) for row in include if row.get("latest_eligible") is True]
    if latest_rows != [("18", "trixie")]:
        fail(artifact, "matrix has exactly one latest owner", repr(latest_rows), "Keep latest on PostgreSQL 18 trixie only across publishable and skipped matrix rows.")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", default="")
    parser.add_argument("--json", default="")
    args = parser.parse_args()
    payload, artifact = load_payload(args)
    validate(payload, artifact)


if __name__ == "__main__":
    main()
