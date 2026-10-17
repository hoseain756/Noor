import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// NOVA's editorial settings primitives. Surface boundaries are reserved for
/// groups; individual controls share quiet separators and generous touch areas.
class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle({super.key, required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(0, 24, 0, 12),
        child: Text(title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.secondary,
                fontWeight: FontWeight.w700)),
      );
}

class SettingsPageIntro extends StatelessWidget {
  const SettingsPageIntro(
      {super.key, required this.title, required this.description, this.icon});
  final String title;
  final String description;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(top: 8, bottom: 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (icon != null) ...[
            Icon(icon,
                color: Theme.of(context).colorScheme.secondary, size: 32),
            const SizedBox(height: 20),
          ],
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Text(description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.65))),
        ]),
      );
}

class SettingsContentSection extends StatelessWidget {
  const SettingsContentSection(
      {super.key,
      required this.title,
      required this.children,
      this.description});
  final String title;
  final String? description;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 24),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SettingsSectionTitle(title: title),
          if (description != null)
            Padding(
                padding: const EdgeInsetsDirectional.only(bottom: 16),
                child: Text(description!,
                    style: Theme.of(context).textTheme.bodySmall)),
          Material(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 20, endIndent: 20),
                children[i],
              ]
            ]),
          ),
        ]),
      );
}

class SettingsTile extends StatelessWidget {
  const SettingsTile(
      {super.key,
      required this.icon,
      required this.title,
      this.subtitle,
      this.trailing,
      this.onTap});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 12, 16),
            child: Row(children: [
              Icon(icon,
                  color: Theme.of(context).colorScheme.secondary, size: 22),
              const SizedBox(width: 16),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(subtitle!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant))
                    ],
                  ])),
              const SizedBox(width: 12),
              trailing ??
                  Icon(
                      Directionality.of(context) == TextDirection.rtl
                          ? LucideIcons.chevronLeft
                          : LucideIcons.chevronRight,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
            ]),
          ),
        ),
      );
}

class SettingsInfoBanner extends StatelessWidget {
  const SettingsInfoBanner(
      {super.key,
      required this.message,
      this.icon = LucideIcons.info,
      this.error = false});
  final String message;
  final IconData icon;
  final bool error;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon,
              size: 20,
              color: error
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 12),
          Expanded(
              child: Text(message,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(height: 1.6))),
        ]),
      );
}

class SettingsOptimisticSwitch extends StatefulWidget {
  const SettingsOptimisticSwitch(
      {super.key,
      required this.value,
      required this.onChanged,
      this.activeThumbColor});
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeThumbColor;
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
            });
}

class SettingsOptimisticSwitchTile extends StatefulWidget {
  const SettingsOptimisticSwitchTile(
      {super.key,
      required this.value,
      required this.onChanged,
      required this.title,
      this.subtitle,
      this.contentPadding,
      this.activeThumbColor});
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget title;
  final Widget? subtitle;
  final EdgeInsetsGeometry? contentPadding;
  final Color? activeThumbColor;
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
      contentPadding: widget.contentPadding ??
          const EdgeInsetsDirectional.fromSTEB(20, 10, 16, 10),
      title: widget.title,
      subtitle: widget.subtitle,
      value: _value,
      activeThumbColor: widget.activeThumbColor,
      onChanged: widget.onChanged == null
          ? null
          : (next) {
              setState(() => _value = next);
              widget.onChanged!(next);
            });
}

class SettingsLanguageDropdown extends StatelessWidget {
  const SettingsLanguageDropdown(
      {super.key,
      required this.value,
      required this.items,
      required this.onChanged,
      this.expanded = false});
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
        borderRadius: BorderRadius.circular(20),
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.secondary),
        icon: const Icon(LucideIcons.chevronDown, size: 18),
      ));
}

Future<bool> confirmSettingsAction(BuildContext context,
        {required String title,
        required String message,
        required String confirm,
        required String cancel}) async =>
    await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              icon: Icon(LucideIcons.shieldAlert,
                  color: Theme.of(context).colorScheme.secondary),
              title: Text(title),
              content: Text(message),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(cancel)),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: Text(confirm))
              ],
            )) ??
    false;
