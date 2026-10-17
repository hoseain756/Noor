# NOVA requirements and acceptance tracker

Date: 17 October 2026. This is a source-inspection and verification checklist, not a release certification. The root workstream is still applying the final localization/theme migration and must update outcomes after the consolidated tests. “Implemented in source” does not imply on-device visual or live-provider verification.

## Status vocabulary

- **Implemented in source**: inspected code provides the behavior; final checks are still necessary.
- **Partial / bounded**: a usable implementation exists, but the requirement includes behavior beyond its supported scope.
- **Verification pending**: a concrete acceptance check has not yet been run or recorded.
- **Follow-up finding**: a missing path found during this audit and reported to the root workstream for repair; re-inspect before final delivery.

## Requirement matrix

| Requirement | Current evidence | Status / acceptance still needed |
|---|---|---|
| NOVA brand and supplied assets | Native label/icon changes, `NovaBrand`, supplied assets copied under assets/brand, NOVA startup and About. | Implemented in source; sweep user-visible old names and inspect Android light/night plus iOS launch screens. Legacy protocol/storage IDs may intentionally remain. |
| Palette-only Light and Dark | `nova_theme.dart` builds both themes from supplied palette roles; dynamic ThemeData selection in NovaApp. | Implemented in source; final whole-app hardcoded-color sweep and visual check of both themes. |
| WCAG AA | Semantic text/control roles exist, with separate readable dark/light accents. | Verification pending: record calculated contrast pairs and rendered overlays/disabled semantics. Do not claim universal AA from the palette alone. |
| Arabic/English strings in localization | ARB/message generator and NovaStrings delegate are present; root extraction is in progress. | Verification pending: no surviving UI inline text/ternary pairs, placeholder consistency, correct Arabic encoding and generated-file freshness. |
| Instant RTL/LTR | Existing setLanguage notifies before persistence; app locale/Directionality are rebuilt; onboarding and settings selectors exist. | Implemented in source; widget test plus every-page/device-direction matrix pending. |
| Device language on first launch | AppState derives first-launch language from PlatformDispatcher when no preference exists. | Implemented in source; verify fresh Arabic/non-Arabic install and upgrades with saved preference. |
| Logical geometry and mirrored controls | New layouts use logical insets/alignment; page chevrons follow Directionality. | Verification pending: source sweep, rails, gestures, sliders, transition direction, mixed-direction content. Universal media icons must remain unmirrored. |
| Typography and text expansion | Bundled Poppins/IBM Plex Sans Arabic, taller Arabic line height, intrinsic settings rows, wrapped actions. | Implemented in source; 200% tests and native accessibility font sizes pending. |
| Responsive mobile/tablet | Shell side navigation at 840+, settings two-pane at 1000+, adaptive grids/wraps. | Implemented in source; phone/tablet portrait/landscape screenshots and interaction checks pending. |
| Home full-width pinned hero | Shared CinematicCoverScroll translates artwork against scroll while opaque content covers it. | Implemented in source; scroll screenshot/profile checks and restored scroll positions pending. |
| Details pinned hero / cast / production / fact table | DetailHero, circular cast/crew, production rail, conditional fact table immediately before Similar Suggestions. | Implemented in source; real movies/series/anime metadata, missing-data and text-scale checks pending. |
| Episodes and source selection | Season/episode layouts, progress, explicit source picker and existing resolution engines retained. | Implemented in source; source selection, resume, long seasons, no-stream/error and player regression tests pending. |
| Kids visual design and filtered content | Distinct header/large controls; explicit family-rating allowlist; Kids context passed to detail/similar titles. | Implemented in source; provider-certificate accuracy and filtering tests pending. Unrated content intentionally hidden. |
| Parent PIN exit protection | Secure local PIN gate; shell tab/back/secondary navigation checks; failed-attempt handling. | Follow-up findings: cold-start Kids persistence, incoming magnet intent gate and outbound detail actions were reported to root; re-inspect repairs. |
| Kids card-size preference preservation | Setting remains available. | Follow-up finding: new Kids grid did not yet consume kidsCardSize at inspection; restore functional mapping. |
| Glass navigation concept | Existing floating dock retained, contrast/labels/targets updated, tablet navigation added. | Implemented in source; safe areas, gesture zones, scroll hysteresis, keyboard and 200% text checks pending. |
| All remaining pages/sheets/dialogs radically redesigned | Browse/search/library/lists/calendar/live TV/anime tracker/settings received structural updates. | Partial at inspection: magnet entry/file flow and player sheet/control layouts still needed a focused structural pass; a global color/icon replacement alone does not satisfy this request. |
| Settings IA/search | Searchable groups and dedicated category pages; tablet master/detail. | Implemented in source; search/navigation and enlarged text tests supplied. |
| Add-on manager | URL validation/install, state feedback, enable/remove, sliver reorder, accessible move buttons, provider configuration link. | Implemented in source; real manifests, configured reinstallation and order persistence tests pending. |
| Every linked service settings | Dedicated Trakt/Simkl/AniList/MAL/TMDB/Debrid pages preserve real flows; actual automatic-sync switches added. | Implemented for supported APIs; live OAuth/key validation, token expiry, sync flags and disconnect checks pending. |
| MDBList personal connection | Existing backend only supplies ratings. | Partial / bounded: accurately labeled ratings-only; personal MDBList lists/account connection is not implemented. |
| Notifications | Real foreground app feedback is described. | Partial / bounded: no push/local notification delivery subsystem or delivery toggles. |
| Downloads | Direct-file queue, secure source storage, foreground progress, retry/cancel/remove and offline playback added; torrent file management retained. | Partial / bounded: foreground only; no OS background scheduling, ranged resume or HLS/DASH/DRM offline packaging. Real file and interruption tests pending. |
| Unified storage visibility | Torrent storage/cache settings exist; direct downloads have their own page. | Follow-up finding: direct-download entry/usage should also be exposed in Storage so all managed disk usage is discoverable. |
| API/add-on cached instant display | CatalogResponseCache supplies bounded disk/memory stale reads with single-flight background refresh. | Partial at inspection: no UI subscriber consumed cache revision, so visible stale FutureBuilders did not yet repaint on refresh. Eligibility also needs care for tokenized add-on URLs. |
| Image sizing/cache/skeletons | Shared cached image wrapper, decode bounds, fallback/placeholder/fade; hero precaching. | Implemented in source; migration coverage, image memory and low-bandwidth rendering checks pending. |
| Granular state/lazy lists | Existing selectors retained; new first-visit shell pages and lazy browse/source/add-on/activity/download lists. | Implemented in source; no benchmark or 60 fps measurement yet. |
| Reduced motion/transparency | App-level reduced motion is wired through MediaQuery; settings expose both flags. | Motion implemented in source. Follow-up finding: transparency had no consumer at inspection; root must wire it to chrome rendering. |
| Every state and accessibility | Themed controls, confirmations, many explicit empty/error/skeleton states and semantic labels added. | Verification pending for every surface: screen reader, keyboard/focus, min 44 px target, loading/error/empty/success states and high text scale. |
| Existing functionality preserved | Existing settings keys and provider/player/add-on implementations retained; compatibility identifiers preserved. | Regression suite and manual workflow checks pending; known inert Kids preference reported above. |

## Tests prepared

- `nova_settings_test.dart`: search → language page → live RTL; mobile 360 and tablet 1200 at 200% text in both directions across settings categories; scroll overflow checks; independent add-on reorder/enable.
- `nova_cinematic_layout_test.dart`: hero/detail layout contracts; inspect final test output for actual coverage and pass count.
- `nova_cinematic_metadata_test.dart`: metadata adaptation contracts; inspect final test output.
- Existing native/player/OAuth/library/add-on tests should be run as the final regression suite. Do not treat newly added widget tests as coverage for remote authorization or real video playback.

A scoped settings analysis completed with zero errors before the global migration. It reported warnings/deprecations that were subsequently repaired. The final whole-app analyzer/build/test results must be recorded separately; they supersede that intermediate result.

## Required manual acceptance matrix

| Dimension | Minimum scenarios |
|---|---|
| Layout | Narrow phone, large phone, tablet; portrait and landscape; split-screen where supported. |
| Language | Arabic and English on every page, sheet and dialog; change language while a route remains open. |
| Appearance | Dark/light/device; focus/pressed/disabled; imagery with bright/dark backgrounds. |
| Accessibility | 200% text and native largest text; screen reader order/labels; keyboard/switch input; reduced motion/transparency. |
| Data/network | Empty install, populated library, slow/offline network, one failed add-on, malformed manifests, stale cache refresh. |
| Kids | Entry/PIN creation, wrong PIN/lockout/cancel, back/tab/secondary exits, app restart, deep links, external/share actions. |
| Playback | Movie/series/anime; direct/Debrid/torrent; resume; audio/subtitles; portrait/landscape; next episode. |
| Services | Each real provider connect/fallback/cancel/expired token/manual sync/automatic-sync toggle/disconnect. |
| Downloads | Direct file success, invalid/playlist source, cancellation, deletion, app interruption/retry, completed offline playback and storage visibility. |
| Performance | Profile-mode warm/cold launch, hero/rail scrolling and image memory on lower-end hardware. |

## Reporting rule

Update this tracker with actual outcomes and artifact paths after verification. Do not replace “pending” with “passed” based on code inspection, a successful compile, or a generic claim that the redesign is complete.
