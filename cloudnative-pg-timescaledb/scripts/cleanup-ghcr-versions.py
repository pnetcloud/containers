#!/usr/bin/env python3
import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


API_VERSION = "2022-11-28"


def fail(message):
    raise SystemExit(message)


def request_json(url, token):
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": API_VERSION,
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode())
    except urllib.error.HTTPError as exc:
        body = exc.read().decode(errors="replace")
        fail(f"GET {url} failed: HTTP {exc.code}: {body}")


def delete_url(url, token):
    request = urllib.request.Request(
        url,
        method="DELETE",
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": API_VERSION,
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            if response.status not in {202, 204}:
                fail(f"DELETE {url} returned HTTP {response.status}")
    except urllib.error.HTTPError as exc:
        body = exc.read().decode(errors="replace")
        fail(f"DELETE {url} failed: HTTP {exc.code}: {body}")


def package_base(owner_kind, owner, package_name):
    encoded_package = urllib.parse.quote(package_name, safe="")
    encoded_owner = urllib.parse.quote(owner, safe="")
    return f"https://api.github.com/{owner_kind}/{encoded_owner}/packages/container/{encoded_package}/versions"


def load_versions(args, token):
    if args.versions_file:
        payload = json.loads(Path(args.versions_file).read_text())
        if not isinstance(payload, list):
            fail(f"{args.versions_file} must contain a package version array")
        return payload

    base = package_base(args.owner_kind, args.owner, args.package)
    versions = []
    for page in range(1, args.max_pages + 1):
        page_versions = request_json(f"{base}?per_page=100&page={page}", token)
        if not isinstance(page_versions, list):
            fail(f"GitHub package versions response page {page} is not an array")
        if not page_versions:
            break
        versions.extend(page_versions)
    return versions


def tags_for(version):
    metadata = version.get("metadata") if isinstance(version, dict) else {}
    container = metadata.get("container") if isinstance(metadata, dict) else {}
    tags = container.get("tags") if isinstance(container, dict) else []
    return [tag for tag in tags if isinstance(tag, str)]


def select_candidate_versions(versions, prefix):
    selected = []
    skipped_mixed = []
    for version in versions:
        version_id = version.get("id")
        tags = tags_for(version)
        if not tags:
            continue
        candidate_tags = [tag for tag in tags if tag.startswith(prefix)]
        if not candidate_tags:
            continue
        record = {
            "id": version_id,
            "created_at": version.get("created_at", ""),
            "tags": tags,
        }
        if len(candidate_tags) == len(tags):
            selected.append(record)
        else:
            skipped_mixed.append(record)
    return selected, skipped_mixed


def main():
    parser = argparse.ArgumentParser(description="Delete temporary GHCR candidate-only package versions.")
    parser.add_argument("--owner", required=True)
    parser.add_argument("--owner-kind", choices=["users", "orgs"], default="users")
    parser.add_argument("--package", required=True)
    parser.add_argument("--candidate-prefix", default="candidate-")
    parser.add_argument("--delete-candidates", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--versions-file")
    parser.add_argument("--max-pages", type=int, default=20)
    args = parser.parse_args()

    token = os.environ.get("GITHUB_TOKEN", "")
    if not args.versions_file and not token:
        fail("GITHUB_TOKEN is required when --versions-file is not used")

    versions = load_versions(args, token)
    selected, skipped_mixed = select_candidate_versions(versions, args.candidate_prefix)

    deleted = []
    if args.delete_candidates and not args.dry_run:
        if args.versions_file:
            fail("--versions-file can only be used with --dry-run")
        base = package_base(args.owner_kind, args.owner, args.package)
        for record in selected:
            version_id = record.get("id")
            if not isinstance(version_id, int):
                fail(f"selected version has invalid id: {record}")
            delete_url(f"{base}/{version_id}", token)
            deleted.append(record)

    summary = {
        "package": f"{args.owner_kind}/{args.owner}/{args.package}",
        "candidate_prefix": args.candidate_prefix,
        "dry_run": args.dry_run,
        "delete_candidates": args.delete_candidates,
        "selected_count": len(selected),
        "deleted_count": len(deleted),
        "skipped_mixed_tag_count": len(skipped_mixed),
        "selected": selected,
        "skipped_mixed_tags": skipped_mixed,
    }
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    sys.dont_write_bytecode = True
    main()
