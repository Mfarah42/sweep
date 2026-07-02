"""Side naming ("landmark") pass — spec §4.4.

1. Editorial overrides from landmarks/{city}.yaml win (confidence "editorial").
2. Geometric fallback: side's facing bearing → city vernacular (confidence "auto").
   UI shows door parity more prominently for auto names; never compass words.
"""
from __future__ import annotations

import math

import yaml

from schema import CurbSegment

LAKE_MERRITT = (37.8055, -122.2565)   # centroid, for Oakland "Lake side"
LAKE_RADIUS_M = 800.0


def load_editorial(path: str) -> dict[str, dict]:
    try:
        with open(path) as f:
            data = yaml.safe_load(f) or {}
    except FileNotFoundError:
        return {}
    return {str(k): v for k, v in (data.get("sides") or {}).items()}


def _bearing_deg(geometry: list[list[float]]) -> float:
    """Bearing of the street line, first → last point. geometry is [[lon,lat]]."""
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
    # Equirectangular — fine at city scale.
    kx = 111320.0 * math.cos(math.radians((a[0] + b[0]) / 2))
    return math.hypot((a[1] - b[1]) * kx, (a[0] - b[0]) * 111320.0)


def _facing(seg: CurbSegment) -> float:
    """Compass bearing the curb side faces: side 'a' looks left of the line
    direction, side 'b' right. Heuristic for auto names only."""
    street = _bearing_deg(seg.geometry)
    return (street - 90.0) % 360.0 if seg.side_key == "a" else (street + 90.0) % 360.0


def _cardinal(bearing: float) -> str:
    if bearing >= 315 or bearing < 45:
        return "north"
    if bearing < 135:
        return "east"
    if bearing < 225:
        return "south"
    return "west"


def _auto_name(seg: CurbSegment) -> str:
    card = _cardinal(_facing(seg))
    if seg.city == "sf":
        return {"west": "Ocean side", "east": "Downtown side",
                "north": "Bay side", "south": "Daly City side"}[card]
    # Oakland
    if card == "west":
        return "Bay side"
    if card == "east":
        return "Hills side"
    if _dist_m(_centroid(seg.geometry), LAKE_MERRITT) <= LAKE_RADIUS_M:
        return "Lake side"
    return "Berkeley side" if card == "north" else "Airport side"


def apply(segments: list[CurbSegment], editorial_path: str) -> tuple[int, int]:
    editorial = load_editorial(editorial_path)
    n_editorial = n_auto = 0
    for seg in segments:
        entry = editorial.get(seg.id)
        if entry:
            seg.landmark = entry.get("landmark")
            seg.landmark_hint = entry.get("hint")
            seg.landmark_confidence = "editorial"
            n_editorial += 1
        else:
            seg.landmark = _auto_name(seg)
            seg.landmark_hint = None
            seg.landmark_confidence = "auto"
            n_auto += 1
    return n_editorial, n_auto
