import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';

class HorseAccountActions extends StatefulWidget {
  const HorseAccountActions({super.key, required this.app});
  final AppState app;

  @override
  State<HorseAccountActions> createState() => _HorseAccountActionsState();
}

class _HorseAccountActionsState extends State<HorseAccountActions> {
  bool _busy = false;
  String? _message;

  Future<void> _sync() async {
    final english = widget.app.english;
    final strategy = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(english ? 'Sync account' : 'مزامنة الحساب'),
        children: [
          (
            'merge',
            english ? 'Merge account and device' : 'دمج الحساب والجهاز'
          ),
          (
            'account',
            english
                ? 'Replace device data with account data'
                : 'استبدال بيانات الجهاز ببيانات الحساب'
          ),
          (
            'local',
            english
                ? 'Replace account data with this device'
                : 'استبدال بيانات الحساب ببيانات الجهاز'
          ),
        ]
            .map((entry) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, entry.$1),
                  child: Text(entry.$2),
                ))
            .toList(),
      ),
    );
    if (strategy == null) return;
    await _run(() => widget.app.syncHorseAccount(strategy: strategy),
        english ? 'Account synced.' : 'تمت مزامنة الحساب.');
  }

  Future<void> _devices() async {
    final english = widget.app.english;
    setState(() => _busy = true);
    try {
      var devices = await widget.app.api.horseSessions();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(english ? 'Signed-in devices' : 'الأجهزة المسجّلة'),
            content: SizedBox(
              width: 460,
              child: devices.isEmpty
                  ? Text(
                      english ? 'No sessions found.' : 'لا توجد جلسات مسجلة.')
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: devices.length,
                      itemBuilder: (context, index) {
                        final device = devices[index];
                        final current = device['current'] == true;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title:
                              Text((device['device'] ?? 'Device').toString()),
                          subtitle: Text(current
                              ? (english ? 'This device' : 'هذا الجهاز')
                              : (device['lastSeenAt'] ?? '').toString()),
                          trailing: current
                              ? null
                              : IconButton(
                                  tooltip: english
                                      ? 'Sign out device'
                                      : 'تسجيل الخروج من الجهاز',
                                  onPressed: () async {
                                    final id = device['id']?.toString();
                                    if (id == null || id.isEmpty) return;
                                    try {
                                      await widget.app.api
                                          .revokeHorseSession(id);
                                      devices =
                                          await widget.app.api.horseSessions();
                                      setDialogState(() {});
                                    } catch (error) {
                                      if (mounted) {
                                        setState(
                                            () => _message = _error(error));
                                      }
                                    }
                                  },
                                  icon: const Icon(Icons.logout_rounded),
                                ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(english ? 'Done' : 'تم'),
              ),
            ],
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _message = _error(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePassword() async {
    final english = widget.app.english;
    final credentials = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _ChangePasswordDialog(english: english),
    );
    if (credentials != null) {
      if (credentials.$2.length < 10) {
        setState(() => _message = english
            ? 'New password must be at least 10 characters.'
            : 'يجب ألا تقل كلمة المرور عن ١٠ أحرف.');
      } else {
        await _run(
          () => widget.app.api
              .changeHorsePassword(credentials.$1, credentials.$2),
          english ? 'Password changed.' : 'تم تغيير كلمة المرور.',
        );
      }
    }
  }

  Future<void> _export() async {
    final english = widget.app.english;
    await _run(() async {
      final data = await widget.app.api.exportHorseAccount();
      await Clipboard.setData(
        ClipboardData(text: const JsonEncoder.withIndent('  ').convert(data)),
      );
    }, english ? 'Full account export copied.' : 'تم نسخ تصدير الحساب الكامل.');
  }

  Future<void> _logoutAll() async {
    final english = widget.app.english;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
            english ? 'Sign out all devices?' : 'تسجيل الخروج من كل الأجهزة؟'),
        content: Text(english
            ? 'All Horse sessions will be revoked.'
            : 'سيتم إنهاء جميع جلسات Horse.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(english ? 'Cancel' : 'إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(english ? 'Sign out' : 'تسجيل الخروج')),
        ],
      ),
    );
    if (accepted == true) await _run(widget.app.logoutHorseAllDevices);
  }

  Future<void> _deleteAccount() async {
    final english = widget.app.english;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(english ? 'Delete Horse account?' : 'حذف حساب Horse؟'),
        content: Text(english
            ? 'This permanently deletes the Horse account and its server data. Local data on this device stays here.'
            : 'سيحذف هذا حساب Horse وبياناته على الخادم نهائيًا. ستبقى البيانات المحلية على هذا الجهاز.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(english ? 'Cancel' : 'إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8F342F)),
              child: Text(english ? 'Delete account' : 'حذف الحساب')),
        ],
      ),
    );
    if (accepted == true) await _run(widget.app.deleteHorseAccount);
  }

  Future<void> _run(Future<void> Function() action, [String? success]) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      if (mounted && success != null) setState(() => _message = success);
    } catch (error) {
      if (mounted) setState(() => _message = _error(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _error(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  @override
  Widget build(BuildContext context) {
    final english = widget.app.english;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _sync,
              icon: const Icon(Icons.sync_rounded),
              label: Text(english ? 'Sync now' : 'مزامنة الآن'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _devices,
              icon: const Icon(Icons.devices_outlined),
              label: Text(english ? 'Devices' : 'الأجهزة'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _changePassword,
              icon: const Icon(Icons.password_rounded),
              label: Text(english ? 'Change password' : 'تغيير كلمة المرور'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.download_outlined),
              label: Text(english ? 'Export account' : 'تصدير الحساب'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _logoutAll,
              icon: const Icon(Icons.logout_rounded),
              label: Text(english
                  ? 'Sign out all devices'
                  : 'تسجيل الخروج من كل الأجهزة'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _deleteAccount,
              icon: const Icon(Icons.delete_outline_rounded),
              label: Text(english ? 'Delete account' : 'حذف الحساب'),
            ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(color: HorseTheme.gold),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child:
                Text(_message!, style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.english});
  final bool english;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.english ? 'Change password' : 'تغيير كلمة المرور'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _current,
              obscureText: true,
              decoration: InputDecoration(
                labelText:
                    widget.english ? 'Current password' : 'كلمة المرور الحالية',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _next,
              obscureText: true,
              decoration: InputDecoration(
                labelText: widget.english
                    ? 'New password (10+ characters)'
                    : 'كلمة المرور الجديدة (١٠ أحرف فأكثر)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(widget.english ? 'Cancel' : 'إلغاء')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(context, (_current.text, _next.text)),
              child: Text(widget.english ? 'Save' : 'حفظ')),
        ],
      );
}
