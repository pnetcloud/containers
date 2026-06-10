import json
import os
from pathlib import Path
import re
import subprocess


DEFAULT_TAG_DATE = "20260609"
TAGS_SCRIPT = Path(__file__).with_name("tags.sh")


def _run_tags(args):
    result = subprocess.run(
        [str(TAGS_SCRIPT), *args],
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "tag policy command failed").strip()
        raise ValueError(detail)
    return result.stdout


def validate_release_date(release_date):
    if not re.fullmatch(r"[0-9]{8}", release_date):
        raise ValueError(f"invalid release_date {release_date!r}; expected UTC YYYYMMDD")
    _run_tags(["--validate-date", release_date])
    return release_date


def resolve_release_date(env=None):
    values = os.environ if env is None else env
    return validate_release_date(values.get("TAG_VALIDATION_DATE") or values.get("DATE") or DEFAULT_TAG_DATE)


def generated_tags(entry, release_date):
    release_date = validate_release_date(release_date)
    output = _run_tags(["--generate-json", release_date, json.dumps(entry, sort_keys=True)])
    return json.loads(output)
