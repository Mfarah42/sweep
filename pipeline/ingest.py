#!/usr/bin/env python3
"""Sweep data pipeline entry point (spec §4).

    python ingest.py --city sf|oak|all [--inspect] [--fixture-dir DIR]
                     [--out DIR] [--built-at ISO8601]

--inspect   (oak) print discovered fields + coded-value domains and exit for
            human field-mapping confirmation before the first real run.
--fixture-dir  read captured API responses instead of the network (golden tests).
--built-at  pin the manifest timestamp for reproducible builds.
"""
from __future__ import annotations

import argparse
import datetime
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import yaml

import bundle_writer
import landmark_pass
from adapters import oak_arcgis, sf_socrata
from schema import DropCounter

HERE = os.path.dirname(os.path.abspath(__file__))
_FIXTURE_RUN = False   # set by main() when --fixture-dir is used


def load_holidays(city: str) -> list[tuple[str, bool]]:
    out: list[tuple[str, bool]] = []
    hdir = os.path.join(HERE, "holidays")
    for name in sorted(os.listdir(hdir)):
        if not name.endswith(".yaml"):
            continue
        with open(os.path.join(hdir, name)) as f:
            data = yaml.safe_load(f) or {}
        for entry in data.get(city, []) or []:
            out.append((str(entry["date"]), bool(entry["suspends"])))
    return out


def run_sf(out_dir: str, built_at: str, fixture_dir: str | None) -> None:
    drops = DropCounter()
    notes: list[str] = []
    if fixture_dir:
        rows = sf_socrata.load_fixture(os.path.join(fixture_dir, "sf_rows.json"))
        source_updated_at = "fixture"
    else:
        session = sf_socrata._session()
        meta = sf_socrata.fetch_metadata(session)
        source_updated_at = str(meta.get("rowsUpdatedAt", ""))
        rows = sf_socrata.fetch_rows(session)
    segments, _ = sf_socrata.build_segments(rows, drops)
    n_ed, n_art, n_geo = landmark_pass.apply(
        segments, os.path.join(HERE, "landmarks", "sf.yaml"))
    notes.append(f"landmarks: {n_ed} editorial, {n_art} arterial, {n_geo} geographic")
    _write(out_dir, "sf", segments, len(rows), source_updated_at, built_at, drops, notes)


def run_oak(out_dir: str, built_at: str, fixture_dir: str | None,
            inspect_only: bool = False) -> None:
    drops = DropCounter()
    notes: list[str] = []
    if fixture_dir:
        features = oak_arcgis.load_fixture(os.path.join(fixture_dir, "oak_features.json"))
        with open(os.path.join(fixture_dir, "oak_layer.json")) as f:
            import json
            layer_info = json.load(f)
        source_updated_at = "fixture"
    else:
        layer_url = oak_arcgis.discover_layer_url()
        layer_info = oak_arcgis.fetch_layer_info(layer_url)
        if inspect_only:
            oak_arcgis.inspect(layer_url, layer_info)
            return
        source_updated_at = str(layer_info.get("editingInfo", {}).get(
            "lastEditDate", "") or layer_info.get("serviceItemId", ""))
        features = oak_arcgis.fetch_features(layer_url)
    oak_arcgis.verify_domains(layer_info)
    segments = oak_arcgis.build_segments(features, drops)
    major_lines = oak_arcgis.collect_major_lines(features)
    n_ed, n_art, n_geo = landmark_pass.apply(
        segments, os.path.join(HERE, "landmarks", "oak.yaml"),
        extra_major_lines=major_lines)
    notes.append(f"landmarks: {n_ed} editorial, {n_art} arterial, {n_geo} geographic")
    notes.append(f"arterial reference lines: {len(major_lines)}")
    notes.append("time code A1 (12:30–3:30 PM) widened outward to 12→16 for integer-hour schema")
    _write(out_dir, "oak", segments, len(features), source_updated_at, built_at, drops, notes)


def _write(out_dir: str, city: str, segments, rows_in: int, source_updated_at: str,
           built_at: str, drops: DropCounter, notes: list[str]) -> None:
    os.makedirs(out_dir, exist_ok=True)
    bundle_path = os.path.join(out_dir, f"{city}.sweepbundle")
    prev_path = bundle_path + ".prev"
    if os.path.exists(bundle_path):
        shutil.copy2(bundle_path, prev_path)
    summary = bundle_writer.write_bundle(
        bundle_path, city, segments, load_holidays(city),
        source_updated_at, built_at, drops)
    bundle_writer.write_report(
        os.path.join(out_dir, f"{city}-report.txt"), city, rows_in, summary,
        drops, bundle_path, prev_path if os.path.exists(prev_path) else None, notes)
    if os.path.exists(prev_path):
        os.remove(prev_path)
    # Ship a copy into the app resources as .sweepdata — codesign refuses to
    # sign nested resources whose extension ends in "bundle". The installed
    # App Group file keeps the .sweepbundle name (spec §10).
    # ONLY for real builds into the default out dir: fixture/golden-test runs
    # (--fixture-dir, custom --out) must never replace the shipped bundles.
    is_default_out = os.path.normpath(out_dir) == os.path.normpath(os.path.join(HERE, "out"))
    if is_default_out and not _FIXTURE_RUN:
        resources_dir = os.path.normpath(os.path.join(HERE, "..", "Sweep", "Resources"))
        if os.path.isdir(resources_dir):
            shutil.copy2(bundle_path, os.path.join(resources_dir, f"{city}.sweepdata"))
    size_mb = os.path.getsize(bundle_path) / 1e6
    print(f"[{city}] {summary['segments']} segments, {summary['rules']} rules, "
          f"{summary['holidays']} holiday rows → {bundle_path} ({size_mb:.1f} MB)")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--city", choices=["sf", "oak", "all"], required=True)
    ap.add_argument("--inspect", action="store_true",
                    help="oak: print field list + domains and exit")
    ap.add_argument("--fixture-dir", default=None)
    ap.add_argument("--out", default=os.path.join(HERE, "out"))
    ap.add_argument("--built-at", default=None)
    args = ap.parse_args()

    global _FIXTURE_RUN
    _FIXTURE_RUN = args.fixture_dir is not None

    built_at = args.built_at or datetime.datetime.now(datetime.UTC).strftime(
        "%Y-%m-%dT%H:%M:%SZ")
    if args.city in ("sf", "all"):
        run_sf(args.out, built_at, args.fixture_dir)
    if args.city in ("oak", "all"):
        run_oak(args.out, built_at, args.fixture_dir, inspect_only=args.inspect)


if __name__ == "__main__":
    main()
