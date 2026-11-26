#!/usr/bin/env python3
"""Small contract check for published release notes."""

import json
import subprocess
import tempfile
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "cloudnative-pg-timescaledb/scripts/write-release-notes.py"
DIGEST = "sha256:" + "a" * 64
release_job = yaml.safe_load((ROOT / ".github/workflows/build.yml").read_text())["jobs"]["github_release"]
assert {"matrix", "publish", "release_metadata_autocommit"}.issubset(release_job["needs"])
assert release_job["permissions"] == {"actions": "read", "contents": "write"}
assert "refs/heads/main" in release_job["if"]
assert "gh release create" in str(release_job["steps"]) and "--notes-file" in str(release_job["steps"])


with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    metadata = root / "metadata" / "row"
    metadata.mkdir(parents=True)
    row = {
        "bake_target": "pg18-trixie",
        "pg_major": "18",
        "debian_variant": "trixie",
        "image": "ghcr.io/pnetcloud/example",
        "intended_tags": ["18", "18-pg18.6-ts2.30.1-20260928"],
        "publish": True,
    }
    (root / "matrix.json").write_text(json.dumps({"include": [row]}))
    (root / "versions.yaml").write_text(yaml.safe_dump({"entries": [], "barman_plugin": {}}))
    record = {
        "image": row["image"],
        "final_tags": row["intended_tags"],
        "published_digest": DIGEST,
        "scan_result": "passed",
        "verified": True,
    }
    path = metadata / "ghcr-release-metadata.json"
    path.write_text(json.dumps(record))
    command = [
        "python3", str(SCRIPT), "--matrix", str(root / "matrix.json"),
        "--metadata-dir", str(root / "metadata"), "--versions", str(root / "versions.yaml"),
        "--source-sha", "test-sha", "--run-url", "https://example.test/run",
        "--repo-url", "https://example.test/repo",
        "--output", str(root / "notes.md"),
    ]
    subprocess.run(command, check=True)
    notes = (root / "notes.md").read_text()
    assert row["intended_tags"][1] in notes and DIGEST in notes
    record["verified"] = False
    path.write_text(json.dumps(record))
    assert subprocess.run(command, capture_output=True).returncode != 0

    record["verified"] = True
    path.write_text(json.dumps(record))
    tracked_versions = root / "cloudnative-pg-timescaledb" / "versions.yaml"
    tracked_versions.parent.mkdir()
    tracked_versions.write_text(yaml.safe_dump({"entries": [], "barman_plugin": {"release": "v1"}}))
    for arguments in (
        ["init", "-q"], ["config", "user.name", "test"], ["config", "user.email", "test@example.test"],
        ["add", "."], ["commit", "-qm", "baseline"], ["tag", "cnpg-timescaledb-r1"],
    ):
        subprocess.run(["git", "-C", str(root), *arguments], check=True)
    tracked_versions.write_text(yaml.safe_dump({"entries": [], "barman_plugin": {"release": "v2"}}))
    subprocess.run(["git", "-C", str(root), "add", "cloudnative-pg-timescaledb/versions.yaml"], check=True)
    subprocess.run(["git", "-C", str(root), "commit", "-qm", "update plugin"], check=True)
    second = command.copy()
    second[second.index("--versions") + 1] = str(tracked_versions)
    second[second.index("--source-sha") + 1] = "HEAD"
    second.extend(["--previous-tag", "cnpg-timescaledb-r1"])
    subprocess.run(second, cwd=root, check=True)
    notes = (root / "notes.md").read_text()
    assert "`v1` → `v2`" in notes and "update plugin" in notes

print("PASS release notes published-matrix gate")
