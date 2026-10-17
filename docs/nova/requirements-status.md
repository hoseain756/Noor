# NOVA requirements and acceptance tracker

Updated: 17 October 2026. The redesign implementation and ordered design documents are in place. This records what has actually been checked; it is not a release certification.

## Verification record

- English and Arabic ARBs each contain 886 messages. Key parity, required-message parity and named-placeholder parity were checked after the final localization additions: zero mismatches.
- Final full analysis (`flutter analyze --no-pub`) completed with **No issues found** (205.8 seconds), including the final navigation and test-harness edits.
- An earlier full serial run had **317 passing and 8 failing tests**. The failures came from outdated test assumptions about compact dock size, Library labels, the Top 10 treatment, eager mounting of hidden pages, and black subtitle outlines. The tests were updated for NOVA's responsive dock, lazy first-visit pages, and palette-derived subtitle color; the edge-to-edge test now also matches the actual test viewport and waits for the dock reveal transition.
- The final full serial run (`flutter test --no-pub --concurrency=1 --reporter=compact`) completed with **325 tests passing and no failures**. Focused verification also passed for browse layouts (13), performance/page lifecycle (6), subtitle styling (20), Top 10 ranking (2), and shell edge-to-edge navigation (1).
- A fresh Android arm64 Release APK was built with `flutter build apk --release --no-pub --target-platform android-arm64`: 95,320,261 bytes, version `1.2.56+60`, SHA-256 `694E850B3326E3CF8F1F0F6F27705E64951A4775692EA6C7DEBCBBBF6DAE7D13`. `aapt` reports application label `NOVA`; `apksigner verify` confirms APK Signature Scheme v2. Kotlin daemon connection retries failed, but Gradle's fallback compilation completed. Flutter also emitted upcoming support warnings for Gradle 8.14, AGP 8.11.1 and Kotlin 2.2.20. `adb devices -l` found no connected device for visual validation. An iOS build requires macOS/Xcode.

## Requirement matrix

| Requirement | Implementation evidence | Acceptance status |
|---|---|---|
| NOVA brand and supplied assets | NOVA wordmark, palette, SVG/native assets, launch screen, About copy, Android label and iOS display name; compatibility IDs remain stable. | Source-checked. Legacy internal class names, callback schemes and storage identifiers are intentionally retained. Native launch screens still need visual device checks. |
| Palette-only Light/Dark and AA | `nova_theme.dart` builds both complete color schemes from supplied palette roles. Contrast calculations are in `02-design-system.md`; glass and pressed states use alpha derivatives. | Key text pairs meet documented AA ratios. Every artwork overlay, disabled state and rendered screen still needs inspection. |
| Arabic/English and instant direction change | 886-key ARB parity, generated `NovaStrings`, live `AppState` locale updates, logical geometry, language controls in onboarding and Settings, Poppins + IBM Plex Sans Arabic. | Settings, browse, detail and player tests exercise both directions; a full every-route/device-language matrix remains pending. |
| Responsive layouts and text scaling | Adaptive phone/tablet shell, settings master/detail, constraint-derived poster grids, wrapping controls, enlarged Arabic line height and scrollable sheets. | Widget coverage includes narrow/large layouts and 200% text for key browse, detail, settings and player paths. Native largest-text and landscape screenshot checks remain pending. |
| Home and details | Pinned cinematic cover behavior, cached hero imagery, cast/crew circles, production logos, conditional fact table before Similar Suggestions, season/episode progress and source selection. | Layout and metadata widget tests pass. Real provider data and on-device scroll/animation quality remain unverified. |
| Kids safety | Explicit certificate allowlist, distinct visual shell, saved card-size preference, local secure PIN, locked-session restoration and gates for navigation/deep-link exits. | Safety logic and responsive browse cases have widget/source coverage. Provider certificate accuracy and cold-start/external-intent device tests remain required. |
| Settings and integrations | Searchable groups, dedicated subpages, add-on URL install/enable/reorder/remove, supported provider controls, storage/download surfaces, reduced-motion and reduced-transparency consumers. | Core search, live language, enlarged-text and add-on interaction tests pass. External OAuth, key validation, sync and disconnect need real accounts. MDBList remains ratings-only; no personal-list connection is fabricated. |
| Remaining screens, sheets and dialogs | Browse, library, lists, calendar, live TV, anime tracker, onboarding, auth/provider flows, source/download selection, player panels, privacy/storage and error/empty/loading states use the shared system. | Source implementation is present; full manual route/state review and complete green regression run remain open. |
| Performance | First-visit shell mounting, inactive ticker muting, lazy slivers, bounded stale cache with refresh subscriptions, isolate parsing, bounded image decoding/cache, hero precache, skeletons, and static glass surfaces replacing repeated blur. Stream-server close now awaits in-flight handlers. | Targeted cache, layout and stream tests cover behavior; profile-mode frame time, image memory and weak-device scroll performance are unmeasured. |
| Accessibility | Lucide-only general UI icons, semantic labels, keyboard activation, 44 dp compact-nav and 48 dp standard control targets, reduced motion/transparency and text scaling. Tab semantics no longer duplicate visible labels. | Selected semantics/layout tests pass; TalkBack/VoiceOver, switch control, focus traversal and high-contrast visual review need device acceptance. |

## Known scope limits

- MDBList currently contributes ratings only; the inspected application has no personal MDBList account/list sync backend.
- Notifications are foreground application feedback, not push or scheduled local delivery.
- Direct downloads support standalone HTTP(S) video files in the foreground; OS background scheduling, ranged resume, HLS/DASH packaging and DRM offline downloads are not claimed.
- The inspected app has no first-party account backend. Device identity and provider-specific authorization remain the actual account flows.
- No measured 60 fps claim is made. The static-glass change removes recurring blur work from shared navigation/search/detail chrome, but only a profile trace can quantify the gain.

## Remaining release acceptance

| Area | Required check |
|---|---|
| Build | Android analysis and arm64 Release APK are verified. Run an iOS build on macOS/Xcode and perform an on-device install/launch check. |
| Regression | The current full serial suite passes all 325 tests. Rerun after future code changes; preserve file/test names if a failure occurs. |
| Visual | Capture Home, Details, Settings, Kids, Library, Search, Downloads and player at phone/tablet portrait/landscape in Arabic/English and Light/Dark. |
| Providers | Exercise each supported OAuth/device/key flow, expired token, sync toggle, manual sync and disconnect with real or provider sandbox accounts. |
| Safety/playback | Verify Kids PIN failures, restored session, back/tab/deep-link exits, then test direct, Debrid and torrent playback, resume, subtitles and next episode. |
| Performance/accessibility | Profile warm/cold launches, hero/rail scrolling and image memory on lower-end Android hardware; test TalkBack/VoiceOver, keyboard/controller and 200% native text. |
