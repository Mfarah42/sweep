# App Store submission kit

Everything App Store Connect asks for, ready to paste. Spec references: §12.

## Listing

Naming follows the house pattern (`Cadence: Am I On or Off`,
`Prayer Windows: Salah Times`): the short brand, a colon, then what it does.
App Store limits: name 30 chars, subtitle 30 chars. Name + subtitle are indexed
for search, so keywords must not repeat their words.

| Field | Value |
|---|---|
| Name | **Sweep: Street Sweeping Alerts** (29) |
| Subtitle | **Parking alarm · SF & Oakland** (28) |
| Category | Navigation (secondary: Utilities) |
| Price | Free, with one non-consumable IAP (Sweep Plus, $3.00) |
| Age rating | 4+ |
| Support URL | https://mfarah42.github.io/sweep-support/ (repo Mfarah42/sweep-support, GitHub Pages) |
| Privacy Policy URL | https://mfarah42.github.io/sweep-support/privacy.html |
| Copyright | 2026 Mohamed Farah |
| Apple ID | 6807645821 (record created 2026-09-01, SKU `sweep-ios`) |
| Support email | stockdapphelp@gmail.com |

Alternates considered (all ≤30): `Sweep: Move Your Car in Time` (28, warmer,
loses the search term), `Sweep: SF & Oakland Parking` (27, cities in the
name, loses "sweeping"). Rejected: the earlier draft `Sweep — Street Sweeping
Alarm` — a competitor already ships as **"Sweep Alarm: Street Sweeping"**
(id1205066796); our name must not read as that app. Other incumbents, all
SF-only: "Street Sweep – San Francisco Street Parking", "Sweep N Park",
"Street Cleaning Parking", CURB, ParkUsher. Oakland coverage and the
offline/no-account posture are the differentiators to lead with.

**Keywords** (100 chars max — no words already in name/subtitle):
`cleaning,ticket,citation,tow,move,car,curb,reminder,schedule,sfmta,bay area,widget,live activity`
**Promotional text** (170 chars max):
> Is the car safe where it's parked? One glance: Safe, Move soon, or Sweeping now — and a wake-up before the sweeper comes. Works entirely offline.

**Description:**

> **Is my car safe where it's parked?**
>
> Sweep answers with one glance: Safe / Move soon / Sweeping now — and a countdown to the next sweep on your block, on your side of the street.
>
> Tell Sweep once when you park. It finds your block from a single location fix, asks at most one friendly question (which side — by the view or the door numbers, never compass directions), and then watches the schedule so you don't have to.
>
> **Wakes you before the sweeper comes.** An evening-before heads-up, a two-hour warning, and a last call thirty minutes out. A lock screen Live Activity counts down the final hours.
>
> **Works with zero signal.** The full SF and Oakland schedules ship inside the app. Verdicts and alarms work in a parking garage, in airplane mode, anywhere.
>
> **Your spot never leaves your phone.** No account, no tracking, no analytics. The only network request Sweep ever makes is a schedule-freshness check.
>
> **Signs beat data.** If the posted sign disagrees with the city's data, tell Sweep once and your block is corrected on your phone.
>
> Home screen and lock screen widgets show the verdict at a glance.
>
> Sweep Plus ($3, one time): every ticket-saving alert is free forever — that never changes. Plus adds the extras: a second car, curb-card themes, and Longest Spot, which finds the block you can stay on longest.
>
> Optional weekly garbage-day reminders, and your move-by deadline can be mirrored into Apple Reminders.
>
> Covers San Francisco (SFMTA schedule data) and Oakland (City of Oakland GIS). Always check the posted sign — schedules can change faster than city data.

## Privacy (App Privacy section)

- **Data Not Collected** — select "No" for all collection questions.
- Location is used on-device only, never stored beyond the parked session,
  never transmitted. `PrivacyInfo.xcprivacy` declares: no tracking, no
  collected data types, UserDefaults required-reason CA92.1.

## App Review notes (paste into the Review Notes field)

> Sweep is fully local — no account or login. To test:
> 1. On first run, tap "I just parked" (grant location When-In-Use), or use the search field with e.g. "1935 Lakeshore Ave" (Oakland).
> 2. If the block's two sides sweep differently, pick a side; reminders schedule automatically.
> 3. QA time control: Settings → tap the version string 5 times to reveal Demo Mode, which scrubs the app clock so verdict transitions and the Live Activity can be observed without waiting for a real sweep.
> The only network call is a weekly schedule-freshness check against a static file on GitHub Releases; the app is fully functional with networking disabled.

## Screenshots (docs/store-assets/, 6.9" iPhone 17 Pro Max, 1320×2868)

| File | Shows |
|---|---|
| 01-empty.png | "Where's your car?" first-run screen |
| 02-parked.png | Verdict card: Safe until Monday 2 AM, Grand Lake block, reminders + coming-up |

Still to capture before submission (needs interactive run): side picker with two
labeled sides, fix-the-sign form, lock screen Live Activity, widget gallery.
Marketing frames/captions can be added in App Store Connect directly.

## In-App Purchase (App Store Connect → In-App Purchases)

| Field | Value |
|---|---|
| Type | Non-Consumable |
| Product ID | `sweep.plus` (created 2026-09-01, IAP Apple ID 6807651612) |
| Reference name | Sweep Plus |
| Price | $3.00 (pick the 3.00 USD price point in Connect) |
| Display name | Sweep Plus |
| Description | Multiple cars, curb-card themes, Longest Spot. |

Local testing: the `Sweep` scheme loads `Sweep/Sweep.storekit`, so purchases
work in the simulator with no Connect setup. Delete the scheme's
`storeKitConfiguration` line to test against the sandbox.

## Editorial copy review (landmark entries)

Reviewed 2026-07-04 against maps; all geographically sound:

| Entry | Verdict |
|---|---|
| 9th Ave (Inner Sunset) "Ocean side / sunset straight down the street" | ✓ west curb, Judah runs to the beach |
| 9th Ave "Downtown side / Sutro Tower over your shoulder" | ✓ tower is SW, behind you facing east |
| Haight St "Panhandle side / the Panhandle a block away" | ✓ one block north |
| Haight St "Buena Vista side / the park uphill from you" | ✓ park is uphill south |
| Grand Ave "Lake side / theater marquee up the street" | ✓ Grand Lake Theatre at 3200 Grand |
| Grand Ave "Hills side / uphill toward Mandana" | ✓ Mandana Blvd uphill east |
| Telegraph "Downtown side / skyline down the avenue" | ✓ Telegraph runs straight downtown |
| Telegraph "Hills side / morning sun in your eyes" | ✓ east-facing |

Auto-generated names ("San Pablo side · toward San Pablo Ave") come from the
arterial pass; door numbers remain the authoritative cue on those.

## Submission checklist

- [x] Placeholders replaced 2026-09-01: `com.mohamed.sweep` / `.widgets`,
      `group.com.mohamed.sweep`, `com.mohamed.sweep.refresh`, team
      `52484H75XU`, `indexURL` → `github.com/Mfarah42/sweep`; MARKETING_VERSION
      1.0 (1). Regenerate with `xcodegen generate`.
- [x] Paid Apple Developer account (team Mohamed Farah, ASC under
      farahmo242@gmail.com)
- [ ] **Account Holder must accept the updated Apple Developer Program License
      Agreement** (ASC banner 2026-09-01) — new apps cannot be created until
      then. Also provide EU trader status (DSA) or the app is hidden in the EU.
- [x] App IDs registered in the Developer portal (com.mohamed.sweep w/ App Groups +
      Time Sensitive, com.mohamed.sweep.widgets w/ App Groups, group.com.mohamed.sweep)
- [x] ASC app record 6807645821 created 2026-09-01: name/subtitle, categories
      Navigation/Utilities, 4+ rating, content rights, Free in 175 regions,
      Mac/Apple Silicon availability OFF, privacy Data Not Collected published,
      version 1.0 metadata + review notes + 2 screenshots (6.5" 1284×2778 JPG)
- [x] `sweep-support` live on GitHub Pages (Support + Privacy URLs above)
- [x] `sweep.plus` IAP in ASC (6807651612): $3.00, all regions, EN localization,
      review screenshot (`docs/store-assets/iap-review-plus.jpg`)
- [x] Pushed to GitHub as public `Mfarah42/sweep` 2026-09-01 (still TODO below: token +
      first OTA release)
- [ ] Push repo to GitHub as **public** `Mfarah42/sweep` (release assets on a
      private repo need auth; the app fetches anonymously); add `SODA_APP_TOKEN`
      secret; run the data-refresh workflow once to publish the first
      `schedule-data` OTA release. Bundles in the repo were built 2026-07-06 —
      rebuild before the first release so v1.0 ships fresh data.
- [ ] Real-device pass: notifications fire locked + airplane mode, Live
      Activity stages, GPS park flow on a real street
- [ ] Capture remaining screenshots; upload 6.9" set
- [ ] Sign into Xcode › Settings › Accounts (farahmo242@gmail.com) — CLI archive
      fails with 'No Accounts' until then; then
      `xcodebuild archive -allowProvisioningUpdates` → export/upload → submit
      version 1.0 + the IAP together
