#!/usr/bin/env python3
import argparse
import datetime
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


API_VERSION = "2022-11-28"
SIGNATURE_TAG_RE = re.compile(r"^sha256-[0-9a-f]{64}$")


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
    for attempt in range(1, 6):
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
                if response.status in {202, 204}:
                    return
                if response.status in {429, 500, 502, 503, 504} and attempt < 5:
                    time.sleep(attempt * 2)
                    continue
                fail(f"DELETE {url} returned HTTP {response.status}")
        except urllib.error.HTTPError as exc:
            body = exc.read().decode(errors="replace")
            if exc.code == 404:
                return
            if exc.code in {429, 500, 502, 503, 504} and attempt < 5:
                time.sleep(attempt * 2)
                continue
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


def select_signature_versions(versions):
    selected = []
    skipped_mixed = []
    for version in versions:
        version_id = version.get("id")
        tags = tags_for(version)
        if not tags:
            continue
        signature_tags = [tag for tag in tags if SIGNATURE_TAG_RE.fullmatch(tag)]
        if not signature_tags:
            continue
        record = {
            "id": version_id,
            "created_at": version.get("created_at", ""),
            "tags": tags,
        }
        if len(signature_tags) == len(tags):
            selected.append(record)
        else:
            skipped_mixed.append(record)
    return selected, skipped_mixed


def candidate_tags_from(records, prefix):
    tags = []
    for record in records:
        for tag in record.get("tags", []):
            if tag.startswith(prefix) and tag not in tags:
                tags.append(tag)
    return tags


def delete_versions(owner_kind, owner, package_name, records, token):
    base = package_base(owner_kind, owner, package_name)
    deleted = []
    for record in records:
        version_id = record.get("id")
        if not isinstance(version_id, int):
            fail(f"selected version has invalid id: {record}")
        delete_url(f"{base}/{version_id}", token)
        deleted.append(record)
    return deleted


def push_tombstone(image, tag):
    created = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
    with tempfile.TemporaryDirectory(prefix="ghcr-candidate-cleanup-") as tmp:
        dockerfile = Path(tmp) / "Dockerfile"
        dockerfile.write_text(
            "\n".join(
                [
                    "FROM scratch",
                    'LABEL org.opencontainers.image.title="temporary GHCR candidate cleanup marker"',
                    'LABEL org.opencontainers.image.description="This image exists only long enough to detach a candidate tag from a release digest."',
                    f'LABEL io.pnet.cleanup.candidate-tag="{tag}"',
                    f'LABEL io.pnet.cleanup.created-at="{created}"',
                    "",
                ]
            )
        )
        ref = f"{image}:{tag}"
        subprocess.run(
            [
                "docker",
                "buildx",
                "build",
                "--file",
                str(dockerfile),
                "--tag",
                ref,
                "--push",
                tmp,
            ],
            check=True,
        )


def main():
    parser = argparse.ArgumentParser(description="Delete temporary GHCR candidate-only package versions.")
    parser.add_argument("--owner", required=True)
    parser.add_argument("--owner-kind", choices=["users", "orgs"], default="users")
    parser.add_argument("--package", required=True)
    parser.add_argument("--image", help="Container image reference used when detaching mixed candidate tags, for example ghcr.io/owner/name.")
    parser.add_argument("--candidate-prefix", default="candidate-")
    parser.add_argument("--delete-candidates", action="store_true")
    parser.add_argument("--delete-signature-tags", action="store_true", help="Delete main-package cosign signature tags named sha256-<64hex>.")
    parser.add_argument("--detach-mixed-candidates", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--versions-file")
    parser.add_argument("--max-pages", type=int, default=20)
    args = parser.parse_args()

    token = os.environ.get("GITHUB_TOKEN", "")
    if not args.versions_file and not token:
        fail("GITHUB_TOKEN is required when --versions-file is not used")

    if args.detach_mixed_candidates and not args.image:
        fail("--image is required with --detach-mixed-candidates")
    if args.detach_mixed_candidates and args.versions_file and not args.dry_run:
        fail("--versions-file can only be used with --detach-mixed-candidates in --dry-run mode")

    versions = load_versions(args, token)
    selected, skipped_mixed = select_candidate_versions(versions, args.candidate_prefix)
    signature_selected, signature_skipped_mixed = select_signature_versions(versions)

    deleted = []
    if args.delete_candidates and not args.dry_run:
        if args.versions_file:
            fail("--versions-file can only be used with --dry-run")
        deleted.extend(delete_versions(args.owner_kind, args.owner, args.package, selected, token))

    signature_deleted = []
    if args.delete_signature_tags and not args.dry_run:
        if args.versions_file:
            fail("--versions-file can only be used with --dry-run")
        signature_deleted.extend(delete_versions(args.owner_kind, args.owner, args.package, signature_selected, token))

    mixed_candidate_tags = candidate_tags_from(skipped_mixed, args.candidate_prefix)
    detached_mixed_tags = []
    if args.detach_mixed_candidates:
        for tag in mixed_candidate_tags:
            if not args.dry_run:
                push_tombstone(args.image, tag)
            detached_mixed_tags.append(tag)

    post_detach_deleted = []
    post_detach_selected = []
    post_detach_skipped_mixed = []
    if args.detach_mixed_candidates and args.delete_candidates and not args.dry_run:
        post_detach_versions = load_versions(args, token)
        post_detach_selected, post_detach_skipped_mixed = select_candidate_versions(post_detach_versions, args.candidate_prefix)
        post_detach_deleted.extend(delete_versions(args.owner_kind, args.owner, args.package, post_detach_selected, token))

    summary = {
        "package": f"{args.owner_kind}/{args.owner}/{args.package}",
        "candidate_prefix": args.candidate_prefix,
        "dry_run": args.dry_run,
        "delete_candidates": args.delete_candidates,
        "detach_mixed_candidates": args.detach_mixed_candidates,
        "selected_count": len(selected),
        "deleted_count": len(deleted),
        "post_detach_selected_count": len(post_detach_selected),
        "post_detach_deleted_count": len(post_detach_deleted),
        "post_detach_skipped_mixed_tag_count": len(post_detach_skipped_mixed),
        "signature_selected_count": len(signature_selected),
        "signature_deleted_count": len(signature_deleted),
        "signature_skipped_mixed_tag_count": len(signature_skipped_mixed),
        "skipped_mixed_tag_count": len(skipped_mixed),
        "mixed_candidate_tags": mixed_candidate_tags,
        "detached_mixed_tags": detached_mixed_tags,
        "signature_selected": signature_selected,
        "signature_deleted": signature_deleted,
        "signature_skipped_mixed_tags": signature_skipped_mixed,
        "selected": selected,
        "post_detach_selected": post_detach_selected,
        "post_detach_deleted": post_detach_deleted,
        "post_detach_skipped_mixed_tags": post_detach_skipped_mixed,
        "skipped_mixed_tags": skipped_mixed,
    }
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    sys.dont_write_bytecode = True
    main()
