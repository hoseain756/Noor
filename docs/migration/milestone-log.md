# Flutter migration milestone log

Updated: 2026-10-13

Completed milestones and their evidence are recorded here as work progresses.
The log records repository state separately from implementation and verification
results so existing local work remains attributable.

## Milestone 1 — Repository synchronization and baseline audit

Status: complete.

- Working repository: `C:/Users/hosea/OneDrive/Desktop/app/Horse`.
- Flutter delivery directory: `mobile_app/`.
- GitHub remote: `https://github.com/hoseain756/Horse.git`.
- Latest fetched mobile branch: `origin/flutter-mobile` at `72409ed` (`v1.0.0`).
- Local delivery branch: `flutter-mobile` at `9e604a6`, eight commits ahead of
  `origin/flutter-mobile`; the remote commit is an ancestor of the local head.
  No upstream mobile commits were missing, so no merge or reset was needed.
- Website source branch: `origin/main` at `428d4f4`; it is part of the same
  repository and is the source audited for the feature matrix.
- Existing user changes were preserved: modified Dart files, root `.vscode/`,
  root `docs/1.png`–`4.png`, and `mobile_app/docs/` references remain untouched.
- Environment: Flutter `3.44.0-0.2.pre` (beta), Dart `3.12.0`.
- Baseline `flutter analyze lib --no-pub`: passed, “No issues found” (126.5 s).
- Baseline `flutter build apk --release`: passed in 661.8 s; Flutter reported a
  56.0 MB `build/app/outputs/flutter-apk/app-release.apk`. Gradle logged Kotlin
  daemon connection retries and then completed the build. The existing Android
  setup also warns that its Kotlin Gradle Plugin integration will need migration
  in a future Flutter release. Artifact package/signature inspection is pending.

## Milestone 2 — Website feature inventory and reference review

Status: source inventory and screenshot review complete; parity gaps are listed.

- Website shell routes and cross-cutting actions are recorded in
  `feature-parity-matrix.md` against `origin/main`.
- The eight supplied screenshots are summarized in `design-reference.md`.
- Backend paths were traced to the existing `src/app/api/` handlers, including
  sync, TMDB, IPTV proxy and device pairing. Provider flows were not called
  with credentials during this work.
- The matrix separates code presence, automated test evidence and real device
  or service verification. Remaining parity gaps are enumerated at its end.

## Milestone 3 — Mobile migration and responsive navigation

Status: implementation pass complete; remaining parity gaps documented.

- Added native Discover, Movies, Shows and add-on Catalog browser surfaces;
  the phone bottom dock remains in place and tablet secondary navigation is
  collapsed by default.
- Added Live TV M3U playlists, group/search filters, optional XMLTV guide and
  channel playback. Playlist URLs are migrated from plaintext preferences to
  secure storage and excluded from backups/cloud sync because they may contain
  provider credentials.
- Added a native weekly schedule from tracked Cinemeta series episodes and the
  website's AniList airing query through `/api/anilist`; airing titles are
  resolved to playable Cinemeta IDs before opening details. The separate
  Cinemeta new-release discovery rail remains open.
- Added TMDB rating/recommendation rails with native title resolution, secure
  TMDB key validation/storage, custom lists with sync/share/import flows, and
  short-code device pairing for saved TMDB/Debrid keys.
- Added parser, custom-list, responsive-layout and tablet-navigation tests.
  Responsive testing found and fixed narrow-phone overflows in the poster grid,
  list creation dialog and library tab labels.
- Full Wrapped achievements, global keyboard/TV navigation, complete
  per-setting parity, and live service/device acceptance remain outstanding;
  see the parity matrix.

## Milestone 4 — Final analysis, tests, APK and platform report

Status: source checks, final APK verification and emulator launch smoke passed;
physical-device and iOS acceptance unavailable.

- Latest `flutter analyze lib --no-pub`: passed, “No issues found” (15.4 s).
- Latest `flutter test --reporter compact`: all 134 tests passed (about 40 s).
- A focused responsive suite passed for home, anime, kids and library screens
  across phone, tablet and desktop widths in RTL and LTR.
- `git diff --check` reported no whitespace errors; Git only warned that its
  configured checkout may normalize LF line endings to CRLF.
- Final `flutter build apk --release`: passed in 182.5 s. APK path:
  `build/app/outputs/flutter-apk/app-release.apk`, 59,791,932 bytes
  (57.0 MiB); SHA-256 is
  `1F93BC24EC77CA60F7A404AF00C5240635A00D8294838CF2C61969E50D26D407`.
- `aapt dump badging`: package `app.horse.mobile`, version `1.0.0` (code 1),
  minimum SDK 24, target SDK 36, application label `Horse`.
- Final APK `apksigner verify`: signature verified with the v2 scheme. The
  certificate is Android Debug, as documented in `README.md`; this is an
  installable development artifact and is not ready for store publication.
- Started the configured Pixel 5 Android emulator after the initial device
  inventory, installed the final APK with ADB, and resolved `app.horse.mobile`
  to `MainActivity`. The app process was running and its activity was resumed;
  the captured home screen rendered the featured title and phone navigation,
  with no fatal exception in the inspected logcat window. Physical-phone
  playback and provider flows remain unverified.
- iOS could not be built because this host is Windows and has no Xcode
  toolchain.
- The release build warns that the app and current Android plugins use Kotlin
  Gradle Plugin integration scheduled for a future Flutter migration. The
  warning did not block this build.
- Final `git diff --check`: passed. Existing local changes were preserved;
  no commit, push, pull request or release was created.

## Milestone 5 — Home hero and bottom dock repair

Status: implementation and automated verification complete; device preview
omitted per user instruction.

- Resized the featured hero and its loading placeholder together to about 64%
  of viewport height, capped at 640 px and constrained by available safe space.
  This keeps the artwork, call to action and page indicators in the first view
  without letting the hero occupy nearly the whole page.
- Anchored the four-icon glass dock to the shell's bottom edge with safe-area
  clearance, matching the supplied reference's Settings, Kids, Anime and Home
  visual order. Reduced unused end-of-home scroll padding from 132 to 24 px.
- Kept Library reachable through a new Library shortcut in Settings after
  matching the reference's four-destination dock.
- Geometry tests cover phone, tablet and desktop widths in RTL and LTR, check
  hero height and dock placement, and verify all four tab names remain exposed
  to accessibility semantics. Verification for this milestone passed all 134
  Flutter tests; `flutter analyze lib --no-pub` reported no issues.
- `flutter build apk --release` succeeded; the current APK is
  `build/app/outputs/flutter-apk/app-release.apk` (59,791,984 bytes, 57.0 MiB).
- Per the user's instruction, no emulator-based app check or screenshot was
  performed. A startup attempt began just before the instruction arrived and
  was interrupted; no APK was installed or inspected on the emulator.
- Existing local work remains uncommitted and preserved.

## Milestone 6 — Home hero, floating navigation and responsive rails

Status: implementation, analyzer and Android release build complete; no
emulator used, per user instruction.

- Matched the Flutter hero's slide pool to the web homepage: the first three
  entries from Trending Movies, In Theaters and Trending Series, capped at
  eight slides. Kept Top 10 as its own separately ranked catalog.
- Enriched hero slides with localized TMDB transparent logos and textless
  artwork, with catalog artwork fallbacks. Removed the title text fallback as
  requested. Reduced the details action, added six-second automatic rotation,
  swipe navigation and tappable page indicators, and respected reduced motion,
  app lifecycle and the selected tab.
- Changed the phone dock to overlay the full-height page content with safe-area
  clearance. Added local scroll-end insets so the floating dock does not cover
  the last content on Home, Anime, Kids, Library or Settings.
- Matched the Top 10 outline rank baseline and bottom offset to the web poster
  strip so the number appears behind the card. Made poster-rail and section
  spacing respond to viewport width; removing poster titles also removes their
  gap and reserved text height.
- Updated `design-reference.md` to describe the logo-led hero and its controls.
- `dart format` completed for the changed Dart sources. `flutter analyze lib
  --no-pub` passed with no issues. `git diff --check` passed; Git reported only
  its existing LF-to-CRLF normalization notices.
- `flutter build apk --release` passed in 317.8 seconds. APK:
  `build/app/outputs/flutter-apk/app-release.apk` (59,841,080 bytes / 57.1 MiB),
  SHA-256 `89A84127125395D8889FCEBEE1EC917AA777F4D4B034F58667CC70025E980184`.
- No tests were run, and no emulator or device preview was used. Existing local
  changes were preserved; no commit or push was created.

## Milestone 7 — Environment-backed service connections

Status: mobile integration status is connected to Horse server APIs; Flutter
analysis, Android release build, and the changed route's lint check passed.

- Matched the environment variables in the supplied reference to existing
  Horse server routes and documented which settings belong on the server and
  which per-user credentials stay in device secure storage.
- Added a status panel to Settings → Connected services. It reads database
  health/RLS, TMDB, Trakt, Simkl, Resend, OMDb, MDBList, and torrent-engine
  readiness from the Horse API. The panel displays statuses only and does not
  expose keys, connection strings, internal engine addresses, or raw errors.
- Extended `/api/integrations/status` with a boolean Resend readiness value so
  the mobile client can show password-recovery email configuration.
- The Supabase Postgres URLs remain server-only: runtime API connections use
  the transaction pooler, while the migration URL is reserved for deployment
  migrations. The Flutter app does not connect directly to Postgres.
- `flutter analyze lib --no-pub`: passed, “No issues found”. Targeted ESLint for
  `/api/integrations/status`: passed. `git diff --check`: passed (Git printed
  only its configured LF-to-CRLF normalization notices).
- `flutter build apk --release`: passed in 231.7 seconds. APK:
  `build/app/outputs/flutter-apk/app-release.apk` (59,841,556 bytes / 57.1 MiB),
  SHA-256 `73D2413486D97630C607EBE1151AA69AF64588FDCE3AA967C5191B464DFE3241`.
- Read-only status check of the configured production server found TMDB,
  Trakt, and Simkl configured; OMDb and MDBList absent; torrent mode `none`;
  database authentication rejected and zero public tables reported. The live
  endpoint predates the new Resend status field, so email readiness is unknown
  until this route is deployed. Correcting Vercel credentials/deploying is
  outside this code change; no production variables were changed.
- A direct metadata-only connection check using the supplied database URLs was
  blocked by Node Postgres certificate validation (`SELF_SIGNED_CERT_IN_CHAIN`).
  Certificate checks were not disabled, so those local values remain unverified.
- No tests or emulator were used. Existing local changes were preserved; no
  commit, push, or deployment was created.

## Milestone 8 — Compact fixed-content Home hero

Status: implementation, Flutter analysis and Android release build complete;
no tests or emulator used.

- Reduced the phone hero to about 45% of viewport height (320–440 px when
  available), with a proportional 48% layout on wider screens. Removed the
  optional synopsis from the hero to keep the next home rows closer to view.
- Separated the changing cover from the fixed hero layout. Only the background
  crossfades every six seconds; the logo, year, localized genre, media type,
  details button and indicators keep their positions. Swipes and indicator
  taps still change the active title, and the details action follows it.
- Kept the foreground and loading skeleton dimensions aligned, and let the
  metadata row grow with system text scaling while truncating long genres.
- `dart format lib/features/home/home_page.dart`: passed (no formatting changes
  required). `flutter analyze lib --no-pub`: passed, “No issues found”.
- `flutter build apk --release`: passed in 175.0 seconds. APK:
  `build/app/outputs/flutter-apk/app-release.apk` (59,825,172 bytes / 57.1 MiB),
  SHA-256 `63C14DA55841F2D3D22B8F6D10384736AED2E714949EDAF5CE267BF5D929FAAF`.
- `git diff --check`: passed; Git printed only its configured LF-to-CRLF
  normalization notices. No emulator/device preview or tests were run, per the
  user's instruction and current task scope. Existing local changes were
  preserved; no commit or push was created.

## Milestone 9 — Immersive Flutter video player

Status: player implementation, responsive timeline tests, Flutter analysis and
Android release build complete. Native device playback and iOS build were not
verified in this Windows session.

- Evaluated the existing `video_player` path against upstream mpv/libmpv
  documentation. Kept `video_player ^2.11.1`, which already wraps the native
  Android and iOS playback backends and preserves signed sources, resume/history,
  external subtitles and episode flow. The evidence and platform caveats are in
  `player-engine-decision.md`.
- Reworked the player surface around the video with safe-area-aware top, center
  and bottom control groups, light fades, reduced-motion-aware control fading,
  landscape/fullscreen behavior, buffering feedback, and compact/capped layouts.
- Connected play/pause, configurable seek steps, double-tap and horizontal drag
  seeking, mute/volume, speed, video fit, subtitles, and fullscreen to the
  existing controller/settings. The timeline previews before seeking, renders
  the controller's buffered ranges, keeps time and progress left-to-right in
  Arabic RTL, and remains keyboard/semantics accessible through its Slider.
- Added previous/next episode controls and an episode picker when catalog data
  permits. Stream resolution and signing use the existing app path; playback
  progress and scrobbling continue to honor `recordProgress`, including across
  automatic episode replacement. Lifecycle pause/resume and orientation cleanup
  are handled by the player route.
- Added `test/player_timeline_test.dart`. It passed at 360, 390, 480, 768, 834,
  1024 and 1280 logical pixels in both RTL and LTR; drag preview/commit also
  passed. `flutter analyze lib --no-pub`: passed, no issues.
- Full `flutter test --reporter compact`: 134 passed, 3 failed. Failures are in
  the unrelated Home/Top 10 responsive test in RTL and LTR (existing card/hero
  layout overflow, followed by its PageView assertion) and the shell auto-hide
  test (a pending 150 ms Home artwork timer). The focused player timeline test
  passed after the final code changes.
- `flutter build apk --release`: passed. APK:
  `build/app/outputs/flutter-apk/app-release.apk` (59,940,640 bytes / 57.2 MiB),
  SHA-256 `A1C6EF3328691E42136FF123777E020718C9BF20BDC3325FA73FE7A42C18EFAF`.
  Gradle warned that the app and Android plugins still use Kotlin Gradle Plugin
  integration scheduled for future Flutter migration; this did not block the
  build.
- `git diff --check`: passed; only configured LF-to-CRLF notices appeared.
  No iOS build was available because this Windows host has no `xcodebuild`.
  Per the user's instruction, no emulator was used; no physical device playback
  or screenshots were claimed. Existing local work was preserved; no commit,
  push or dependency change was made.


## Milestone 10 — Full-width Home hero artwork

Status: implementation, Flutter analysis and Android release build complete.

- Fixed the narrow portrait strip in the Home hero. `AnimatedSwitcher` could lay
  out the background image at its intrinsic size, leaving black space at both
  sides. The artwork now expands to the full hero bounds and `BoxFit.cover`
  crops it to the viewport; logo, metadata, details action and slide indicators
  keep their existing layout.
- `dart format lib/features/home/home_page.dart`: passed (no changes needed).
  `flutter analyze lib --no-pub`: passed, “No issues found”.
- `flutter build apk --release`: passed in 79 seconds. APK:
  `build/app/outputs/flutter-apk/app-release.apk` (59,940,640 bytes / 57.2 MiB),
  SHA-256 `E5F9CDE20A40FF3BD008EAB4C55D7F30A86DD7A5E6EABE9DA5E72CA88E026141`.
- `git diff --check`: passed; Git printed only configured LF-to-CRLF notices.
  No emulator or tests were used, per the user's instruction and current task
  scope. A physical-device screenshot was not captured.

## Milestone 11 — Publish only the Flutter mobile app

Status: GitHub `Noor/main` now publishes only the `mobile_app/` directory.

- Replaced the previous whole-repository snapshot on `Noor/main` with an
  independent snapshot whose repository root contains only `mobile_app/`.
  This removes the web app, root documentation and previous broad snapshot from
  the branch's visible history.
- Kept the complete local Horse checkout intact; this change affects the remote
  `Noor` repository only.

## Milestone 12 — Flatten repository layout (app at root)

Status: GitHub `Noor/main` root IS the Flutter project.

- All previously `mobile_app/`-nested files (lib/, android/, ios/, docs/,
  pubspec.yaml, analysis_options.yaml, README.md, .gitignore, .metadata) now
  live at the repository root; the `mobile_app/` directory is gone.
- Historical documents in `docs/migration/` keep their original
  `mobile_app/...` paths as written at the time; paths are pre-restructure.
- Build instructions: clone, `flutter pub get`, `flutter run` from the root.
