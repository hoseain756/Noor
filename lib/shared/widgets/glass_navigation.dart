import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/horse_theme.dart';

// The old `GlassNavigationBar` (4-slot bottom bar) was replaced by the
// translated Harbor glass dock — see `features/shell/glass_dock.dart` and
// `features/shell/noor_dock_tabs.dart` (Task 107-d). Page-content bottom
// clearance moved with it (`glassDockContentClearance`).

class GlassSearchButton extends StatelessWidget {
  const GlassSearchButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
  });

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .34),
              blurRadius: 16,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Material(
              color: HorseTheme.surface.withValues(alpha: .9),
              shape: const CircleBorder(
                side: BorderSide(color: Color(0x4DFFFFFF)),
              ),
              child: IconButton(
                tooltip: tooltip,
                onPressed: onPressed,
                icon: const Icon(Icons.search_rounded),
                color: HorseTheme.ink,
                iconSize: 22,
                constraints: const BoxConstraints.tightFor(
                  width: 48,
                  height: 48,
                ),
              ),
            ),
          ),
        ),
      );
}
