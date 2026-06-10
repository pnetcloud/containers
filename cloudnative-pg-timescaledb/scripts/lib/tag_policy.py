import os
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True


DEFAULT_TAG_DATE = "20260609"
TAGS_SCRIPT = Path(__file__).with_name("tags.sh")


def _run_tags(args):
    proc = subprocess.run(
        ["bash", str(TAGS_SCRIPT), *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if proc.returncode != 0:
        raise ValueError((proc.stderr or proc.stdout).strip())
    return proc.stdout


def _bool_arg(entry, field):
    value = entry[field]
    if value is True:
        return "true"
    if value is False:
        return "false"
    raise ValueError(f"{field} must be boolean")


def validate_release_date(release_date):
    _run_tags(["--validate-date", release_date])
    return release_date


def resolve_release_date(env=None):
    values = os.environ if env is None else env
    return validate_release_date(values.get("TAG_VALIDATION_DATE") or values.get("DATE") or DEFAULT_TAG_DATE)


def generated_tags(entry, release_date):
    output = _run_tags(
        [
            "--generate-fields",
            release_date,
            entry["pg_major"],
            entry["pg_version"],
            entry["debian_variant"],
            entry["timescaledb_version"],
            _bool_arg(entry, "experimental"),
            _bool_arg(entry, "latest_eligible"),
        ]
    )
    return output.splitlines()
