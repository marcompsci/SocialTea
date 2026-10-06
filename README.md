# SocialTea

A privacy-first, session-only follower tracker for Instagram, Facebook and TikTok **data exports**.
Native SwiftUI, iOS 17+. No network, no logins, no persistence of imported data.

## Open & run

1. Open `SocialTea.xcodeproj` in **Xcode 16 or later** (the project uses synchronized folders — drop new files into `SocialTea/` and they're picked up automatically).
2. Select the **SocialTea** scheme → an iPhone simulator → ⌘R.
3. For a real device: target **SocialTea** → Signing & Capabilities → pick your Team.
4. Run unit tests with ⌘U (parser + set logic, including a hand-verified Instagram sample).

If the project ever refuses to open, `brew install xcodegen && xcodegen` in this folder regenerates it from `project.yml`.

## Layout

```
SocialTea/
  App/        SocialTeaApp (tabs + lock overlay), SessionStore (in-memory state), LockManager
  Core/       Foundation-only logic: Models, ImportParser, RelationshipEngine, ListTools/Export, SampleData
  Views/      Dashboard · Lists · Cleanup · Guide · Import · Settings/Lock · Components
  Resources/  Assets (generic tea-cup icon), BaselineSnapshot.json, PrivacyInfo.xcprivacy
SocialTeaTests/  XCTest suite
```

## How the spec is met

| Requirement | Where |
|---|---|
| Zero network calls, no SDKs, no keys | No `URLSession`/web views anywhere. Profile buttons hand a URL to iOS (`openURL`) on the user's tap only. |
| Imported data in memory only | `SessionStore` holds everything in properties. The only `UserDefaults` value is the Face ID on/off *preference*. Share exports use a temp file deleted when the Share Sheet closes (and purged on launch). |
| In-app privacy statement | `PrivacyPromise` on Dashboard, Import, Settings; full promise in Guide. |
| Five tabs | Dashboard, Lists, Cleanup, Insights, Guide. Settings is the gear on Dashboard. |
| Import JSON/CSV/TXT incl. official exports | `ImportParser` — Instagram `followers_1.json` (+ `followers_2.json`, multi-select merges) and `following.json` in old and new layouts, TikTok `user_data.json` (auto-scopes to Follower/Following) and its text export, Facebook `your_friends.json`. |
| Newer snapshot + demo data | Import sheet per platform: older (baseline) + optional newer; "Make newer the baseline"; Demo button on every platform card. |
| Labeled baseline | `Resources/BaselineSnapshot.json` → "Snapshot · Sep 30, 2026": IG 3,977 / 777 / 191 not-following-back, FB 53 friends. Replace via import; "Start over" restores it. |
| One status label | `SessionStore.statusLabel`, derived only from loaded platforms. |
| Six views, exact set logic | `RelationshipEngine` (Gone quiet = former mutuals now absent from both lists, always labeled as a heuristic). Facebook: everyone under Friends, NFB/Fans = 0 with an explanation. |
| Search, sort, share TXT/CSV | Lists tab (`.searchable`, sort menu, `UIActivityViewController`). CSV escapes formula injection. |
| Dashboard | Animated counters, follow-back ring (mutuals ÷ following), platform cards that jump to Lists. |
| Cleanup | Swipe deck, keep/queue buttons, undo, completion summary + confetti, light/success haptics, shareable unfollow queue. |
| App lock | Face ID/Touch ID (off by default, falls back to device passcode) or a 4-digit session PIN kept in memory. |

### About the bundled baseline
It currently holds **counts only** (no usernames), so the Dashboard shows the real numbers and the lists explain
that names need an import. To ship names too, fill `followerUsernames` / `followingUsernames` in
`BaselineSnapshot.json` — lists then take over and every count is derived from them.

### SocialTea Pro ($7.99/month)
StoreKit 2 auto-renewing subscription (`com.phoronomics.socialtea.pro.monthly`). Free: import, Dashboard numbers,
list counts, first 5 names per list, Guide, App Lock. Pro: every name, comparisons, Cleanup, Insights, export.
Demo data is always fully unlocked. Test purchases locally with `StoreKit/SocialTea.storekit` (already set in the scheme).

### Widget & Siri (opt-in)
Off by default (Settings → Home Screen & Siri). When on, only totals are saved for the widget and Siri; turning it
off erases them. The widget needs its own Widget Extension target and an App Group — see `SocialTeaWidget.swift`.

### Support & privacy pages
`docs/` is published with GitHub Pages: support at `/SocialTea/`, privacy policy at `/SocialTea/privacy`.

## App Store notes
- Privacy label: **Data Not Collected** (accurate for this build). `PrivacyInfo.xcprivacy` declares no tracking, no collected data, and the UserDefaults reason `CA92.1`.
- Guideline 5.2.3: no scraping, private APIs or automation; all processing on-device.
- Name/subtitle form: "SocialTea — Follower Tracker for Instagram". Generic SF Symbols and an original icon; no platform logos; in-app non-affiliation notice.
- Bundle ID is `com.phoronomics.socialtea` — change it in the target settings if you like.
- Acceptance check for "no network": run in Instruments (Network template) or behind Proxyman/Charles — the app makes no requests.
