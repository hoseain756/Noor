# NOVA player interaction specification

The video remains the darkest surface. Universal playback icons stay white over dark NOVA ink scrims; the played timeline uses the supplied red-to-soft-red brand gradient. Picker/settings/episode/subtitle-style surfaces follow the active Light or Dark theme.

Phone portrait: source/audio/subtitle/settings panels are full-width bounded bottom surfaces at 82% of viewport height. Playback controls split into two independent rows below the timeline, removing the previous overlapping start/end groups. Landscape phones and tablets: pickers attach to logical end, width 48% clamped to 360–560px. Only the actual outer screen edge's safe inset is applied. Outside tap dismisses the panel. Existing pause/resume ownership is preserved.

Sources now include local search, available-result count, selected-source treatment, and spacious rows. Loading panels use immediate row skeletons. Subtitle language grouping and search, audio language grouping, delays, source refresh, speed, fit, episodes, subtitle style and live previews all remain functional. Playback setting chips have 48px targets and switch to two columns under larger text scaling. Audio/subtitle timing steppers have their own rows to avoid Arabic and enlarged-text collisions.

The timeline fills from inline start. Tap/drag positions, horizontal seek deltas and double-tap seek regions mirror RTL together. Numeric timestamps remain LTR, while universal play/pause and transport symbols retain their shapes. Brightness/volume gesture regions and feedback use logical start/end. The custom timeline exposes accessible increment/decrement actions.

Reduced motion disables chrome fades, timeline thumb animation, ripple scale/fade, picker slides and subtitle-group rotations. Sheet transitions otherwise use 220ms easeOutCubic. Side pickers remain instant, with data loading visible inside them.

Subtitle colours are user-editable content values, preserved independently of the UI palette. No network or engine contract was removed. The targeted tests in test/nova_player_direction_test.dart check mirror math and timeline tap behavior; player surfaces still require real device playback and GPU profiling before a 60fps claim can be made.
