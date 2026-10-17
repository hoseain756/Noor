# 02 — NOVA design system

The Flutter source of truth is [`nova_theme.dart`](../../lib/core/theme/nova_theme.dart). This specification uses the supplied brand palette; surfaces, translucent overlays and interaction states are alpha treatments of those supplied colors.

## Color roles

| Supplied token | Value | Dark mode | Light mode |
|---|---|---|---|
| Brand red | `#D13B47` | Primary filled actions and progress | Primary filled actions and progress |
| Deep red | `#9E2A34` | Pressed/critical container | Accessible text on blush/error container |
| Soft red | `#E8858D` | Accent text, selected controls, errors | Supporting tone when paired with a suitable surface |
| Blush | `#F9E4E6` | Restrained selected tint | Selected/error containers |
| Ink | `#141417` | Canvas and dark scrim source | Main text and dark foreground |
| Graphite | `#232329` | Base surface | — |
| Surface high | `#2E2E35` | Raised controls | — |
| Divider | `#3A3A42` | Dark outline | — |
| White | `#FFFFFF` | Main text and primary-button label | Surface and primary-button label |
| Mist | `#A4A4AC` | Secondary text and inactive controls | — |
| Disabled | `#6E6E78` | Disabled foreground | Disabled foreground where contrast permits |
| Success | `#3FB27F` | Success indicator | Success indicator |
| Warning | `#E8A93B` | Warning indicator | Warning indicator |
| Information | `#4C8DE0` | Information indicator | Information indicator |
| Error | `#E5484D` | Semantic error; theme selects readable red foreground | Semantic error; theme selects deep-red foreground |
| Rating | `#F5C451` | Rating/highlight | Rating/highlight |
| Light background | `#F6F6F7` | — | Canvas and grouped surfaces |
| Light secondary text | `#585862` | — | Supporting text |
| Light accent | `#B82C39` | — | Accent text and selected controls |
| Light divider | `#DCDCE0` | — | Outline and divider |
| Scrim | supplied black 60% | Dialog/video/photo scrim | Dialog/photo scrim |

No additional opaque UI color literals are used outside the token definitions and user-selected subtitle colors. Image legibility scrims derive from NOVA ink; low-transparency variants are confined to overlays and decoration.

## Contrast check

Contrast ratios were calculated from the supplied sRGB values with the WCAG relative-luminance formula. These foreground/background roles pass the 4.5:1 AA threshold for normal text:

| Foreground / background | Ratio |
|---|---:|
| White / graphite | 15.63:1 |
| White / ink | 18.39:1 |
| Mist / graphite | 6.31:1 |
| Dark accent redSoft / graphite | 6.08:1 |
| Ink / light background | 17.02:1 |
| Light secondary / light background | 6.51:1 |
| Light accent / white | 6.07:1 |
| White / deep-red container | 7.41:1 |
| Deep red / blush | 6.09:1 |
| White / primary-red button | 4.74:1 |

The supplied primary red is **not** used for small text over the dark surfaces: it measures 3.88:1 on ink, 3.29:1 on graphite, 2.84:1 on surfaceHigh and 4.39:1 on lightBackground. A contrast pass for semantic text roles does not guarantee every image overlay, disabled state or third-party artwork pairing; those still need visual inspection.

## Typography

Latin uses bundled Poppins and Arabic uses bundled IBM Plex Sans Arabic, each with regular, medium, semibold and bold weights. The families are mutual fallbacks. Arabic text receives an additional 0.1 line-height. User/device text scaling remains enabled.

| Role | Size | Weight |
|---|---:|---|
| Display large | 48 | 700 |
| Display medium | 40 | 700 |
| Display small / headline large | 32 | 700 |
| Headline medium | 28 | 700 |
| Headline small | 24 | 600 |
| Title large | 20 | 600 |
| Title/body large | 16 | 600 / 400 |
| Body/title small | 14 | 400 / 600 |
| Body small / labels | 12 | 400 / 500 |
| Compact label | 11 | 500 |

## Geometry and motion

- Spacing: 4, 8, 16, 24, 32 and 48 dp; 4 dp serves compact icon/text gaps, while page and group spacing follows the 8 dp rhythm.
- Radius: 4 dp checkboxes, 8 dp compact badges, 12 dp input/image surfaces, 16 dp cards/buttons, 24 dp sheets and major containers, pill geometry for chips and dock controls.
- Elevation: surfaces use zero or very low shadow; hierarchy comes from supplied surface levels, outlines and scrims. Background blur is limited to the existing optional media quick-look surface and falls back to an opaque panel when reduced transparency is enabled.
- Motion: 120 ms press, 180 ms state, 240 ms route at easeOutCubic; cinematic hero uses an isolated transform and short opacity/scale cover effect. User and OS reduced-motion settings disable decorative animation.

## Shared component catalogue

| Component family | Shared behavior and states |
|---|---|
| Buttons and icon buttons | Filled, outlined, text and icon variants; 48 dp minimum; focus, hover, pressed, disabled and progress feedback. |
| Inputs | Themed fill, outline, helper/error text, clear/search actions and visible focus; URL, OAuth code and magnet values explicitly use LTR. |
| Cards and media rails | Consistent poster sizing, bounded cached image decoding, shimmer/failure fallback, selection/press affordance and lazy children. |
| Tabs and navigation | Selected foreground/container, readable label, semantics, focus, mirrored order/chevrons and adaptive phone dock/tablet rail. |
| Chips and filters | Wrap when constrained, selected/disabled contrast and direction-aware order. |
| Lists and settings rows | 48 dp controls, intrinsic text height, grouped separators, loading/empty/error/success copy and destructive confirmation. |
| Switches, sliders and pickers | Themed track/thumb/focus; RTL-aware progress; explicit apply or instant-save semantics. |
| Dialogs and sheets | Shared surface/radius/scrim, safe area, bounded height, scrollable content and clear cancel/confirm actions. |
| Loading and feedback | Geometry-stable skeletons, static fallback under reduced motion, live-region snackbar and distinct empty versus failed states. |

Reusable implementations include `NovaBrand`, `NovaNetworkImage`, `ShimmerBox`, `AppStateMessage`, `NovaBrowseHeader`, `NovaBrowseSkeleton`, shared settings tile components, player panels and the single responsive shell navigation system. No second general-purpose icon family is used; general interface icons use Lucide. Supplied brand art remains SVG/raster brand art and is not mirrored.

## Adaptive rules

| Width | Navigation and layout |
|---|---|
| Under 600 dp | Phone single-column reading; full-width cinematic hero, wrapping actions, compact lazy rails and two-column posters where content permits. |
| 600–839 dp | Larger phone/small tablet; increase content gutter and grid columns from actual constraints; retain phone navigation. |
| 840–1199 dp | Persistent tablet side rail, two-column detail/source opportunities and wider reading surfaces. |
| 1200 dp and above | Expanded labelled side navigation; settings master/detail from 1000 dp; constrain content to reading widths rather than stretching. |

Breakpoints are component-specific when content width gives a better decision (for example, Settings master/detail at 1000 dp and Home/Details artwork splits around 640–700 dp). Landscape layouts use available height and safe-area insets; text is allowed to wrap and sheets scroll rather than clip.
