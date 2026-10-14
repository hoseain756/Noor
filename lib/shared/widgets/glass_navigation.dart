import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/horse_theme.dart';

class GlassNavigationBar extends StatelessWidget {
  const GlassNavigationBar({
    super.key,
    required this.index,
    required this.labels,
    required this.icons,
    required this.onSelected,
  });

  static const contentBottomInset = 76.0;

  final int index;
  final List<String> labels;
  final List<IconData> icons;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 260);
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: 16,
        end: 16,
        bottom: safeBottom + 12,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SizedBox(
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF68777B).withValues(alpha: .72),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .32),
                    ),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final segmentWidth = constraints.maxWidth / labels.length;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragUpdate: (details) {
                          if (segmentWidth <= 0) return;
                          final direction = Directionality.of(context);
                          final inlinePosition = direction == TextDirection.rtl
                              ? constraints.maxWidth - details.localPosition.dx
                              : details.localPosition.dx;
                          final selected =
                              (inlinePosition / segmentWidth).floor().clamp(
                                    0,
                                    labels.length - 1,
                                  );
                          if (selected != index) onSelected(selected);
                        },
                        child: Stack(
                          children: [
                            AnimatedPositionedDirectional(
                              duration: duration,
                              curve: Curves.easeOutCubic,
                              start: index * segmentWidth + 5,
                              top: 5,
                              bottom: 5,
                              width: segmentWidth - 10,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .17),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: .12),
                                  ),
                                  borderRadius: BorderRadius.circular(22),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                for (var i = 0; i < labels.length; i++)
                                  Expanded(
                                    child: Semantics(
                                      button: true,
                                      selected: i == index,
                                      label: labels[i],
                                      child: InkWell(
                                        onTap: () => onSelected(i),
                                        borderRadius: BorderRadius.circular(22),
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            minHeight: 60,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 2,
                                              vertical: 5,
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  icons[i],
                                                  size: 23,
                                                  color: i == index
                                                      ? Colors.white
                                                      : Colors.white70,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
