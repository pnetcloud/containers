from datetime import datetime
import os
import re


DEFAULT_TAG_DATE = "20260609"
DOCKER_TAG_RE = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}")


def validate_release_date(release_date):
    if not re.fullmatch(r"[0-9]{8}", release_date):
        raise ValueError(f"invalid release_date {release_date!r}; expected UTC YYYYMMDD")
    try:
        datetime.strptime(release_date, "%Y%m%d")
    except ValueError as exc:
        raise ValueError(f"invalid release_date {release_date!r}; expected valid UTC calendar date") from exc
    return release_date


def resolve_release_date(env=None):
    values = os.environ if env is None else env
    return validate_release_date(values.get("TAG_VALIDATION_DATE") or values.get("DATE") or DEFAULT_TAG_DATE)


def generated_tags(entry, release_date):
    release_date = validate_release_date(release_date)
    suffix = "" if entry["debian_variant"] == "trixie" else f"-{entry['debian_variant']}"
    immutable = f"{entry['pg_major']}-pg{entry['pg_version']}-ts{entry['timescaledb_version']}-{release_date}{suffix}"
    if entry["experimental"]:
        tags = [immutable]
    else:
        tags = [entry["pg_major"] if entry["debian_variant"] == "trixie" else f"{entry['pg_major']}-{entry['debian_variant']}", immutable]
        if entry["latest_eligible"]:
            tags.append("latest")
    for tag in tags:
        if not DOCKER_TAG_RE.fullmatch(tag):
            raise ValueError(f"invalid Docker tag {tag!r}; expected [A-Za-z0-9_][A-Za-z0-9_.-]{{0,127}}")
    return tags
