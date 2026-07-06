"""Pipeline tests (spec §13.10): golden-file determinism + loud validation.

    .venv/bin/python -m pytest test_pipeline.py   (or plain: python test_pipeline.py)
"""
from __future__ import annotations

import hashlib
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
PY = sys.executable


def _build(out_dir: str) -> None:
    subprocess.run(
        [PY, os.path.join(HERE, "ingest.py"), "--city", "all",
         "--fixture-dir", os.path.join(HERE, "fixtures"),
         "--out", out_dir, "--built-at", "2026-01-01T00:00:00Z"],
        check=True, capture_output=True)


def _sha(path: str) -> str:
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


class GoldenFileTest(unittest.TestCase):
    def test_fixture_builds_are_byte_identical(self):
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            _build(a)
            _build(b)
            for city in ("sf", "oak"):
                pa = os.path.join(a, f"{city}.sweepbundle")
                pb = os.path.join(b, f"{city}.sweepbundle")
                self.assertTrue(os.path.getsize(pa) > 1024)
                self.assertEqual(_sha(pa), _sha(pb), f"{city} bundle not deterministic")

    def test_fixture_bundle_has_expected_shape(self):
        import sqlite3
        with tempfile.TemporaryDirectory() as d:
            _build(d)
            con = sqlite3.connect(os.path.join(d, "sf.sweepbundle"))
            manifest = dict(con.execute("SELECT key, value FROM manifest"))
            self.assertEqual(manifest["schema_version"], "1")
            self.assertEqual(manifest["built_at"], "2026-01-01T00:00:00Z")
            n_seg = con.execute("SELECT COUNT(*) FROM segments").fetchone()[0]
            n_rules = con.execute("SELECT COUNT(*) FROM rules").fetchone()[0]
            self.assertGreater(n_seg, 0)
            self.assertGreaterEqual(n_rules, n_seg)
            bad = con.execute(
                "SELECT COUNT(*) FROM rules WHERE to_hour <= from_hour").fetchone()[0]
            self.assertEqual(bad, 0, "unsplit overnight window escaped normalization")

    def test_landmark_invariants(self):
        """A block's two sides never share a name; a side never has two."""
        import sqlite3
        with tempfile.TemporaryDirectory() as d:
            _build(d)
            for city in ("sf", "oak"):
                con = sqlite3.connect(os.path.join(d, f"{city}.sweepbundle"))
                clash = con.execute("""SELECT COUNT(*) FROM (
                    SELECT street, block_label FROM segments
                    GROUP BY street, block_label
                    HAVING COUNT(DISTINCT side_key) > 1
                       AND COUNT(DISTINCT landmark) < 2)""").fetchone()[0]
                self.assertEqual(clash, 0, f"{city}: block sides sharing a landmark")
                split = con.execute("""SELECT COUNT(*) FROM (
                    SELECT street, block_label, side_key FROM segments
                    GROUP BY street, block_label, side_key
                    HAVING COUNT(DISTINCT landmark) > 1)""").fetchone()[0]
                self.assertEqual(split, 0, f"{city}: side with two landmarks")


class ShippedBundleGuard(unittest.TestCase):
    """Fixture/golden runs must never touch the shipped app bundles — this
    once silently replaced Sweep/Resources/*.sweepdata with 57KB fixture data,
    which CI would then have committed and shipped."""

    def test_fixture_build_leaves_shipped_bundles_alone(self):
        resources = os.path.join(HERE, "..", "Sweep", "Resources")
        shipped = {name: _sha(os.path.join(resources, name))
                   for name in ("sf.sweepdata", "oak.sweepdata")
                   if os.path.exists(os.path.join(resources, name))}
        with tempfile.TemporaryDirectory() as d:
            _build(d)
        for name, digest in shipped.items():
            self.assertEqual(_sha(os.path.join(resources, name)), digest,
                             f"{name} was modified by a fixture build")

    def test_shipped_bundles_are_real_not_fixture(self):
        resources = os.path.join(HERE, "..", "Sweep", "Resources")
        for name in ("sf.sweepdata", "oak.sweepdata"):
            path = os.path.join(resources, name)
            if os.path.exists(path):
                self.assertGreater(os.path.getsize(path), 1_000_000,
                                   f"{name} is suspiciously small — fixture data?")


class ValidationTest(unittest.TestCase):
    def test_unknown_sf_weekday_fails_loudly(self):
        sys.path.insert(0, HERE)
        sys.path.insert(0, os.path.join(HERE, "adapters"))
        from adapters import sf_socrata
        from schema import DropCounter, ValidationError
        row = {"cnn": "1", "cnnrightleft": "L", "weekday": "Blursday",
               "fromhour": 8, "tohour": 10, "week1": 1, "week2": 1,
               "week3": 1, "week4": 1, "week5": 1,
               "line": {"type": "LineString", "coordinates": [[-122.4, 37.7], [-122.41, 37.7]]}}
        with self.assertRaises(ValidationError):
            sf_socrata.build_segments([row], DropCounter())

    def test_travel_hint_follows_parking_direction(self):
        """Two-way street ending at an arterial: cars park in their direction
        of travel, so the right-hand curb's cars point at the arterial."""
        sys.path.insert(0, HERE)
        import landmark_pass as lp
        # Street axis due north (0°), arterial at the north end.
        # East curb (facing 90°) = right side of northbound travel → toward.
        self.assertEqual(lp._travel_hint(90.0, 0.0, "MacArthur Blvd"),
                         "your car points toward MacArthur Blvd")
        # West curb (facing 270°) → away.
        self.assertEqual(lp._travel_hint(270.0, 0.0, "MacArthur Blvd"),
                         "your car points away from MacArthur Blvd")
        # A facing along the axis is no curb at all — no hint.
        self.assertIsNone(lp._travel_hint(0.0, 0.0, "MacArthur Blvd"))

    def test_overnight_rule_is_split(self):
        sys.path.insert(0, HERE)
        from schema import ScheduleRule, normalize_rules
        out = normalize_rules([ScheduleRule(2, None, 22, 2, True)])
        self.assertEqual([(r.weekday, r.from_hour, r.to_hour) for r in out],
                         [(2, 22, 24), (3, 0, 2)])


if __name__ == "__main__":
    unittest.main()
