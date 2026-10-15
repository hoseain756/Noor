import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/addon.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';

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
      'https://addon-list.stremio.workers.dev/manifest.json',
    ),
  ];

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _install([String? value]) async {
    final url = (value ?? _url.text).trim();
    if (url.isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await context.read<AppState>().installAddon(url);
      if (!mounted) return;
      _url.clear();
      setState(() {
        _message = context.read<AppState>().english
            ? 'Add-on installed and synced.'
            : 'تم تثبيت الإضافة ومزامنتها.';
        _messageError = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString().replaceFirst('Exception: ', '');
          _messageError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final english = app.english;
    return Scaffold(
      appBar: AppBar(title: Text(english ? 'Add-ons' : 'الإضافات')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
            children: [
              Text(
                english
                    ? 'Bring your own catalog and streams.'
                    : 'أضف الكتالوجات ومصادر البث التي تفضّلها.',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 7),
              Text(
                english
                    ? 'Noor uses the open Stremio add-on protocol. Add-ons provide catalogs, streams, and subtitles.'
                    : 'يستخدم Noor بروتوكول إضافات Stremio المفتوح. توفّر الإضافات الكتالوجات ومصادر البث والترجمات.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: HorseTheme.muted),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(17),
                decoration: BoxDecoration(
                  color: HorseTheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: HorseTheme.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      english
                          ? 'Install from manifest URL'
                          : 'التثبيت عبر رابط manifest',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _url,
                      keyboardType: TextInputType.url,
                      textDirection: TextDirection.ltr,
                      autocorrect: false,
                      onSubmitted: (_) => _install(),
                      decoration: InputDecoration(
                        hintText: 'https://addon.example/manifest.json',
                        suffixIcon: IconButton(
                          onPressed: _busy ? null : _install,
                          icon: const Icon(Icons.add_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final suggestion in _suggestions)
                          ActionChip(
                            label: Text(suggestion.$1),
                            onPressed:
                                _busy ? null : () => _install(suggestion.$2),
                          ),
                      ],
                    ),
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.only(top: 14),
                        child: LinearProgressIndicator(
                          minHeight: 2,
                          color: HorseTheme.gold,
                        ),
                      ),
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _message!,
                          style: TextStyle(
                            color: _messageError
                                ? HorseTheme.danger
                                : HorseTheme.gold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      english ? 'Installed' : 'المثبتة',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    '${app.addons.length}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (app.addons.isEmpty)
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: HorseTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    english
                        ? 'No add-ons yet. Public catalogs still work; install a stream add-on to watch titles.'
                        : 'لا توجد إضافات بعد. الكتالوجات العامة تعمل، وثبّت إضافة بث لتشغيل العناوين.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              else
                for (final addon
                    in app.addons..sort((a, b) => a.order.compareTo(b.order)))
                  _AddonRow(addon: addon),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1815),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 19,
                      color: HorseTheme.gold,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        english
                            ? 'Add-ons are independent services. Noor only loads catalog metadata and plays sources you choose.'
                            : 'الإضافات خدمات مستقلة. يعرض Noor بيانات الكتالوج ويشغّل المصدر الذي تختاره.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddonRow extends StatelessWidget {
  const _AddonRow({required this.addon});
  final Addon addon;
  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final english = app.english;
    final resources = (addon.manifest['resources'] as List? ?? const [])
        .map(
          (value) =>
              value is Map ? value['name']?.toString() ?? '' : value.toString(),
        )
        .where((value) => value.isNotEmpty)
        .toSet();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: HorseTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HorseTheme.line),
      ),
      child: ListTile(
        contentPadding: const EdgeInsetsDirectional.fromSTEB(14, 5, 8, 5),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: HorseTheme.raised,
            borderRadius: BorderRadius.circular(13),
          ),
          child: addon.manifest['logo'] is String
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: Image.network(
                    addon.manifest['logo'] as String,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.extension_rounded,
                      color: HorseTheme.gold,
                    ),
                  ),
                )
              : const Icon(Icons.extension_rounded, color: HorseTheme.gold),
        ),
        title: Text(
          addon.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            resources.isEmpty
                ? '${addon.catalogs.length} ${english ? 'catalogs' : 'كتالوج'}'
                : resources.join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        trailing: SizedBox(
          width: 88,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Switch(
                value: addon.enabled,
                activeThumbColor: HorseTheme.gold,
                onChanged: (value) => app.setAddonEnabled(addon.id, value),
              ),
              IconButton(
                tooltip: english ? 'Remove' : 'إزالة',
                onPressed: () => _confirmRemove(context, addon),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: HorseTheme.muted,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context, Addon addon) async {
    final english = context.read<AppState>().english;
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(english ? 'Remove add-on?' : 'إزالة الإضافة؟'),
        content: Text(
          english
              ? '“${addon.name}” will be removed from this account.'
              : 'ستتم إزالة «${addon.name}» من هذا الحساب.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(english ? 'Cancel' : 'إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(english ? 'Remove' : 'إزالة'),
          ),
        ],
      ),
    );
    if (remove == true && context.mounted) {
      await context.read<AppState>().removeAddon(addon.id);
    }
  }
}
