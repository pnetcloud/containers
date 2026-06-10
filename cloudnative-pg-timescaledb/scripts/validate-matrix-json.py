#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import re
import sys


REQUIRED_INCLUDE = {
    "pg_major", "pg_version", "debian_variant", "image", "candidate_ref", "digest",
    "platforms", "bake_target", "dockerfile", "intended_tags", "publish", "experimental",
    "latest_eligible", "scan_result", "sbom_ref", "provenance_ref", "signature_ref",
}
DOCKER_TAG_RE = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}")


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
    include = payload.get("include")
    if not isinstance(include, list):
        fail(artifact, "include is array", repr(include), "Emit include[] for GitHub Actions strategy matrix rows.")
    for idx, row in enumerate(include):
        if not isinstance(row, dict):
            fail(artifact, f"include[{idx}] is object", type(row).__name__, "Emit object rows for matrix include[].")
        missing = sorted(REQUIRED_INCLUDE - set(row))
        if missing:
            fail(artifact, f"include[{idx}] required keys", f"missing {missing}", "Keep downstream workflow keys explicit; do not recompute release fields.")
        intended_tags = row["intended_tags"]
        if not isinstance(intended_tags, list) or not intended_tags:
            fail(artifact, f"include[{idx}].intended_tags is non-empty array", repr(intended_tags), "Emit deterministic tag-policy output for every publishable matrix row.")
        for tag in intended_tags:
            if not isinstance(tag, str) or not DOCKER_TAG_RE.fullmatch(tag):
                fail(artifact, f"include[{idx}].intended_tags use Docker tag grammar", repr(tag), "Regenerate matrix tags from validated tag policy output.")
        candidate_ref = row["candidate_ref"]
        if not isinstance(candidate_ref, str) or ":" not in candidate_ref.rsplit("/", 1)[-1]:
            fail(artifact, f"include[{idx}].candidate_ref has tagged image reference", repr(candidate_ref), "Use image:immutable-tag candidate references.")
        candidate_tag = candidate_ref.rsplit(":", 1)[-1]
        if not DOCKER_TAG_RE.fullmatch(candidate_tag):
            fail(artifact, f"include[{idx}].candidate_ref tag uses Docker tag grammar", repr(candidate_ref), "Use a Docker tag-safe immutable candidate reference.")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", default="")
    parser.add_argument("--json", default="")
    args = parser.parse_args()
    payload, artifact = load_payload(args)
    validate(payload, artifact)


if __name__ == "__main__":
    main()
