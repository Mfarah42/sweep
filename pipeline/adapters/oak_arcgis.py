"""Oakland street sweeping adapter — ArcGIS feature layer (spec §4.3).

Discovery chain VERIFIED 2026-07-01:
  webapp 075bf89b418c4fbd9a4c5a8e93200711 (Web AppBuilder config)
    → map.itemId aee92986e86a4d28aa7c238ca6b5d0ff (web map)
    → operational layer "StreetSweeping"
    → https://services.arcgis.com/9tC74aDHuml0x5Yz/arcgis/rest/services/StreetSweeping/FeatureServer/0

Schedule encoding: one line feature per street segment with DAY_ODD/TIME_ODD and
DAY_EVEN/TIME_EVEN coded values. The layer publishes the full coded-value
domains (51 day codes, 7 time codes); we decode from a table confirmed against
those domains at run time — any unmapped code fails the build loudly.

Human field-mapping checkpoint (--inspect) confirmed 2026-07-01.
"""
from __future__ import annotations

import json

import requests

from schema import CurbSegment, DropCounter, ScheduleRule, ValidationError

WEBAPP_ITEM = "075bf89b418c4fbd9a4c5a8e93200711"
PORTAL = "https://oakgis.maps.arcgis.com/sharing/rest/content/items"
# Discovery result cached as a fallback; discover_layer_url() re-derives it.
KNOWN_LAYER_URL = ("https://services.arcgis.com/9tC74aDHuml0x5Yz/arcgis/rest/"
                   "services/StreetSweeping/FeatureServer/0")
PAGE = 1000

MON, TUE, WED, THU, FRI, SAT, SUN = 1, 2, 3, 4, 5, 6, 0
ALL_DAYS = [SUN, MON, TUE, WED, THU, FRI, SAT]

# Day code → list of (weekday, weeks-or-None). Empty list = no sweeping side.
# Vocabulary from the layer's own coded-value domain "StreetSweepingD".
DAY_CODES: dict[str, list[tuple[int, list[int] | None]]] = {
    "E":     [(d, None) for d in ALL_DAYS],           # Everyday
    "EEH":   [(d, None) for d in ALL_DAYS],           # Everyday except holidays
    "EESSH": [(d, None) for d in (MON, TUE, WED, THU, FRI)],
    "MF":    [(d, None) for d in (MON, TUE, WED, THU, FRI)],  # Every Mon to Fri
    "MWF":   [(MON, None), (WED, None), (FRI, None)],
    "TTH":   [(TUE, None), (THU, None)],
    "TTHE":  [(TUE, None), (THU, None)],
    "TTHS":  [(TUE, None), (THU, None), (SAT, None)],
    "TFE":   [(TUE, None), (FRI, None)],
    "MTHE":  [(MON, None), (THU, None)],
    "THFE":  [(THU, None), (FRI, None)],
    "MFE":   [(MON, None), (FRI, None)],
    "ME":    [(MON, None)], "TE": [(TUE, None)], "WE": [(WED, None)],
    "THE":   [(THU, None)], "FE": [(FRI, None)],
    "S":     [(SAT, None)], "SU": [(SUN, None)],
    "M1":  [(MON, [1])], "M2": [(MON, [2])], "M13": [(MON, [1, 3])], "M24": [(MON, [2, 4])],
    "T1":  [(TUE, [1])], "T2": [(TUE, [2])], "T13": [(TUE, [1, 3])], "T24": [(TUE, [2, 4])],
    "W2":  [(WED, [2])], "W4": [(WED, [4])], "W13": [(WED, [1, 3])],
    "FW":  [(WED, [1])],                              # "First Wednesday"
    "TH1": [(THU, [1])], "TH2": [(THU, [2])], "TH4": [(THU, [4])], "TH13": [(THU, [1, 3])],
    "F1":  [(FRI, [1])], "F2": [(FRI, [2])], "F4": [(FRI, [4])], "F13": [(FRI, [1, 3])],
}
# Codes that mean "no schedule for this side" (exempt, unsigned, no addresses,
# outside city, alleyway, mapped elsewhere, duplicate-line major street, …).
NO_SWEEP_CODES = {"N", "N-S", "N-O", "N-E", "NS", "NS-A", "NS-H", "NS-O",
                  "NS-UC", "O", "DM", "MS", "", "MISSING"}

# Time code → (from_hour, to_hour). From domain "StreetSweepingT".
# A1 is posted 12:30–3:30 PM; integer-hour schema forces widening OUTWARD to
# 12→16 — errs toward warning early and holding "sweeping" longer (§1.3).
TIME_CODES: dict[str, tuple[int, int]] = {
    "M1": (0, 3), "M2": (3, 6), "M23": (2, 3), "M3": (9, 12),
    "M68": (6, 8), "A1": (12, 16),
}


def discover_layer_url(session: requests.Session | None = None) -> str:
    s = session or requests.Session()
    app = s.get(f"{PORTAL}/{WEBAPP_ITEM}/data", params={"f": "json"}, timeout=60).json()
    map_item = (app.get("map") or {}).get("itemId")
    if not map_item:
        return KNOWN_LAYER_URL
    webmap = s.get(f"{PORTAL}/{map_item}/data", params={"f": "json"}, timeout=60).json()
    for layer in webmap.get("operationalLayers", []):
        url = layer.get("url") or ""
        if "sweep" in (layer.get("title", "") + url).lower():
            return url
    return KNOWN_LAYER_URL


def fetch_layer_info(layer_url: str, session: requests.Session | None = None) -> dict:
    s = session or requests.Session()
    r = s.get(layer_url, params={"f": "json"}, timeout=60)
    r.raise_for_status()
    return r.json()


def fetch_features(layer_url: str, session: requests.Session | None = None) -> list[dict]:
    s = session or requests.Session()
    features: list[dict] = []
    offset = 0
    while True:
        r = s.get(f"{layer_url}/query", params={
            "where": "1=1", "outFields": "*", "f": "geojson",
            "resultOffset": offset, "resultRecordCount": PAGE,
            "orderByFields": "OBJECTID"}, timeout=120)
        r.raise_for_status()
        page = r.json().get("features", [])
        if not page:
            break
        features.extend(page)
        offset += len(page)
    return features


def verify_domains(layer_info: dict) -> None:
    """Every code the layer's domain declares must be in our decode tables."""
    for f in layer_info.get("fields", []):
        domain = f.get("domain") or {}
        codes = {str(cv["code"]).strip().upper() for cv in domain.get("codedValues", [])}
        if f["name"] in ("DAY_ODD", "DAY_EVEN"):
            unknown = codes - set(DAY_CODES) - NO_SWEEP_CODES
            if unknown:
                raise ValidationError(f"oak: unmapped day codes in domain: {sorted(unknown)}")
        if f["name"] in ("TIME_ODD", "TIME_EVEN"):
            unknown = codes - set(TIME_CODES) - {"NA"}
            if unknown:
                raise ValidationError(f"oak: unmapped time codes in domain: {sorted(unknown)}")


def inspect(layer_url: str, layer_info: dict) -> None:
    print(f"Layer: {layer_info.get('name')}  ({layer_url})")
    print("Fields:")
    for f in layer_info.get("fields", []):
        dom = f.get("domain")
        suffix = f"  [coded domain, {len(dom['codedValues'])} values]" if dom else ""
        print(f"  {f['name']:16} {f['type']}{suffix}")
    for f in layer_info.get("fields", []):
        if f.get("domain") and f["name"].startswith(("DAY", "TIME")):
            print(f"\nDomain for {f['name']}:")
            for cv in f["domain"]["codedValues"]:
                print(f"  {cv['code']:8} = {cv['name']}")
    print("\nConfirm the mapping in oak_arcgis.py (DAY_CODES / TIME_CODES / "
          "NO_SWEEP_CODES) matches the domains above, then re-run without --inspect.")


def _street_name(p: dict) -> str:
    parts = [str(p.get(k) or "").strip() for k in ("PREFIX", "NAME", "TYPE", "SUFFIX")]
    return " ".join(x for x in parts if x)


def _addr_range_for_parity(p: dict, parity: str) -> str | None:
    """Pick the L/R address range whose first house number matches the parity."""
    want_even = parity == "even"
    for lo_k, hi_k in (("L_F_ADD", "L_T_ADD"), ("R_F_ADD", "R_T_ADD")):
        lo, hi = str(p.get(lo_k) or "").strip(), str(p.get(hi_k) or "").strip()
        if lo.isdigit() and hi.isdigit():
            if (int(lo) % 2 == 0) == want_even:
                a, b = sorted((int(lo), int(hi)))
                return f"{a}–{b}"
    return None


def _block_label(p: dict) -> str:
    nums = [int(v) for k in ("L_F_ADD", "R_F_ADD")
            if str(v := p.get(k) or "").strip().isdigit()]
    if nums:
        return f"{min(nums) // 100 * 100} block"
    return "block"


def _decode_side(day_raw, time_raw, drops: DropCounter, ctx: str) -> list[ScheduleRule] | None:
    day = str(day_raw or "").strip().upper()
    if day in NO_SWEEP_CODES:
        return None
    if day not in DAY_CODES:
        raise ValidationError(f"oak: unknown day code {day_raw!r} ({ctx})")
    time = str(time_raw or "").strip().upper()
    if time in ("", "NA"):
        drops.drop("oak: day code present but time is NA")
        return None
    if time not in TIME_CODES:
        raise ValidationError(f"oak: unknown time code {time_raw!r} ({ctx})")
    from_hour, to_hour = TIME_CODES[time]
    # holiday_enforced: false for all Oakland rules — city suspends on holidays.
    return [ScheduleRule(weekday=wd, weeks=wk, from_hour=from_hour,
                         to_hour=to_hour, holiday_enforced=False)
            for wd, wk in DAY_CODES[day]]


def collect_major_lines(features: list[dict]) -> list[tuple[str, list[list[float]]]]:
    """(street, [[lon,lat],…]) for every arterial feature, swept or not — the
    landmark pass names neighboring curb sides after these."""
    out: list[tuple[str, list[list[float]]]] = []
    for feat in features:
        p = feat.get("properties", {})
        fcc = str(p.get("FCC") or "").strip().upper()
        if fcc[:2] not in ("A1", "A2", "A3"):
            continue
        geom = feat.get("geometry") or {}
        if geom.get("type") == "LineString":
            coords = [[float(x), float(y)] for x, y in geom.get("coordinates", [])]
        elif geom.get("type") == "MultiLineString":
            coords = [[float(x), float(y)] for part in geom.get("coordinates", [])
                      for x, y in part]
        else:
            continue
        street = _street_name(p)
        if street and coords:
            out.append((street, coords))
    return out


def build_segments(features: list[dict], drops: DropCounter) -> list[CurbSegment]:
    segments: list[CurbSegment] = []
    for feat in features:
        p = feat.get("properties", {})
        gid = str(p.get("GLOBALID") or p.get("OBJECTID") or "").strip().strip("{}").lower()
        if not gid:
            drops.drop("oak: feature without id")
            continue
        geom = feat.get("geometry") or {}
        if geom.get("type") == "LineString":
            coords = [[float(x), float(y)] for x, y in geom.get("coordinates", [])]
        elif geom.get("type") == "MultiLineString":
            coords = [[float(x), float(y)] for part in geom.get("coordinates", [])
                      for x, y in part]
        else:
            coords = []
        if not coords:
            drops.drop("oak: feature without geometry")
            continue

        street = _street_name(p)
        label = _block_label(p)
        # Census FCC road class: A1/A2/A3 = primary/secondary arterials. The
        # landmark pass names neighboring sides after these ("MacArthur side").
        fcc = str(p.get("FCC") or "").strip().upper()
        road_class = "major" if fcc[:2] in ("A1", "A2", "A3") else None
        # parity → side_key: even → "a", odd → "b" (spec §4.3).
        for parity, side_key, day_f, time_f in (
                ("even", "a", "DAY_EVEN", "TIME_EVEN"),
                ("odd",  "b", "DAY_ODD",  "TIME_ODD")):
            ctx = f"{street} OBJECTID={p.get('OBJECTID')}"
            rules = _decode_side(p.get(day_f), p.get(time_f), drops, ctx)
            if rules is None:
                drops.drop(f"oak: no-sweep side ({parity})")
                continue
            segments.append(CurbSegment(
                id=f"oak:{gid}:{side_key}",
                city="oak",
                street=street,
                block_label=label,
                side_key=side_key,
                door_parity=parity,
                door_range=_addr_range_for_parity(p, parity),
                geometry=coords,
                rules=rules,
                road_class=road_class,
            ))
    segments.sort(key=lambda s: s.id)
    return segments


def load_fixture(path: str) -> list[dict]:
    with open(path) as f:
        data = json.load(f)
    return data["features"] if isinstance(data, dict) else data
