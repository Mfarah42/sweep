# Sweep

Street-sweeping parking guardian for San Francisco and Oakland. One glance
gives a verdict — **Safe / Move soon / Sweeping now** — and a countdown to the
next sweep on your block and side. Local-first: the full schedule ships inside
the app; verdicts and reminders work in airplane mode. The parked spot never
leaves the phone.

## Layout

```
pipeline/      Python data ingestion (dev/CI only, never on device)
Sweep/         iOS app (SwiftUI) — Core/ is a SwiftPM package (SweepCore)
SweepWidgets/  Widget + Live Activity extension
SweepTests/    SweepCore test suite (§13) — runs on macOS via `swift test`
project.yml    XcodeGen manifest → Sweep.xcodeproj
```

## Build

```sh
# 1. Data bundles (committed; rebuild when sources change)
cd pipeline && python3 -m venv .venv && .venv/bin/pip install requests shapely pyyaml
.venv/bin/python ingest.py --city all          # writes out/*.sweepbundle
                                               # + Sweep/Resources/*.sweepdata

# 2. Core tests (no simulator needed)
swift test

# 3. App
brew install xcodegen
xcodegen generate
open Sweep.xcodeproj                           # or xcodebuild -scheme Sweep …
```

Bundle ids are `com.mohamed.sweep` / `com.mohamed.sweep.widgets`, App Group
`group.com.mohamed.sweep`, team `52484H75XU` (set in `project.yml`;
mirrored in `PersistenceStore.appGroupId` and `BundleManager`).

## Data pipeline notes

- **SF**: Socrata dataset `yhqp-riqs` (SFMTA). Column names verified
  2026-07-01. Set `SODA_APP_TOKEN` in CI to avoid throttling.
- **Oakland**: ArcGIS feature service discovered live via the city webapp →
  webmap chain. Day/time coded-value domains are validated against the layer
  on every run — an unknown code fails the build (`--inspect` prints the
  domains for human confirmation).
- Oakland time code `A1` (12:30–3:30 PM) is widened outward to 12→16 to fit
  the integer-hour schema — errs toward warning early, never late.
- Holiday behavior lives in `pipeline/holidays/*.yaml` (SF suspends only
  New Year's/Thanksgiving/Christmas; Oakland suspends on all observed city
  holidays). Review yearly.
- `pipeline/out/{city}-report.txt` carries drop counts and the diff vs the
  previous bundle — the staleness changelog.

## Known deviations from spec

- The web prototype (`sweep-app.jsx`) was not available at build time; the
  eight editorial landmark entries in `pipeline/landmarks/*.yaml` are authored
  fresh in the same style rather than ported verbatim — review copy.
- In-app resource copies of the bundles are named `.sweepdata` because
  codesign refuses nested resources whose extension ends in "bundle"; the
  installed App Group files keep the spec's `.sweepbundle` name.
- Live Activity ends via `staleDate` + foreground sync rather than a literal
  `.after(end)` dismissal (ActivityKit only accepts a dismissal policy at
  `end()` time; the stale UI state covers app-not-running).

## OTA schedule refresh

`BundleManager.indexURL` points at a static `index.json`
(`{city: {built_at, url, sha256}}`). The weekly `BGAppRefreshTask` downloads,
verifies sha256, swaps atomically in the App Group, and reschedules
notifications. All failures are silent. `.github/workflows/data-refresh.yml`
rebuilds bundles weekly and commits when the source `rowsUpdatedAt` changed.
