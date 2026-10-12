#!/usr/bin/env python3
"""Write GitHub Release notes from the published matrix and version changes."""

import argparse
import json
import re
import subprocess
from pathlib import Path

import yaml


DIGEST = re.compile(r"sha256:[0-9a-f]{64}\Z")
VERSION_FIELDS = (
    "pg_version",
    "cnpg_tag",
    "cnpg_digest",
    "timescaledb_version",
    "timescaledb_package_version",
    "toolkit_version",
    "toolkit_package_version",
    "publish",
    "experimental",
    "latest_eligible",
    "tags",
)


def load_previous(tag):
    if not tag:
        return None
    content = subprocess.check_output(
        ["git", "show", f"{tag}:cloudnative-pg-timescaledb/versions.yaml"], text=True
    )
    return yaml.safe_load(content)


def rows_by_key(versions):
    return {(row["pg_major"], row["debian_variant"]): row for row in versions["entries"]}


def changes(previous, current):
    if previous is None:
        return ["First GitHub Release for this image family."]
    lines = []
    old_rows, new_rows = rows_by_key(previous), rows_by_key(current)
    for key in sorted(old_rows.keys() | new_rows.keys()):
        label = f"PostgreSQL {key[0]} / Debian {key[1]}"
        if key not in old_rows:
            lines.append(f"Added {label}.")
        elif key not in new_rows:
            lines.append(f"Removed {label}.")
        else:
            for field in VERSION_FIELDS:
                old, new = old_rows[key].get(field), new_rows[key].get(field)
                if old != new:
                    lines.append(f"{label}: {field} `{old}` → `{new}`.")
    old_plugin = previous.get("barman_plugin", {})
    new_plugin = current.get("barman_plugin", {})
    if old_plugin.get("release") != new_plugin.get("release"):
        lines.append(
            f"Barman Cloud Plugin: `{old_plugin.get('release')}` → `{new_plugin.get('release')}`."
        )
    return lines or ["No version metadata changes; images were rebuilt and verified."]


def source_changes(previous_tag, source_sha):
    if not previous_tag:
        return ["Initial GitHub Release baseline."]
    subprocess.run(["git", "merge-base", "--is-ancestor", previous_tag, source_sha], check=True)
    output = subprocess.check_output(
        ["git", "log", "--no-merges", "--format=%h %s", f"{previous_tag}..{source_sha}"],
        text=True,
    )
    return output.splitlines() or ["No source commits since the previous release."]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--matrix", type=Path, required=True)
    parser.add_argument("--metadata-dir", type=Path, required=True)
    parser.add_argument("--versions", type=Path, required=True)
    parser.add_argument("--previous-tag", default="")
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--repo-url", required=True)
    parser.add_argument("--run-url", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    matrix = json.loads(args.matrix.read_text())
    expected = [row for row in matrix["include"] if row["publish"]]
    records = [json.loads(path.read_text()) for path in args.metadata_dir.rglob("ghcr-release-metadata.json")]
    if not expected or len(records) != len(expected):
        raise SystemExit(f"published matrix incomplete: expected {len(expected)} records, got {len(records)}")
    by_tags = {tuple(sorted(record["final_tags"])): record for record in records}
    if len(by_tags) != len(records):
        raise SystemExit("duplicate published tag set")
    for row in expected:
        record = by_tags.get(tuple(sorted(row["intended_tags"])))
        if not record or record.get("image") != row["image"]:
            raise SystemExit(f"missing published metadata for {row['bake_target']}")
        if not DIGEST.fullmatch(record.get("published_digest", "")):
            raise SystemExit(f"invalid published digest for {row['bake_target']}")
        if record.get("scan_result") != "passed" or record.get("verified") is not True:
            raise SystemExit(f"unverified published metadata for {row['bake_target']}")

    current = yaml.safe_load(args.versions.read_text())
    previous = load_previous(args.previous_tag)
    lines = [
        "# CloudNativePG TimescaleDB images",
        "",
        "## Changes since the previous release",
        "",
        *[f"- {change}" for change in changes(previous, current)],
        "",
        "## Source changes",
        "",
        *[f"- {commit}" for commit in source_changes(args.previous_tag, args.source_sha)],
        *(["", f"Full comparison: {args.repo_url}/compare/{args.previous_tag}...{args.source_sha}"] if args.previous_tag else []),
        "",
        "## Published images",
        "",
        "| PostgreSQL | Debian | Version tag | Published digest |",
        "| --- | --- | --- | --- |",
    ]
    for row in sorted(expected, key=lambda item: (item["pg_major"], item["debian_variant"])):
        record = by_tags[tuple(sorted(row["intended_tags"]))]
        version_tag = next(tag for tag in row["intended_tags"] if "-pg" in tag)
        lines.append(
            f"| {row['pg_major']} | {row['debian_variant']} | "
            f"`{record['image']}:{version_tag}` | `{record['published_digest']}` |"
        )
    lines.extend(
        [
            "",
            "Every row passed the candidate smoke tests, vulnerability gate, signing checks, and public pull verification in the linked build.",
            "",
            f"Source commit: `{args.source_sha}`  ",
            f"Build and evidence: {args.run_url}",
            "",
        ]
    )
    args.output.write_text("\n".join(lines))


if __name__ == "__main__":
    main()
