# Mobile design reference notes

Reviewed references: `docs/1.jpg`, `5.jpg`, `6.jpg`, `7.jpg`,
`8.jpg`, `9.jpg`, `10.jpg`, and `11.jpg`.

## Shared visual language

- The references use a near-black page canvas with deep plum/brown surfaces,
  high-contrast white text and muted gray metadata. The design should continue
  using Horse theme tokens and adapt their values where the references call for
  blacker surfaces; avoid introducing unrelated component styling.
- Arabic is right-to-left. Headings and action labels align to the logical end;
  Latin title, episode and rating values retain readable left-to-right order.
- Poster art is prominent and uses consistent rounded corners. Ratings appear
  as compact dark pills with a gold star; metadata appears as low-profile chips.
- The phone bottom navigation floats above content with a translucent glass
  surface, a clear selected state, safe-area clearance and four icon-only
  destinations. Their visual order is Settings, Kids, Anime, Home; the library
  remains reachable from Settings. Search is a separate circular control at
  the top-left in the supplied screenshots.

## Screen structure

- Home: a compact featured area sized near 45% of phone height (320–440 px) and
  48% on wider layouts (380–540 px), with full-bleed, textless artwork. Keep
  the logo, year/genre/type metadata, small “view details” action and page
  indicators in fixed positions; crossfade only the background artwork as the
  active item changes. Slides advance every six seconds and respond to swipes
  or indicator taps. Below it, show Continue Watching as a wide episode card,
  ranked Top 10 posters, then horizontal Popular, recommendation and
  similar-title rails.
- Media detail: large landscape/portrait artwork with a readable bottom fade,
  title, year/type/genre and rating chips, provider ratings, centered summary,
  a prominent play action and secondary watchlist/season controls.
- Episodes: a season dropdown with selected checkmark and count, a list/grid
  switch and sort action. List rows place episode information beside a wide
  still; grid cards use 16:9 stills. Selection, watched state and loading state
  remain visible and accessible.
- Home browse cards: posters stay tall and unclipped; ranking numerals sit
  behind/alongside cards and do not cover controls. Section headings and “show
  all” actions align to the right in Arabic.
- Recommendations and similar titles follow the same poster/card language as
  home rails and remain reachable by scrolling below the episode section.

## Responsive and interaction requirements

- The references are phone captures at approximately 720 px wide. They do not
  specify tablet geometry; tablet behavior follows the task requirement for a
  collapsible side navigation hidden by default and a wider content layout.
- Preserve vertical scrolling and horizontal poster rails. Bottom navigation
  must not cover the last row or playback controls. Details and season menus
  must fit short screens and work with Arabic/English text scaling.
- Use the supplied eight images as visual guidance, not as in-app image assets.
  The implementation must continue loading real catalog and metadata images.

## Video player reference

- Treat the video as a full-screen surface with subtle top and bottom fades.
  Group the back/title/actions at the top, transport controls around the center,
  and a thin timeline with current and total time near the bottom.
- Keep touch targets accessible while keeping icons visually light. On phones,
  use compact spacing; cap the control row width on tablets instead of stretching
  it across the entire display. Respect display cutouts and safe areas.
- The timeline follows left-to-right playback progression even in Arabic RTL,
  shows only buffered ranges reported by the player, and previews the seek
  position before committing it to playback.
- The reference's side icons are represented only when backed by existing
  player operations: subtitles, settings, episode navigation, volume, fit mode
  and fullscreen. Avoid screenshot/repeat controls unless the engine path
  provides those operations.
- Tapping the video reveals or hides controls, double-tapping either side seeks
  by ten seconds, and horizontal dragging previews and commits a seek. Keep
  controls visible while paused, seeking or choosing a menu option.
