"""Side naming ("landmark") pass — spec §4.4, extended with arterial naming.

Priority per side:
1. Editorial overrides from landmarks/{city}.yaml (confidence "editorial").
2. Nearby big street the side faces — "MacArthur side · toward MacArthur
   Blvd" (confidence "auto"). A major street beats an abstract landmark
   because it's what people actually say ("we're on the MacArthur side").
3. Geographic fallback: facing bearing → city vernacular (hills / bay /
   ocean / lake, confidence "auto").

Never compass words in UI copy. The two sides of a block are always given
distinct names — if both resolve to the same arterial, the nearer side keeps
it and the other falls back to geography.
"""
from __future__ import annotations

import math
from collections import defaultdict

import yaml

from schema import CurbSegment

LAKE_MERRITT = (37.8055, -122.2565)   # centroid, for Oakland "Lake side"
LAKE_RADIUS_M = 800.0

ARTERIAL_MAX_DIST_M = 300.0    # "near a big street" = a couple of blocks
ARTERIAL_MAX_ANGLE = 60.0      # side must roughly face it
# An arterial only distinguishes the two curbs when it runs ALONGSIDE the
# block — parallel, one street over — so "toward San Pablo Ave" names exactly
# one curb. When your street runs INTO the arterial (Maybelle → MacArthur),
# "toward MacArthur" reads as travel direction and confuses both sides, even
# if some bend of the arterial happens to sit laterally.
ARTERIAL_MIN_AXIS_ANGLE = 45.0   # sample must sit to the side, not ahead/behind
ARTERIAL_PARALLEL_TOL = 30.0     # arterial's own direction ≈ block's axis
SAMPLE_STEP_M = 20.0           # arterial polyline sampling for the grid index
GRID_CELL_M = 150.0

STREET_TYPES = {"St", "Ave", "Blvd", "Way", "Dr", "Rd", "Pl", "Ct", "Ln", "Ter", "Pkwy"}


def load_config(path: str) -> dict:
    try:
        with open(path) as f:
            data = yaml.safe_load(f) or {}
    except FileNotFoundError:
        return {}
    return data


# ---------------------------------------------------------------------------
# Geometry helpers (equirectangular meters — fine at city scale)

def _bearing_deg(geometry: list[list[float]]) -> float:
    (lon1, lat1), (lon2, lat2) = geometry[0], geometry[-1]
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dlon = math.radians(lon2 - lon1)
    x = math.sin(dlon) * math.cos(phi2)
    y = math.cos(phi1) * math.sin(phi2) - math.sin(phi1) * math.cos(phi2) * math.cos(dlon)
    return (math.degrees(math.atan2(x, y)) + 360.0) % 360.0


def _centroid(geometry: list[list[float]]) -> tuple[float, float]:
    lat = sum(p[1] for p in geometry) / len(geometry)
    lon = sum(p[0] for p in geometry) / len(geometry)
    return lat, lon


def _dist_m(a: tuple[float, float], b: tuple[float, float]) -> float:
    kx = 111_320.0 * math.cos(math.radians((a[0] + b[0]) / 2))
    return math.hypot((a[1] - b[1]) * kx, (a[0] - b[0]) * 111_320.0)


def _facing(seg: CurbSegment) -> float:
    """Compass bearing the curb side faces: side 'a' looks left of the line
    direction, side 'b' right. Heuristic for auto names only."""
    street = _bearing_deg(seg.geometry)
    return (street - 90.0) % 360.0 if seg.side_key == "a" else (street + 90.0) % 360.0


def _bearing_between(a: tuple[float, float], b: tuple[float, float]) -> float:
    """Bearing from point a to point b (lat, lon)."""
    phi1, phi2 = math.radians(a[0]), math.radians(b[0])
    dlon = math.radians(b[1] - a[1])
    x = math.sin(dlon) * math.cos(phi2)
    y = math.cos(phi1) * math.sin(phi2) - math.sin(phi1) * math.cos(phi2) * math.cos(dlon)
    return (math.degrees(math.atan2(x, y)) + 360.0) % 360.0


def _angle_diff(a: float, b: float) -> float:
    d = abs(a - b) % 360.0
    return min(d, 360.0 - d)


def _cardinal(bearing: float) -> str:
    if bearing >= 315 or bearing < 45:
        return "north"
    if bearing < 135:
        return "east"
    if bearing < 225:
        return "south"
    return "west"


# ---------------------------------------------------------------------------
# Arterial index: grid of sampled points from major-street polylines

class ArterialIndex:
    def __init__(self) -> None:
        self.grid: dict[tuple[int, int], list[tuple[float, float, str]]] = defaultdict(list)

    def _cell(self, lat: float, lon: float) -> tuple[int, int]:
        kx = 111_320.0 * math.cos(math.radians(lat))
        return (int(lat * 111_320.0 / GRID_CELL_M), int(lon * kx / GRID_CELL_M))

    def add_line(self, street: str, geometry: list[list[float]]) -> None:
        for i in range(len(geometry) - 1):
            (lon1, lat1), (lon2, lat2) = geometry[i], geometry[i + 1]
            seg_len = _dist_m((lat1, lon1), (lat2, lon2))
            steps = max(1, int(seg_len / SAMPLE_STEP_M))
            line_dir = _bearing_deg([[lon1, lat1], [lon2, lat2]])
            for s in range(steps + 1):
                t = s / steps
                lat, lon = lat1 + (lat2 - lat1) * t, lon1 + (lon2 - lon1) * t
                self.grid[self._cell(lat, lon)].append((lat, lon, street, line_dir))

    def nearest_facing(self, origin: tuple[float, float], facing: float,
                       street_axis: float, exclude_street: str) -> tuple[str, float] | None:
        """Nearest arterial that genuinely distinguishes this side: within
        ARTERIAL_MAX_DIST_M, roughly in the facing direction, NOT the
        segment's own street, and lateral to the block — at least
        ARTERIAL_MIN_AXIS_ANGLE off the street's own axis, so end-of-street
        arterials never name a curb. Returns (street, distance_m)."""
        best: tuple[str, float] | None = None
        c0 = self._cell(*origin)
        reach = int(ARTERIAL_MAX_DIST_M / GRID_CELL_M) + 1
        exclude = exclude_street.lower()
        for di in range(-reach, reach + 1):
            for dj in range(-reach, reach + 1):
                for lat, lon, street, line_dir in self.grid.get((c0[0] + di, c0[1] + dj), []):
                    if street.lower() == exclude:
                        continue
                    d = _dist_m(origin, (lat, lon))
                    if d > ARTERIAL_MAX_DIST_M or (best and d >= best[1]):
                        continue
                    # The arterial must run alongside the block, not across
                    # or at the end of it.
                    parallel_off = min(_angle_diff(line_dir, street_axis),
                                       _angle_diff(line_dir, (street_axis + 180.0) % 360.0))
                    if parallel_off > ARTERIAL_PARALLEL_TOL:
                        continue
                    bearing = _bearing_between(origin, (lat, lon))
                    if _angle_diff(bearing, facing) > ARTERIAL_MAX_ANGLE:
                        continue
                    axis_off = min(_angle_diff(bearing, street_axis),
                                   _angle_diff(bearing, (street_axis + 180.0) % 360.0))
                    if axis_off < ARTERIAL_MIN_AXIS_ANGLE:
                        continue   # ahead/behind, not to a side
                    best = (street, d)
        return best


def _short_street_name(street: str) -> str:
    """'MacArthur Blvd' → 'MacArthur'; numbered streets keep their type
    ('53rd Ave side', because '53rd side' is ambiguous with the St twin)."""
    parts = street.split()
    if len(parts) >= 2 and parts[-1] in STREET_TYPES and not parts[0][0].isdigit():
        return " ".join(parts[:-1])
    return street


def _geo_name(seg: CurbSegment, avoid: str | None = None) -> str:
    name = _geo_name_for_facing(seg, _facing(seg), avoid)
    if name != avoid:
        return name
    # Parity-keyed sides on opposite-digitized features can compute the same
    # facing for both sides; flip 180° so the block's two names stay distinct
    # (door parity is the authoritative cue on auto-named sides, §4.4.2).
    return _geo_name_for_facing(seg, (_facing(seg) + 180.0) % 360.0, avoid)


def _geo_name_for_facing(seg: CurbSegment, facing: float, avoid: str | None) -> str:
    card = _cardinal(facing)
    if seg.city == "sf":
        return {"west": "Ocean side", "east": "Downtown side",
                "north": "Bay side", "south": "Daly City side"}[card]
    if card == "west":
        return "Bay side"
    if card == "east":
        return "Hills side"
    # Near Lake Merritt both sides of a N-S block can face the lake; `avoid`
    # keeps the block's two side names distinct.
    if _dist_m(_centroid(seg.geometry), LAKE_MERRITT) <= LAKE_RADIUS_M \
            and avoid != "Lake side":
        return "Lake side"
    return "Berkeley side" if card == "north" else "Airport side"


# ---------------------------------------------------------------------------

def apply(segments: list[CurbSegment], editorial_path: str,
          extra_major_lines: list[tuple[str, list[list[float]]]] | None = None
          ) -> tuple[int, int, int]:
    """Returns (n_editorial, n_arterial, n_geo)."""
    config = load_config(editorial_path)
    editorial = {str(k): v for k, v in (config.get("sides") or {}).items()}
    major_names = {str(n).lower() for n in (config.get("majors") or [])}

    index = ArterialIndex()
    seen_major_streets: set[str] = set()
    for seg in segments:
        if seg.road_class == "major" or seg.street.lower() in major_names:
            index.add_line(seg.street, seg.geometry)
            seen_major_streets.add(seg.street.lower())
    for street, line in extra_major_lines or []:
        index.add_line(street, line)
        seen_major_streets.add(street.lower())

    # Pass 1: per-segment assignment. arterial distance recorded for the
    # harmonization/dedupe passes below.
    arterial_dist: dict[str, float] = {}
    for seg in segments:
        entry = editorial.get(seg.id)
        if entry:
            seg.landmark = entry.get("landmark")
            seg.landmark_hint = entry.get("hint")
            seg.landmark_confidence = "editorial"
            continue
        hit = index.nearest_facing(_centroid(seg.geometry), _facing(seg),
                                   _bearing_deg(seg.geometry), seg.street)
        if hit:
            street, dist = hit
            seg.landmark = f"{_short_street_name(street)} side"
            seg.landmark_hint = f"toward {street}"
            seg.landmark_confidence = "auto"
            arterial_dist[seg.id] = dist
        else:
            seg.landmark = _geo_name(seg)
            seg.landmark_hint = None
            seg.landmark_confidence = "auto"

    by_side: dict[tuple[str, str, str, str], list[CurbSegment]] = defaultdict(list)
    for seg in segments:
        by_side[(seg.city, seg.street, seg.block_label, seg.side_key)].append(seg)

    # Pass 2: a side must carry ONE name across all its source features —
    # the nearest arterial name wins; otherwise the first geo name.
    for side_segs in by_side.values():
        auto = [s for s in side_segs if s.landmark_confidence == "auto"]
        if len(auto) < 2:
            continue
        arterial = [s for s in auto if s.id in arterial_dist]
        canonical = min(arterial, key=lambda s: arterial_dist[s.id]) if arterial else auto[0]
        for seg in auto:
            seg.landmark = canonical.landmark
            seg.landmark_hint = canonical.landmark_hint

    # Pass 3: a block's two sides must never share a name — when both resolve
    # to the same arterial (curved blocks), the nearer side keeps it.
    by_block: dict[tuple[str, str, str], list[tuple[str, list[CurbSegment]]]] = defaultdict(list)
    for (city, street, label, side_key), side_segs in sorted(by_side.items()):
        by_block[(city, street, label)].append((side_key, side_segs))
    for side_groups in by_block.values():
        if len(side_groups) < 2:
            continue
        (_, a_segs), (_, b_segs) = side_groups[0], side_groups[1]
        if a_segs[0].landmark != b_segs[0].landmark:
            continue
        name = a_segs[0].landmark

        def min_dist(segs: list[CurbSegment]) -> float:
            return min((arterial_dist.get(s.id, math.inf) for s in segs), default=math.inf)

        loser = a_segs if min_dist(a_segs) >= min_dist(b_segs) else b_segs
        # One name for the whole side — reassigning per segment would split
        # the side again when its features disagree on facing.
        replacement = _geo_name(loser[0], avoid=name)
        for seg in loser:
            if seg.landmark_confidence == "auto":
                seg.landmark = replacement
                seg.landmark_hint = None

    n_editorial = sum(1 for s in segments if s.landmark_confidence == "editorial")
    n_arterial = sum(1 for s in segments if s.landmark_confidence == "auto"
                     and (s.landmark_hint or "").startswith("toward "))
    n_geo = sum(1 for s in segments if s.landmark_confidence == "auto"
                and not (s.landmark_hint or "").startswith("toward "))
    return n_editorial, n_arterial, n_geo
