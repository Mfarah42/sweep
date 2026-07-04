#!/usr/bin/env python3
"""Build the OTA index.json (spec §4.7) from the bundles in pipeline/out.

    python make_index.py --base-url https://github.com/OWNER/sweep/releases/latest/download

Writes pipeline/out/index.json:
    {"sf": {"built_at": "...", "url": ".../sf.sweepbundle", "sha256": "..."}, ...}
The app's BundleManager verifies sha256 before an atomic swap; a bad or
missing index simply means no refresh — never a broken app.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sqlite3

HERE = os.path.dirname(os.path.abspath(__file__))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", required=True,
                    help="URL prefix the bundle files will be downloadable from")
    ap.add_argument("--out", default=os.path.join(HERE, "out"))
    args = ap.parse_args()

    index: dict[str, dict] = {}
    for city in ("sf", "oak"):
        path = os.path.join(args.out, f"{city}.sweepbundle")
        with open(path, "rb") as f:
            payload = f.read()
        con = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        built_at = con.execute(
            "SELECT value FROM manifest WHERE key='built_at'").fetchone()[0]
        con.close()
        index[city] = {
            "built_at": built_at,
            "url": f"{args.base_url.rstrip('/')}/{city}.sweepbundle",
            "sha256": hashlib.sha256(payload).hexdigest(),
        }

    out_path = os.path.join(args.out, "index.json")
    with open(out_path, "w") as f:
        json.dump(index, f, indent=2, sort_keys=True)
        f.write("\n")
    print(f"wrote {out_path}")
    for city, entry in index.items():
        print(f"  {city}: built_at={entry['built_at']} sha256={entry['sha256'][:12]}…")


if __name__ == "__main__":
    main()
