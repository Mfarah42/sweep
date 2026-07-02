"""Normalized schema for Sweep bundles — the contract everything depends on (spec §4.1).

Adapters emit CurbSegment/ScheduleRule in exactly this shape; normalization and
validation here fail the build loudly rather than emitting questionable data.
"""
from __future__ import annotations

from dataclasses import dataclass, field


class ValidationError(Exception):
    pass


@dataclass
class ScheduleRule:
    weekday: int                 # 0=Sunday … 6=Saturday
    weeks: list[int] | None      # subset of 1..5, None = every week
    from_hour: int               # 0..23 local wall-clock
    to_hour: int                 # 1..24, always > from_hour after normalization
    holiday_enforced: bool

    def key(self) -> tuple:
        return (self.weekday, tuple(self.weeks) if self.weeks else None,
                self.from_hour, self.to_hour, self.holiday_enforced)


@dataclass
class CurbSegment:
    id: str                      # "{city}:{source_block_id}:{side_key}"
    city: str                    # "sf" | "oak"
    street: str
    block_label: str
    side_key: str                # "a" | "b"
    door_parity: str | None      # "even" | "odd" | "mixed" | None
    door_range: str | None
    landmark: str | None = None
    landmark_hint: str | None = None
    landmark_confidence: str | None = None   # "editorial" | "auto"
    geometry: list[list[float]] = field(default_factory=list)  # [[lon, lat], ...]
    rules: list[ScheduleRule] = field(default_factory=list)


@dataclass
class DropCounter:
    """Tracks dropped rows/sides and why, for the {city}-report.txt changelog."""
    reasons: dict[str, int] = field(default_factory=dict)

    def drop(self, reason: str, n: int = 1) -> None:
        self.reasons[reason] = self.reasons.get(reason, 0) + n


def normalize_rules(rules: list[ScheduleRule]) -> list[ScheduleRule]:
    """Split overnight windows, dedupe, sort (spec §4.5)."""
    split: list[ScheduleRule] = []
    for r in rules:
        if r.to_hour <= r.from_hour:
            # Overnight: from_hour→24 on day D, 0→to_hour on day D+1.
            split.append(ScheduleRule(r.weekday, r.weeks, r.from_hour, 24, r.holiday_enforced))
            next_day = (r.weekday + 1) % 7
            # Week occurrence of the following day is not necessarily the same
            # (a 31st→1st crossing), but sign semantics follow the posted day;
            # keep the same weeks subset — matches how cities post these signs.
            if r.to_hour > 0:
                split.append(ScheduleRule(next_day, r.weeks, 0, r.to_hour, r.holiday_enforced))
        else:
            split.append(r)

    seen: set[tuple] = set()
    out: list[ScheduleRule] = []
    for r in split:
        if r.key() not in seen:
            seen.add(r.key())
            out.append(r)
    out.sort(key=lambda r: (r.weekday, r.from_hour, r.to_hour))
    return out


def validate_segment(seg: CurbSegment) -> None:
    """Raise ValidationError on schema violations. Empty rules is handled by the
    caller (segment dropped with a logged count), not an exception."""
    if seg.city not in ("sf", "oak"):
        raise ValidationError(f"{seg.id}: bad city {seg.city!r}")
    if seg.side_key not in ("a", "b"):
        raise ValidationError(f"{seg.id}: bad side_key {seg.side_key!r}")
    if seg.door_parity not in (None, "even", "odd", "mixed"):
        raise ValidationError(f"{seg.id}: bad door_parity {seg.door_parity!r}")
    if not seg.geometry:
        raise ValidationError(f"{seg.id}: empty geometry")
    for pt in seg.geometry:
        if len(pt) != 2 or not (-180 <= pt[0] <= 180 and -90 <= pt[1] <= 90):
            raise ValidationError(f"{seg.id}: bad coordinate {pt!r}")
    for r in seg.rules:
        if not (0 <= r.weekday <= 6):
            raise ValidationError(f"{seg.id}: weekday {r.weekday} out of range")
        if not (0 <= r.from_hour <= 23):
            raise ValidationError(f"{seg.id}: from_hour {r.from_hour} out of range")
        if not (1 <= r.to_hour <= 24):
            raise ValidationError(f"{seg.id}: to_hour {r.to_hour} out of range")
        if r.to_hour <= r.from_hour:
            raise ValidationError(f"{seg.id}: unsplit overnight window {r.from_hour}→{r.to_hour}")
        if r.weeks is not None:
            if not r.weeks or any(w < 1 or w > 5 for w in r.weeks):
                raise ValidationError(f"{seg.id}: bad weeks {r.weeks!r}")
