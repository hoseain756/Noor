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

/// Optimistically-painted [Switch]: a tap paints the new value INSTANTLY
/// (local state) and only then forwards to the caller, so the slow
/// AppState notify / persistence round trip never gates the visual.
/// [didUpdateWidget] re-syncs from [value] whenever the external value
/// changes (web sync, backup restore), so a remotely-reverted toggle
/// snaps back; rapid double-taps are last-write-wins.
class SettingsOptimisticSwitch extends StatefulWidget {
  const SettingsOptimisticSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeThumbColor = HorseTheme.gold,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color activeThumbColor;

  @override
  State<SettingsOptimisticSwitch> createState() =>
      _SettingsOptimisticSwitchState();
}

class _SettingsOptimisticSwitchState extends State<SettingsOptimisticSwitch> {
  late bool _value = widget.value;

  @override
  void didUpdateWidget(SettingsOptimisticSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _value = widget.value;
  }

  @override
  Widget build(BuildContext context) => Switch(
        value: _value,
        activeThumbColor: widget.activeThumbColor,
        onChanged: widget.onChanged == null
            ? null
            : (next) {
                setState(() => _value = next);
                widget.onChanged!(next);
              },
      );
}

/// Optimistically-painted [SwitchListTile.adaptive] — the row idiom the
/// settings pages use (whole row is the tap target, adaptive switch keeps
/// its platform form, [HorseTheme.gold] thumb). Geometry is identical to a
/// plain SwitchListTile.adaptive; only the painted value is optimistic
/// (same local-state contract as [SettingsOptimisticSwitch]).
class SettingsOptimisticSwitchTile extends StatefulWidget {
  const SettingsOptimisticSwitchTile({
    super.key,
    required this.value,
    required this.onChanged,
    required this.title,
    this.subtitle,
    this.contentPadding,
    this.activeThumbColor = HorseTheme.gold,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget title;
  final Widget? subtitle;
  final EdgeInsetsGeometry? contentPadding;
  final Color activeThumbColor;

  @override
  State<SettingsOptimisticSwitchTile> createState() =>
      _SettingsOptimisticSwitchTileState();
}

class _SettingsOptimisticSwitchTileState
    extends State<SettingsOptimisticSwitchTile> {
  late bool _value = widget.value;

  @override
  void didUpdateWidget(SettingsOptimisticSwitchTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _value = widget.value;
  }

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
        contentPadding: widget.contentPadding,
        title: widget.title,
        subtitle: widget.subtitle,
        value: _value,
        activeThumbColor: widget.activeThumbColor,
        onChanged: widget.onChanged == null
            ? null
            : (next) {
                setState(() => _value = next);
                widget.onChanged!(next);
              },
      );
}

/// Compact themed dropdown for the two language rows (UI language on the
/// settings root, content language on the display page): hidden underline,
/// dense height so the hosting row keeps its geometry, gold selected label
/// with a muted affordance icon, rounded menu. Labels are caller-owned and
/// rendered natively (no language flag here, like the rest of this file).
class SettingsLanguageDropdown extends StatelessWidget {
  const SettingsLanguageDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.expanded = false,
  });

  final String value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String> onChanged;
  final bool expanded;

  @override
  Widget build(BuildContext context) => DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          items: items,
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
          isExpanded: expanded,
          isDense: true,
          borderRadius: BorderRadius.circular(14),
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(color: HorseTheme.gold),
          iconEnabledColor: HorseTheme.muted,
        ),
      );
}
