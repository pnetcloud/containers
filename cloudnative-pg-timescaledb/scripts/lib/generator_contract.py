#!/usr/bin/env python3
import argparse
import difflib
import json
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[3]
DEFAULT_METADATA = ROOT / "cloudnative-pg-timescaledb" / "versions.yaml"


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


def bake_target(entry):
    return f"pg{entry['pg_major']}-{entry['debian_variant']}"


def image_ref(data, entry):
    registry = data["image"]["registry"]
    repo = data["image"]["repository"]
    tag = f"{entry['pg_major']}-pg{entry['pg_version']}-ts{entry['timescaledb_version'] or 'unresolved'}-00000000"
    if entry["debian_variant"] != "trixie":
        tag = f"{tag}-{entry['debian_variant']}"
    return f"{registry}/{repo}:{tag}"


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
                "dockerfile": dockerfile_path(entry, output_root),
                "source_entry": row_id(entry),
                "publish": entry["publish"],
                "experimental": entry["experimental"],
                "skip_reason": entry["skip_reason"],
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
            for entry in entries
        ],
    }


def matrix_summary(entries):
    return {
        "include": [
            {
                "pg_major": entry["pg_major"],
                "pg_version": entry["pg_version"],
                "debian_variant": entry["debian_variant"],
                "platforms": entry["platforms"],
                "dockerfile": dockerfile_path(entry),
                "bake_target": bake_target(entry),
                "publish": entry["publish"],
                "experimental": entry["experimental"],
                "latest_eligible": entry["latest_eligible"],
                "skip_reason": entry["skip_reason"],
            }
            for entry in entries
        ]
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
    lines = [
        "# Generated by cloudnative-pg-timescaledb/scripts/generate-dockerfiles.sh",
        f"# Source entry: {row_id(entry)}",
        f"# PostgreSQL major: {entry['pg_major']}",
        f"# PostgreSQL version: {entry['pg_version']}",
        f"# Debian variant: {entry['debian_variant']}",
        f"# CNPG tag: {entry['cnpg_tag']}",
        f"# Publish: {str(entry['publish']).lower()}",
        f"# Experimental: {str(entry['experimental']).lower()}",
        f"# Platforms: {', '.join(entry['platforms'])}",
        f"# Skip reason: {entry['skip_reason']}",
        "# Story 1.5 skeleton only; buildable Dockerfile content is owned by Story 3.1.",
        "",
    ]
    return "\n".join(lines)


def render_bake(entries):
    lines = [
        "# Generated by cloudnative-pg-timescaledb/scripts/generate-bake.sh",
        "# Story 1.5 skeleton only; executable Bake behavior is owned by Story 3.3.",
        "group \"default\" {",
        "  targets = [",
    ]
    for entry in entries:
        lines.append(f"    \"{bake_target(entry)}\",")
    lines.extend(["  ]", "}", ""])
    for entry in entries:
        lines.extend(
            [
                f"target \"{bake_target(entry)}\" {{",
                "  context = \".\"",
                f"  dockerfile = \"{dockerfile_path(entry)}\"",
                "  platforms = [" + ", ".join(json.dumps(platform) for platform in entry["platforms"]) + "]",
                f"  tags = [\"local/{bake_target(entry)}:skeleton\"]",
                "  labels = {",
                f"    \"org.opencontainers.image.version\" = \"{entry['pg_major']}\"",
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


def run(kind, metadata, output, check, as_json):
    command = f"generate-{kind}"
    data = parse_metadata(metadata, command)
    validate_metadata_shape(data, command, metadata)
    entries = data["entries"]
    validate_latest(entries, command, metadata)
    if kind == "dockerfiles":
        root = output or "cloudnative-pg-timescaledb/generated"
        summary = dockerfiles_summary(entries, root)
        if check or not as_json:
            for entry in entries:
                write_or_check(dockerfile_path(entry, root), render_dockerfile(entry), check, command)
        if not as_json:
            print(f"generated dockerfile skeletons: {len(entries)}", file=sys.stderr)
    elif kind == "bake":
        bake_file = output or "cloudnative-pg-timescaledb/docker-bake.hcl"
        summary = bake_summary(entries, bake_file)
        if check or not as_json:
            write_or_check(bake_file, render_bake(entries), check, command)
        if not as_json:
            print(f"generated bake skeleton: {bake_file}", file=sys.stderr)
    elif kind == "matrix":
        summary = matrix_summary(entries)
        if check or not as_json:
            content = json.dumps(summary, indent=2, sort_keys=True) + "\n"
            write_or_check(output or "cloudnative-pg-timescaledb/matrix.json", content, check, command)
        if not as_json:
            print(f"generated matrix skeleton entries: {len(entries)}", file=sys.stderr)
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
            if "barman_plugin" in data:
                barman_doc_path = (Path(doc_path).parent / "barman-plugin-reference.md").as_posix()
                write_or_check(barman_doc_path, render_barman_plugin_reference(data["barman_plugin"]), check, command)
        if not as_json:
            print(f"generated compatibility docs skeleton: {doc_path}", file=sys.stderr)
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
