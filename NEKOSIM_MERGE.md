# NekoSim

NekoSim is a unified SIM / eSIM manager built on top of NekokoLPA2.

This workspace adds a SIM asset layer for:

- phone number records
- operator / country metadata
- expiry and renewal tracking
- ICCID / EID / SM-DP+ / activation code fields
- LPA import into an asset record

The original NekokoLPA2 profile-management stack is kept as the eSIM / eUICC layer.

## First integration slice

Added files:

```text
lib/models/nekosim_asset.dart
lib/services/nekosim_asset_service.dart
lib/pages/nekosim_assets_page.dart
```

Patched:

```text
lib/pages/main_tab_screen.dart
pubspec.yaml
android/app/build.gradle.kts
```

The app now opens with an **Assets** tab before the original profile management tab.

## Build

```bash
flutter pub get
flutter analyze
flutter build apk --debug --flavor community
```

## Notes

The Android package id is intentionally kept as `ee.nekoko.nlpa2.open` for this first slice to avoid breaking native plugins, OTBridge / NBridge queries, and Flutter Android wiring. Rename package id only after the unified app boots and plugin paths are tested.

## Slice 2: Profile ↔ Asset linking

Added bidirectional linking primitives:

- `NekoSimAsset.linkedProfileIccid` is now used by UI and service logic.
- Asset edit page can choose a discovered profile from `ProfileMetadataService.getAllProfiles()`.
- Profile context menu now includes **Add to NekoSim Assets**.
- `NekoSimAssetService.createFromProfile()` creates or updates an asset from an installed eSIM profile.
- Duplicate prevention uses `linkedProfileIccid` / `iccid` lookup.

Patched:

```text
lib/services/nekosim_asset_service.dart
lib/pages/nekosim_assets_page.dart
lib/pages/profiles_screen.dart
```

## Slice 3: Architecture convergence

Goal: stop NekoSim being a side-car; make it part of the host pipeline.

1. `NekoSimAssetService` is now a `ChangeNotifier` singleton with an in-memory
   cache (`cachedAssets` / `cachedByIccid`). All mutations funnel through
   `upsert`/`delete` so listeners fire exactly once per change.
2. Initialized at startup in `main.dart` (`NekoSimAssetService().init()`),
   so the table exists before any page touches it.
3. New `NekoSimPlugin` registered in `BuildPluginRegistry`:
   - `onProfilesLoaded` → silently backfills operator name / EID into linked
     assets whenever a reader lists profiles.
   - `getProfileCardBottomData` → eSIM profile cards now show the linked
     asset's phone number, renewal date countdown, and balance note using the
     host's existing card-bottom merge pipeline.
4. Renewal reminders now reuse the host `scheduled_notifications` table via
   `TagNotificationService` — no parallel reminder system. Renew/delete keeps
   reminders in sync.
5. Assets page rewritten to listen to the service (no manual reloads), and
   shows linked profile status (enabled/disabled, last seen) joined from
   `profile_metadata`.

Patched / added:

```text
lib/services/nekosim_asset_service.dart   (rewritten)
lib/plugins/nekosim_plugin.dart           (new)
lib/plugins/build_plugin_registry.dart
lib/pages/nekosim_assets_page.dart
lib/main.dart
```

## Slice 4: Cloud reminders + l10n + import/export (items 2/3/4)

### Cloud reminders (SimJiang server protocol)
- `lib/services/nekosim_cloud_service.dart` — speaks the SimJiang reminder
  server API (`/api/status`, `/api/register`, `/api/sync`,
  `/api/test-telegram`, `/api/test-email`, `/api/check-now`), X-API-Key auth,
  API-key extraction (`cleanApiKey`), config persisted via SharedPreferences
  under `nekosim.cloud.*`.
- `lib/pages/nekosim_cloud_page.dart` — settings UI: server URL, key
  generate/copy, remind days, Telegram (token/chatId, obscured), SMTP
  (host/port/user/app-password, obscured), test buttons, check-now,
  secrets warning.
- Auto sync: `NekoSimAssetService.upsert/delete` fire
  `NekoSimCloudService().maybeAutoSync()` (fire-and-forget, gated on
  enabled+autoSync+key+url).
- Server source remains SimJiang `server/simjiang-reminder/server.py`
  (protocol-compatible).

### Localization (9 locales)
- `lib/l10n/nekosim_strings.dart` — self-contained string table for
  en / zh / zh-Hant / ja / ko / de / es / fr / it, resolved from the app
  locale. Used by assets page, edit page, cloud page, Assets tab label,
  and the profile context-menu entry.
- Kept separate from the generated arb/l10n pipeline on purpose; strings
  can be upstreamed to .arb later without code changes (getter API stays).

### Import / Export
- `lib/utils/nekosim_import_export.dart` — JSON + CSV export; import parses
  NekoSim format AND legacy SimJiang exports (number/operator/expireDate/
  eid/smdp/activationCode/cycleDays/balance). Same-ID entries update.
- Assets page AppBar menu: Cloud reminders / Export JSON / Export CSV /
  Import data. Export dialog supports copy-to-clipboard.

Added:

```text
lib/l10n/nekosim_strings.dart
lib/services/nekosim_cloud_service.dart
lib/pages/nekosim_cloud_page.dart
lib/utils/nekosim_import_export.dart
```

Patched:

```text
lib/services/nekosim_asset_service.dart   (auto cloud sync hooks)
lib/pages/nekosim_assets_page.dart        (menu + full l10n)
lib/pages/main_tab_screen.dart            (localized tab label)
lib/pages/profiles_screen.dart            (localized menu entry)
```

## Slice 5: Assets page UX + QR/LPA import

### Assets page

- Search box filtering on operator / number / country / ICCID / EID /
  SM-DP+ / balance / note.
- Filter chips: all / due soon / expired / not linked to a profile.
- Sort menu: expiry soonest, expiry latest, recently updated (no-expiry
  records always sort last for the expiry orders).
- Card quick actions: per-card menu with copy number / copy ICCID /
  copy LPA code (assembles `LPA:1$smdp$code` when SM-DP+ is known) and
  delete; renew chips extended to +7 / +30 / +90 / +180 / +365.
- Dedicated "no matching assets" empty state when a filter/search hides
  everything.

### LPA import dialog

- Paste from clipboard, scan QR (reuses host `QrScannerPage`; hidden on
  Windows/Linux like the host download page), and decode QR from an image
  file (`mobile_scanner` analyzeImage with `zxing_lib` fallback, zxing-only
  on Windows/Linux — same platform split as the host).
- Live parse preview of SM-DP+ / activation code via
  `NekoSimAssetService.parseLpa` while typing.

### Fixes

- Cloud sync payload: removed the corrupted `remind天` settings key (left
  over from a bad find-and-replace); `remindDays` is the canonical key.
- CSV import: replaced the per-line splitter with a full-text RFC 4180
  tokenizer so quoted fields containing newlines (e.g. multi-line notes)
  round-trip through export/import correctly.

Added:

```text
lib/utils/nekosim_qr_import.dart
```

Patched:

```text
lib/pages/nekosim_assets_page.dart       (rewritten: toolbar, card menu, dialog)
lib/l10n/nekosim_strings.dart            (16 new keys x 9 locales)
lib/services/nekosim_cloud_service.dart  (remind天 key removed)
lib/utils/nekosim_import_export.dart     (multi-line CSV fields)
```

## Slice 5.1: Consistency polish + zh locale fix

### Host fix: Simplified Chinese resolved to Traditional

`supportedLocales` lists `zh_TW` before `zh`, and the languageCode-only
fallback in `_resolveLocale` (main.dart) returned the first match — so
zh-Hans devices got Traditional Chinese app-wide. Chinese is now resolved
script-aware (Hant / TW / HK / MO → `zh_TW`, otherwise `zh`).

### Consistency with the host design language

- All NekoSim text fields use the host's rounded-16 `OutlineInputBorder`.
- ICCID / EID / SM-DP+ / activation-code fields render in `AppTheme.mono`.
- LPA import dialog uses the host `LpaTextEditingController` for inline
  LPA syntax highlighting, same as the download page.
- `_fmtLastSeen` relative times and the profile-link snackbars in
  `profiles_screen.dart` are localized (previously hardcoded English).

### Functional polish

- Edit page: expiry date now has a date-picker suffix button (manual
  YYYY-MM-DD typing still works) and exposes `renewalCycleDays`.
- Cloud page: pending text edits are flushed on page exit (previously
  lost unless the keyboard "done" action fired).

Patched:

```text
lib/main.dart                       (script-aware zh resolution)
lib/l10n/nekosim_strings.dart       (8 new keys x 9 locales)
lib/pages/nekosim_assets_page.dart  (theme, date picker, cycle field, l10n)
lib/pages/nekosim_cloud_page.dart   (save-on-exit, rounded fields)
lib/pages/profiles_screen.dart      (localized link snackbars)
```

## Slice 6: Real local reminders (zonedSchedule)

Before this slice `scheduled_notifications` rows were stored but nothing
ever armed an OS alarm — the only notification in the app was the 5-second
test reminder. Reminders silently never fired once the app was killed.

- `LocalNotificationService`: timezone db init; `scheduleReminder` /
  `cancelReminder` built on `zonedSchedule` (inexactAllowWhileIdle — no
  exact-alarm permission needed for day-level reminders); deterministic
  31-bit `reminderId(text, scheduledDate)` matching the table PK.
- `TagNotificationService.upsertNotification/deleteNotification` now mirror
  every row into an OS alarm (fires 09:00 local on the day; same-day late
  upserts fire ~2 min later; respects `enableScheduledNotifications`).
  Host tag reminders and NekoSim renewals both flow through here.
- `rescheduleAllPending()` at startup re-arms alarms after app updates and
  for rows created before this slice; `ScheduledNotificationBootReceiver`
  in the manifest restores alarms after reboot.
- `timezone` promoted to a direct dependency.

Patched:

```text
pubspec.yaml                                  (timezone dep)
android/app/src/main/AndroidManifest.xml      (fln receivers)
lib/services/local_notification_service.dart  (zonedSchedule API)
lib/services/tag_notification_service.dart    (OS mirror + resync)
lib/main.dart                                 (startup resync)
```

## Slice 7: One UI — glass design system + config wiring

See RELEASE_PLAN.md for the full road-to-release workflow.

### Config correctness

- `DatabaseService.importDatabase/resetDatabase` now include
  `nekosim_assets` (assets previously lost on backup restore / kept on
  reset).
- Cloud reminders entry added to Settings → Tags & Reminders (host tile
  style), no longer discoverable only from the assets-page menu.

### One UI: glass design system

New `lib/widgets/nekosim_glass.dart`:

- `GlassSurface` — real frosted glass (BackdropFilter) for toolbars/headers
- `GlassCard` — cheap glass-look for list items (no per-item saveLayer)
- `GlassAmbientBackground` — soft color-scheme blobs behind page content
- `GlassSection` — settings-style captioned section, glass-skinned

Applied:

- Assets tab now uses the same transparent AppBar chrome as the manage tab
  (logo + app name + tab caption) — the "two UIs" feel is gone
- Search/filter toolbar is a frosted panel; asset cards are glass cards
- Edit page and cloud page migrated to the host `StyledHeaderScaffold`;
  cloud page restructured into captioned glass sections with host-style
  switch tiles
- All NekoSim text fields share one filled, borderless rounded style
- Cleared the two remaining host analyzer infos (deprecated cacheExtent,
  null-aware spread) — `flutter analyze` is now fully clean

Added:

```text
RELEASE_PLAN.md
lib/widgets/nekosim_glass.dart
```

Patched:

```text
lib/pages/nekosim_assets_page.dart
lib/pages/nekosim_cloud_page.dart            (rewritten)
lib/pages/settings/tags_and_reminders_page.dart
lib/services/database_service.dart
lib/pages/notifications_screen.dart
lib/widgets/styled_header_scaffold.dart
```
