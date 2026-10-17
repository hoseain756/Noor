# NOVA motion, direction and accessibility

## Motion system implemented

NOVA defines 120 ms press feedback, 180 ms state changes and 240 ms route/state transition tokens using easeOutCubic. The retained floating dock has its own deliberate interaction timing: a 350 ms cubic(0.2, 0, 0, 1) sliding indicator, 150 ms press/scrub feedback and 200 ms initial indicator appearance. Phone shell chrome fades in or out over 220 ms. Existing dock scrub navigation commits one selection on release and preserves haptic feedback.

Home and Details place a full-width hero in a stationary translated sliver. Content scrolls over the artwork. As it is covered, the hero scales down by at most 2.5% and fades by at most 18%; only the transform observes the scroll controller, and the artwork is a RepaintBoundary child. Reduced motion keeps scale and opacity stable. Featured hero artwork uses an easeOutCubic cross-fade, with a 6-second autoplay interval and an 8-second pause after interaction. Inactive Home, background app lifecycle and reduced-motion state stop autoplay.

Static browse skeletons intentionally do not run an endless shimmer. Visited-but-hidden shell tabs keep their state while TickerMode disables their animations. Newly visited tabs mount lazily, so initial navigation does not request all catalogs. The dock uses one static glass-tinted fill; reduceTransparency changes that fill to opaque. It does not apply a backdrop blur to scrolling content.

Cached catalog refreshes use a 300 ms debounce. Refresh events are emitted for stale background refresh, coalesced and applied only to an active, current route. Hidden tabs defer their refresh until visible. Existing scroll controllers and page elements remain mounted so background data updates do not reset reading position. Search uses a 350 ms typing debounce and request-generation checks; clearing the field prevents old responses from appearing.

## Direction and typography

Language changes rebuild the root locale and Directionality without a restart. Arabic uses IBM Plex Sans Arabic; Latin uses Poppins, with the complementary family as fallback. Theme text height adds breathing room for Arabic. The typography system spans 11–48 logical pixels and preserves platform text scaling.

Primary navigation supplies one logical destination order in both languages: Home, Anime, Kids, Library, Settings. Flutter Directionality places Home at the start edge. Tablet side navigation also follows the start edge. Start/end padding and positioned controls are direction-aware. Search fields follow the active language; URL fields use LTR to keep their values legible. Calendar dates and times use MaterialLocalizations. Calendar week arrows and disclosure chevrons mirror. Universal play, checkmark and brand assets are not mirrored. Progress bars and sliders inherit the active direction.

Browse headings and action groups size themselves from their content. Narrow layouts wrap actions and filters into additional rows. Poster grids derive card width from actual constraints and add scaled text space instead of stretching one fixed mobile layout. Phone-to-tablet breakpoints differ by component: browsing artwork/copy splits at 640 dp of content width, editorial actions sit alongside at 680 dp, persistent navigation begins at 840 dp, and expanded side navigation begins at 1200 dp.

## Interaction and feedback

The shared button system sets a minimum 48×48 dp target. The floating dock reserves at least 60 dp height per destination, includes visible labels, selected semantics, full accessible labels and keyboard activation. Narrow labels may ellipsize visually while semantics retains their full name. Tablet navigation is always available. Phone auto-hide is disabled in Kids, on tablets and when accessibleNavigation is enabled. Floating global search is restricted to Home on phones, avoiding overlap with Anime and Library editorial headers; those pages expose their own search affordances.

Inputs have visible focused borders, labels/helper text and multiline validation errors. Network-driven screens distinguish loading, empty results and failure with an actionable retry. Collection and playlist deletion ask for confirmation; quick collection/watchlist removals provide Undo. Anime tracker preload failure prevents editing unknown remote progress and offers retry. Modal contents scroll above persistent tracker actions; list pickers show existing membership and can create a first collection.

Kids requires an explicitly allowlisted family certificate. A Family genre alone does not establish safety. Unknown ratings stay hidden. Entering requires a configured parent PIN, leaving requires verification, and the active Kids restriction persists locally across restart. Global search is unavailable in Kids and child detail routes carry their restriction into recommendations. This describes the implemented navigation safeguards; catalogue age-rating accuracy still depends on its provider metadata.

## Contrast and verification boundaries

Palette foreground roles must be chosen for their actual surface. The main D13B47 brand red is appropriate for white-labelled filled buttons but fails 4.5:1 for small text on several NOVA surfaces: approximately 3.88:1 against ink, 3.29:1 against graphite, 2.84:1 against surfaceHigh and 4.39:1 against lightBackground. Small foreground accents therefore use the theme's secondary role (redSoft in dark mode, lightAccent in light mode). Primary-container backgrounds keep their separately selected onPrimaryContainer foreground. Token contrast checks are necessary; a screen containing artwork or overlays still requires visual inspection.

The new browse test suite checks explicit age-rating exclusions, dock logical/physical mirroring, minimum dock sizing, Library layout at 320 and 900 dp with 200% text in RTL/LTR and Light/Dark, stale search-response invalidation, and cache-refresh coalescing/deferred updates without scroll reset. The existing shell test now checks lazy first mounting while retaining edge-to-edge Home and safe-area assertions. Cinematic and settings suites cover their own components. These checks do not replace TalkBack/VoiceOver exploration, switch control/remote focus testing, live account synchronization, or low-end Android frame profiling. No unmeasured 60 fps guarantee is claimed.
