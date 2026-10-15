import 'package:flutter/material.dart';

import '../../core/theme/horse_theme.dart';

/// Shared empty/error/loading state message — the single implementation of
/// the centered "icon → 12 → message → 14 → action button" column
/// that existed as 8 near-identical private widgets across features
/// (evidence: audit 121-a1 + 121-a2 — live_tv `_StateMessage`, catalog
/// `_Message` + `_GridMessage`, calendar `_CalendarMessage`, anime
/// `_CatalogState`, home `_RailMessage`/`_ServiceMessage`, detail
/// `_ErrorView`; the live-tv/catalog/calendar family was pixel-identical
/// apart from padding 28 vs 24 and icon 44 vs 42).
///
/// Visual spec (audit 121-a2 §3): a [Center]ed, non-scrolling column sized
/// for `Expanded`/`SliverFillRemaining` slots; muted icon (or the standard
/// gold spinner when [loading]); unstyled centered message text; one action
/// button — [filledButton] selects `FilledButton` vs `OutlinedButton`, and
/// [actionIcon] reproduces the page-specific button glyph (live TV's
/// `Icons.add_rounded`) without altering any existing visual.
///
/// Usage rules:
///  * Strings are pre-localized by the caller (`english ? 'en' : 'ar'`
///    ternary) — this widget deliberately takes no `english` flag, matching
///    the MediaRail shared-widget convention.
///  * The icon always renders [HorseTheme.muted] at [iconSize]; pages whose
///    state needs a different icon color or gap rhythm (e.g. anime's gold
///    `_CatalogState`) keep their local widget.
///  * Pass [iconSize]/[padding] to reproduce the page being migrated
///    (catalog family: 42 + `EdgeInsets.all(24)`; live-tv/calendar: the
///    44 + 28 defaults).
class AppStateMessage extends StatelessWidget {
  const AppStateMessage({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.loading = false,
    this.filledButton = false,
    this.actionIcon,
    this.iconSize = 44,
    this.padding = const EdgeInsets.all(28),
  });

  /// State icon (muted) shown unless [loading] is true.
  final IconData icon;

  /// Pre-localized body line under the icon.
  final String message;

  /// Pre-localized button label; the button renders only when both this and
  /// [onAction] are provided.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Swap the icon for the app-standard gold spinner
  /// (`CircularProgressIndicator(color: HorseTheme.gold, strokeWidth: 2)`).
  final bool loading;

  /// `true` → `FilledButton`, `false` (default) → `OutlinedButton`.
  final bool filledButton;

  /// Optional glyph inside the action button (mirrors `XxxButton.icon`).
  final IconData? actionIcon;

  final double iconSize;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const CircularProgressIndicator(
                color: HorseTheme.gold,
                strokeWidth: 2,
              )
            else
              Icon(icon, size: iconSize, color: HorseTheme.muted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              if (filledButton && actionIcon != null)
                FilledButton.icon(
                  onPressed: onAction,
                  icon: Icon(actionIcon),
                  label: Text(actionLabel!),
                )
              else if (filledButton)
                FilledButton(onPressed: onAction, child: Text(actionLabel!))
              else if (actionIcon != null)
                OutlinedButton.icon(
                  onPressed: onAction,
                  icon: Icon(actionIcon),
                  label: Text(actionLabel!),
                )
              else
                OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
