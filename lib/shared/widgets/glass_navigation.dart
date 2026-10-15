import 'package:flutter/material.dart';

import '../../core/theme/horse_theme.dart';

// The old `GlassNavigationBar` (4-slot bottom bar) was replaced by the
// translated Harbor glass dock — see `features/shell/glass_dock.dart` and
// `features/shell/noor_dock_tabs.dart` (Task 107-d). Page-content bottom
// clearance moved with it (`glassDockContentClearance`).

/// Circular floating glass button wearing the OLD detail back-pill recipe
/// (user mandate, Task 120: "the pre-118 back-button glow background for
/// the search button AND the navigation bar"): originally a blur-12 backdrop
/// over a black/55 fill with a 1px white/15 ring and a soft black drop
/// shadow. Task 136 (perf): the live blur is retired — the surface is now a
/// static black/72 fill under the same ring + shadow (the button mounts on
/// every screen, and a persistent BackdropFilter re-blurred the page on
/// every content frame).
///
/// Task 118: parameterized with [icon] and [size] so the detail page's back
/// button (and any future floating chrome) wears the exact same surface —
/// defaults keep the original 48dp search look.
class GlassSearchButton extends StatelessWidget {
  const GlassSearchButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    this.icon = Icons.search_rounded,
    this.size = 48,
  });

  final String tooltip;
  final VoidCallback onPressed;

  /// Glyph inside the glass circle (search by default).
  final IconData icon;

  /// Circle diameter — 48 (dock spec) by default; smaller values shrink
  /// every recipe layer proportionally (they are all fill-relative).
  final double size;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      // 1px white/15 ring painted above the clipped glass + soft shadow —
      // the pre-118 back-pill decoration verbatim.
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: .15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .35),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            children: [
              // Glass backdrop — Task 136 (perf): the LIVE BackdropFilter
              // (blur-12) used to re-blur the page beneath the button on
              // every content frame; the button sits on EVERY screen, so
              // the blur rode along on all of them. Static fill now — the
              // ring above and the shadow are unchanged.
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: .72),
                ),
              ),
              // Icon layer: transparent Material INSIDE the clip so the ink
              // ripple stays circular (an outer Material would paint the
              // splash unclipped).
              Center(
                child: Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: IconButton(
                    tooltip: tooltip,
                    onPressed: onPressed,
                    icon: Icon(icon),
                    color: HorseTheme.ink,
                    iconSize: size * 22 / 48,
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints.tightFor(
                      width: size,
                      height: size,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
