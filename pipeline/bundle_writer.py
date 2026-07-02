"""SQLite .sweepbundle writer + validation report (spec §4.5–4.6).

Deterministic: same inputs + same built_at → byte-identical bundle (golden test
§13.10). Inserts happen in sorted order, journaling is off, and the file is
created fresh every build.
"""
from __future__ import annotations

import os
import sqlite3
import struct

from schema import CurbSegment, DropCounter, ValidationError, normalize_rules, validate_segment

SCHEMA_VERSION = "1"


def _pack_geometry(geometry: list[list[float]]) -> bytes:
    # Bundle stores [[lat,lon]] binary doubles (schema exchange shape is [[lon,lat]]).
    flat: list[float] = []
    for lon, lat in geometry:
        flat.extend((lat, lon))
    return struct.pack(f"<{len(flat)}d", *flat)


def _bbox(geometry: list[list[float]]) -> tuple[float, float, float, float]:
    lats = [p[1] for p in geometry]
    lons = [p[0] for p in geometry]
    return min(lats), min(lons), max(lats), max(lons)


def write_bundle(path: str, city: str, segments: list[CurbSegment],
                 holidays: list[tuple[str, bool]], source_updated_at: str,
                 built_at: str, drops: DropCounter) -> dict:
    """Normalize, validate, write. Returns summary counts for the report."""
    kept: list[CurbSegment] = []
    for seg in segments:
        seg.rules = normalize_rules(seg.rules)
        if not seg.rules:
            drops.drop(f"{city}: segment with zero rules after normalization")
            continue
        validate_segment(seg)   # raises ValidationError → build fails loudly
        kept.append(seg)
    kept.sort(key=lambda s: s.id)

    ids = [s.id for s in kept]
    if len(ids) != len(set(ids)):
        dupes = sorted({i for i in ids if ids.count(i) > 1})[:5]
        raise ValidationError(f"{city}: duplicate segment ids, e.g. {dupes}")

    if os.path.exists(path):
        os.remove(path)
    con = sqlite3.connect(path)
    con.executescript("""
        PRAGMA journal_mode = OFF;
        PRAGMA synchronous = OFF;
        CREATE TABLE manifest(key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE segments(
            id TEXT PRIMARY KEY, city TEXT, street TEXT, block_label TEXT,
            side_key TEXT, door_parity TEXT, door_range TEXT,
            landmark TEXT, landmark_hint TEXT, landmark_confidence TEXT,
            min_lat REAL, min_lon REAL, max_lat REAL, max_lon REAL,
            geometry BLOB);
        CREATE TABLE rules(
            segment_id TEXT, weekday INTEGER, weeks TEXT,
            from_hour INTEGER, to_hour INTEGER, holiday_enforced INTEGER);
        CREATE TABLE holidays(date TEXT, city TEXT, suspends INTEGER);
        CREATE INDEX idx_segments_bbox ON segments(min_lat, max_lat, min_lon, max_lon);
    """)
    con.executemany("INSERT INTO manifest VALUES (?,?)", sorted({
        "schema_version": SCHEMA_VERSION,
        "city": city,
        "source_updated_at": source_updated_at,
        "built_at": built_at,
    }.items()))
    for s in kept:
        min_lat, min_lon, max_lat, max_lon = _bbox(s.geometry)
        con.execute("INSERT INTO segments VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                    (s.id, s.city, s.street, s.block_label, s.side_key,
                     s.door_parity, s.door_range, s.landmark, s.landmark_hint,
                     s.landmark_confidence, min_lat, min_lon, max_lat, max_lon,
                     _pack_geometry(s.geometry)))
        for r in s.rules:
            weeks = ",".join(str(w) for w in r.weeks) if r.weeks else None
            con.execute("INSERT INTO rules VALUES (?,?,?,?,?,?)",
                        (s.id, r.weekday, weeks, r.from_hour, r.to_hour,
                         1 if r.holiday_enforced else 0))
    for date, suspends in sorted(holidays):
        con.execute("INSERT INTO holidays VALUES (?,?,?)", (date, city, 1 if suspends else 0))
    con.commit()
    con.execute("VACUUM")
    con.close()
    return {"segments": len(kept), "rules": sum(len(s.rules) for s in kept),
            "holidays": len(holidays)}


def _read_rule_map(path: str) -> dict[str, tuple]:
    con = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    out: dict[str, list] = {}
    for sid, wd, wk, fh, th, he in con.execute(
            "SELECT segment_id, weekday, weeks, from_hour, to_hour, holiday_enforced "
            "FROM rules ORDER BY segment_id, weekday, from_hour"):
        out.setdefault(sid, []).append((wd, wk, fh, th, he))
    con.close()
    return {k: tuple(v) for k, v in out.items()}


def write_report(report_path: str, city: str, rows_in: int, summary: dict,
                 drops: DropCounter, new_bundle: str, prev_bundle: str | None,
                 notes: list[str]) -> None:
    lines = [f"Sweep pipeline report — {city}", "=" * 40,
             f"source rows/features in : {rows_in}",
             f"segments out            : {summary['segments']}",
             f"rules out               : {summary['rules']}",
             f"holiday rows            : {summary['holidays']}", "",
             "Dropped:"]
    for reason, n in sorted(drops.reasons.items()):
        lines.append(f"  {n:6}  {reason}")
    if not drops.reasons:
        lines.append("  (none)")
    lines.append("")
    for n in notes:
        lines.append(f"note: {n}")

    # Diff vs previous bundle — the staleness changelog (spec §4.5).
    lines.append("")
    lines.append("Diff vs previous bundle:")
    if prev_bundle and os.path.exists(prev_bundle):
        old, new = _read_rule_map(prev_bundle), _read_rule_map(new_bundle)
        added = sorted(set(new) - set(old))
        removed = sorted(set(old) - set(new))
        changed = sorted(k for k in set(old) & set(new) if old[k] != new[k])
        lines.append(f"  segments added   : {len(added)}")
        lines.append(f"  segments removed : {len(removed)}")
        lines.append(f"  rules changed    : {len(changed)}")
        for label, items in (("+", added), ("-", removed), ("~", changed)):
            for sid in items[:20]:
                lines.append(f"    {label} {sid}")
            if len(items) > 20:
                lines.append(f"    … {len(items) - 20} more")
    else:
        lines.append("  (no previous bundle)")
    with open(report_path, "w") as f:
        f.write("\n".join(lines) + "\n")
