import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/horse_theme.dart';

// The old `GlassNavigationBar` (4-slot bottom bar) was replaced by the
// translated Harbor glass dock — see `features/shell/glass_dock.dart` and
// `features/shell/noor_dock_tabs.dart` (Task 107-d). Page-content bottom
// clearance moved with it (`glassDockContentClearance`).

/// Circular floating glass button wearing the SAME liquid-glass recipe as
/// the glass dock (user mandate, Task 115: "same liquid glass as the bottom
/// navigation"): saturate(1.35) + blur(12/14) backdrop, panel fill at
/// alpha 0.434, the 160° tint sheen, and the 1px tint ring. The only
/// adaptations for the circular form: the dock's straight 1px inset edges
/// become curved specular (top) / dark (bottom) gradients, plus a soft drop
/// shadow so the floating circle separates from scrolling content.
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

  // glass_dock.dart's private recipe constants, mirrored verbatim.
  static const Color _kGlassTint = Color(0xFFBFE6F2); // rgb(191 230 242)
  static const Color _kPanelFill = Color(0xFF10181C); // rgb(16 24 28)

  static final ColorFilter _kSaturate =
      ColorFilter.matrix(_saturationMatrix(1.35));

  @override
  Widget build(BuildContext context) {
    // Same blur ladder as the dock (web window classes → phone/desktop).
    final blur = MediaQuery.sizeOf(context).width < 600 ? 12.0 : 14.0;
    return DecoratedBox(
      // 1px tint ring painted above the clipped glass + ambient shadow.
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _kGlassTint.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .34),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            children: [
              // Glass backdrop: blur(sigma) + saturate(1.35), then the panel
              // fill (web backdrop-filter + color-mix) — dock recipe 1:1.
              Positioned.fill(
                child: ColorFiltered(
                  colorFilter: _kSaturate,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                    child: ColoredBox(
                      // color-mix(panel-fill 70%, transparent) =
                      // alpha 0.62 × 0.7.
                      color: _kPanelFill.withValues(alpha: 0.434),
                    ),
                  ),
                ),
              ),
              // Tint sheen — web linear-gradient(160deg, …), dock verbatim.
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(-0.34, -1),
                      end: Alignment(0.34, 1),
                      stops: [0, 0.6],
                      colors: [
                        Color(0x1FBFE6F2), // tint 0.12
                        Color(0x0DBFE6F2), // tint 0.05
                      ],
                    ),
                  ),
                ),
              ),
              // The dock's inset edges adapted to the circle: tinted specular
              // at the top, dark shading at the bottom.
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment(0, 0.55),
                      colors: [Color(0x80BFE6F2), Color(0x00BFE6F2)],
                    ),
                  ),
                ),
              ),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(0, 0.8),
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0x24000000)],
                    ),
                  ),
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

// glass_dock.dart's private saturation helper, mirrored verbatim.
List<double> _saturationMatrix(double s) {
  final lr = 0.213, lg = 0.715, lb = 0.072; // luma weights
  return <double>[
    lr + (1 - lr) * s, lg * (1 - s), lb * (1 - s), 0, 0, //
    lr * (1 - s), lg + (1 - lg) * s, lb * (1 - s), 0, 0, //
    lr * (1 - s), lg * (1 - s), lb + (1 - lb) * s, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}
