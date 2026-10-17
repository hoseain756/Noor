import 'package:flutter/material.dart';
import 'shimmer_box.dart';

/// Shared responsive empty/error surface. The caller owns localized copy/actions.
class AppStateMessage extends StatelessWidget {
  const AppStateMessage(
      {super.key,
      required this.icon,
      required this.message,
      this.actionLabel,
      this.onAction,
      this.loading = false,
      this.filledButton = false,
      this.actionIcon,
      this.iconSize = 44,
      this.padding = const EdgeInsets.all(24)});
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool loading, filledButton;
  final IconData? actionIcon;
  final double iconSize;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
        child: SingleChildScrollView(
            padding: padding,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Semantics(
                  liveRegion: true,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (loading)
                      const ShimmerBox(width: 64, height: 64)
                    else
                      Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                              color: scheme.surfaceContainerHigh,
                              shape: BoxShape.circle),
                          child: Icon(icon,
                              size: iconSize, color: scheme.secondary)),
                    const SizedBox(height: 24),
                    Text(message,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge),
                    if (loading) ...[
                      const SizedBox(height: 24),
                      const ShimmerBox(width: 160, height: 6)
                    ],
                    if (actionLabel != null && onAction != null) ...[
                      const SizedBox(height: 24),
                      if (filledButton)
                        FilledButton.icon(
                            onPressed: onAction,
                            icon: actionIcon == null
                                ? const SizedBox.shrink()
                                : Icon(actionIcon),
                            label: Text(actionLabel!))
                      else
                        OutlinedButton.icon(
                            onPressed: onAction,
                            icon: actionIcon == null
                                ? const SizedBox.shrink()
                                : Icon(actionIcon),
                            label: Text(actionLabel!)),
                    ],
                  ])),
            )));
  }
}
