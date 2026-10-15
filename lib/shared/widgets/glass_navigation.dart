import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/horse_theme.dart';

// The old `GlassNavigationBar` (4-slot bottom bar) was replaced by the
// translated Harbor glass dock — see `features/shell/glass_dock.dart` and
// `features/shell/noor_dock_tabs.dart` (Task 107-d). Page-content bottom
// clearance moved with it (`glassDockContentClearance`).

/// Circular floating glass button wearing the OLD detail back-pill recipe
/// (user mandate, Task 120: "the pre-118 back-button glow background for
/// the search button AND the navigation bar"): a blur-12 backdrop over a
/// black/55 fill with a 1px white/15 ring and a soft black drop shadow.
/// This neutral dark glass replaces the previous dock's cyan-tint recipe
/// (saturate(1.35) + `#BFE6F2` sheen/ring) across the whole floating-glass
/// family — search button, detail back, sources back, glass dock and the
/// detail page's pill toolbar all render the exact same surface now.
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
              // Glass backdrop: blur-12 over the black/55 fill — the old
              // back-pill recipe verbatim (no tint sheen, no saturate).
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: ColoredBox(color: Colors.black.withValues(alpha: .55)),
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
