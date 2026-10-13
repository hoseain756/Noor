import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';

class IntegrationsPage extends StatelessWidget {
  const IntegrationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final english = context.watch<AppState>().english;
    return Scaffold(
      appBar: AppBar(
          title: Text(english ? 'Connected services' : 'الخدمات المرتبطة')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
            children: [
              Text(
                english
                    ? 'Bring your watch history and playback services together.'
                    : 'اجمع سجل المشاهدة وخدمات التشغيل في مكان واحد.',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 7),
              Text(
                english
                    ? 'Trakt and Simkl link through your Horse account. Your personal TMDB and Debrid keys stay in secure device storage.'
                    : 'يرتبط Trakt وSimkl بحساب Horse. تُحفظ مفاتيح TMDB وDebrid الشخصية بأمان على الجهاز.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: HorseTheme.muted,
                    ),
              ),
              const SizedBox(height: 22),
              const _ServerEnvironmentCard(),
              const SizedBox(height: 12),
              _LinkedServiceCard(
                service: 'trakt',
                title: 'Trakt',
                subtitle: english
                    ? 'Import your watchlist and history; sync playback progress.'
                    : 'استيراد قائمتك وسجل المشاهدة ومزامنة تقدم التشغيل.',
                icon: Icons.local_movies_outlined,
              ),
              const SizedBox(height: 12),
              _LinkedServiceCard(
                service: 'simkl',
                title: 'Simkl',
                subtitle: english
                    ? 'Import your watchlist and history; sync playback progress.'
                    : 'استيراد قائمتك وسجل المشاهدة ومزامنة تقدم التشغيل.',
                icon: Icons.sync_rounded,
              ),
              const SizedBox(height: 12),
              const _TmdbKeyCard(),
              const SizedBox(height: 12),
              const _DevicePairingCard(),
              const SizedBox(height: 12),
              const _DebridCard(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServerEnvironmentCard extends StatefulWidget {
  const _ServerEnvironmentCard();

  @override
  State<_ServerEnvironmentCard> createState() => _ServerEnvironmentCardState();
}

class _ServerEnvironmentCardState extends State<_ServerEnvironmentCard> {
  late Future<_ServerEnvironmentReport> _report;

  @override
  void initState() {
    super.initState();
    _report = _loadReport();
  }

  Future<Map<String, dynamic>?> _readSafely(
    Future<Map<String, dynamic>> Function() request,
  ) async {
    try {
      return await request();
    } catch (_) {
      return null;
    }
  }

  Future<_ServerEnvironmentReport> _loadReport() async {
    final api = context.read<AppState>().api;
    final responses = await Future.wait([
      _readSafely(api.serverHealth),
      _readSafely(api.integrationStatus),
      _readSafely(api.mediaCapabilities),
    ]);
    return _ServerEnvironmentReport(
      health: responses[0],
      integrations: responses[1],
      capabilities: responses[2],
    );
  }

  Future<void> _refresh() async {
    setState(() => _report = _loadReport());
    await _report;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final english = app.english;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: HorseTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: HorseTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _ServiceIcon(icon: Icons.dns_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  english ? 'Horse server setup' : 'إعداد خادم Horse',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: english ? 'Refresh status' : 'تحديث الحالة',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 48, end: 4),
            child: Text(
              english
                  ? 'Server keys stay on Horse. This page checks which server integrations are configured.'
                  : 'تبقى مفاتيح الخادم في Horse. تعرض هذه الصفحة الخدمات المهيأة على الخادم.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: HorseTheme.muted,
                  ),
            ),
          ),
          const SizedBox(height: 8),
          FutureBuilder<_ServerEnvironmentReport>(
            future: _report,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 22),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              final report = snapshot.data;
              if (report == null || report.allUnavailable) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(48, 8, 8, 8),
                  child: Text(
                    english
                        ? 'Could not read the server status. Check the Horse server URL and try again.'
                        : 'تعذر قراءة حالة الخادم. تحقق من عنوان خادم Horse ثم أعد المحاولة.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFFF8178),
                        ),
                  ),
                );
              }

              final health = report.health;
              final integrations = report.integrations;
              final capabilities = report.capabilities;
              final tableCount = (health?['tables'] as num?)?.toInt();
              final rlsCount = (health?['rlsTables'] as num?)?.toInt();
              final databaseReady = health == null
                  ? null
                  : health['ok'] == true &&
                      (tableCount ?? 0) > 0 &&
                      rlsCount == tableCount;
              final torrentMode = capabilities?['torrent']?.toString();
              final torrentReady = torrentMode == null
                  ? null
                  : torrentMode == 'external' || torrentMode == 'builtin';
              final tmdbReady = app.api.tmdbUserKey?.isNotEmpty == true
                  ? true
                  : _configured(integrations, 'tmdb');
              final items = <_ServerServiceStatus>[
                _ServerServiceStatus(
                  title:
                      english ? 'Account sync database' : 'قاعدة مزامنة الحساب',
                  ready: databaseReady,
                  detail: _databaseDetail(
                    english,
                    health,
                    tableCount: tableCount,
                    rlsCount: rlsCount,
                  ),
                ),
                _ServerServiceStatus(
                  title: 'TMDB',
                  ready: tmdbReady,
                  detail: _tmdbDetail(
                    english,
                    tmdbReady,
                    personalKey: app.api.tmdbUserKey?.isNotEmpty == true,
                  ),
                ),
                _ServerServiceStatus(
                  title: 'Trakt',
                  ready: _configured(integrations, 'trakt'),
                  detail: _providerDetail(
                    english,
                    _configured(integrations, 'trakt'),
                  ),
                ),
                _ServerServiceStatus(
                  title: 'Simkl',
                  ready: _configured(integrations, 'simkl'),
                  detail: _providerDetail(
                    english,
                    _configured(integrations, 'simkl'),
                  ),
                ),
                _ServerServiceStatus(
                  title: english
                      ? 'Password recovery email'
                      : 'بريد استعادة كلمة المرور',
                  ready: _configured(integrations, 'email'),
                  detail: _configured(integrations, 'email') == null
                      ? _unavailableDetail(english)
                      : _configured(integrations, 'email') == true
                          ? (english
                              ? 'The Resend key is present; sender verification and delivery depend on Resend.'
                              : 'مفتاح Resend موجود؛ يعتمد اعتماد المرسل ووصول الرسالة على إعداد الخدمة.')
                          : (english
                              ? 'Set RESEND_API_KEY on the Horse server.'
                              : 'أضف RESEND_API_KEY إلى إعداد خادم Horse.'),
                ),
                _ServerServiceStatus(
                  title: 'OMDb',
                  ready: _configured(integrations, 'omdb'),
                  detail:
                      _ratingDetail(english, _configured(integrations, 'omdb')),
                ),
                _ServerServiceStatus(
                  title: 'MDBList',
                  ready: _configured(integrations, 'mdblist'),
                  detail: _ratingDetail(
                    english,
                    _configured(integrations, 'mdblist'),
                  ),
                ),
                _ServerServiceStatus(
                  title: english ? 'Torrent engine' : 'محرك التورنت',
                  ready: torrentReady,
                  detail: _torrentDetail(english, torrentMode),
                ),
              ];

              return Column(
                children: [
                  for (var index = 0; index < items.length; index++) ...[
                    _ServerServiceStatusTile(
                      item: items[index],
                      english: english,
                    ),
                    if (index < items.length - 1)
                      Divider(height: 1, color: HorseTheme.line.withAlpha(150)),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  bool? _configured(Map<String, dynamic>? response, String key) =>
      response?[key] is bool ? response![key] as bool : null;

  String _databaseDetail(
    bool english,
    Map<String, dynamic>? health, {
    required int? tableCount,
    required int? rlsCount,
  }) {
    if (health == null) return _unavailableDetail(english);
    if (health['ok'] != true) {
      return english
          ? 'Horse could not reach the database.'
          : 'تعذر على Horse الاتصال بقاعدة البيانات.';
    }
    if ((tableCount ?? 0) == 0) {
      return english
          ? 'The database is reachable, but its schema is empty.'
          : 'قاعدة البيانات متاحة لكن جداول التطبيق غير موجودة.';
    }
    if (rlsCount != tableCount) {
      return english
          ? 'Some public tables are missing row-level security.'
          : 'بعض جداول public لا تطبق سياسات أمان الصفوف.';
    }
    return english
        ? 'Connected; $tableCount public tables have row-level security.'
        : 'متصلة؛ أمان الصفوف مفعّل على جداول public وعددها $tableCount.';
  }

  String _providerDetail(bool english, bool? ready) => ready == null
      ? _unavailableDetail(english)
      : ready
          ? (english
              ? 'The provider client ID is present on the server; provider approval may still be needed.'
              : 'معرّف التطبيق موجود على الخادم؛ قد يلزم إكمال الموافقة لدى الخدمة.')
          : (english
              ? 'Add this provider’s client ID to the Horse server.'
              : 'أضف معرّف التطبيق لهذه الخدمة إلى خادم Horse.');

  String _tmdbDetail(
    bool english,
    bool? configured, {
    required bool personalKey,
  }) =>
      configured == null
          ? _unavailableDetail(english)
          : configured
              ? (english
                  ? personalKey
                      ? 'A personal key is saved on this device or TMDB is configured on Horse.'
                      : 'TMDB is configured on Horse; provider validity is checked when artwork loads.'
                  : personalKey
                      ? 'حُفظ مفتاح شخصي على هذا الجهاز أو تم إعداد TMDB على Horse.'
                      : 'تم إعداد TMDB على Horse؛ تتحقق الصفحة من صلاحية المزود عند جلب الصور.')
              : (english
                  ? 'Add a TMDB key to the Horse server or save your own below.'
                  : 'أضف مفتاح TMDB إلى خادم Horse أو احفظ مفتاحك أدناه.');

  String _ratingDetail(bool english, bool? ready) => ready == null
      ? _unavailableDetail(english)
      : ready
          ? (english
              ? 'The API key is present; provider validity and quota are checked when ratings load.'
              : 'مفتاح API موجود؛ تتحقق الصفحة من صلاحيته وحد الاستخدام عند جلب التقييمات.')
          : (english
              ? 'Add this API key to the Horse server.'
              : 'أضف مفتاح API لهذه الخدمة إلى خادم Horse.');

  String _torrentDetail(bool english, String? mode) => switch (mode) {
        'external' => english
            ? 'External engine mode is configured; playback checks whether it responds.'
            : 'وضع المحرك الخارجي مهيأ؛ يتحقق التشغيل من استجابة المحرك.',
        'builtin' => english
            ? 'Built-in engine mode is selected on this server.'
            : 'وضع محرك التورنت المدمج محدد على هذا الخادم.',
        'none' => english
            ? 'No torrent engine is configured; direct HTTP/HLS and Debrid remain available.'
            : 'لا يوجد محرك تورنت مهيأ؛ يظل HTTP/HLS وDebrid متاحين.',
        _ => _unavailableDetail(english),
      };

  String _unavailableDetail(bool english) => english
      ? 'Status could not be read from the Horse server.'
      : 'تعذر جلب الحالة من خادم Horse.';
}

class _ServerEnvironmentReport {
  const _ServerEnvironmentReport({
    required this.health,
    required this.integrations,
    required this.capabilities,
  });

  final Map<String, dynamic>? health;
  final Map<String, dynamic>? integrations;
  final Map<String, dynamic>? capabilities;

  bool get allUnavailable =>
      health == null && integrations == null && capabilities == null;
}

class _ServerServiceStatus {
  const _ServerServiceStatus({
    required this.title,
    required this.ready,
    required this.detail,
  });

  final String title;
  final bool? ready;
  final String detail;
}

class _ServerServiceStatusTile extends StatelessWidget {
  const _ServerServiceStatusTile({
    required this.item,
    required this.english,
  });

  final _ServerServiceStatus item;
  final bool english;

  @override
  Widget build(BuildContext context) {
    final color = item.ready == true
        ? HorseTheme.gold
        : item.ready == false
            ? const Color(0xFFFFB66D)
            : HorseTheme.muted;
    final icon = item.ready == true
        ? Icons.check_circle_rounded
        : item.ready == false
            ? Icons.settings_suggest_rounded
            : Icons.help_outline_rounded;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsetsDirectional.only(start: 48, end: 4),
      minVerticalPadding: 7,
      title: Text(item.title),
      subtitle: Text(item.detail),
      trailing: Tooltip(
        message: item.ready == true
            ? (english ? 'Configured' : 'مهيأ')
            : item.ready == false
                ? (english ? 'Needs setup' : 'يحتاج إعدادًا')
                : (english ? 'Unknown' : 'غير معروف'),
        child: Icon(icon, color: color),
      ),
    );
  }
}

class _TmdbKeyCard extends StatefulWidget {
  const _TmdbKeyCard();

  @override
  State<_TmdbKeyCard> createState() => _TmdbKeyCardState();
}

class _TmdbKeyCardState extends State<_TmdbKeyCard> {
  final TextEditingController _key = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _error = false;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final app = context.read<AppState>();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await app.api.saveTmdbUserKey(_key.text);
      if (!mounted) return;
      setState(() {
        _message = app.english
            ? 'TMDB key verified and saved securely on this device.'
            : 'تم التحقق من مفتاح TMDB وحفظه بأمان على هذا الجهاز.';
        _error = false;
      });
      _key.clear();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = _friendlyError(error);
        _error = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    await context.read<AppState>().api.clearTmdbUserKey();
    if (!mounted) return;
    setState(() {
      _message = context.read<AppState>().english
          ? 'TMDB key removed from this device.'
          : 'تمت إزالة مفتاح TMDB من هذا الجهاز.';
      _error = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final english = app.english;
    final connected = app.api.tmdbUserKey?.isNotEmpty == true;
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: HorseTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: HorseTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _ServiceIcon(icon: Icons.auto_awesome_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TMDB',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 3),
                    Text(
                      english
                          ? 'Power recommendations with your own API key.'
                          : 'فعّل الترشيحات بمفتاح TMDB الخاص بك.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (connected)
                const Icon(Icons.check_circle_rounded, color: HorseTheme.gold),
            ],
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(english ? 'TMDB features' : 'ميزات TMDB'),
            subtitle: Text(english
                ? 'Use TMDB recommendations when available.'
                : 'استخدم ترشيحات TMDB عند توفرها.'),
            value: app.webSettings['tmdbEnabled'] != false,
            onChanged: (value) => app.setSetting('tmdbEnabled', value),
          ),
          if (connected) ...[
            Text(
              english
                  ? 'A validated key is stored in secure device storage.'
                  : 'المفتاح المتحقق منه محفوظ في التخزين الآمن للجهاز.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: _busy ? null : _remove,
                icon: const Icon(Icons.key_off_rounded),
                label: Text(english ? 'Remove key' : 'إزالة المفتاح'),
              ),
            ),
          ] else ...[
            TextField(
              controller: _key,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText:
                    english ? 'TMDB API key or token' : 'مفتاح أو رمز TMDB',
                hintText: english
                    ? 'Paste your key or read token'
                    : 'ألصق المفتاح أو رمز القراءة',
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _busy ? null : _save,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.verified_user_outlined),
                label: Text(english ? 'Verify and save' : 'التحقق والحفظ'),
              ),
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(
              _message!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _error ? const Color(0xFFFF8178) : HorseTheme.gold,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DevicePairingCard extends StatefulWidget {
  const _DevicePairingCard();

  @override
  State<_DevicePairingCard> createState() => _DevicePairingCardState();
}

class _DevicePairingCardState extends State<_DevicePairingCard> {
  final _code = TextEditingController();
  Timer? _pollTimer;
  String _service = 'tmdb';
  String? _waitingCode;
  String? _displayCode;
  int? _expiresAt;
  String? _message;
  bool _busy = false;
  bool _error = false;

  @override
  void dispose() {
    _pollTimer?.cancel();
    _code.dispose();
    super.dispose();
  }

  String? _savedKey(AppState app) => _service == 'tmdb'
      ? app.api.tmdbUserKey
      : app.api.debridService == _service
          ? app.api.debridApiKey
          : null;

  Future<void> _receive() async {
    final app = context.read<AppState>();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await app.api.createPairingCode(_service);
      final code = result['code']?.toString() ?? '';
      if (code.length != 6) {
        throw const FormatException('تعذر إنشاء رمز الاقتران.');
      }
      if (!mounted) return;
      setState(() {
        _waitingCode = code;
        _displayCode = result['displayCode']?.toString() ??
            '${code.substring(0, 3)}-${code.substring(3)}';
        _expiresAt = (result['expiresAt'] as num?)?.toInt();
      });
      _schedulePoll();
    } catch (error) {
      _setMessage(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _schedulePoll([Duration delay = const Duration(seconds: 3)]) {
    _pollTimer?.cancel();
    _pollTimer = Timer(delay, _poll);
  }

  Future<void> _poll() async {
    final code = _waitingCode;
    if (code == null) return;
    if (_expiresAt != null &&
        DateTime.now().millisecondsSinceEpoch >= _expiresAt!) {
      _finishWaiting(
        context.read<AppState>().english
            ? 'Pairing code expired.'
            : 'انتهت صلاحية رمز الاقتران.',
        error: true,
      );
      return;
    }
    try {
      final result = await context.read<AppState>().api.pairingStatus(code);
      if (!mounted) return;
      final status = result['status']?.toString();
      if (status == 'waiting') {
        _schedulePoll();
        return;
      }
      if (status == 'linked' && result['apiKey'] is String) {
        final app = context.read<AppState>();
        final service = result['service']?.toString() ?? _service;
        final apiKey = result['apiKey'] as String;
        if (service == 'tmdb') {
          await app.api.saveTmdbUserKey(apiKey);
        } else if (const {'realdebrid', 'alldebrid', 'torbox'}
            .contains(service)) {
          await app.configureDebrid(service, apiKey);
        } else {
          throw const FormatException('نوع خدمة الاقتران غير معروف.');
        }
        _finishWaiting(
          app.english
              ? '${_serviceName(service)} connected securely.'
              : 'تم ربط ${_serviceName(service)} بأمان.',
        );
        return;
      }
      _finishWaiting(
        context.read<AppState>().english
            ? 'Pairing code is no longer active.'
            : 'رمز الاقتران لم يعد نشطًا.',
        error: true,
      );
    } catch (error) {
      if (!mounted) return;
      if (_expiresAt == null ||
          DateTime.now().millisecondsSinceEpoch < _expiresAt!) {
        _schedulePoll(const Duration(seconds: 6));
      } else {
        _finishWaiting(_friendlyError(error), error: true);
      }
    }
  }

  void _finishWaiting(String message, {bool error = false}) {
    _pollTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _waitingCode = null;
      _displayCode = null;
      _expiresAt = null;
      _message = message;
      _error = error;
    });
  }

  Future<void> _cancelReceive() async {
    final code = _waitingCode;
    _pollTimer?.cancel();
    if (code != null) {
      try {
        await context.read<AppState>().api.cancelPairingCode(code);
      } catch (_) {
        // Local waiting still ends if the cancellation request is offline.
      }
    }
    if (mounted) {
      setState(() {
        _waitingCode = null;
        _displayCode = null;
        _expiresAt = null;
        _message = null;
      });
    }
  }

  Future<void> _sendSavedKey() async {
    final app = context.read<AppState>();
    final key = _savedKey(app);
    final code = _code.text.trim();
    if (key == null || key.isEmpty) {
      _setMessage(
        app.english
            ? 'Save this service key on the device first.'
            : 'احفظ مفتاح هذه الخدمة على الجهاز أولًا.',
        error: true,
      );
      return;
    }
    if (code.replaceAll(RegExp(r'[\s-]'), '').length != 6) {
      _setMessage(
        app.english
            ? 'Enter the six-character code.'
            : 'أدخل الرمز المكوّن من ٦ أحرف.',
        error: true,
      );
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await app.api.claimPairingCode(
        code: code,
        service: _service,
        apiKey: key,
      );
      _code.clear();
      _setMessage(
        app.english
            ? 'Key sent securely. The other device can finish pairing.'
            : 'أُرسل المفتاح بأمان. أكمل الاقتران على الجهاز الآخر.',
      );
    } catch (error) {
      _setMessage(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setMessage(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final english = app.english;
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: HorseTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: HorseTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _ServiceIcon(icon: Icons.phonelink_lock_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(english ? 'Device pairing' : 'اقتران الأجهزة',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 3),
                    Text(
                      english
                          ? 'Transfer a saved provider key with a temporary code.'
                          : 'انقل مفتاح خدمة محفوظًا برمز مؤقت.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _service,
            decoration:
                InputDecoration(labelText: english ? 'Service' : 'الخدمة'),
            items: const [
              DropdownMenuItem(value: 'tmdb', child: Text('TMDB')),
              DropdownMenuItem(value: 'realdebrid', child: Text('Real-Debrid')),
              DropdownMenuItem(value: 'alldebrid', child: Text('AllDebrid')),
              DropdownMenuItem(value: 'torbox', child: Text('TorBox')),
            ],
            onChanged: _busy || _waitingCode != null
                ? null
                : (value) => setState(() => _service = value ?? _service),
          ),
          const SizedBox(height: 10),
          if (_waitingCode != null) ...[
            Text(english
                ? 'Enter this code on the device sending its key. It expires in 10 minutes.'
                : 'أدخل هذا الرمز على الجهاز الذي سيرسل المفتاح. تنتهي صلاحيته بعد ١٠ دقائق.'),
            const SizedBox(height: 8),
            Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(
                _displayCode ?? '',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: HorseTheme.gold,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                    ),
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                        ClipboardData(text: _displayCode ?? ''));
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: Text(english ? 'Copy code' : 'نسخ الرمز'),
                ),
                TextButton(
                  onPressed: _cancelReceive,
                  child: Text(english ? 'Cancel' : 'إلغاء'),
                ),
              ],
            ),
          ] else ...[
            TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              textDirection: TextDirection.ltr,
              maxLength: 7,
              decoration: InputDecoration(
                labelText: english ? 'Other device code' : 'رمز الجهاز الآخر',
                hintText: 'ABC-123',
                counterText: '',
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _receive,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.vpn_key_outlined),
                  label: Text(english ? 'Receive a key' : 'استلام مفتاح'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _sendSavedKey,
                  icon: const Icon(Icons.send_rounded),
                  label: Text(
                      english ? 'Send saved key' : 'إرسال المفتاح المحفوظ'),
                ),
              ],
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(
              _message!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _error ? const Color(0xFFFF8178) : HorseTheme.gold,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LinkedServiceCard extends StatefulWidget {
  const _LinkedServiceCard({
    required this.service,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String service;
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  State<_LinkedServiceCard> createState() => _LinkedServiceCardState();
}

class _LinkedServiceCardState extends State<_LinkedServiceCard> {
  Timer? _pollTimer;
  Map<String, dynamic>? _flow;
  bool _busy = false;
  bool _syncing = false;
  String? _message;
  bool _error = false;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final app = context.read<AppState>();
    if (app.horseUser == null) {
      _setMessage(
        app.english
            ? 'Sign in to your Horse account first.'
            : 'سجّل الدخول إلى حساب Horse أولًا.',
        error: true,
      );
      return;
    }
    _pollTimer?.cancel();
    setState(() {
      _busy = true;
      _flow = null;
      _message = null;
    });
    try {
      final result = await app.api.startLinkedService(widget.service);
      final pollId = result['pollId']?.toString() ?? '';
      final code = result['userCode']?.toString() ?? '';
      final verificationUrl = result['verificationUrl']?.toString() ?? '';
      if (pollId.isEmpty || code.isEmpty || verificationUrl.isEmpty) {
        throw const FormatException('تعذر إنشاء رمز الربط.');
      }
      if (!mounted) return;
      setState(() {
        _flow = {
          'pollId': pollId,
          'userCode': code,
          'verificationUrl': verificationUrl,
          'intervalSec': (result['intervalSec'] as num?)?.toInt() ?? 5,
          'expiresAt': (result['expiresAt'] as num?)?.toInt() ??
              DateTime.now()
                  .add(const Duration(minutes: 10))
                  .millisecondsSinceEpoch,
          'status': 'waiting',
        };
      });
      await launchUrl(
        Uri.parse(verificationUrl),
        mode: LaunchMode.externalApplication,
      );
      _schedulePoll(
        Duration(seconds: (_flow?['intervalSec'] as int? ?? 5).clamp(3, 30)),
      );
    } catch (error) {
      _setMessage(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _schedulePoll(Duration delay) {
    _pollTimer?.cancel();
    _pollTimer = Timer(delay, _poll);
  }

  Future<void> _poll() async {
    final flow = _flow;
    if (flow == null || flow['status'] != 'waiting') return;
    final pollId = flow['pollId']?.toString() ?? '';
    try {
      final result = await context.read<AppState>().api.pollLinkedService(
            widget.service,
            pollId,
          );
      if (!mounted) return;
      final status = result['status']?.toString();
      if (status == 'authorized' && result['linkId'] is String) {
        await context.read<AppState>().saveLinkedService(widget.service, {
          'linkId': result['linkId'],
          'username': result['username'],
          'avatar': result['avatar'],
          'linkedAt': DateTime.now().millisecondsSinceEpoch,
        });
        if (!mounted) return;
        setState(() {
          _flow = null;
          _error = false;
          _message = context.read<AppState>().english
              ? 'Account connected.'
              : 'تم ربط الحساب.';
        });
        return;
      }
      if (status == 'pending') {
        final retryMs = (result['retryInMs'] as num?)?.toInt() ??
            ((_flow?['intervalSec'] as int? ?? 5) * 1000);
        _schedulePoll(Duration(milliseconds: retryMs.clamp(3000, 30000)));
        return;
      }
      setState(() {
        _flow = {...flow, 'status': status ?? 'failed'};
        _message = result['error']?.toString() ??
            (status == 'expired'
                ? (context.read<AppState>().english
                    ? 'The code expired.'
                    : 'انتهت صلاحية الرمز.')
                : (context.read<AppState>().english
                    ? 'The link was not approved.'
                    : 'لم تتم الموافقة على الربط.'));
        _error = true;
      });
    } catch (_) {
      // Keep the device flow alive through brief mobile-network interruptions.
      if (mounted) _schedulePoll(const Duration(seconds: 8));
    }
  }

  Future<void> _sync() async {
    setState(() {
      _syncing = true;
      _message = null;
    });
    try {
      final (watchlist, history) =
          await context.read<AppState>().syncLinkedService(widget.service);
      if (mounted) {
        final english = context.read<AppState>().english;
        _setMessage(
          english
              ? 'Imported $watchlist titles and $history history items.'
              : 'تم استيراد $watchlist عنوانًا و$history من سجل المشاهدة.',
        );
      }
    } catch (error) {
      _setMessage(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _unlink() async {
    await context.read<AppState>().unlinkService(widget.service);
    if (mounted) {
      _setMessage(
        context.read<AppState>().english
            ? 'Account disconnected.'
            : 'تم فصل الحساب.',
      );
    }
  }

  void _setMessage(String value, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = value;
      _error = error;
    });
  }

  void _cancelFlow() {
    _pollTimer?.cancel();
    setState(() => _flow = null);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final english = app.english;
    final linked = app.linkedServices[widget.service];
    final waiting = _flow?['status'] == 'waiting';
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: HorseTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: HorseTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ServiceIcon(icon: widget.icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 3),
                    Text(widget.subtitle,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              if (linked != null)
                const Icon(Icons.check_circle_rounded, color: HorseTheme.gold),
            ],
          ),
          const SizedBox(height: 14),
          if (linked != null) ...[
            Text(
              '${english ? 'Connected as' : 'متصل باسم'}  ${linked['username'] ?? widget.title}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (linked['lastSyncedAt'] is num)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 3),
                child: Text(
                  '${english ? 'Last synced' : 'آخر مزامنة'} · ${_formatSyncTime(linked['lastSyncedAt'] as num)}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: HorseTheme.muted),
                ),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _syncing ? null : _sync,
                  icon: _syncing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded),
                  label: Text(english ? 'Sync library' : 'مزامنة المكتبة'),
                ),
                TextButton.icon(
                  onPressed: _unlink,
                  icon: const Icon(Icons.link_off_rounded),
                  label: Text(english ? 'Disconnect' : 'فصل'),
                ),
              ],
            ),
          ] else if (waiting) ...[
            Text(
              english
                  ? 'Open ${widget.title} and enter this code:'
                  : 'افتح ${widget.title} وأدخل رمز التفعيل:',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SelectableText(
              _flow?['userCode']?.toString() ?? '',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: HorseTheme.gold,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: _flow?['userCode']?.toString() ?? ''),
                    );
                    if (mounted) {
                      _setMessage(
                        english ? 'Code copied.' : 'تم نسخ الرمز.',
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: Text(english ? 'Copy code' : 'نسخ الرمز'),
                ),
                OutlinedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(_flow?['verificationUrl'].toString() ?? ''),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text(
                      english ? 'Open activation page' : 'فتح صفحة التفعيل'),
                ),
                TextButton(
                  onPressed: _cancelFlow,
                  child: Text(english ? 'Cancel' : 'إلغاء'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              english ? 'Waiting for approval…' : 'بانتظار الموافقة…',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: HorseTheme.muted,
                  ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy || app.horseUser == null ? null : _start,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link_rounded),
                label: Text(
                  app.horseUser == null
                      ? (english
                          ? 'Sign in to Horse first'
                          : 'سجّل الدخول إلى Horse أولًا')
                      : (english
                          ? 'Connect ${widget.title}'
                          : 'ربط ${widget.title}'),
                ),
              ),
            ),
            if (_flow?['status'] != null)
              TextButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(english ? 'Generate a new code' : 'إنشاء رمز جديد'),
              ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(
              _message!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _error ? const Color(0xFFFF8178) : HorseTheme.gold,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

String _formatSyncTime(num timestamp) {
  final value =
      DateTime.fromMillisecondsSinceEpoch(timestamp.toInt()).toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
}

class _DebridCard extends StatefulWidget {
  const _DebridCard();

  @override
  State<_DebridCard> createState() => _DebridCardState();
}

class _DebridCardState extends State<_DebridCard> {
  final _key = TextEditingController();
  String _service = 'realdebrid';
  bool _busy = false;
  String? _message;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _service = context.read<AppState>().api.debridService ?? _service;
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_key.text.trim().isEmpty) return;
    final app = context.read<AppState>();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await app.configureDebrid(_service, _key.text);
      _key.clear();
      if (mounted) {
        setState(() {
          _message = app.english
              ? 'Key verified and saved securely.'
              : 'تم التحقق من المفتاح وحفظه بأمان.';
          _error = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = _friendlyError(error);
          _error = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    await context.read<AppState>().disconnectDebrid();
    if (mounted) {
      setState(() {
        _message = context.read<AppState>().english
            ? 'Debrid service disconnected.'
            : 'تم فصل خدمة Debrid.';
        _error = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final english = app.english;
    final service = app.api.debridService;
    final connected = service != null && app.api.debridApiKey != null;
    final user = app.debridUser;
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: HorseTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: HorseTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _ServiceIcon(icon: Icons.bolt_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Debrid',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 3),
                    Text(
                      english
                          ? 'Unlock cached torrent streams.'
                          : 'تشغيل التورنتات المتاحة عبر خدمة Debrid.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (connected)
                const Icon(Icons.check_circle_rounded, color: HorseTheme.gold),
            ],
          ),
          const SizedBox(height: 14),
          if (connected) ...[
            Text(
              '${_serviceName(service)}${user?['username'] == null ? '' : ' · ${user!['username']}'}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (user?['premium'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '${english ? 'Plan' : 'الخطة'}: ${user!['premium']}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: _busy ? null : _remove,
                icon: const Icon(Icons.link_off_rounded),
                label: Text(english ? 'Remove key' : 'إزالة المفتاح'),
              ),
            ),
          ] else ...[
            DropdownButtonFormField<String>(
              initialValue: _service,
              decoration:
                  InputDecoration(labelText: english ? 'Service' : 'الخدمة'),
              items: const [
                DropdownMenuItem(
                    value: 'realdebrid', child: Text('Real-Debrid')),
                DropdownMenuItem(value: 'alldebrid', child: Text('AllDebrid')),
                DropdownMenuItem(value: 'torbox', child: Text('TorBox')),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _service = value ?? _service),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _key,
              obscureText: true,
              autocorrect: false,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: english ? 'API key' : 'مفتاح API',
                hintText: english
                    ? 'Paste your service API key'
                    : 'ألصق مفتاح الخدمة',
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _busy ? null : _save,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.verified_user_outlined),
                label: Text(english ? 'Verify and save' : 'التحقق والحفظ'),
              ),
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(
              _message!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _error ? const Color(0xFFFF8178) : HorseTheme.gold,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ServiceIcon extends StatelessWidget {
  const _ServiceIcon({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: HorseTheme.gold.withValues(alpha: .11),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: HorseTheme.gold),
      );
}

String _serviceName(String? service) => switch (service) {
      'tmdb' => 'TMDB',
      'realdebrid' => 'Real-Debrid',
      'alldebrid' => 'AllDebrid',
      'torbox' => 'TorBox',
      _ => 'Debrid',
    };

String _friendlyError(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['error'] is String) return data['error'] as String;
  }
  return error
      .toString()
      .replaceFirst(RegExp(r'^(Exception|FormatException):\s*'), '');
}
