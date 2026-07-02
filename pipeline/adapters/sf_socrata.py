"""SF street sweeping adapter — Socrata SODA dataset yhqp-riqs (spec §4.2).

Endpoint DECIDED; field names VERIFIED 2026-07-01 against
https://data.sfgov.org/api/views/yhqp-riqs — columns: cnn, corridor, limits,
cnnrightleft, blockside, fullname, weekday, fromhour, tohour, week1..week5
(0/1 numbers), holidays (0/1 number), blocksweepid, line (GeoJSON LineString).
"""
from __future__ import annotations

import json
import os
import re

import requests

from schema import CurbSegment, DropCounter, ScheduleRule, ValidationError

RESOURCE_URL = "https://data.sfgov.org/resource/yhqp-riqs.json"
METADATA_URL = "https://data.sfgov.org/api/views/yhqp-riqs.json"
PAGE = 5000

# Sun/Mon/Tues/… → 0..6. Reject unknown values loudly (fail the build).
WEEKDAYS = {
    "sun": 0, "sunday": 0,
    "mon": 1, "monday": 1,
    "tue": 2, "tues": 2, "tuesday": 2,
    "wed": 3, "wednesday": 3,
    "thu": 4, "thur": 4, "thurs": 4, "thursday": 4,
    "fri": 5, "friday": 5,
    "sat": 6, "saturday": 6,
}


def _session() -> requests.Session:
    s = requests.Session()
    token = os.environ.get("SODA_APP_TOKEN")
    if token:
        s.headers["X-App-Token"] = token
    return s


def fetch_metadata(session: requests.Session | None = None) -> dict:
    r = (session or _session()).get(METADATA_URL, timeout=60)
    r.raise_for_status()
    return r.json()


def fetch_rows(session: requests.Session | None = None) -> list[dict]:
    s = session or _session()
    rows: list[dict] = []
    offset = 0
    while True:
        r = s.get(RESOURCE_URL, params={
            "$limit": PAGE, "$offset": offset, "$order": ":id"}, timeout=120)
        r.raise_for_status()
        page = r.json()
        if not page:
            break
        rows.extend(page)
        offset += PAGE
    return rows


def _truthy(v) -> bool:
    return str(v).strip() in ("1", "1.0", "true", "True", "Y")


def build_segments(rows: list[dict], drops: DropCounter) -> tuple[list[CurbSegment], str]:
    """Returns (segments, source_updated_at_placeholder). Groups rows by
    (cnn, side); one dataset row = one schedule window on one block side."""
    by_side: dict[tuple[str, str], dict] = {}

    for row in rows:
        cnn = str(row.get("cnn") or "").strip()
        if not cnn:
            drops.drop("sf: row without cnn")
            continue
        lr = str(row.get("cnnrightleft") or "").strip().upper()
        if lr not in ("L", "R"):
            drops.drop(f"sf: unknown cnnrightleft {lr!r}")
            continue
        side_key = "a" if lr == "L" else "b"

        wd_raw = str(row.get("weekday") or "").strip()
        wd_norm = wd_raw.lower().rstrip(".")
        if wd_norm in ("holiday",):
            # A handful of rows encode holiday-only routes; they are not a
            # weekly window and the engine has no day for them.
            drops.drop("sf: weekday=Holiday row")
            continue
        if wd_norm not in WEEKDAYS:
            raise ValidationError(f"sf: unknown weekday value {wd_raw!r} (cnn {cnn})")
        weekday = WEEKDAYS[wd_norm]

        try:
            from_hour = int(float(row["fromhour"]))
            to_hour = int(float(row["tohour"]))
        except (KeyError, TypeError, ValueError):
            drops.drop("sf: missing/invalid hours")
            continue
        if from_hour == to_hour:
            drops.drop("sf: zero-length window")
            continue

        flags = [_truthy(row.get(f"week{i}")) for i in range(1, 6)]
        if not any(flags):
            drops.drop("sf: no week flags set")
            continue
        weeks = None if all(flags) else [i + 1 for i, f in enumerate(flags) if f]

        holidays_col = row.get("holidays")
        holiday_enforced = _truthy(holidays_col) if holidays_col is not None else True

        geometry = None
        line = row.get("line")
        if isinstance(line, dict) and line.get("type") == "LineString":
            geometry = [[float(x), float(y)] for x, y in line.get("coordinates", [])]
        if not geometry:
            drops.drop("sf: missing line geometry")
            continue

        key = (cnn, side_key)
        entry = by_side.setdefault(key, {
            # Dataset zero-pads numbered streets ("09th Ave"); display wants "9th Ave".
            "street": re.sub(r"^0(\d)", r"\1",
                             str(row.get("corridor") or row.get("fullname") or "").strip()),
            "block_label": str(row.get("limits") or "").strip(),
            "blockside": str(row.get("blockside") or "").strip(),
            "geometry": geometry,
            "rules": [],
        })
        entry["rules"].append(ScheduleRule(
            weekday=weekday, weeks=weeks,
            from_hour=from_hour, to_hour=to_hour,
            holiday_enforced=holiday_enforced))

    segments = []
    for (cnn, side_key), e in sorted(by_side.items()):
        segments.append(CurbSegment(
            id=f"sf:{cnn}:{side_key}",
            city="sf",
            street=e["street"],
            block_label=e["block_label"],
            side_key=side_key,
            # SF source has no address ranges — never guess parity (spec §4.4.3).
            door_parity=None,
            door_range=None,
            geometry=e["geometry"],
            rules=e["rules"],
        ))
    return segments, ""


def load_fixture(path: str) -> list[dict]:
    with open(path) as f:
        return json.load(f)
