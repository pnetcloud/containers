#!/usr/bin/env python3
import argparse
import json
import re
import sys
from pathlib import Path

DIGEST_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
IMMUTABLE_REF_RE = re.compile(r"^ghcr\.io/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@sha256:[0-9a-f]{64}(?:[#:].+)?$")
EXPECTED_ISSUER = "https://token.actions.githubusercontent.com"
DEFAULT_IDENTITY = "https://github.com/pnetcloud/containers/.github/workflows/build.yml@refs/heads/main"

REQUIRED_TOP_LEVEL = {
    "image",
    "candidate_digest",
    "index_digest",
    "platform_digests",
    "per_digest_evidence",
    "scan_result",
    "expected_certificate_identity",
    "cosign_certificate_issuer",
    "verified",
}
REQUIRED_PER_DIGEST = {
    "digest",
    "sbom_ref",
    "provenance_ref",
    "signature_ref",
    "verification_ref",
    "verification_path",
    "attestation_path",
    "verified",
    "signed_digest",
    "verification_identity",
    "verification_issuer",
}


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


def load_json(path, command):
    try:
        payload = json.loads(path.read_text())
    except FileNotFoundError:
        diag(command, path, "release evidence JSON exists", "missing", "Upload and download the release evidence artifact before validation.")
    except json.JSONDecodeError as exc:
        diag(command, path, "valid JSON", str(exc), "Write release evidence as deterministic JSON.")
    require(isinstance(payload, dict), command, path, "top-level JSON object", type(payload).__name__, "Emit one evidence object per release candidate image row.")
    return payload


def validate_digest(command, artifact, field, value):
    require(isinstance(value, str) and DIGEST_RE.fullmatch(value), command, artifact, f"{field} matches sha256:<64 lowercase hex>", repr(value), "Record immutable registry digests only.")


def normalize_per_digest(records, command, artifact):
    require(isinstance(records, list) and records, command, artifact, "per_digest_evidence is a non-empty array", type(records).__name__, "Write one evidence object for the index digest and every platform digest.")
    by_digest = {}
    for idx, record in enumerate(records):
        require(isinstance(record, dict), command, artifact, f"per_digest_evidence[{idx}] is an object", type(record).__name__, "Use structured per-digest evidence records.")
        missing = sorted(REQUIRED_PER_DIGEST - set(record))
        require(not missing, command, artifact, f"per_digest_evidence[{idx}] contains keys {sorted(REQUIRED_PER_DIGEST)}", f"missing {missing}", "Keep signature and verification evidence complete for every digest.")
        digest = record["digest"]
        validate_digest(command, artifact, f"per_digest_evidence[{idx}].digest", digest)
        require(digest not in by_digest, command, artifact, "one per_digest_evidence record per digest", digest, "Do not duplicate digest evidence records.")
        by_digest[digest] = record
    return by_digest


def require_immutable_ref(command, artifact, field, value, image, digest):
    require(isinstance(value, str) and value.strip(), command, artifact, f"{field} is non-empty", repr(value), "Persist the registry evidence reference.")
    require(IMMUTABLE_REF_RE.fullmatch(value), command, artifact, f"{field} is an immutable ghcr.io/...@sha256 reference", value, "Use digest-addressed GHCR references for release evidence.")
    subject = f"{image}@{digest}"
    require(value.startswith(subject), command, artifact, f"{field} references subject {subject}", value, "Bind SBOM, provenance, signature, and verification evidence to the same digest that will be promoted.")


def resolve_evidence_path(base_file, value, command, artifact, field):
    require(isinstance(value, str) and value.strip(), command, artifact, f"{field} is a non-empty artifact path", repr(value), "Persist verifier outputs inside the release evidence artifact.")
    path = Path(value)
    require(not path.is_absolute() and ".." not in path.parts, command, artifact, f"{field} is a relative path inside the evidence artifact", value, "Store evidence output paths relative to release-evidence.json.")
    resolved = base_file.parent / path
    require(resolved.exists(), command, artifact, f"{field} exists", value, "Upload cosign verification and BuildKit attestation inspection outputs with release evidence.")
    return resolved


def validate_verification_output(path, digest, command, artifact):
    try:
        payload = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        diag(command, artifact, "cosign verification output is JSON", f"{path}: {exc}", "Capture raw cosign verify JSON output.")
    rows = payload if isinstance(payload, list) else [payload]
    found = False
    for row in rows:
        if not isinstance(row, dict):
            continue
        critical = row.get("critical") or {}
        image = critical.get("image") or {}
        if image.get("docker-manifest-digest") == digest:
            found = True
    require(found, command, artifact, f"cosign verification output proves digest {digest}", f"{path}", "Persist the cosign verify output for the same immutable digest that was signed.")


def validate_attestation_output(path, digest, platform_digests, index_digest, command, artifact):
    try:
        payload = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        diag(command, artifact, "BuildKit attestation inspection output is JSON", f"{path}: {exc}", "Capture docker buildx imagetools inspect --raw output for the candidate index.")
    require(isinstance(payload, dict), command, artifact, "BuildKit attestation inspection output is an object", type(payload).__name__, "Store raw OCI index JSON.")
    manifests = payload.get("manifests", [])
    require(isinstance(manifests, list) and manifests, command, artifact, "BuildKit attestation inspection output has manifests", type(manifests).__name__, "Inspect the candidate index digest that Buildx pushed.")
    attestation_count = 0
    manifest_digests = set()
    for manifest in manifests:
        if not isinstance(manifest, dict):
            continue
        annotations = manifest.get("annotations") or {}
        if annotations.get("vnd.docker.reference.type") == "attestation-manifest":
            attestation_count += 1
        if isinstance(manifest.get("digest"), str):
            manifest_digests.add(manifest["digest"])
    require(attestation_count > 0, command, artifact, "BuildKit SBOM/provenance attestation manifests are present", f"attestation_count={attestation_count}", "Build with docker buildx bake --sbom=true --provenance=mode=max and preserve attestations in the candidate index.")
    if digest != index_digest:
        require(digest in manifest_digests, command, artifact, f"attestation inspection output includes platform digest {digest}", sorted(manifest_digests), "Keep per-platform evidence tied to the candidate index that contains the platform manifest and its BuildKit attestations.")
    require(set(platform_digests.values()).issubset(manifest_digests), command, artifact, "attestation inspection output includes every platform digest", sorted(manifest_digests), "Inspect the final candidate index, not a stale or partial manifest.")


def validate_evidence(path, expected_identity, expected_issuer):
    command = f"validate-release-evidence --file {path}"
    payload = load_json(path, command)
    missing = sorted(REQUIRED_TOP_LEVEL - set(payload))
    require(not missing, command, path, f"top-level keys include {sorted(REQUIRED_TOP_LEVEL)}", f"missing {missing}", "Emit the complete release evidence contract before publishing tags.")

    image = payload["image"]
    require(isinstance(image, str) and image.startswith("ghcr.io/") and ":" not in image, command, path, "image is an untagged GHCR repository", repr(image), "Store registry/repository separately from immutable digests.")
    validate_digest(command, path, "candidate_digest", payload["candidate_digest"])
    validate_digest(command, path, "index_digest", payload["index_digest"])
    require(payload["candidate_digest"] != payload["index_digest"], command, path, "candidate_digest is a single-platform digest and differs from index_digest", f"candidate={payload['candidate_digest']} index={payload['index_digest']}", "Use Story 4.2 candidate metadata without collapsing platform and index digest semantics.")

    platform_digests = payload["platform_digests"]
    require(isinstance(platform_digests, dict) and platform_digests, command, path, "platform_digests is a non-empty object", type(platform_digests).__name__, "Carry every required platform digest from candidate metadata.")
    require(len(platform_digests) == len(set(platform_digests)), command, path, "platform_digests has unique platform keys", sorted(platform_digests), "Do not duplicate platform keys.")
    for platform, digest in platform_digests.items():
        require(platform in {"linux/amd64", "linux/arm64"}, command, path, "platform_digests keys are supported platforms", platform, "Keep Story 4.4 scoped to Debian multi-platform images already generated by the matrix.")
        validate_digest(command, path, f"platform_digests[{platform!r}]", digest)
    require(payload["index_digest"] not in set(platform_digests.values()), command, path, "index_digest is distinct from platform digests", f"index={payload['index_digest']} platform_digests={platform_digests}", "Sign the final multi-platform index and every platform manifest separately.")

    require(payload["scan_result"] == "passed", command, path, "scan_result is passed", repr(payload["scan_result"]), "Block publish until the Story 4.3 vulnerability gate passes for the same candidate.")
    require(payload["verified"] is True, command, path, "verified is true", repr(payload["verified"]), "Do not publish unless every digest has a passing cosign verification.")
    require(payload["expected_certificate_identity"] == expected_identity, command, path, "expected_certificate_identity equals the exact workflow ref", repr(payload["expected_certificate_identity"]), "Derive the identity as https://github.com/pnetcloud/containers/.github/workflows/build.yml@<ref> and do not use regex verification.")
    require(payload["cosign_certificate_issuer"] == expected_issuer, command, path, "cosign_certificate_issuer is GitHub Actions OIDC", repr(payload["cosign_certificate_issuer"]), "Use https://token.actions.githubusercontent.com for keyless GitHub OIDC verification.")

    required_digests = [payload["index_digest"], *platform_digests.values()]
    by_digest = normalize_per_digest(payload["per_digest_evidence"], command, path)
    require(set(by_digest) == set(required_digests), command, path, "per_digest_evidence covers index_digest and every platform digest exactly", f"expected={required_digests}; actual={sorted(by_digest)}", "Write one evidence record for the final index and each platform manifest digest.")

    for digest in required_digests:
        record = by_digest[digest]
        for field in ["sbom_ref", "provenance_ref", "signature_ref", "verification_ref"]:
            require_immutable_ref(command, path, f"per_digest_evidence[{digest}].{field}", record[field], image, digest)
        require(record["signed_digest"] == digest, command, path, f"per_digest_evidence[{digest}].signed_digest matches digest", f"signed_digest={record['signed_digest']} digest={digest}", "Record the exact digest passed to cosign sign and verify.")
        require(record["verification_identity"] == expected_identity, command, path, f"per_digest_evidence[{digest}].verification_identity matches expected identity", repr(record["verification_identity"]), "Verify with --certificate-identity using the exact workflow identity.")
        require(record["verification_issuer"] == expected_issuer, command, path, f"per_digest_evidence[{digest}].verification_issuer matches GitHub issuer", repr(record["verification_issuer"]), "Verify with --certificate-oidc-issuer https://token.actions.githubusercontent.com.")
        require(record["verified"] is True, command, path, f"per_digest_evidence[{digest}].verified is true", repr(record["verified"]), "Reject missing, stale, failed, or digest-mismatched cosign verification results.")
        verification_path = resolve_evidence_path(path, record["verification_path"], command, path, f"per_digest_evidence[{digest}].verification_path")
        attestation_path = resolve_evidence_path(path, record["attestation_path"], command, path, f"per_digest_evidence[{digest}].attestation_path")
        validate_verification_output(verification_path, digest, command, path)
        validate_attestation_output(attestation_path, digest, platform_digests, payload["index_digest"], command, path)

    print(f"PASS release evidence digests={len(required_digests)} artifact={path}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", type=Path, required=True)
    parser.add_argument("--expected-certificate-identity", default=DEFAULT_IDENTITY)
    parser.add_argument("--cosign-certificate-issuer", default=EXPECTED_ISSUER)
    args = parser.parse_args()
    validate_evidence(args.file, args.expected_certificate_identity, args.cosign_certificate_issuer)


if __name__ == "__main__":
    sys.dont_write_bytecode = True
    main()
