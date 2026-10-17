# 01 — NOVA UI/UX and performance audit

Audit date: 17 October 2026. Baseline: the repository's `HEAD` before the NOVA work; findings come from source inspection, not measured device profiling. Supplied inputs are `Nova_Brand_Identity.pdf`, `nova_brand_assets.zip` and `nova_colors.dart`. Existing unrelated checkout changes are not attributed to this redesign.

## Executive finding

The inherited app already has substantial functionality: independent add-ons, linked tracking services, native playback, torrent playback, subtitles, lists, live TV, calendar and device-based sync. The redesign should reorganize that functionality around discovery, watching and a personal library. The most important gaps are a dark-only bronze visual system, dispersed bilingual copy, unstructured settings, insufficient Kids boundaries and inconsistent state/layout treatment. Preserve the existing APIs and data formats wherever possible.

## Inventory

Primary areas: Home, Anime, Kids, Library and Settings. Secondary pages: global search, anime search, catalog browser and catalog grid, title details, source selection, calendar, live TV, custom lists, add-on manager, integrations, activity statistics, playback settings, subtitle settings, display settings, storage/privacy and About. Transient surfaces include list picker/edit/delete, anime tracker, provider authorization/code entry, stream resolution, magnet entry/file selection, player subtitle/audio/source/settings panels, color picker, restore backup, destructive confirmations and startup error handling.

There is no separate existing NOVA account login, password, registration or profile-auth backend. The app uses device identity plus provider-specific authorization. Adding a decorative login screen would remove access or imply nonexistent account functionality. Provider auth and device/cloud account settings are the real authentication surfaces to retain and improve.

## Baseline findings

| Area | Observed source evidence | User impact / priority |
|---|---|---|
| Brand/theme | `horse_theme.dart` defines black, greenish surfaces and bronze; `NoorApp` sets only `HorseTheme.dark`; app title and native metadata use Noor. | The supplied NOVA identity and light mode do not exist. High. |
| Type/localization | Theme uses Tajawal only; copy is commonly written as inline `english ? ... : ...`. `MaterialApp` already has Arabic/English delegates and a locale selector. | Preserve existing live switching, centralize all user-facing copy and introduce the brand's Arabic/Latin typography. High. |
| Home | Multiple catalogs and connected-service data already exist; a conventional scrolling hero precedes rails. | Improve hierarchy and implement the requested stationary hero with covering content without fabricating recommendations. High. |
| Details | Director/starring are short text lines; no complete circular cast/crew, production-logo rail or comprehensive conditional fact table. | Metadata lacks hierarchy and people/production context. High. |
| Source picker | Existing stream ranking, compatibility and torrent/Debrid logic are functional and complex. | Preserve selection semantics and make formats/provider information easier to scan. High. |
| Settings | Long boxed list, no settings search, locked dark/bronze appearance, wide layouts remain one list. | Finding controls requires excessive scanning; requested appearance/accessibility controls are unavailable. High. |
| Add-ons | URL install, enable and remove exist. `Addon.order` exists, but no reorder control. Provider configuration is not exposed. | Users cannot manage priority or discover configuration. High. |
| Services | Trakt, Simkl, AniList, MAL, TMDB and Debrid panels are expanded together. OAuth fallbacks, profile stats and key validation already exist. | Connection flows compete visually; preserve the actual flows while separating provider subpages. High. |
| MDBList | Metadata aggregation exists, but personal account/list synchronization does not. | A connect button would be misleading without a new backend. Explicitly describe the available integration. Medium. |
| Kids | Cinemeta family catalogs are displayed without the new explicit certificate allowlist; the shell has no parent-gated tab exit. | Family branding is not a sufficient safety boundary. High. |
| Data safety | Statistics clears history directly. Torrent storage can delete one/all downloads without confirmation, and scan failures are shown as empty. | Accidental loss and misleading feedback. High. |
| Tablet | Existing shell has a secondary navigation panel, but discovery/settings primarily stretch existing layouts. | Weak use of available width and less predictable navigation. Medium. |
| Notifications/downloads | No push-notification subsystem or standalone persistent direct-file download manager exists in HEAD; torrent storage management does exist. | New features must be implemented honestly rather than represented by cosmetic toggles. Medium. |

## Performance: what was already good

Do not credit existing optimizations to the redesign. The inherited app already caches its ThemeData, scopes several Provider reads, uses optimistic settings toggles, has bounded image decode helpers, pauses hero autoplay when inactive and uses Offstage/TickerMode for inactive shell pages. Ratings and featured artwork also have some in-memory caching. These are retained.

## Performance opportunities and changes

| Finding | Redesign change | Verification limit |
|---|---|---|
| All five shell pages are mounted before first visit, even though hidden tickers are muted. | Mount pages on their first visit and preserve visited pages afterward. | Source inspection confirms `_visited`; startup/profile measurements remain required. |
| Public add-on metadata/catalog requests do not have a shared disk-backed stale cache. | Bounded catalog cache with single-flight refresh, disk storage, stale reads and isolate JSON encoding/decoding. Visible pages subscribe to refresh revisions, coalesce rebuilds and defer offstage work. | Cache-coalescing/visible-refresh widget coverage passes; tokenized add-on eligibility and offline latency still need production-data checks. No latency benchmark claimed. |
| Image.network does not provide a shared disk-cache abstraction. | Shared `NovaNetworkImage` wraps a cached provider with bounded decoding, placeholders, failure UI and short fade. | Migration exists across the primary media rails and hero/detail paths; full image-memory measurements still need device profiling. |
| Hero artwork can decode as the slide changes. | Precache the next hero image and isolate artwork in RepaintBoundary. | No device frame-time measurement yet. |
| Large lists/rail content can do unnecessary work. | Sliver/lazy builders for browse, source, add-on, download and activity lists; granular setting controls retained. | Verify realistic long catalogs and low-end devices. |
| Repeated complex glass effects can be costly. | Dock, search chrome and detail pills use palette-derived static surfaces rather than live per-frame BackdropFilter blur. reduceTransparency switches the dock to opaque; reduceMotion and the platform preference disable decorative movement. | Component tests assert no live blur on the shared chrome and preferences have rendering consumers. GPU frame time remains unmeasured. |
| State feedback varies by surface. | Geometry-aware skeletons, explicit retry/empty/error states and foreground progress. | Every modal/state still requires the acceptance matrix. |

No blanket 60 fps or percentage speedup is claimed. Such claims require profile-mode device traces with representative providers, images, scroll gestures and memory pressure.

## Important preservation contracts

- Existing add-on manifest formats, installed entries, enabled state and order must round-trip.
- Trakt direct/relay redirect choices, Simkl device-code polling, AniList/MAL callbacks and manual-code fallback must remain usable.
- Existing bookmarks, custom lists, watch history, resume positions, subtitle settings, IPTV playlists and device sync are retained.
- User-visible naming becomes NOVA. Legacy package IDs, callback schemes and persisted storage keys are compatibility identifiers; renaming them blindly can break upgrades or provider authorization.
- Kids controls must cover navigation, external intents and cold starts, not just the visible exit button.

See `requirements-status.md` for the evidence/acceptance tracker and unresolved checks. The final verification log should supersede this inspection snapshot.
