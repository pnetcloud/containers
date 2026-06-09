#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
metadata="${SMOKE_METADATA:-${SCRIPT_DIR}/../versions.yaml}"
fixture="${SMOKE_CONTAINER_FIXTURE:-}"
sql_fixture="${SMOKE_SQL_FIXTURE:-}"
extension_policy="${SMOKE_EXTENSION_POLICY:-}"
docker_bin="${DOCKER_BIN:-docker}"
pg="${1:-}"
debian="${2:-}"

source "${SCRIPT_DIR}/lib/command.sh"
require_pg_debian "smoke-test container" "${pg}" "${debian}"

python3 - "${ROOT_DIR}" "${metadata}" "${fixture}" "${sql_fixture}" "${extension_policy}" "${docker_bin}" "${pg}" "${debian}" <<'PY'
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys

ROOT = Path(sys.argv[1])
metadata = Path(sys.argv[2])
fixture = sys.argv[3]
sql_fixture = sys.argv[4]
extension_policy = sys.argv[5]
docker_bin = sys.argv[6]
pg = sys.argv[7]
debian = sys.argv[8]
checks = os.environ.get("CHECKS", "container") or "container"
expected_platform = os.environ.get("SMOKE_EXPECTED_PLATFORM", "")
SOURCE_REPOSITORY = "https://github.com/pnetcloud/containers"
EXIT_UNSUPPORTED = 65
EXIT_UNAVAILABLE = 69
ARCH_TO_PLATFORM = {"amd64": "linux/amd64", "arm64": "linux/arm64"}


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
printf 'runtime_architecture=%s\n' "$(dpkg --print-architecture)"
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
    run_args = [docker_bin, "run", "--rm"]
    if expected_platform:
        run_args.extend(["--platform", expected_platform])
    run_args.extend(["--entrypoint", "/bin/sh", image_ref, "-eu", "-c", shell])
    run = subprocess.run(run_args, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
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
    if expected_platform:
        runtime_arch = value_at(payload, "runtime_architecture")
        actual_platform = ARCH_TO_PLATFORM.get(runtime_arch, f"unsupported/{runtime_arch}")
        if actual_platform != expected_platform:
            exit_with_message(1, "smoke-test container", fixture or image_ref, image_ref, "runtime architecture", expected_platform, f"dpkg={runtime_arch}; platform={actual_platform}", "Run the candidate smoke check with the platform that matches the built release candidate.")

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


def parse_sql_transcript(path):
    values = {}
    try:
        lines = Path(path).read_text().splitlines()
    except FileNotFoundError:
        exit_with_message(1, "smoke-test sql", path, "", "SQL fixture", "fixture exists", "missing", "Create the SQL smoke fixture.")
    for raw in lines:
        line = raw.strip()
        if not line.startswith("-- smoke:"):
            continue
        item = line[len("-- smoke:"):].strip()
        if "=" not in item:
            exit_with_message(1, "smoke-test sql", path, "", "SQL fixture", "-- smoke: key=value", line, "Use deterministic key/value smoke transcript lines.")
        key, value = item.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def sql_value(transcript, key):
    return transcript.get(key)


def require_sql(image_ref, artifact, transcript, check, expected, actual, remediation):
    if actual != expected:
        exit_with_message(1, "smoke-test sql", artifact, image_ref, check, repr(expected), repr(actual), remediation)


def require_sql_present(image_ref, artifact, transcript, check, actual, remediation):
    if actual in {None, "", "missing", "failed"}:
        exit_with_message(1, "smoke-test sql", artifact, image_ref, check, "present/non-empty result", repr(actual), remediation)


def extension_policies_for_entry(entry):
    by_extension = {}
    for key, value in entry.items():
        parts = key.split(".")
        if len(parts) != 3 or parts[0] != "extensions":
            continue
        by_extension.setdefault(parts[1], {"extension": parts[1]})[parts[2]] = value
    false_policies = {}
    for extension, policy in by_extension.items():
        if policy.get("creatable") is not False:
            continue
        required_false = {"non_creatable_reason", "validation_mode", "validation_target"}
        missing_false = [key for key in required_false if not str(policy.get(key, "")).strip()]
        if missing_false:
            exit_with_message(1, "smoke-test sql", metadata, "", f"extension {extension} creatable: false", f"non-empty {sorted(required_false)}", f"missing {missing_false}; actual metadata {policy}", "Document non-creatable extensions with reason, validation mode, and validation target.")
        if policy.get("validation_mode") not in {"control-file", "library", "preinstalled-extension"}:
            exit_with_message(1, "smoke-test sql", metadata, "", f"extension {extension} validation_mode", "control-file|library|preinstalled-extension", repr(policy.get("validation_mode")), "Use a supported validation-only mode for non-creatable extensions.")
        false_policies[extension] = policy
    return false_policies


def expected_extensions(entry):
    extensions = [
        {"name": "timescaledb", "expected_version": entry.get("timescaledb_version", ""), "library": True},
        {"name": "vector", "expected_version": entry.get("pgvector_package_version", ""), "library": False},
        {"name": "pgaudit", "expected_version": entry.get("pgaudit_package_version", ""), "library": False},
    ]
    if entry.get("toolkit_version", ""):
        extensions.insert(1, {"name": "timescaledb_toolkit", "expected_version": entry.get("toolkit_version", ""), "library": False})
    return extensions


def collect_live_sql(image_ref, entry):
    pg_major = entry["pg_major"]
    bin_dir = f"/usr/lib/postgresql/{pg_major}/bin"
    control_dir = f"/usr/share/postgresql/{pg_major}/extension"
    policies = extension_policies_for_entry(entry)
    non_creatable_names = " ".join(sorted(policies))
    validation_script = []
    for extension, policy in sorted(policies.items()):
        mode = policy["validation_mode"]
        target = policy["validation_target"]
        validation_script.append(f"printf 'validation.{extension}.target=%s\\n' {shlex.quote(target)}")
        if mode == "control-file":
            validation_script.append(f"if [ -f \"${{control_dir}}/{shlex.quote(target)}\" ]; then printf 'validation.{extension}.result=present\\n'; else printf 'validation.{extension}.result=missing\\n'; fi")
        elif mode == "library":
            validation_script.append(f"if [ -e {shlex.quote(target)} ] || ls {shlex.quote(target)} >/dev/null 2>&1; then printf 'validation.{extension}.result=present\\n'; else printf 'validation.{extension}.result=missing\\n'; fi")
        elif mode == "preinstalled-extension":
            validation_script.append(f"value=\"$($psql \"SELECT COALESCE((SELECT extversion FROM pg_extension WHERE extname='{extension}'), '')\")\"; printf 'extversion.{extension}=%s\\n' \"${{value}}\"; if [ -n \"${{value}}\" ]; then printf 'validation.{extension}.result=present\\n'; else printf 'validation.{extension}.result=missing\\n'; fi")
    validation_block = "\n".join(validation_script) or ":"
    shell = f"""
set -eu
printf 'runtime_architecture=%s\n' "$(dpkg --print-architecture)"
bin_dir="{bin_dir}"
control_dir="{control_dir}"
non_creatable="{non_creatable_names}"
data_dir="$(mktemp -d /tmp/cnpg-sql-smoke.XXXXXX)"
"${{bin_dir}}/initdb" -D "${{data_dir}}" >/tmp/cnpg-sql-initdb.log 2>&1
cat >>"${{data_dir}}/postgresql.conf" <<'CONF'
shared_preload_libraries = 'timescaledb,pgaudit'
CONF
"${{bin_dir}}/pg_ctl" -D "${{data_dir}}" -o "-c listen_addresses= -c unix_socket_directories=/tmp" -w start >/tmp/cnpg-sql-start.log 2>&1
psql="${{bin_dir}}/psql -h /tmp -d postgres -Atqc"
if $psql "SELECT version()" >/tmp/cnpg-sql-version.out 2>&1; then printf 'select.version=ok\n'; else printf 'select.version=failed\n'; fi
printf 'show.server_version=%s\n' "$($psql "SHOW server_version")"
printf 'show.shared_preload_libraries=%s\n' "$($psql "SHOW shared_preload_libraries")"
if ls "$(${{bin_dir}}/pg_config --pkglibdir 2>/dev/null || printf /usr/lib/postgresql/{pg_major}/lib)"/timescaledb*.so >/dev/null 2>&1; then printf 'library.timescaledb=present\n'; else printf 'library.timescaledb=missing\n'; fi
for ext in timescaledb timescaledb_toolkit vector pgaudit; do
  case " ${{non_creatable}} " in
    *" ${{ext}} "*) continue ;;
  esac
  if $psql "CREATE EXTENSION IF NOT EXISTS ${{ext}}" >/tmp/cnpg-sql-create-${{ext}}.log 2>&1; then
    printf 'create.%s=ok\n' "${{ext}}"
  else
    printf 'create.%s=missing\n' "${{ext}}"
  fi
  printf 'extversion.%s=%s\n' "${{ext}}" "$($psql "SELECT COALESCE((SELECT extversion FROM pg_extension WHERE extname='${{ext}}'), '')")"
done
for ext in vector pgaudit; do
  if [ -f "${{control_dir}}/${{ext}}.control" ]; then printf 'control.%s=%s.control:present\n' "${{ext}}" "${{ext}}"; else printf 'control.%s=%s.control:missing\n' "${{ext}}" "${{ext}}"; fi
done
{validation_block}
"${{bin_dir}}/pg_ctl" -D "${{data_dir}}" -m fast -w stop >/tmp/cnpg-sql-stop.log 2>&1 || true
rm -rf "${{data_dir}}"
"""
    run_args = [docker_bin, "run", "--rm"]
    if expected_platform:
        run_args.extend(["--platform", expected_platform])
    run_args.extend(["--entrypoint", "/bin/sh", image_ref, "-eu", "-c", shell])
    run = subprocess.run(run_args, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if run.returncode != 0:
        exit_with_message(EXIT_UNAVAILABLE, "smoke-test sql", image_ref, image_ref, "SQL live collector", "docker run SQL smoke collector succeeds", run.stderr.strip()[:600], "Inspect the local image SQL runtime and required preload settings.")
    values = {}
    for line in run.stdout.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
    return values


def run_sql_checks(entry, transcript):
    image_ref = os.environ.get("SMOKE_IMAGE_REF", default_image_ref(entry))
    artifact = sql_fixture or image_ref
    canonical_preload = "timescaledb,pgaudit"
    require_sql(image_ref, artifact, transcript, "SELECT version()", "ok", sql_value(transcript, "select.version"), "Ensure the test PostgreSQL instance accepts basic SQL queries.")
    require_sql(image_ref, artifact, transcript, "SHOW server_version", entry["pg_version"], sql_value(transcript, "show.server_version"), "Start the PostgreSQL server version declared in metadata.")
    require_sql(image_ref, artifact, transcript, "shared_preload_libraries", canonical_preload, sql_value(transcript, "show.shared_preload_libraries"), f"Start SQL smoke with shared_preload_libraries={canonical_preload}.")
    if expected_platform:
        runtime_arch = sql_value(transcript, "runtime_architecture")
        actual_platform = ARCH_TO_PLATFORM.get(runtime_arch, f"unsupported/{runtime_arch}")
        if actual_platform != expected_platform:
            exit_with_message(1, "smoke-test sql", artifact, image_ref, "runtime architecture", expected_platform, f"dpkg={runtime_arch}; platform={actual_platform}", "Run the candidate SQL smoke check with the platform that matches the built release candidate.")

    if extension_policy:
        exit_with_message(1, "smoke-test sql", "SMOKE_EXTENSION_POLICY", image_ref, "non-creatable extension policy source", "selected metadata entry extensions.<ext>.* fields", extension_policy, "Do not bypass metadata-owned non-creatable policy with an environment-only policy file.")
    non_creatable = extension_policies_for_entry(entry)
    for extension in expected_extensions(entry):
        name = extension["name"]
        if name in non_creatable:
            mode = non_creatable[name]["validation_mode"]
            target = non_creatable[name]["validation_target"]
            require_sql(image_ref, metadata, transcript, f"extension {name} creatable: false validation target", target, sql_value(transcript, f"validation.{name}.target"), "Run the documented validation-only probe target for the non-creatable extension.")
            if mode in {"control-file", "library"}:
                require_sql(image_ref, metadata, transcript, f"extension {name} {mode} validation", "present", sql_value(transcript, f"validation.{name}.result"), "The validation-only target must prove the documented control file or library is available.")
            elif mode == "preinstalled-extension":
                require_sql_present(image_ref, metadata, transcript, f"extension {name} preinstalled extversion", sql_value(transcript, f"extversion.{name}"), "Preinstalled-extension validation must query pg_extension.extversion.")
            continue

        require_sql(image_ref, artifact, transcript, f"CREATE EXTENSION {name}", "ok", sql_value(transcript, f"create.{name}"), "Create expected PostgreSQL extensions unless metadata explicitly marks them non-creatable.")
        expected_version = extension["expected_version"]
        if expected_version:
            require_sql(image_ref, artifact, transcript, f"pg_extension.extversion {name}", expected_version, sql_value(transcript, f"extversion.{name}"), "Extension version must match metadata before publish eligibility.")
        else:
            require_sql_present(image_ref, artifact, transcript, f"pg_extension.extversion {name}", sql_value(transcript, f"extversion.{name}"), "Extensions without exact package metadata still need a visible pg_extension.extversion or explicit validation policy.")
            if name in {"vector", "pgaudit"}:
                control_name = "vector.control" if name == "vector" else "pgaudit.control"
                require_sql(image_ref, artifact, transcript, f"control-file expectation {name}", f"{control_name}:present", sql_value(transcript, f"control.{name}"), "Extensions without exact package metadata must also match the documented control-file expectation.")
        if extension["library"]:
            require_sql(image_ref, artifact, transcript, "TimescaleDB shared library", "present", sql_value(transcript, "library.timescaledb"), "Validate TimescaleDB library availability before publish eligibility.")

    print(f"PASS SQL smoke image={image_ref} PG={pg} DEBIAN={debian}")


data = parse_metadata(metadata)
entry = find_entry(data)
image_ref = default_image_ref(entry)

if checks == "container":
    if not entry.get("publish") and not fixture:
        exit_with_message(EXIT_UNSUPPORTED, "smoke-test container", metadata, image_ref, "publishable smoke target", f"publish:true row for PG={pg} DEBIAN={debian}", f"skipped: {entry.get('skip_reason', '')}", "Enable the release gate for this row and build the image before running container smoke checks.")
    payload = load_fixture(fixture, image_ref) if fixture else collect_live(image_ref, entry)
    run_checks(entry, payload)
    print(f"PASS container smoke image={payload.get('image_ref') or image_ref} PG={pg} DEBIAN={debian}")
elif checks == "sql":
    if not entry.get("publish") and not sql_fixture:
        exit_with_message(EXIT_UNSUPPORTED, "smoke-test sql", metadata, image_ref, "publishable SQL smoke target", f"publish:true row for PG={pg} DEBIAN={debian}", f"skipped: {entry.get('skip_reason', '')}", "Enable the release gate for this row and build the image before running SQL smoke checks.")
    transcript = parse_sql_transcript(sql_fixture) if sql_fixture else collect_live_sql(image_ref, entry)
    run_sql_checks(entry, transcript)
else:
    exit_with_message(64, "smoke-test", "CHECKS", image_ref, "CHECKS", "container or sql", checks, "Use CHECKS=container or CHECKS=sql.")
PY
