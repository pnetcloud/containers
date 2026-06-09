#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
metadata="${SMOKE_METADATA:-${SCRIPT_DIR}/../versions.yaml}"
fixture="${SMOKE_CONTAINER_FIXTURE:-}"
docker_bin="${DOCKER_BIN:-docker}"
pg="${1:-}"
debian="${2:-}"

source "${SCRIPT_DIR}/lib/command.sh"
require_pg_debian "smoke-test container" "${pg}" "${debian}"

python3 - "${ROOT_DIR}" "${metadata}" "${fixture}" "${docker_bin}" "${pg}" "${debian}" <<'PY'
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(sys.argv[1])
metadata = Path(sys.argv[2])
fixture = sys.argv[3]
docker_bin = sys.argv[4]
pg = sys.argv[5]
debian = sys.argv[6]
SOURCE_REPOSITORY = "https://github.com/pnetcloud/containers"
EXIT_UNSUPPORTED = 65
EXIT_UNAVAILABLE = 69


def exit_with_message(code, command, artifact, image, check, expected, actual, remediation):
    print(
        f"command: {command}\n"
        f"artifact: {artifact}\n"
        f"image: {image}\n"
        f"PG: {pg}\n"
        f"DEBIAN: {debian}\n"
        f"check: {check}\n"
        f"expected: {expected}\n"
        f"actual: {actual}\n"
        f"remediation: {remediation}",
        file=sys.stderr,
    )
    raise SystemExit(code)


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


def parse_mapping_item(text, line_no):
    if ":" not in text:
        exit_with_message(1, "smoke-test container", metadata, "", "metadata parse", "parseable YAML subset", f"line {line_no}: {text!r}", "Use versions.yaml schema-compatible metadata.")
    key, raw_value = text.split(":", 1)
    return key.strip(), parse_scalar(raw_value)


def assign_mapping(target, key, value, line_no, scope):
    if key in target:
        exit_with_message(1, "smoke-test container", metadata, "", "metadata parse", "unique YAML keys", f"duplicate {key!r} at line {line_no} in {scope}", "Remove duplicate metadata keys.")
    target[key] = value


def parse_metadata(path):
    data = {}
    current_top = None
    current_entry = None
    for line_no, raw_line in enumerate(path.read_text().splitlines(), start=1):
        line = raw_line.rstrip()
        if line.strip() == "" or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip(" "))
        item = line.lstrip(" ")
        if indent == 0:
            key, value = parse_mapping_item(item, line_no)
            if item.endswith(":"):
                value = [] if key == "entries" else {}
            assign_mapping(data, key, value, line_no, "top-level metadata")
            current_top = key if isinstance(value, (dict, list)) else None
            current_entry = None
            continue
        if indent == 2 and current_top == "entries":
            if not item.startswith("- "):
                exit_with_message(1, "smoke-test container", path, "", "metadata parse", "entries list item", f"line {line_no}: {item!r}", "Use '- key: value' entry mappings.")
            current_entry = {}
            data["entries"].append(current_entry)
            key, value = parse_mapping_item(item[2:].strip(), line_no)
            assign_mapping(current_entry, key, value, line_no, "entries[] item")
            continue
        if indent == 2 and isinstance(data.get(current_top), dict):
            key, value = parse_mapping_item(item, line_no)
            assign_mapping(data[current_top], key, value, line_no, current_top)
            continue
        if indent == 4 and current_top == "entries" and isinstance(current_entry, dict):
            key, value = parse_mapping_item(item, line_no)
            assign_mapping(current_entry, key, value, line_no, "entries[] item")
            continue
        exit_with_message(1, "smoke-test container", path, "", "metadata parse", "parseable metadata YAML subset", f"line {line_no}: {line!r}", "Use the versions.yaml schema indentation.")
    return data


def default_image_ref(entry):
    return os.environ.get("SMOKE_IMAGE_REF", f"local/pg{entry['pg_major']}-{entry['debian_variant']}:skeleton")


def find_entry(data):
    for entry in data.get("entries", []):
        if entry.get("pg_major") == pg and entry.get("debian_variant") == debian:
            return entry
    exit_with_message(EXIT_UNSUPPORTED, "smoke-test container", metadata, "", "metadata row", f"PG={pg} DEBIAN={debian} row exists", "missing", "Use a supported PG/Debian combination from versions.yaml.")


def load_fixture(path, image_ref):
    try:
        payload = json.loads(Path(path).read_text())
    except json.JSONDecodeError as exc:
        exit_with_message(1, "smoke-test container", path, image_ref, "fixture parse", "valid JSON", str(exc), "Fix the smoke fixture JSON.")
    return payload


def collect_live(image_ref, entry):
    inspect = subprocess.run([docker_bin, "image", "inspect", image_ref], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if inspect.returncode != 0:
        exit_with_message(EXIT_UNAVAILABLE, "smoke-test container", image_ref, image_ref, "image inspect", "locally built image exists", inspect.stderr.strip()[:400], "Run make build for a publishable row, or set SMOKE_IMAGE_REF to the local image reference.")
    try:
        labels = (json.loads(inspect.stdout)[0].get("Config", {}) or {}).get("Labels", {}) or {}
    except (json.JSONDecodeError, IndexError, TypeError) as exc:
        exit_with_message(1, "smoke-test container", image_ref, image_ref, "image inspect", "Docker image inspect JSON with labels", str(exc), "Use a Docker image produced by the generated Dockerfile.")

    pg_major = entry["pg_major"]
    control_dir = f"/usr/share/postgresql/{pg_major}/extension"
    shell = f"""
set -eu
. /etc/os-release
printf 'debian_release=%s\n' "${{VERSION_CODENAME}}"
postgres_version="$(postgres --version | sed -E 's/^.*PostgreSQL\\) *//; s/ .*//')"
printf 'postgres_server_version=%s\n' "${{postgres_version}}"
printf 'postgres_major=%s\n' "${{postgres_version%%.*}}"
for control in timescaledb timescaledb_toolkit vector pgaudit; do
  if [ -f "{control_dir}/${{control}}.control" ]; then
    printf 'control_%s=present\n' "${{control}}"
  else
    printf 'control_%s=missing\n' "${{control}}"
  fi
done
for binary in postgres initdb pg_ctl psql; do
  binary_path="/usr/lib/postgresql/{pg_major}/bin/${{binary}}"
  printf 'binary_path_%s=%s\n' "${{binary}}" "${{binary_path}}"
  if [ -x "${{binary_path}}" ] && "${{binary_path}}" --version >/dev/null 2>&1; then
    printf 'binary_%s=ok\n' "${{binary}}"
  else
    printf 'binary_%s=missing\n' "${{binary}}"
  fi
done
if getent passwd postgres >/dev/null 2>&1; then
  printf 'postgres_user=present\n'
else
  printf 'postgres_user=missing\n'
fi
data_dir="$(mktemp -d /tmp/cnpg-smoke.XXXXXX)"
if initdb -D "${{data_dir}}" >/tmp/cnpg-smoke-initdb.log 2>&1; then
  printf 'data_dir_permissions=%s\n' "$(stat -c '%a' "${{data_dir}}")"
  if pg_ctl -D "${{data_dir}}" -o "-c listen_addresses= -c unix_socket_directories=/tmp" -w start >/tmp/cnpg-smoke-start.log 2>&1; then
    printf 'postgres_startup=ok\n'
    pg_ctl -D "${{data_dir}}" -m fast -w stop >/tmp/cnpg-smoke-stop.log 2>&1 || true
  else
    printf 'postgres_startup=failed\n'
  fi
else
  printf 'data_dir_permissions=unknown\n'
  printf 'postgres_startup=failed\n'
fi
rm -rf "${{data_dir}}"
"""
    run = subprocess.run([docker_bin, "run", "--rm", "--entrypoint", "/bin/sh", image_ref, "-eu", "-c", shell], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if run.returncode != 0:
        exit_with_message(EXIT_UNAVAILABLE, "smoke-test container", image_ref, image_ref, "container runtime", "docker run smoke collector succeeds", run.stderr.strip()[:600], "Inspect the local image runtime and ensure Docker can run it.")
    values = {}
    for line in run.stdout.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
    return {"image_ref": image_ref, "labels": labels, "container": values}


def value_at(payload, key, default=None):
    return payload.get("container", {}).get(key, default)


def require_equal(payload, image_ref, check, expected, actual, remediation):
    if actual != expected:
        exit_with_message(1, "smoke-test container", fixture or image_ref, image_ref, check, repr(expected), repr(actual), remediation)


def require_label(labels, image_ref, name, expected):
    actual = labels.get(name)
    if actual != expected:
        exit_with_message(1, "smoke-test container", fixture or image_ref, image_ref, f"label {name}", repr(expected), repr(actual), "Build the image from the generated Dockerfile so labels match metadata.")


def run_checks(entry, payload):
    image_ref = payload.get("image_ref") or default_image_ref(entry)
    labels = payload.get("labels", {})
    if not isinstance(labels, dict):
        exit_with_message(1, "smoke-test container", fixture or image_ref, image_ref, "labels", "JSON object", repr(labels), "Fixture labels must be a JSON object.")

    require_equal(payload, image_ref, "Debian release", entry["debian_variant"], value_at(payload, "debian_release"), "Use the Debian variant declared in versions.yaml.")
    require_equal(payload, image_ref, "PostgreSQL major", entry["pg_major"], value_at(payload, "postgres_major"), "Use a PostgreSQL server that belongs to the metadata major line.")
    require_equal(payload, image_ref, "PostgreSQL server version", entry["pg_version"], value_at(payload, "postgres_server_version"), "Build from the CNPG base tag resolved in metadata.")

    required_controls = ["timescaledb", "vector", "pgaudit"]
    if entry.get("toolkit_version", ""):
        required_controls.append("timescaledb_toolkit")
    for control in required_controls:
        require_equal(payload, image_ref, f"control file {control}.control", "present", value_at(payload, f"control_{control}"), "Install or verify the required PostgreSQL extension control file in the image.")

    for binary in ["postgres", "initdb", "pg_ctl", "psql"]:
        require_equal(payload, image_ref, f"runtime binary {binary}", "ok", value_at(payload, f"binary_{binary}"), "Ensure CNPG PostgreSQL runtime binaries are present on PATH and executable.")
        expected_path = f"/usr/lib/postgresql/{entry['pg_major']}/bin/{binary}"
        require_equal(payload, image_ref, f"runtime binary path {binary}", expected_path, value_at(payload, f"binary_path_{binary}"), "Ensure CNPG PostgreSQL runtime binaries are present on the expected PostgreSQL path.")

    require_equal(payload, image_ref, "postgres user", "present", value_at(payload, "postgres_user"), "The CNPG operand image must contain the expected postgres user.")
    perms = value_at(payload, "data_dir_permissions")
    if perms not in {"700", "0700"}:
        exit_with_message(1, "smoke-test container", fixture or image_ref, image_ref, "data directory permissions", "0700-compatible permissions", repr(perms), "Use initdb-created PostgreSQL data directory permissions that allow startup.")
    require_equal(payload, image_ref, "temporary PostgreSQL startup", "ok", value_at(payload, "postgres_startup"), "Fix container runtime assumptions so PostgreSQL starts without legacy system-* Barman tooling.")

    required_labels = {
        "org.opencontainers.image.source": SOURCE_REPOSITORY,
        "org.pnet.postgresql.major": entry["pg_major"],
        "org.pnet.postgresql.version": entry["pg_version"],
        "org.pnet.debian.variant": entry["debian_variant"],
        "org.pnet.cnpg.tag": entry["cnpg_tag"],
        "org.pnet.cnpg.digest": entry["cnpg_digest"],
        "org.pnet.timescaledb.version": entry["timescaledb_version"],
        "org.pnet.timescaledb_toolkit.version": entry["toolkit_version"],
    }
    for name, expected in required_labels.items():
        require_label(labels, image_ref, name, expected)
    created = labels.get("org.opencontainers.image.created")
    if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", str(created or "")):
        exit_with_message(1, "smoke-test container", fixture or image_ref, image_ref, "label org.opencontainers.image.created", "UTC YYYY-MM-DD date", repr(created), "Build the image from the generated Dockerfile label contract.")


data = parse_metadata(metadata)
entry = find_entry(data)
image_ref = default_image_ref(entry)

if not entry.get("publish") and not fixture:
    exit_with_message(EXIT_UNSUPPORTED, "smoke-test container", metadata, image_ref, "publishable smoke target", f"publish:true row for PG={pg} DEBIAN={debian}", f"skipped: {entry.get('skip_reason', '')}", "Enable the release gate for this row and build the image before running container smoke checks.")

payload = load_fixture(fixture, image_ref) if fixture else collect_live(image_ref, entry)
run_checks(entry, payload)
print(f"PASS container smoke image={payload.get('image_ref') or image_ref} PG={pg} DEBIAN={debian}")
PY
