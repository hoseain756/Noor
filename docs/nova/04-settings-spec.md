# NOVA settings: audit, architecture and screen specification

## Audit of the inherited implementation

- Settings was a long undifferentiated stack of boxed rows with no search. Language was buried beside an explicitly locked dark/bronze theme. The old brand remained in headers, help and About.
- Tablet layouts merely widened the same list. Controls often reserved a fixed 150 px trailing column, while long Arabic labels and enlarged text competed for the remaining space.
- Add-ons supported URL installation, enabling and removal, but offered no priority reordering or access to a configurable provider's settings. Each row squeezed its switch and delete action into 88 px.
- The integrations page mounted six expanded connection panels at once. This made users scan unrelated OAuth instructions, keys and provider controls. Trakt has two real redirect methods plus a paste-code fallback; Simkl has device-code polling; AniList and MAL have browser OAuth plus paste fallback. These implementations must remain intact.
- Storage inspection swallowed read failures as an empty state. Download deletion and viewing-history deletion in Activity had no confirmation. Sync timestamps sat on a rigid horizontal row.
- Playback already used granular Provider selectors and optimistic switches. Retain that behavior. Existing URL artwork already bounded decode sizes; the new add-on rows retain correctly sized decode requests.
- The app has no notification delivery subsystem. MDBList currently supplies built-in aggregate ratings; there is no personal MDBList OAuth or list-sync implementation. Showing account connection or fake notification switches would misrepresent the build.

## Design system application

Settings uses the shared NOVA Light/Dark ColorScheme exclusively. No custom UI hex colors or alternate icon library are introduced. General icons use Lucide at 18–24 px, with 32 px page-leading symbols. The supplied NOVA launcher asset anchors About.

The visual approach is editorial: a short expressive title, concise practical description, generous 24/32 px section spacing and one calm surface per related control group. Individual rows use separators instead of nested cards. 16/20/24 px padding follows the common spacing system; 24 px group corners and 16 px row corners distinguish hierarchy. Primary actions remain limited to the user's immediate task. Inputs, switches, focus, hover, disabled, error, dialogs and sheets inherit NOVA theme behavior.

Reusable components live in `widgets/settings_tiles.dart`: page introduction, section heading, grouped control surface, direction-aware settings row, semantic information/error banner, optimistic switch/switch row, language dropdown and destructive confirmation helper.

## Information architecture and flows

Settings search indexes English and Arabic category descriptions plus feature keywords. At widths below 1000 logical pixels it is a readable category index with native drill-down routes. At 1000+ it becomes a 340 px category pane beside the selected settings page. Content pages constrain their reading width to 800–900 px and scroll independently. The current category receives a palette-derived selected surface.

Categories: Account & sync; Playback; Subtitles; Downloads & storage; Appearance; Catalog & navigation; Language; Notifications; Privacy & security; Add-ons; Connected services; Kids & parental controls; Viewing activity; About & support. Existing library shortcut remains available when hosted in the main shell.

Key flows:

1. Search settings → relevant category → control → immediate UI update and existing persistence.
2. Add manifest URL → validation → install progress → confirmed result → reorder with drag handle or accessible up/down controls → enable/configure/remove.
3. Choose service → dedicated provider page → existing verified OAuth/device/key flow → connection status → supported automatic-sync controls, manual import or disconnect confirmation.
4. Choose app language → existing `setLanguage` → app-level locale and Directionality update immediately, without restart.
5. Appearance → dark/light/device choice, reduce-motion/transparency flags, or Navigation bar style → the root theme or bottom dock updates live.
6. Kids controls → configure/change parental PIN through `NovaParentalGate.change` → secure parent gate maintained by the shared implementation.

## Screen and state specifications

### Index

Single column below 1000 px; two panes above. Search has clear action and an explicit no-results state. Rows wrap descriptions; no fixed text height. Desktop focus follows visual reading order. Main-shell bottom clearance uses the existing safe-area/dock helper.

### Playback and subtitles

Playback groups: viewing flow, picture/sound, playback controls, stream selection. Subtitle groups: languages, text/style, timing. Every inherited setting remains available, including multi-select speeds/languages, precise sliders and full subtitle color picker. Individual settings retain selective rebuilds. Values sit beneath labels, avoiding a narrow trailing value column. Select sheets have a title, drag handle and bounded viewport; longer content scrolls. Multiple selections and sliders retain save/cancel semantics.

### Appearance and language

Appearance provides Cinema dark, Daylight and Follow device, plus functional reduced-motion/transparency flags and a dedicated Navigation bar style page. Its top preview uses the real five primary tabs and a visible active Anime indicator, and updates as Classic, Compact icons or Mini is highlighted. Selecting an option saves `navigationBarStyle` through the existing settings bucket and updates the phone shell immediately. Classic retains the current glass dock with icon labels; Compact icons hides labels while preserving Classic's shape and spacing; Mini is a narrower, 56 dp-high floating capsule with 48 dp tab targets and at least 24 dp horizontal phone insets. Icon-only choices retain localized tab names in semantics and tooltips. The selector changes only the horizontal dock; the existing tablet side rail at 840 dp and wider remains unchanged for every choice. Language provides native English/Arabic labels and independent provider-content language. Choices apply immediately. Device text scaling is respected rather than clamped.

### Catalog and Kids controls

Home layout, add-on catalog visibility, watched-title filtering, anime/adult filtering, poster badges/titles/radius, episode spoiler blur/layout, library sort and scroll navigation behavior are retained in deliberate groups. The Kids route isolates kids poster sizing and parental PIN management, and explains provider review. Parent gate behavior belongs to the shared app-level gate.

### Add-ons and provider settings

Lazy sliver reorder list, installation progress/error/success, explicit zero-installed state and bounded logo decode. Each item separates its switch from priority controls. Reorder handles support touch/pointer drag; move-up/down buttons provide keyboard/screen-reader-friendly alternatives. Provider detail includes enable state, manifest-copy feedback, declared catalogs and a configuration link only when the manifest advertises `behaviorHints.configurable`. Removal requires confirmation. Configured add-on installation continues using the existing manifest workflow.

### Integrations

Overview groups trackers, metadata/ratings and cloud playback. It shows real connected/disconnected state and routes to dedicated pages. The existing browser redirects, device-code polling, manual code entry, expiry/retry/cancel, avatar/profile stats, verified credential save and manual sync remain available.

Actual automatic controls (all enabled by default to preserve existing behavior):

- Trakt: playback activity (`traktScrobbling`) and watchlist mirroring (`traktWatchlistSync`).
- Simkl: playback activity (`simklScrobbling`).
- AniList/MAL: watchlist mirroring (`anilistWatchlistSync`/`malWatchlistSync`) and automatic episode progress (`anilistProgressSync`/`malProgressSync`).

These controls depend on the corresponding backend guards implemented in AppState/player by the parent workstream. Manual sync and manual tracking edits remain independent. TMDB exposes its existing feature flag and validated personal key; Debrid retains Real-Debrid, AllDebrid and TorBox verification and status. MDBList explicitly describes its current built-in ratings-only integration. Disconnect/key removal requires confirmation and does not delete imported library titles.

### Account, privacy and storage

Account focuses on existing device-based cloud sync and bucket timestamps; it does not invent account authentication. Privacy exposes export/restore, clear-history and clear-library flows. Storage isolates torrent files and automatic temporary-cache reset. Read failures now have a retry state; initial scans show progress. Deleting one/all local downloads requires confirmation. Existing cache reset and backup implementations remain intact.

### Viewing activity

Responsive summary metrics use Wrap with intrinsic height, followed by seven real date buckets derived from history and a lazily built recent timeline (up to 50). Bars have accessible count labels and follow direction. Empty history has an explicit invitation. Clear-history action requires confirmation and explains its Continue Watching effect.

### About and notifications

About uses the supplied brand asset, exact existing build version, license viewer, Harbor attribution and TMDB metadata acknowledgement. Notifications accurately reports the current in-app-feedback behavior; no inoperative push toggles are provided.

## RTL, accessibility and motion

Directional padding and alignment are used for layout. Forward chevrons follow Directionality; media/provider icons do not mirror. Numeric URLs/code inputs remain LTR, preserving provider syntax. Rows are at least 48 px in interactive height; icon buttons retain standard 48 px targets. Values/descriptions wrap, sheet content scrolls, destructive dialogs explicitly identify the effect, and installation results announce as live regions.

Settings does not add ambient animation or any live blur. The navigation preview reuses the production dock in non-interactive, reduced-motion mode and uses theme surfaces. Page navigation, pressed/focus feedback and switch motion use the root NOVA motion/theme contract; reduced-motion settings apply there. This keeps settings inexpensive and readable during long work sessions.

## Added controls and rationale

- Theme mode: both requested visual modes and device preference.
- Reduced motion/transparency: real accessibility and rendering comfort choices.
- Add-on priority: makes provider ordering understandable and controllable.
- Provider configuration access: surfaces options supplied by the actual add-on.
- Per-service automatic-sync controls: gives users control over network writes without changing manual actions.
- Parental PIN management: makes the shared exit gate discoverable.
- Confirmation for storage/history deletion: prevents accidental irreversible loss.
- Settings search, dedicated provider pages and adaptive navigation: reduce scanning and cognitive load.

## Verification status

A scoped `flutter analyze lib/features/settings --no-pub` completed with zero errors. Its three warnings (unused scan-error state and unused dropdown parameters) were corrected afterward; RadioGroup and onReorderItem replaced the deprecated controls identified by that run. The parent workstream performs final combined analysis and tests after all edits.

`test/nova_settings_test.dart` covers search-to-language navigation and live RTL switching, 360 px phone/1200 px tablet layouts at 200% text in both directions, and independent add-on reorder/enable interactions. `test/navigation_bar_style_test.dart` covers five tab targets, visible-label rules, localized semantics/tooltips, mirrored order, minimum touch size, all three styles in Arabic/English and Light/Dark at 200% text, live preview updates and the saved selection across a screen rebuild. These tests do not claim real-device visual or frame-rate verification, and no live provider authorization is attempted during UI testing.
