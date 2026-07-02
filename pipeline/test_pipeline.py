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

    def test_overnight_rule_is_split(self):
        sys.path.insert(0, HERE)
        from schema import ScheduleRule, normalize_rules
        out = normalize_rules([ScheduleRule(2, None, 22, 2, True)])
        self.assertEqual([(r.weekday, r.from_hour, r.to_hour) for r in out],
                         [(2, 22, 24), (3, 0, 2)])


if __name__ == "__main__":
    unittest.main()
