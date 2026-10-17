import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_theme.dart';

/// Floating glass chrome uses a tinted static surface, with an opaque fallback.
class GlassSearchButton extends StatelessWidget {
  const GlassSearchButton(
      {super.key,
      required this.tooltip,
      required this.onPressed,
      this.icon = LucideIcons.search,
      this.size = 48});
  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;
  final double size;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    bool opaque = MediaQuery.highContrastOf(context);
    try {
      opaque = opaque ||
          context.select<AppState, bool>(
              (app) => app.webSettings['reduceTransparency'] == true);
    } catch (_) {}
    return SizedBox(
        width: size.clamp(48, 72),
        height: size.clamp(48, 72),
        child: DecoratedBox(
          decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
            BoxShadow(
                color: NovaColors.ink.withValues(alpha: .2),
                blurRadius: 14,
                offset: const Offset(0, 4))
          ]),
          child: Material(
              color: scheme.surface.withValues(alpha: opaque ? 1 : .94),
              shape: CircleBorder(side: BorderSide(color: scheme.outline)),
              clipBehavior: Clip.antiAlias,
              child: IconButton(
                  tooltip: tooltip,
                  onPressed: onPressed,
                  icon: Icon(icon, size: 22, color: scheme.onSurface))),
        ));
  }
}
