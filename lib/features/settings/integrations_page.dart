import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';
import '../../core/track/track_link.dart';
import '../../shared/widgets/noor_toast.dart';

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
                    ? 'Trakt and Simkl link directly from this device — no account needed. Your personal TMDB and Debrid keys stay in secure device storage.'
                    : 'يرتبط Trakt وSimkl مباشرة من هذا الجهاز دون حساب. تُحفظ مفاتيح TMDB وDebrid الشخصية بأمان على الجهاز.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: HorseTheme.muted,
                    ),
              ),
              const SizedBox(height: 22),
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
              _LinkedServiceCard(
                service: 'anilist',
                title: 'AniList',
                subtitle: english
                    ? 'Track anime lists, progress and scores; sync your library.'
                    : 'تتبّع قوائم الأنمي وتقدمك وتقييماتك ومزامنة مكتبتك.',
                icon: Icons.auto_stories_outlined,
              ),
              const SizedBox(height: 12),
              _LinkedServiceCard(
                service: 'mal',
                title: 'MyAnimeList',
                subtitle: english
                    ? 'Track anime lists, progress and scores; sync your library.'
                    : 'تتبّع قوائم الأنمي وتقدمك وتقييماتك ومزامنة مكتبتك.',
                icon: Icons.menu_book_outlined,
              ),
              const SizedBox(height: 12),
              const _TmdbKeyCard(),
              const SizedBox(height: 12),
              const _DebridCard(),
            ],
          ),
        ),
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

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final app = context.read<AppState>();
    setState(() => _busy = true);
    try {
      await app.api.saveTmdbUserKey(_key.text);
      if (!mounted) return;
      _key.clear();
      NoorToast.show(
        context,
        app.english
            ? 'TMDB key verified and saved securely on this device.'
            : 'تم التحقق من مفتاح TMDB وحفظه بأمان على هذا الجهاز.',
      );
    } catch (error) {
      if (!mounted) return;
      NoorToast.show(context, _friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final app = context.read<AppState>();
    await app.api.clearTmdbUserKey();
    if (!mounted) return;
    NoorToast.show(
      context,
      app.english
          ? 'TMDB key removed from this device.'
          : 'تمت إزالة مفتاح TMDB من هذا الجهاز.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final english = app.english;
    final connected = app.api.hasUserTmdbKey;
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
            Text(
              english
                  ? 'Built-in default key — works with no setup.'
                  : 'مفتاح مضمّن افتراضيًا — يعمل بدون إعداد.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: HorseTheme.muted,
                  ),
            ),
            const SizedBox(height: 8),
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
  // Trakt return-leg choice: 'direct' (noor://callback — straight back into
  // the app, no website) or 'relay' (the registered HTTPS companion).
  String _traktMethod = 'direct';
  bool _traktMethodLoaded = false;
  // Paste fallback shared by every browser-OAuth service (Trakt/AniList/MAL).
  final TextEditingController _codeCtrl = TextEditingController();
  bool _submittingCode = false;
  // AniList credential override editor (the embedded Client ID is a
  // placeholder AniList rejects — the real numeric ID lives in the user's
  // developer dashboard, and confidential apps also need the secret).
  bool _showCredEditor = false;
  final TextEditingController _credIdCtrl = TextEditingController();
  final TextEditingController _credSecretCtrl = TextEditingController();
  bool _savingCred = false;
  String? _credError;
  bool _anilistNeedsSetup = false;

  @override
  void initState() {
    super.initState();
    if (widget.service == 'trakt') {
      context.read<AppState>().api.traktLinkMethod().then((method) {
        if (mounted) {
          setState(() {
            _traktMethod = method;
            _traktMethodLoaded = true;
          });
        }
      });
    }
    if (widget.service == 'anilist' || widget.service == 'mal') {
      // Live profile (username / avatar / anime stats) for the linked card.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final app = context.read<AppState>();
        if (app.linkedServices[widget.service]?['linked'] == true) {
          unawaited(app.refreshTrackerProfile(widget.service));
        }
      });
    }
    if (widget.service == 'anilist') {
      // Pre-fill the credentials editor with the effective override so the
      // user sees exactly what the OAuth URL will carry.
      context.read<AppState>().api.aniListCredentials().then((creds) {
        if (!mounted) return;
        setState(() {
          _credIdCtrl.text = creds.$1;
          _credSecretCtrl.text = creds.$2;
        });
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _codeCtrl.dispose();
    _credIdCtrl.dispose();
    _credSecretCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTraktMethod(String method) async {
    if (method == _traktMethod) return;
    // Changing the return leg invalidates any pending handshake — drop it
    // so a stale verifier can never complete against the wrong redirect.
    await context.read<AppState>().api.setTraktLinkMethod(method);
    if (!mounted) return;
    setState(() {
      _traktMethod = method;
      _flow = null;
    });
  }

  Future<void> _submitCode() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty || _submittingCode) return;
    setState(() => _submittingCode = true);
    final app = context.read<AppState>();
    final Map<String, dynamic> result;
    switch (widget.service) {
      case 'trakt':
        result = await app.completeTraktWithCode(code);
      case 'anilist':
        result = await app.completeAniListWithCode(code);
      case 'mal':
        result = await app.completeMalWithCode(code);
      default:
        result = <String, dynamic>{'status': 'error', 'reason': 'unsupported'};
    }
    if (!mounted) return;
    setState(() => _submittingCode = false);
    final english = app.english;
    if (result['status']?.toString() == 'success') {
      _codeCtrl.clear();
      setState(() {
        _flow = null;
        _anilistNeedsSetup = false;
      });
      if (widget.service == 'anilist' || widget.service == 'mal') {
        unawaited(app.refreshTrackerProfile(widget.service));
      }
      NoorToast.show(context, english ? 'Account connected.' : 'تم ربط الحساب.');
    } else {
      final failedCredentials = result['reason']?.toString() == 'invalid_client';
      setState(() {
        if (widget.service == 'anilist' && failedCredentials) {
          _showCredEditor = true;
          _anilistNeedsSetup = true;
        }
      });
      NoorToast.show(
        context,
        _oauthFailureText(app.english, result['reason']?.toString()),
        error: true,
      );
    }
  }

  String _oauthFailureText(bool english, String? reason) {
    if (reason == 'invalid_client') {
      return english
          ? 'AniList rejected the app credentials — enter the numeric Client ID (and secret) below and retry.'
          : 'رفض AniList بيانات التطبيق — أدخل معرّف العميل الرقمي (والسر) أدناه وأعد المحاولة.';
    }
    if (reason == 'state_mismatch' || reason == 'flow_expired' || reason == 'no_pending_flow') {
      return english
          ? 'This code has expired — start a new link and paste the fresh code.'
          : 'انتهت صلاحية هذا الرمز — ابدأ ربطًا جديدًا والصق الرمز الحديث.';
    }
    return english
        ? 'Could not complete with this code — check it or restart the link.'
        : 'تعذر الإكمال بهذا الرمز — تحقق منه أو أعد بدء الربط.';
  }

  /// Persists the AniList credential override in secure storage after
  /// validating the shape (AniList IDs are numeric). Empty id clears the
  /// override; an invalid id keeps the editor open with an inline error.
  Future<void> _saveCredentials() async {
    if (_savingCred) return;
    final app = context.read<AppState>();
    final english = app.english;
    final id = _credIdCtrl.text.trim();
    final secret = _credSecretCtrl.text.trim();
    if (id.isNotEmpty && !isValidAniListClientId(id)) {
      setState(() {
        _credError = english
            ? 'AniList Client IDs are numbers (e.g. 2789) — this doesn\'t look like one.'
            : 'معرّفات AniList أرقام فقط (مثل 2789) — هذه القيمة لا تشبهها.';
      });
      return;
    }
    setState(() {
      _savingCred = true;
      _credError = null;
    });
    await app.api.saveAniListCredentials(
      clientId: id,
      clientSecret: secret,
    );
    if (!mounted) return;
    setState(() {
      _savingCred = false;
      _showCredEditor = false;
      _anilistNeedsSetup = false;
    });
    NoorToast.show(
      context,
      english
          ? 'AniList credentials saved securely.'
          : 'تم حفظ بيانات AniList بأمان.',
    );
  }

  /// The always-available AniList credentials section: warning banner when a
  /// flow failed on credentials, the toggle, the developer-dashboard
  /// walkthrough and the editor itself (numeric-ID validated).
  List<Widget> _anilistCredentialsSection(bool english) {
    return [
      if (_anilistNeedsSetup) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: HorseTheme.gold.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: HorseTheme.gold.withValues(alpha: .35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: HorseTheme.gold,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  english
                      ? 'One step left: enter the numeric Client ID from anilist.co/settings/developer — your Client Secret is already saved in the app.'
                      : 'خطوة واحدة متبقية: أدخل معرّف العميل الرقمي من anilist.co/settings/developer — سر العميل محفوظ مسبقًا داخل التطبيق.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 6),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: () => setState(() {
            _showCredEditor = !_showCredEditor;
            _credError = null;
          }),
          icon: const Icon(Icons.key_rounded, size: 17),
          label: Text(
            english
                ? (_showCredEditor
                    ? 'Hide app credentials'
                    : 'App credentials')
                : (_showCredEditor
                    ? 'إخفاء بيانات التطبيق'
                    : 'بيانات التطبيق'),
          ),
        ),
      ),
      if (_showCredEditor) ...[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: HorseTheme.surface.withValues(alpha: .55),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: HorseTheme.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                english
                    ? 'One-time setup — get your AniList credentials:'
                    : 'إعداد لمرة واحدة — احصل على بيانات AniList:',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 6),
              _credStep(
                english,
                '1',
                english
                    ? 'Open anilist.co/settings/developer and press “Create New App”.'
                    : 'افتح anilist.co/settings/developer واضغط «Create New App».',
              ),
              _credStep(
                english,
                '2',
                english
                    ? 'Name it anything (e.g. Noor) and set its Redirect URL to app.noor.mobile://callback'
                    : 'سمّه ما شئت (مثل Noor) وضع في حقل Redirect URL القيمة app.noor.mobile://callback',
              ),
              _credStep(
                english,
                '3',
                english
                    ? 'Copy the Client ID (a number like 2789) and the Client Secret.'
                    : 'انسخ معرّف العميل (رقم مثل 2789) وسر العميل.',
              ),
              _credStep(
                english,
                '4',
                english
                    ? 'Paste both below, save, then press Connect again.'
                    : 'الصقهما أدناه واحفظ، ثم اضغط «ربط» من جديد.',
              ),
              const SizedBox(height: 8),
              Text(
                english
                    ? 'Your 40-character value is already saved as the Client Secret — only the small number (Client ID) shown beside it on the dashboard is missing.'
                    : 'قيمتك ذات الـ40 حرفًا محفوظة الآن كسر عميل — تبقى فقط إضافة الرقم الصغير (معرّف العميل) الظاهر بجانبها في لوحة المطوّر.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: HorseTheme.muted,
                    ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse('https://anilist.co/settings/developer'),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text(
                    english
                        ? 'Open the AniList developer settings'
                        : 'فتح إعدادات مطوّر AniList',
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _credIdCtrl,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textDirection: TextDirection.ltr,
          style: Theme.of(context).textTheme.bodySmall,
          decoration: InputDecoration(
            isDense: true,
            labelText: english ? 'Client ID' : 'معرّف العميل',
            hintText: english ? 'e.g. 2789' : 'مثال: 2789',
            errorText: _credError,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _credSecretCtrl,
          autocorrect: false,
          enableSuggestions: false,
          obscureText: true,
          textDirection: TextDirection.ltr,
          style: Theme.of(context).textTheme.bodySmall,
          decoration: InputDecoration(
            isDense: true,
            labelText: english
                ? 'Client secret (AniList requires it for every app)'
                : 'سر العميل (يشترطه AniList لكل تطبيق)',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.tonalIcon(
            onPressed: _savingCred ? null : _saveCredentials,
            icon: _savingCred
                ? const SizedBox.square(
                    dimension: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.verified_user_outlined, size: 18),
            label: Text(english ? 'Save credentials' : 'حفظ البيانات'),
          ),
        ),
      ],
    ];
  }

  Widget _credStep(bool english, String number, String text) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 17,
            height: 17,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: HorseTheme.gold,
            ),
            child: Text(
              number,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.black,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall,
              textDirection: english ? TextDirection.ltr : TextDirection.rtl,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _start() async {
    final app = context.read<AppState>();
    _pollTimer?.cancel();
    setState(() {
      _busy = true;
      _flow = null;
    });
    try {
      if (widget.service == 'anilist' || widget.service == 'mal') {
        // Browser OAuth over app.noor.mobile://callback (RFC 8252): approve
        // on the provider and the OS bounces straight back into Noor; the
        // paste field below is the fallback when the bounce never fires.
        final result = widget.service == 'anilist'
            ? await app.api.startAniListLink()
            : await app.api.startMalLink();
        if (widget.service == 'anilist' &&
            result?['status']?.toString() == 'invalid_client_id') {
          // The authorize page would only show an unknown-client error —
          // surface the credentials editor with the setup guide instead.
          if (!mounted) return;
          setState(() {
            _showCredEditor = true;
            _anilistNeedsSetup = true;
          });
          NoorToast.show(
            context,
            app.english
                ? 'Just one number missing: your AniList Client ID.'
                : 'يبقى رقم واحد فقط: معرّف AniList الخاص بك.',
            error: true,
          );
          return;
        }
        final authorizeUrl = result?['authorizeUrl']?.toString() ?? '';
        if (authorizeUrl.isEmpty) {
          throw const FormatException('تعذر بدء الربط.');
        }
        if (!mounted) return;
        setState(() {
          _flow = {'status': 'waiting', 'kind': 'browser'};
        });
        await launchUrl(
          Uri.parse(authorizeUrl),
          mode: LaunchMode.externalApplication,
        );
        return;
      }
      if (widget.service == 'trakt') {
        // Browser PKCE (RFC 7636/8252): the user's Trakt app is PKCE-only —
        // Trakt issues NO client secret for it and its device grant rejects
        // secret-less exchanges, so the device flow can never complete.
        // Return leg per the user's choice: direct (noor://callback — the OS
        // bounces back into Noor the moment Trakt approves) or relay (the
        // companion site stores the code and the app-wide watcher fetches
        // it). IncomingLinkListener finishes the handshake either way.
        final result = await app.api.startTraktLink();
        final authorizeUrl = result?['authorizeUrl']?.toString() ?? '';
        if (authorizeUrl.isEmpty) {
          throw const FormatException('تعذر بدء ربط Trakt.');
        }
        if (!mounted) return;
        setState(() {
          _flow = {'status': 'waiting', 'kind': 'pkce'};
        });
        if (_traktMethod == 'relay') {
          // Relay leg only: the browser lands on the Noor companion which
          // stores the code — this watcher fetches it and finishes the
          // exchange even if this sheet is closed. Direct flows complete
          // via the noor:// deep link instead; there is nothing to poll.
          app.beginTraktRelayWatch();
        }
        await launchUrl(
          Uri.parse(authorizeUrl),
          mode: LaunchMode.externalApplication,
        );
        return;
      }
      final result = await app.api.startLinkedService(widget.service);
      final deviceCode = result?['device_code']?.toString() ?? '';
      final code = result?['user_code']?.toString() ?? '';
      // Simkl's OAuth 2.0 flow names the field verification_uri(_complete);
      // accept every variant just in case.
      final verificationUrl = (result?['verification_uri_complete'] ??
              result?['verification_uri'] ??
              result?['verification_url'])
          ?.toString() ??
          '';
      if (deviceCode.isEmpty || code.isEmpty || verificationUrl.isEmpty) {
        throw const FormatException('تعذر إنشاء رمز الربط.');
      }
      if (!mounted) return;
      final interval =
          ((result?['interval'] as num?)?.toInt() ?? 5).clamp(3, 30);
      setState(() {
        _flow = {
          'device_code': deviceCode,
          'user_code': code,
          'verification_url': verificationUrl,
          'interval': interval,
          'expiresAt': DateTime.now()
              .add(
                Duration(seconds: (result?['expires_in'] as num?)?.toInt() ?? 600),
              )
              .millisecondsSinceEpoch,
          'status': 'waiting',
          'kind': 'device',
        };
      });
      await launchUrl(
        Uri.parse(verificationUrl),
        mode: LaunchMode.externalApplication,
      );
      _schedulePoll(Duration(seconds: interval));
    } catch (error) {
      if (mounted) NoorToast.show(context, _friendlyError(error), error: true);
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
    try {
      final result = await context.read<AppState>().api.pollLinkedService(
            widget.service,
            flow,
          );
      if (!mounted) return;
      final status = result?['status']?.toString();
      if (status == 'success') {
        // NoorApi stores the provider token in secure storage itself; only
        // the display state is mirrored into app state.
        await context.read<AppState>().saveLinkedService(widget.service, {
          'linked': true,
          'linkedAt': DateTime.now().millisecondsSinceEpoch,
        });
        if (!mounted) return;
        setState(() {
          _flow = null;
        });
        NoorToast.show(
          context,
          context.read<AppState>().english
              ? 'Account connected.'
              : 'تم ربط الحساب.',
        );
        return;
      }
      if (status == 'pending') {
        final retryMs = ((flow['interval'] as int? ?? 5) * 1000)
            .clamp(3000, 30000);
        _schedulePoll(Duration(milliseconds: retryMs));
        return;
      }
      setState(() {
        _flow = {...flow, 'status': status ?? 'error'};
      });
      NoorToast.show(
        context,
        context.read<AppState>().english
            ? 'The link was not approved. Generate a new code and try again.'
            : 'لم تتم الموافقة على الربط. أنشئ رمزًا جديدًا وأعد المحاولة.',
        error: true,
      );
    } catch (_) {
      // Keep the device flow alive through brief mobile-network interruptions.
      if (mounted) _schedulePoll(const Duration(seconds: 8));
    }
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final (watchlist, history) =
          await context.read<AppState>().syncLinkedService(widget.service);
      if (mounted) {
        final english = context.read<AppState>().english;
        NoorToast.show(
          context,
          english
              ? 'Imported $watchlist titles and $history history items.'
              : 'تم استيراد $watchlist عنوانًا و$history من سجل المشاهدة.',
        );
      }
    } catch (error) {
      if (mounted) NoorToast.show(context, _friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _unlink() async {
    await context.read<AppState>().unlinkService(widget.service);
    if (mounted) {
      NoorToast.show(
        context,
        context.read<AppState>().english
            ? 'Account disconnected.'
            : 'تم فصل الحساب.',
      );
    }
  }

  void _cancelFlow() {
    _pollTimer?.cancel();
    switch (widget.service) {
      case 'trakt':
        // Drop the stored PKCE pair so a stale verifier can't complete later.
        context.read<AppState>().api.cancelTraktLink();
      case 'anilist':
        context.read<AppState>().api.cancelAniListLink();
      case 'mal':
        context.read<AppState>().api.cancelMalLink();
    }
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
            Row(
              children: [
                if ((linked['avatar']?.toString() ?? '').isNotEmpty) ...[
                  CircleAvatar(
                    radius: 17,
                    backgroundImage:
                        NetworkImage(linked['avatar'].toString()),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${english ? 'Connected as' : 'متصل باسم'}  ${linked['username'] ?? widget.title}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (linked['lastSyncedAt'] is num)
                        Padding(
                          padding:
                              const EdgeInsetsDirectional.only(top: 3),
                          child: Text(
                            '${english ? 'Last synced' : 'آخر مزامنة'} · ${_formatSyncTime(linked['lastSyncedAt'] as num)}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: HorseTheme.muted),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (widget.service == 'anilist' || widget.service == 'mal') ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  if (linked['animeCount'] is num)
                    _ProfileStat(
                      english ? 'Anime' : 'أعمال',
                      '${(linked['animeCount'] as num).toInt()}',
                    ),
                  if (linked['episodesWatched'] is num)
                    _ProfileStat(
                      english ? 'Episodes' : 'حلقات',
                      '${(linked['episodesWatched'] as num).toInt()}',
                    ),
                  if (linked['meanScore'] is num)
                    _ProfileStat(
                      english ? 'Mean score' : 'متوسط التقييم',
                      (linked['meanScore'] as num).toStringAsFixed(1),
                    ),
                ],
              ),
            ],
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
          ] else if (waiting && _flow?['kind'] == 'browser') ...[
            Text(
              english
                  ? 'Approve the link in the ${widget.title} browser tab — the browser returns straight into Noor the moment you approve (Redirect URI app.noor.mobile://callback).'
                  : 'وافق على الربط في تبويب ${widget.title} بالمتصفح — سيعيدك المتصفح إلى التطبيق فور الموافقة (Redirect URI ‏app.noor.mobile://callback).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    english ? 'Waiting for approval…' : 'بانتظار الموافقة…',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: HorseTheme.muted,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              english
                  ? 'Browser stuck or showing an auth code? Paste it here:'
                  : 'المتصفح متوقف أو يُظهر رمز تفويض؟ الصقه هنا:',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeCtrl,
                    textAlign: TextAlign.start,
                    textDirection: TextDirection.ltr,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: Theme.of(context).textTheme.bodySmall,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: english ? 'Authorization code' : 'رمز التفويض',
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => unawaited(_submitCode()),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _submittingCode ? null : _submitCode,
                  child: _submittingCode
                      ? const SizedBox.square(
                          dimension: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(english ? 'Finish' : 'إكمال'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: _cancelFlow,
                child: Text(english ? 'Cancel' : 'إلغاء'),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              english
                  ? 'One-time setup: register app.noor.mobile://callback as the app Redirect URI in the ${widget.title} developer settings.'
                  : 'إعداد لمرة واحدة: سجّل app.noor.mobile://callback كـ Redirect URI للتطبيق في إعدادات مطوّر ${widget.title}.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: HorseTheme.muted,
                  ),
            ),
            if (widget.service == 'anilist')
              ..._anilistCredentialsSection(english),
          ] else if (waiting && _flow?['kind'] == 'pkce') ...[
            Text(
              _traktMethod == 'direct'
                  ? (english
                      ? 'Complete the approval in the Trakt browser tab — Trakt bounces you straight back into Noor the moment you approve (no website involved).'
                      : 'أكمل الموافقة في تبويب Trakt بالمتصفح — سيعيدك Trakt إلى التطبيق فور الموافقة مباشرة (بدون أي موقع وسيط).')
                  : (english
                      ? 'Complete the approval in the Trakt browser tab — Noor finishes the link automatically the moment Trakt approves (you may need to switch back to the app).'
                      : 'أكمل الموافقة في تبويب Trakt بالمتصفح — سيُكمل التطبيق الربط تلقائيًا فور الموافقة (قد تحتاج للعودة إلى التطبيق يدويًا).'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    english ? 'Waiting for approval…' : 'بانتظار الموافقة…',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: HorseTheme.muted,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              english
                  ? 'Browser stuck or showing an auth code? Paste it here:'
                  : 'المتصفح متوقف أو يُظهر رمز تفويض؟ الصقه هنا:',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeCtrl,
                    textAlign: TextAlign.start,
                    textDirection: TextDirection.ltr,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: Theme.of(context).textTheme.bodySmall,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: english ? 'Authorization code' : 'رمز التفويض',
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => unawaited(_submitCode()),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _submittingCode ? null : _submitCode,
                  child: _submittingCode
                      ? const SizedBox.square(
                          dimension: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(english ? 'Finish' : 'إكمال'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: _cancelFlow,
                child: Text(english ? 'Cancel' : 'إلغاء'),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _traktMethod == 'direct'
                  ? (english
                      ? 'If Trakt shows an error after approving, add noor://callback to the Redirect URIs on trakt.tv/oauth/applications (one time) — or switch the method above to “Via website”.'
                      : 'إن ظهرت رسالة خطأ من Trakt بعد الموافقة، أضف noor://callback إلى قائمة Redirect URIs في لوحة Trakt (مرة واحدة) — أو بدّل الطريقة إلى «عبر الموقع».')
                  : (english
                      ? 'No setup needed — Trakt returns the approval to Noor through the Noor companion site automatically.'
                      : 'لا حاجة لأي إعداد — يعيد Trakt الموافقة إلى التطبيق تلقائيًا عبر موقع Noor المصاحب.'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: HorseTheme.muted,
                  ),
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
              _flow?['user_code']?.toString() ?? '',
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
                      ClipboardData(text: _flow?['user_code']?.toString() ?? ''),
                    );
                    if (!mounted) return;
                    NoorToast.show(
                      this.context,
                      english ? 'Code copied.' : 'تم نسخ الرمز.',
                    );
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: Text(english ? 'Copy code' : 'نسخ الرمز'),
                ),
                OutlinedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(_flow?['verification_url']?.toString() ?? ''),
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
                onPressed: _busy ? null : _start,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link_rounded),
                label: Text(
                  english
                      ? 'Connect ${widget.title}'
                      : 'ربط ${widget.title}',
                ),
              ),
            ),
            if (widget.service == 'anilist')
              ..._anilistCredentialsSection(english),
            if (widget.service == 'trakt' &&
                linked == null &&
                _flow?['status'] == null && _traktMethodLoaded) ...[
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'direct',
                    icon: const Icon(Icons.phone_iphone_rounded, size: 17),
                    label: Text(
                      english ? 'Direct to app' : 'مباشر للتطبيق',
                    ),
                  ),
                  ButtonSegment(
                    value: 'relay',
                    icon: const Icon(Icons.language_rounded, size: 17),
                    label: Text(english ? 'Via website' : 'عبر الموقع'),
                  ),
                ],
                selected: {_traktMethod},
                onSelectionChanged: (selection) =>
                    unawaited(_pickTraktMethod(selection.first)),
                showSelectedIcon: false,
              ),
              const SizedBox(height: 6),
              Text(
                _traktMethod == 'direct'
                    ? (english
                        ? 'Approve in Trakt and the browser hands you straight back to Noor — no website in between. One-time setup: add noor://callback to the Redirect URIs on trakt.tv/oauth/applications.'
                        : 'وافق في Trakt ويعيدك المتصفح إلى التطبيق مباشرة — بدون أي موقع وسيط. إعداد لمرة واحدة: أضف noor://callback إلى قائمة Redirect URIs في لوحة مطوّر Trakt (trakt.tv/oauth/applications).')
                    : (english
                        ? 'Opens the browser — the approval returns to Noor automatically through the Noor companion site. No dashboard setup required.'
                        : 'يفتح المتصفح — تعود الموافقة إلى التطبيق تلقائيًا عبر موقع Noor المصاحب. لا حاجة لأي إعداد في لوحة Trakt.'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: HorseTheme.muted,
                    ),
              ),
            ],
            if (_flow?['status'] != null)
              TextButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(
                  english
                      ? (widget.service == 'trakt'
                          ? 'Restart the link'
                          : 'Generate a new code')
                      : (widget.service == 'trakt'
                          ? 'إعادة بدء الربط'
                          : 'إنشاء رمز جديد'),
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

/// Tiny stat chip for tracker profile rows (anime count / episodes / mean).
class _ProfileStat extends StatelessWidget {
  const _ProfileStat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: HorseTheme.gold.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: HorseTheme.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: HorseTheme.gold,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
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
    setState(() => _busy = true);
    try {
      await app.configureDebrid(_service, _key.text);
      _key.clear();
      if (mounted) {
        NoorToast.show(
          context,
          app.english
              ? 'Key verified and saved securely.'
              : 'تم التحقق من المفتاح وحفظه بأمان.',
        );
      }
    } catch (error) {
      if (mounted) NoorToast.show(context, _friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final app = context.read<AppState>();
    await app.disconnectDebrid();
    if (mounted) {
      NoorToast.show(
        context,
        app.english
            ? 'Debrid service disconnected.'
            : 'تم فصل خدمة Debrid.',
      );
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
