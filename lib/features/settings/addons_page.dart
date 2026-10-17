import 'package:nova_mobile/shared/widgets/nova_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/models/addon.dart';
import '../../core/state/app_state.dart';
import '../../shared/widgets/image_decode.dart';
import 'widgets/settings_tiles.dart';

class AddonsPage extends StatefulWidget {
  const AddonsPage({super.key});
  @override
  State<AddonsPage> createState() => _AddonsPageState();
}

class _AddonsPageState extends State<AddonsPage> {
  final _url = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _messageError = false;
  static const _suggestions = [
    ('Cinemeta', 'https://v3-cinemeta.strem.io/manifest.json'),
    ('OpenSubtitles', 'https://opensubtitles-v3.strem.io/manifest.json'),
    (
      'Stremio Add-on Catalog',
      'https://addon-list.stremio.workers.dev/manifest.json'
    ),
  ];
  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _install([String? value]) async {
    if (_busy) return;
    final app = context.read<AppState>();
    final url = (value ?? _url.text).trim();
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['https', 'http', 'stremio'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      setState(() {
        _message = app.tr('message218');
        _messageError = true;
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await app.installAddon(url);
      if (!mounted) return;
      _url.clear();
      setState(() {
        _message = app.tr('message219');
        _messageError = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error is FormatException
              ? app.tr('addonInvalidManifest')
              : app.tr('addonInstallFailed');
          _messageError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (_, addons) = context.select<AppState, (bool, List<Addon>)>(
        (app) => (app.english, app.addons));
    final app = context.read<AppState>();
    final sorted = List.of(addons)..sort((a, b) => a.order.compareTo(b.order));
    return Scaffold(
        appBar: AppBar(title: Text(app.tr('message220'))),
        body: Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: CustomScrollView(slivers: [
            SliverPadding(
                padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 24, 0),
                sliver: SliverToBoxAdapter(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SettingsPageIntro(
                        title: app.tr('message221'),
                        description: app.tr('message222'),
                        icon: LucideIcons.puzzle),
                    Text(app.tr('message223'),
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    TextField(
                        controller: _url,
                        keyboardType: TextInputType.url,
                        textDirection: TextDirection.ltr,
                        autocorrect: false,
                        onSubmitted: (_) => _install(),
                        decoration: InputDecoration(
                            labelText: app.tr('message224'),
                            hintText: 'https://addon.example/manifest.json',
                            prefixIcon: const Icon(LucideIcons.link))),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                        onPressed: _busy ? null : _install,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(LucideIcons.plus),
                        label: Text(app.tr('message225'))),
                    const SizedBox(height: 16),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final suggestion in _suggestions)
                        ActionChip(
                            label: Text(suggestion.$1),
                            onPressed:
                                _busy ? null : () => _install(suggestion.$2))
                    ]),
                    if (_message != null)
                      Padding(
                          padding: const EdgeInsetsDirectional.only(top: 16),
                          child: Semantics(
                              liveRegion: true,
                              child: SettingsInfoBanner(
                                  message: _message!,
                                  error: _messageError,
                                  icon: _messageError
                                      ? LucideIcons.circleAlert
                                      : LucideIcons.circleCheck))),
                    const SizedBox(height: 32),
                    Text(app.tr('message226', {'p0': addons.length}),
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(app.tr('message227'),
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 16),
                    if (sorted.isEmpty)
                      SettingsInfoBanner(
                          icon: LucideIcons.puzzle,
                          message: app.tr('message228')),
                  ],
                ))),
            SliverPadding(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 24),
                sliver: SliverReorderableList(
                    itemCount: sorted.length,
                    onReorderItem: (oldIndex, newIndex) => app.reorderAddons(
                        oldIndex,
                        newIndex > oldIndex ? newIndex + 1 : newIndex),
                    itemBuilder: (context, index) {
                      final addon = sorted[index];
                      return _AddonRow(
                          key: ValueKey(addon.id),
                          addon: addon,
                          index: index,
                          count: sorted.length);
                    })),
            SliverPadding(
                padding: const EdgeInsets.all(24),
                sliver: SliverToBoxAdapter(
                    child: SettingsInfoBanner(message: app.tr('message229')))),
          ]),
        )));
  }
}

class _AddonRow extends StatelessWidget {
  const _AddonRow(
      {super.key,
      required this.addon,
      required this.index,
      required this.count});
  final Addon addon;
  final int index, count;
  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 12),
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => _AddonDetailsPage(addonId: addon.id))),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Row(children: [
                    ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                            width: 48,
                            height: 48,
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            child: addon.manifest['logo'] is String
                                ? NovaNetworkImage(
                                    addon.manifest['logo'] as String,
                                    fit: BoxFit.cover,
                                    cacheWidth: imageCacheWidth(context, 48),
                                    errorBuilder: (_, __, ___) =>
                                        const Icon(LucideIcons.puzzle))
                                : const Icon(LucideIcons.puzzle))),
                    const SizedBox(width: 16),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(addon.name,
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(
                              app.tr('message230', {
                                'p0': index + 1,
                                'p1': addon.catalogs.length
                              }),
                              style: Theme.of(context).textTheme.bodySmall),
                        ])),
                    Semantics(
                        label: app.tr('message231', {'p0': addon.name}),
                        child: SettingsOptimisticSwitch(
                            value: addon.enabled,
                            onChanged: (v) =>
                                app.setAddonEnabled(addon.id, v))),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child: Text(
                            addon.enabled
                                ? app.tr('message232')
                                : app.tr('message233'),
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .secondary))),
                    IconButton(
                        tooltip: app.tr('message234'),
                        onPressed: index == 0
                            ? null
                            : () => app.reorderAddons(index, index - 1),
                        icon: const Icon(LucideIcons.arrowUp, size: 18)),
                    IconButton(
                        tooltip: app.tr('message235'),
                        onPressed: index == count - 1
                            ? null
                            : () => app.reorderAddons(index, index + 2),
                        icon: const Icon(LucideIcons.arrowDown, size: 18)),
                    ReorderableDragStartListener(
                        index: index,
                        child: Tooltip(
                            message: app.tr('message236'),
                            child: const SizedBox.square(
                                dimension: 48,
                                child:
                                    Icon(LucideIcons.gripVertical, size: 20)))),
                  ]),
                ]),
              )),
        ));
  }
}

class _AddonDetailsPage extends StatelessWidget {
  const _AddonDetailsPage({required this.addonId});
  final String addonId;
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final addon = app.addons.where((a) => a.id == addonId).firstOrNull;
    if (addon == null) {
      return Scaffold(
          appBar: AppBar(), body: Center(child: Text(app.tr('message237'))));
    }
    final configurable =
        (addon.manifest['behaviorHints'] as Map?)?['configurable'] == true;
    return Scaffold(
        appBar: AppBar(title: Text(addon.name)),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: ListView(
                  padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 24, 48),
                  children: [
                    SettingsPageIntro(
                        title: addon.name,
                        description:
                            addon.manifest['description']?.toString() ??
                                app.tr('message238'),
                        icon: LucideIcons.puzzle),
                    SettingsContentSection(
                        title: app.tr('message239'),
                        children: [
                          SettingsOptimisticSwitchTile(
                              title: Text(app.tr('message240')),
                              subtitle: Text(app.tr('message241')),
                              value: addon.enabled,
                              onChanged: (v) =>
                                  app.setAddonEnabled(addon.id, v)),
                          if (configurable)
                            SettingsTile(
                                icon: LucideIcons.slidersHorizontal,
                                title: app.tr('message242'),
                                subtitle: app.tr('message243'),
                                onTap: () async {
                                  final opened = await launchUrl(
                                      Uri.parse('${addon.baseUrl}/configure'),
                                      mode: LaunchMode.externalApplication);
                                  if (!opened && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            content:
                                                Text(app.tr('message244'))));
                                  }
                                }),
                          SettingsTile(
                              icon: LucideIcons.copy,
                              title: app.tr('message245'),
                              onTap: () async {
                                await Clipboard.setData(
                                    ClipboardData(text: addon.transportUrl));
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(app.tr('message246'))));
                                }
                              }),
                        ]),
                    if (addon.catalogs.isNotEmpty)
                      SettingsContentSection(
                          title: app.tr('message247'),
                          children: [
                            for (final catalog in addon.catalogs)
                              ListTile(
                                  title: Text(catalog.name),
                                  subtitle: Text(catalog.type),
                                  leading: const Icon(LucideIcons.library))
                          ]),
                    if (!configurable)
                      SettingsInfoBanner(message: app.tr('message248')),
                    const SizedBox(height: 32),
                    OutlinedButton.icon(
                        icon: const Icon(LucideIcons.trash2),
                        label: Text(app.tr('message249')),
                        onPressed: () async {
                          final remove = await confirmSettingsAction(context,
                              title: app.tr('message250'),
                              message: app.tr('message251', {'p0': addon.name}),
                              confirm: app.tr('remove'),
                              cancel: app.tr('cancel'));
                          if (remove) {
                            await app.removeAddon(addon.id);
                            if (context.mounted) Navigator.pop(context);
                          }
                        }),
                  ],
                ))));
  }
}
