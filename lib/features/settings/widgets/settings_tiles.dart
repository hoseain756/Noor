import 'package:flutter/material.dart';

import '../../../core/theme/horse_theme.dart';

/// Shared primitives for the settings feature, extracted verbatim from
/// settings_page.dart (Task 121-d). Pages adopt these only where their
/// geometry is pixel-identical; near-miss rows keep their local widgets
/// (settings_data_page `_DataRow`, settings_preferences_page
/// `_PreferenceTile`, addons_page `_AddonRow`, the integrations_page
/// panel cards).
///
/// Localization stays caller-owned: strings arrive pre-localized via the
/// inline `english ? :` convention — no language flag lives here.

/// Gold caption above a group of [SettingsTile]s (padding bottom 9 /
/// start 3, `titleMedium` tinted [HorseTheme.gold]).
class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 9, start: 3),
        child: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: HorseTheme.gold),
        ),
      );
}

/// Standard tappable settings row: bordered [HorseTheme.surface] card
/// (radius 15, [HorseTheme.line] border, bottom margin 8) with a 42×42
/// gold-tinted leading icon box and a default chevron trailing that goes
/// muted when the tile is not tappable.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: HorseTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: const BorderSide(color: HorseTheme.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            onTap: onTap,
            minVerticalPadding: 12,
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: HorseTheme.gold.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(HorseTheme.radiusChip),
              ),
              child: Icon(icon, color: HorseTheme.gold, size: 21),
            ),
            title: Text(title, style: Theme.of(context).textTheme.titleMedium),
            subtitle: subtitle == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(subtitle!,
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
            trailing: trailing ??
                Icon(
                  Icons.chevron_left_rounded,
                  color: onTap == null ? HorseTheme.muted : HorseTheme.gold,
                ),
          ),
        ),
      );
}
