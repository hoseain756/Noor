# NOVA cinematic pages: audit and implementation

## Findings

- Home waited for three independent catalogs before showing any hero artwork; one slow provider delayed first content. The hero disappeared with page scroll. Carousel pagination had tiny visual targets, and no visible title fallback when a logo was unavailable.
- Phone detail artwork was an inset rounded card, unlike the required edge-to-edge cinematic view. Cast and crew were compressed into two text lines. The model discarded provider portraits, roles and production metadata. Important actions were hidden behind an unlabeled menu.
- Detail synopsis was truncated on tablets without an expansion control. Metadata was a single horizontal line. Source loading used a blank spinner; sources were dense, and refresh failures were indistinguishable from an empty catalog.
- The prior Top 10 deliberately imitated another service's overlapping outlined number composition. NOVA now has a simpler editorial rank, consistent poster ratio, and readable title.

## Page structure and flows

Home: full-width spotlight carousel → category shortcuts → continue watching → personalized recommendations → Top 10 → trend/anime/provider/new-release rails → connected-service rails. Existing addon and linked-library data paths remain active. Classic Home remains an alternate editorial introduction.

Details: full-width artwork and title → wrapping metadata → primary playback, watchlist, share, download and more actions → provider ratings → complete synopsis → seasons/episodes → circular cast and crew → production logos → two-column facts table → similar suggestions. Facts are filtered to available fields and type. Episodes/seasons appear only for series; runtime appears for movies. No portraits, company marks, or facts are fabricated.

Playback: title/episode → source selection → optional torrent/debrid preparation → existing player. Downloads: title download action → direct source selection → DownloadManager queue. Source headers are normalized through the existing PlaybackSource parser. Adaptive playlists and unsupported torrent offline jobs are not advertised as file downloads.

Kids detail routes carry a kidsMode flag into similar-title navigation. Similar titles require explicit certification in the same allowlist as Kids: G, PG, TV-Y, TV-Y7, TV-G, TV-PG, U, 0, 6, 7. Unknown and adult ratings are withheld. Download actions are omitted inside Kids.

## Responsive specification

- Phones below 700 logical pixels: full-width hero; 24px content gutters; actions wrap at their intrinsic size; 2:3 posters; metadata wraps; source controls and results share one sliver scroll view.
- Tablets at 700px+: 40px gutters, landscape hero artwork, spacious synopsis, adaptive episode grids. Source selection at 840px+ separates a 320px filter/context column from the result list.
- Landscape phone hero has a 420px readability floor. The page can scroll naturally when its viewport is short. Hero height expands with text scaling.
- At 200% text scale episode rows stack thumbnail above text. Cast rails reserve additional height; production captions and facts table grow. Labels use directional padding/alignment. Carousel previous/next and swipe direction mirror, while play and brand artwork remain universal.

## Components, states and motion

CinematicCoverScroll translates only the hero against scroll offset. Later opaque slivers cover it. A RepaintBoundary isolates artwork from scroll content. Reduced motion disables the 2.5% scale and 18% fade; the stationary cover behavior remains. No backdrop blur is added.

Featured transitions: 380ms easeOutCubic; artwork fade 320ms; carousel interval 6 seconds; interaction pauses autoplay for 8 seconds. Autoplay pauses for app inactivity, inactive tabs, and reduced motion. Explicit previous/next buttons and watchlist/play controls have at least 48px targets. One upcoming image is precached at its actual decode width.

Sources: immediate row skeletons; retained previous results during refresh; retry action for failed loaders; distinct no-source and no-filter-match states. Sorting, addon, quality and kind filters remain. Production image failures use a Lucide clapperboard; people image failures use initials; metadata absence removes its row.

## Data and performance

- First nonempty featured catalog now wins instead of waiting for all catalog futures.
- Provider metadata now persists typed people and production fields through JSON, artwork copies and anime-identity copies.
- Existing TMDB artwork detail data is reused for production and facts. Credits are fetched only when a detail page opens, avoiding large cast payloads for every Home slide. Enrichment is optional; warm addon detail renders first.
- Episodes and source results remain lazy slivers; no nested episode scrolling or shrink-wrapped long lists. Source facts are parsed once per response.
- Source failure retains previously loaded choices, and warm title information remains readable if metadata refresh fails.

## Verification

Focused tests are in test/nova_cinematic_layout_test.dart and test/nova_cinematic_metadata_test.dart. They cover model preservation/fallbacks, phone/tablet Light/Dark RTL/LTR at 200% text, and stationary hero geometry while the body scrolls. Final execution results are tracked by the parent integration pass. Device GPU frame timing and live provider artwork are not asserted by widget tests.
