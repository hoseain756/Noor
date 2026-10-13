import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';

class SettingsDataPage extends StatelessWidget {
  const SettingsDataPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final english = app.english;
    return Scaffold(
      appBar: AppBar(
          title: Text(english ? 'Data and privacy' : 'البيانات والخصوصية')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 36),
            children: [
              _DataRow(
                icon: Icons.cloud_sync_outlined,
                title: english ? 'Cloud sync' : 'المزامنة السحابية',
                detail: english
                    ? 'Sync your library and preferences with your Horse account.'
                    : 'مزامنة مكتبتك وتفضيلاتك مع حساب Horse.',
                trailing: Switch(
                  value: app.webSettings['cloudSyncEnabled'] != false,
                  activeThumbColor: HorseTheme.gold,
                  onChanged: (value) =>
                      app.setSetting('cloudSyncEnabled', value),
                ),
              ),
              _DataRow(
                icon: Icons.download_outlined,
                title: english ? 'Export backup' : 'تصدير نسخة احتياطية',
                detail: english
                    ? '${app.watchlist.length} saved titles · ${app.history.length} history records'
                    : '${app.watchlist.length} عنوان محفوظ · ${app.history.length} سجل مشاهدة',
                onTap: () async {
                  await Clipboard.setData(
                      ClipboardData(text: await app.exportLocalData()));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(english
                            ? 'Backup copied as JSON.'
                            : 'تم نسخ النسخة الاحتياطية بصيغة JSON.')),
                  );
                },
              ),
              _DataRow(
                icon: Icons.restore_rounded,
                title: english ? 'Restore backup' : 'استعادة نسخة احتياطية',
                detail: english
                    ? 'Paste a Horse mobile JSON backup to restore this device.'
                    : 'الصق نسخة Horse الاحتياطية بصيغة JSON لاستعادتها على هذا الجهاز.',
                onTap: () => _restoreBackup(context, app),
              ),
              _DataRow(
                icon: Icons.history_toggle_off_rounded,
                title: english ? 'Clear viewing history' : 'مسح سجل المشاهدة',
                detail: english
                    ? '${app.history.length} records'
                    : '${app.history.length} سجل',
                destructive: true,
                onTap: () => _confirm(
                  context,
                  title:
                      english ? 'Clear viewing history?' : 'مسح سجل المشاهدة؟',
                  body: english
                      ? 'This also removes your Continue Watching progress.'
                      : 'سيؤدي هذا أيضًا إلى إزالة تقدم «متابعة المشاهدة».',
                  onConfirm: app.clearHistory,
                ),
              ),
              _DataRow(
                icon: Icons.delete_outline_rounded,
                title: english
                    ? 'Clear library and history'
                    : 'مسح المكتبة والسجل',
                detail: english
                    ? 'Remove saved titles and playback records from this account.'
                    : 'إزالة العناوين المحفوظة وسجلات التشغيل من هذا الحساب.',
                destructive: true,
                onTap: () => _confirm(
                  context,
                  title: english ? 'Clear your library?' : 'مسح مكتبتك؟',
                  body: english
                      ? 'Your add-ons and account will stay connected.'
                      : 'ستبقى الإضافات والحساب مرتبطين.',
                  onConfirm: app.clearLibraryData,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                english
                    ? 'Provider API credentials are kept on this device and excluded from cloud sync.'
                    : 'تُحفظ مفاتيح الخدمات على هذا الجهاز ولا تدخل ضمن المزامنة السحابية.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: HorseTheme.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required Future<void> Function() onConfirm,
  }) async {
    final english = context.read<AppState>().english;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(english ? 'Cancel' : 'إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(english ? 'Clear' : 'مسح')),
        ],
      ),
    );
    if (accepted == true) await onConfirm();
  }
}

Future<void> _restoreBackup(BuildContext context, AppState app) async {
  final english = app.english;
  final backup = await showDialog<String>(
    context: context,
    builder: (_) => _RestoreBackupDialog(english: english),
  );
  if (backup != null && context.mounted) {
    try {
      await app.restoreLocalData(backup);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(english ? 'Backup restored.' : 'تمت استعادة النسخة.'),
        ));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString().replaceFirst('FormatException: ', '')),
        ));
      }
    }
  }
}

class _RestoreBackupDialog extends StatefulWidget {
  const _RestoreBackupDialog({required this.english});
  final bool english;

  @override
  State<_RestoreBackupDialog> createState() => _RestoreBackupDialogState();
}

class _RestoreBackupDialogState extends State<_RestoreBackupDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.english ? 'Restore backup' : 'استعادة النسخة'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: _controller,
            minLines: 5,
            maxLines: 10,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              hintText:
                  widget.english ? 'Paste backup JSON' : 'الصق نص JSON هنا',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(widget.english ? 'Cancel' : 'إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: Text(widget.english ? 'Restore' : 'استعادة'),
          ),
        ],
      );
}

class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.icon,
    required this.title,
    required this.detail,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

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
            minVerticalPadding: 10,
            leading: Icon(icon,
                color: destructive ? const Color(0xFFFF8178) : HorseTheme.gold),
            title: Text(title,
                style: TextStyle(
                    color: destructive ? const Color(0xFFFFA29B) : null)),
            subtitle:
                Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: trailing ??
                const Icon(Icons.chevron_left_rounded, color: HorseTheme.muted),
          ),
        ),
      );
}

class SettingsAboutPage extends StatelessWidget {
  const SettingsAboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final english = context.watch<AppState>().english;
    return Scaffold(
      appBar: AppBar(title: Text(english ? 'About Horse' : 'حول Horse')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: HorseTheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: HorseTheme.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Horse',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 12),
                    Text(
                      english
                          ? 'An independent, open-source media center for the Stremio add-on protocol. Horse is not affiliated with Stremio, does not host or ship media, and users install their own add-ons.'
                          : 'مركز وسائط مستقل ومفتوح المصدر لبروتوكول إضافات Stremio. لا يرتبط Horse بـ Stremio ولا يستضيف أو يوزّع محتوى؛ ويثبّت المستخدم إضافاته بنفسه.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      english
                          ? 'MIT licensed. Attribution: Harbor desktop project.'
                          : 'مرخّص بموجب MIT. الإسناد: مشروع Harbor لسطح المكتب.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: HorseTheme.muted),
                    ),
                    const SizedBox(height: 12),
                    const SelectableText('github.com/harborstremio/harbor'),
                    const Divider(height: 28),
                    Text(
                      english
                          ? 'Movie metadata and images may be provided by TMDB.'
                          : 'قد تُقدَّم بيانات الأفلام وصورها عبر TMDB.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: HorseTheme.muted),
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
