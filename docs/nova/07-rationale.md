# 07 — Design and engineering rationale

## A recognizable NOVA identity

The supplied mark, red/ink palette and Arabic/Latin typography define the identity. Dark mode leads with restrained cinematic contrast; light mode receives its own surface hierarchy and readable secondary accent rather than merely inverting the dark colors. Red identifies the primary decision, while supporting actions stay quieter. This avoids competing calls to action on dense media pages.

The product's visual signature is a stationary image stage with a softly rounded, opaque content sheet moving over it. It makes the requested hero behavior tangible while keeping reading areas stable. The implementation isolates the artwork from routine scroll/list rebuilds. It does not require multiple layers of live backdrop blur.

## Discovery before decoration

NOVA already knows about real add-on catalogs, watch progress and linked libraries. The redesign gives those data sources clear roles rather than adding invented marketing content. Continue Watching prioritizes an unfinished task; scoped discovery rails support exploration. Different provider failures should degrade one area instead of making the whole app appear broken.

The Details page follows the viewing decision: title/context, Play/Resume, story and episodes, people/production, then a fact table and similar options. The fact table is directly before Similar Suggestions as requested. Missing metadata is omitted; names replace missing logos/photos where appropriate. Production images and cast details are obtained from actual metadata and are not invented.

## A system that works in Arabic and English

Directionality is an application-level concern. A live locale change updates the route tree, stock controls and custom logical alignment together. Arabic and Latin receive appropriate bundled fonts and line height. Mixed-content URLs, authorization codes and other protocol syntax keep LTR direction, while surrounding controls follow the user's interface language.

Text expansion is handled through intrinsic height, wrapping, bounded sheets and breakpoint changes. Deliberately avoiding a narrow trailing value column in Settings makes long Arabic controls easier to read. Reduced motion is propagated through MediaQuery so shared components can respect both device and app preferences.

## Information architecture should reduce work

Settings is now a searchable directory with a second pane on large screens. Related controls share a surface; rows no longer require repeated nested cards. Provider pages separate connection tasks from unrelated services while retaining every real authorization path. Add-on priority is explicit and can be changed with either drag or buttons.

The navigation dock retains the user's established concept. Larger screens gain a persistent side navigation layout rather than a stretched phone dock. The primary destinations remain Home, Anime, Kids, Library and Settings, with secondary tools organized around discovery and library management.

## Honest controls and compatibility

An available UI control must correspond to working behavior. Theme, language, parent PIN and supported automatic provider-sync switches are wired to real state/backend paths. Notifications does not claim push capability that the build lacks. MDBList does not pretend to support a personal account when only ratings aggregation exists.

The existing app is accountless. It is more useful to improve device sync and provider authorization than to add a decorative username/password form. Legacy package IDs, OAuth callback schemes and persisted storage keys are intentionally kept when required for upgrades or registered provider flows. The visible product brand is NOVA.

## Children need a real boundary

The Kids visual language is friendlier, with larger choices and palette-derived brighter surfaces, but visual treatment alone is insufficient. Discovery uses an explicit family-certificate allowlist; unknown/adult certificates stay hidden. A locally secured parent PIN controls leaving Kids. Details must keep the Kids context for recommendations and gate outbound actions. Restart and deep-link routes require the same boundary and are part of acceptance, not optional edge cases.

Family certificates are broad classification metadata, not a guarantee for every child's age or every independent source. The application should never equate an animation/family genre tag with a verified age rating.

## Performance choices

Lazy first-visit page creation avoids starting hidden features unnecessarily. Existing scoped selectors, paused offscreen animations and decode bounds are retained. Cached image providers and a bounded stale catalog cache improve repeat visits. Encoding/decoding disk cache records can use isolates; stream URLs and provider authorization must remain outside this generic cache path. Foreground download progress is throttled rather than rebuilding per network chunk.

These choices are engineering improvements, not measured 60 fps guarantees. Release acceptance requires profile-mode traces on representative mobile/tablet hardware, together with scroll/image memory and low-bandwidth scenarios.

## Safe destructive actions and understandable state

Removing an add-on or credential, deleting files and clearing viewing history require a clear confirmation. Empty, loading and failed states are distinct. Storage read failure should not say there are no files. A failed provider should offer retry without discarding already usable data. New direct downloads state their foreground-only limitation, so the user can make an informed decision.

## Verification standard

A passing analyzer proves static consistency; widget tests prove selected interactions/layout contracts. Neither proves external OAuth success, real media playback, all-device accessibility or visual fidelity to the brand guide. The documentation and final report should state the exact evidence obtained and retain the remaining device/provider checks in `requirements-status.md`.
