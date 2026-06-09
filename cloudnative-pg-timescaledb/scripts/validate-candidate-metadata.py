#!/usr/bin/env python3
import argparse
import json
import re
import sys
from pathlib import Path

REQUIRED_KEYS = {
    "image",
    "candidate_ref",
    "candidate_digest",
    "platform_digest",
    "index_digest",
    "platform_digests",
    "platform",
    "platforms",
    "expected_platform",
    "runtime_architecture",
    "smoke_architecture_status",
    "bake_target",
    "dockerfile",
    "pg_major",
    "pg_version",
    "debian_variant",
    "intended_tags",
    "publish",
    "experimental",
    "latest_eligible",
    "smoke_container_status",
    "smoke_sql_status",
}
DIGEST_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
ARCH_TO_PLATFORM = {"amd64": "linux/amd64", "arm64": "linux/arm64"}


def diag(command, artifact, expected, actual, remediation):
    raise SystemExit(
        f"command: {command}\n"
        f"artifact: {artifact}\n"
        f"expected: {expected}\n"
        f"actual: {actual}\n"
        f"remediation: {remediation}"
    )


def require(condition, command, artifact, expected, actual, remediation):
    if not condition:
        diag(command, artifact, expected, actual, remediation)


def load_records(path):
    command = f"validate-candidate-metadata --file {path}"
    try:
        payload = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        diag(command, path, "valid JSON", str(exc), "Write candidate metadata as deterministic JSON.")
    records = payload if isinstance(payload, list) else [payload]
    require(records and all(isinstance(record, dict) for record in records), command, path, "object record or non-empty array of object records", type(payload).__name__, "Emit one record per smoked platform candidate.")
    return command, records


def validate_record(command, artifact, record, index):
    missing = sorted(REQUIRED_KEYS - set(record))
    extra = sorted(set(record) - REQUIRED_KEYS)
    require(not missing and not extra, command, artifact, f"record[{index}] keys exactly {sorted(REQUIRED_KEYS)}", f"missing {missing}; extra {extra}", "Keep the candidate metadata artifact schema stable for downstream release stories.")

    platform = record["platform"]
    platforms = record["platforms"]
    require(isinstance(platforms, list) and platforms, command, artifact, f"record[{index}].platforms is a non-empty array", repr(platforms), "List every publishable platform that must pass smoke before candidate manifest creation.")
    require(len(platforms) == len(set(platforms)), command, artifact, f"record[{index}].platforms has no duplicates", repr(platforms), "Do not duplicate platform smoke coverage.")
    require(platform in platforms, command, artifact, f"record[{index}].platform is listed in platforms", f"platform={platform}; platforms={platforms}", "Record one candidate metadata object per smoked platform.")
    require(record["expected_platform"] == platform, command, artifact, f"record[{index}].expected_platform equals platform", f"expected_platform={record['expected_platform']}; platform={platform}", "Use the platform under test as the expected runtime platform.")

    platform_digests = record["platform_digests"]
    require(isinstance(platform_digests, dict), command, artifact, f"record[{index}].platform_digests is an object", type(platform_digests).__name__, "Key platform digests by platform string.")
    require(set(platform_digests) == set(platforms), command, artifact, f"record[{index}].platform_digests keys exactly match platforms", f"keys={sorted(platform_digests)}; platforms={platforms}", "Write one immutable digest for every publishable platform and no extra platforms.")

    digest_fields = ["candidate_digest", "platform_digest", "index_digest"]
    for field in digest_fields:
        require(isinstance(record[field], str) and DIGEST_RE.fullmatch(record[field]), command, artifact, f"record[{index}].{field} matches sha256:<64 lowercase hex>", repr(record[field]), "Record immutable registry digests, not mutable tags.")
    for key, value in platform_digests.items():
        require(isinstance(value, str) and DIGEST_RE.fullmatch(value), command, artifact, f"record[{index}].platform_digests[{key!r}] matches sha256:<64 lowercase hex>", repr(value), "Record immutable platform manifest digests.")
    require(record["platform_digest"] == platform_digests[platform], command, artifact, f"record[{index}].platform_digest equals platform_digests[platform]", f"platform_digest={record['platform_digest']}; platform_digests[{platform}]={platform_digests[platform]}", "Keep singular platform digest and digest map semantics aligned.")
    require(record["index_digest"] not in set(platform_digests.values()), command, artifact, f"record[{index}].index_digest is distinct from per-platform digests", f"index_digest={record['index_digest']}; platform_digests={platform_digests}", "Create the multi-platform candidate index only after all platform smoke checks pass.")
    require(len(set(platform_digests.values())) == len(platform_digests), command, artifact, f"record[{index}].platform_digests values are not duplicated", platform_digests, "Do not reuse one platform digest for multiple platform records.")

    runtime_arch = record["runtime_architecture"]
    actual_platform = ARCH_TO_PLATFORM.get(runtime_arch, f"unsupported/{runtime_arch}")
    require(actual_platform == record["expected_platform"], command, artifact, f"record[{index}] runtime architecture maps to expected platform", f"dpkg={runtime_arch}; actual_platform={actual_platform}; expected_platform={record['expected_platform']}", "Run dpkg --print-architecture inside the candidate image and fail mismatches before publish.")
    for field in ["smoke_architecture_status", "smoke_container_status", "smoke_sql_status"]:
        require(record[field] == "passed", command, artifact, f"record[{index}].{field} is passed", repr(record[field]), "Only emit publish-path candidate metadata after every smoke gate passes.")

    require(record["publish"] is True, command, artifact, f"record[{index}].publish is true", repr(record["publish"]), "Exclude skipped metadata rows from candidate publish jobs.")
    require(record["experimental"] is False, command, artifact, f"record[{index}].experimental is false", repr(record["experimental"]), "Do not send experimental PostgreSQL preview rows into the publish path.")
    require(isinstance(record["intended_tags"], list) and record["intended_tags"], command, artifact, f"record[{index}].intended_tags is a non-empty array", repr(record["intended_tags"]), "Carry final tags as metadata only; do not push them in the candidate job.")
    forbidden_refs = {f"{record['image']}:{tag}" for tag in record["intended_tags"]}
    require(record["candidate_ref"] not in forbidden_refs and ":latest" not in record["candidate_ref"], command, artifact, f"record[{index}].candidate_ref is candidate-only, not a final tag", record["candidate_ref"], "Use a candidate-scoped tag or digest reference for the release candidate.")


def validate_record_groups(command, artifact, records):
    groups = {}
    for record in records:
        key = (
            record["image"],
            record["bake_target"],
            record["dockerfile"],
            record["pg_major"],
            record["pg_version"],
            record["debian_variant"],
        )
        groups.setdefault(key, []).append(record)
    for key, group in groups.items():
        label = "/".join(str(part) for part in key)
        expected_platforms = group[0]["platforms"]
        expected_digests = group[0]["platform_digests"]
        expected_index = group[0]["index_digest"]
        expected_tags = group[0]["intended_tags"]
        for idx, record in enumerate(group):
            require(record["platforms"] == expected_platforms, command, artifact, f"group {label} record[{idx}].platforms is consistent", f"expected={expected_platforms}; actual={record['platforms']}", "Do not mix platform coverage contracts within one image row.")
            require(record["platform_digests"] == expected_digests, command, artifact, f"group {label} record[{idx}].platform_digests is consistent", f"expected={expected_digests}; actual={record['platform_digests']}", "All platform records for an image row must point to the same complete digest map.")
            require(record["index_digest"] == expected_index, command, artifact, f"group {label} record[{idx}].index_digest is consistent", f"expected={expected_index}; actual={record['index_digest']}", "All platform records for an image row must reference the same post-smoke candidate index.")
            require(record["intended_tags"] == expected_tags, command, artifact, f"group {label} record[{idx}].intended_tags is consistent", f"expected={expected_tags}; actual={record['intended_tags']}", "Do not mix final tag intent between platform records.")
        actual_platforms = [record["platform"] for record in group]
        require(len(actual_platforms) == len(set(actual_platforms)), command, artifact, f"group {label} contains at most one record per platform", actual_platforms, "Emit exactly one candidate metadata record for each smoked platform.")
        require(set(actual_platforms) == set(expected_platforms), command, artifact, f"group {label} records cover every declared platform", f"records={sorted(actual_platforms)}; platforms={expected_platforms}", "Fail candidate metadata validation when any publishable platform lacks smoke results.")


def validate_file(path):
    command, records = load_records(path)
    for idx, record in enumerate(records):
        validate_record(command, path, record, idx)
    validate_record_groups(command, path, records)
    print(f"PASS candidate metadata records={len(records)} artifact={path}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", type=Path, required=True)
    args = parser.parse_args()
    validate_file(args.file)


if __name__ == "__main__":
    main()
