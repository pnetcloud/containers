import re


def generated_tags(entry, release_date):
    if not re.fullmatch(r"[0-9]{8}", release_date):
        raise ValueError(f"invalid release_date {release_date!r}; expected YYYYMMDD")
    suffix = "" if entry["debian_variant"] == "trixie" else f"-{entry['debian_variant']}"
    immutable = f"{entry['pg_major']}-pg{entry['pg_version']}-ts{entry['timescaledb_version']}-{release_date}{suffix}"
    if entry["experimental"]:
        return [immutable]
    tags = [entry["pg_major"] if entry["debian_variant"] == "trixie" else f"{entry['pg_major']}-{entry['debian_variant']}", immutable]
    if entry["latest_eligible"]:
        tags.append("latest")
    return tags
