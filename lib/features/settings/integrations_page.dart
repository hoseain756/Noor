import 'package:noor_mobile/l10n/nova_strings.dart';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/state/app_state.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../shared/widgets/noor_toast.dart';
import 'widgets/settings_tiles.dart';

class IntegrationsPage extends StatelessWidget {
  const IntegrationsPage({super.key});
  @override
  Widget build(BuildContext context) {
    context.select<AppState,
            (bool, Map<String, Map<String, dynamic>>, bool, String?)>(
        (app) => (
              app.english,
              app.linkedServices,
              app.api.hasUserTmdbKey,
              app.api.debridService
            ));
    final app = context.read<AppState>();
    final linked = app.linkedServices;
    return Scaffold(
        appBar: AppBar(title: Text(app.tr('message252'))),
        body: Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
              padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 24, 48),
              children: [
                SettingsPageIntro(
                    title: app.tr('message253'),
                    description: app.tr('message254'),
                    icon: LucideIcons.orbit),
                SettingsContentSection(title: app.tr('message255'), children: [
                  for (final service in ['trakt', 'simkl', 'anilist', 'mal'])
                    _ServiceDestination(
                        service: service,
                        connected: linked[service] != null,
                        subtitle: linked[service]?['username']?.toString()),
                ]),
                SettingsContentSection(title: app.tr('message256'), children: [
                  _ServiceDestination(
                      service: 'tmdb',
                      connected: app.api.hasUserTmdbKey,
                      subtitle:
                          app.api.hasUserTmdbKey ? null : app.tr('message257')),
                  _ServiceDestination(
                      service: 'mdblist',
                      connected: false,
                      subtitle: app.tr('message258')),
                ]),
                SettingsContentSection(title: app.tr('message259'), children: [
                  _ServiceDestination(
                      service: 'debrid',
                      connected: app.api.debridService != null,
                      subtitle: app.api.debridService == null
                          ? app.tr('message260')
                          : _serviceName(app.api.debridService)),
                ]),
                SettingsInfoBanner(
                    icon: LucideIcons.shieldCheck,
                    message: app.tr('message261')),
              ]),
        )));
  }
}

String _providerName(String service) => switch (service) {
      'trakt' => 'Trakt',
      'simkl' => 'Simkl',
      'anilist' => 'AniList',
      'mal' => 'MyAnimeList',
      'tmdb' => 'TMDB',
      'mdblist' => 'MDBList',
      _ => 'Debrid'
    };
IconData _providerIcon(String service) => switch (service) {
      'trakt' => LucideIcons.clapperboard,
      'simkl' => LucideIcons.refreshCw,
      'anilist' || 'mal' => LucideIcons.bookOpen,
      'tmdb' => LucideIcons.film,
      'mdblist' => LucideIcons.star,
      _ => LucideIcons.cloud
    };

class _ServiceDestination extends StatelessWidget {
  const _ServiceDestination(
      {required this.service, required this.connected, this.subtitle});
  final String service;
  final bool connected;
  final String? subtitle;
  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return SettingsTile(
        icon: _providerIcon(service),
        title: _providerName(service),
        subtitle: subtitle ??
            (connected ? app.tr('message262') : app.tr('message263')),
        trailing: Icon(
            connected
                ? LucideIcons.circleCheck
                : Directionality.of(context) == TextDirection.rtl
                    ? LucideIcons.chevronLeft
                    : LucideIcons.chevronRight,
            size: 20,
            color: connected
                ? Theme.of(context).colorScheme.secondary
                : Theme.of(context).colorScheme.onSurfaceVariant),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => _ServiceSettingsPage(service: service))));
  }
}

class _ServiceSettingsPage extends StatelessWidget {
  const _ServiceSettingsPage({required this.service});
  final String service;
  @override
  Widget build(BuildContext context) {
    context.select<AppState, bool>((app) => app.english);
    final connected = context
        .select<AppState, bool>((app) => app.linkedServices[service] != null);
    final app = context.read<AppState>();
    final tracker = ['trakt', 'simkl', 'anilist', 'mal'].contains(service);
    return Scaffold(
        appBar: AppBar(title: Text(_providerName(service))),
        body: Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
              padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 24, 48),
              children: [
                SettingsPageIntro(
                    title: _providerName(service),
                    description: tracker
                        ? app.tr('message264')
                        : service == 'debrid'
                            ? app.tr('message265')
                            : app.tr('message266'),
                    icon: _providerIcon(service)),
                if (tracker)
                  _LinkedServiceCard(
                      service: service,
                      title: _providerName(service),
                      subtitle: ['anilist', 'mal'].contains(service)
                          ? app.tr('message267')
                          : app.tr('message268'),
                      icon: _providerIcon(service)),
                if (service == 'tmdb') const _TmdbKeyCard(),
                if (service == 'debrid') const _DebridCard(),
                if (service == 'mdblist')
                  SettingsInfoBanner(
                      icon: LucideIcons.star, message: app.tr('message269')),
                if (tracker && connected) ...[
                  const SizedBox(height: 24),
                  SettingsContentSection(
                      title: app.tr('message270'),
                      children: [
                        if (service == 'trakt' || service == 'simkl')
                          _ServicePreference(
                              settingKey: '${service}Scrobbling',
                              title: app.tr('message271'),
                              description: app.tr('message272')),
                        if (service == 'trakt' ||
                            service == 'anilist' ||
                            service == 'mal')
                          _ServicePreference(
                              settingKey: '${service}WatchlistSync',
                              title: app.tr('message273'),
                              description: app.tr('message274')),
                        if (service == 'anilist' || service == 'mal')
                          _ServicePreference(
                              settingKey: '${service}ProgressSync',
                              title: app.tr('message275'),
                              description: app.tr('message276')),
                      ]),
                ],
                if (tracker) ...[
                  const SizedBox(height: 24),
                  SettingsContentSection(
                      title: app.tr('message277'),
                      children: [
                        ListTile(
                            leading: const Icon(LucideIcons.listVideo),
                            title: Text(app.tr('message278')),
                            subtitle: Text(app.tr('message279'))),
                        ListTile(
                            leading: const Icon(LucideIcons.activity),
                            title: Text(app.tr('message280')),
                            subtitle: Text(['anilist', 'mal'].contains(service)
                                ? app.tr('message281')
                                : app.tr('message282'))),
                      ]),
                ],
              ]),
        )));
  }
}

class _ServicePreference extends StatelessWidget {
  const _ServicePreference(
      {required this.settingKey,
      required this.title,
      required this.description});
  final String settingKey, title, description;
  @override
  Widget build(BuildContext context) {
    final enabled = context
        .select<AppState, bool>((app) => app.webSettings[settingKey] != false);
    return SettingsOptimisticSwitchTile(
        title: Text(title),
        subtitle: Text(description),
        value: enabled,
        onChanged: (value) =>
            context.read<AppState>().setSetting(settingKey, value));
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
        NovaStrings.lookup(app.english, 'message283'),
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
    if (!await confirmSettingsAction(context,
        title: app.tr('message284'),
        message: app.tr('message285'),
        confirm: app.tr('remove'),
        cancel: app.tr('cancel'))) return;
    await app.api.clearTmdbUserKey();
    if (mounted) setState(() {});
    if (!mounted) return;
    NoorToast.show(
      context,
      NovaStrings.lookup(app.english, 'message286'),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Task 122-c F4: scoped select — this card repaints only when the UI
    // language, the stored-key flag, or the TMDB-features flag changes.
    final (english, connected, tmdbEnabled) =
        context.select<AppState, (bool, bool, bool)>((app) => (
              app.english,
              app.api.hasUserTmdbKey,
              app.webSettings['tmdbEnabled'] != false,
            ));
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _ServiceIcon(icon: LucideIcons.sparkles),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TMDB',
                        style: Theme.of(context).textTheme.titleMedium),
                    SizedBox(height: 3),
                    Text(
                      NovaStrings.lookup(english, 'message287'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (connected)
                Icon(LucideIcons.circleCheck,
                    color: Theme.of(context).colorScheme.secondary),
            ],
          ),
          SettingsOptimisticSwitchTile(
            contentPadding: EdgeInsets.zero,
            title: Text(NovaStrings.lookup(english, 'message288')),
            subtitle: Text(NovaStrings.lookup(english, 'message289')),
            value: tmdbEnabled,
            onChanged: (value) =>
                context.read<AppState>().setSetting('tmdbEnabled', value),
          ),
          if (connected) ...[
            Text(
              NovaStrings.lookup(english, 'message290'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: _busy ? null : _remove,
                icon: Icon(LucideIcons.keyRound),
                label: Text(NovaStrings.lookup(english, 'message291')),
              ),
            ),
          ] else ...[
            Text(
              NovaStrings.lookup(english, 'message292'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            SizedBox(height: 8),
            TextField(
              controller: _key,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: NovaStrings.lookup(english, 'message293'),
                hintText: NovaStrings.lookup(english, 'message294'),
              ),
            ),
            SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _busy ? null : _save,
                icon: _busy
                    ? SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(LucideIcons.shieldCheck),
                label: Text(NovaStrings.lookup(english, 'message295')),
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
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _codeCtrl.dispose();
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
      setState(() => _flow = null);
      if (widget.service == 'anilist' || widget.service == 'mal') {
        unawaited(app.refreshTrackerProfile(widget.service));
      }
      NoorToast.show(context, NovaStrings.lookup(english, 'message296'));
    } else {
      NoorToast.show(
        context,
        _oauthFailureText(app.english, result['reason']?.toString()),
        error: true,
      );
    }
  }

  String _oauthFailureText(bool english, String? reason) {
    if (reason == 'invalid_client') {
      return NovaStrings.lookup(english, 'message297');
    }
    if (reason == 'invalid_token') {
      return NovaStrings.lookup(english, 'message298');
    }
    if (reason == 'state_mismatch' ||
        reason == 'flow_expired' ||
        reason == 'no_pending_flow') {
      return NovaStrings.lookup(english, 'message299');
    }
    return NovaStrings.lookup(english, 'message300');
  }

  Future<void> _start() async {
    final app = context.read<AppState>();
    final english = app.english;
    _pollTimer?.cancel();
    setState(() {
      _busy = true;
      _flow = null;
    });
    try {
      if (widget.service == 'anilist' || widget.service == 'mal') {
        // Browser OAuth over app.noor.mobile://callback (RFC 8252): approve
        // on the provider and the OS bounces straight back into NOVA; the
        // paste field below is the fallback when the bounce never fires.
        final result = widget.service == 'anilist'
            ? await app.api.startAniListLink()
            : await app.api.startMalLink();
        final authorizeUrl = result?['authorizeUrl']?.toString() ?? '';
        if (authorizeUrl.isEmpty) {
          // Task 122-c translation sweep: surfaced through the error toast.
          throw FormatException(NovaStrings.lookup(english, 'message301'));
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
        // bounces back into NOVA the moment Trakt approves) or relay (the
        // companion site stores the code and the app-wide watcher fetches
        // it). IncomingLinkListener finishes the handshake either way.
        final result = await app.api.startTraktLink();
        final authorizeUrl = result?['authorizeUrl']?.toString() ?? '';
        if (authorizeUrl.isEmpty) {
          // Task 122-c translation sweep: surfaced through the error toast.
          throw FormatException(NovaStrings.lookup(english, 'message302'));
        }
        if (!mounted) return;
        setState(() {
          _flow = {'status': 'waiting', 'kind': 'pkce'};
        });
        if (_traktMethod == 'relay') {
          // Relay leg only: the browser lands on the NOVA companion which
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
        // Task 122-c translation sweep: surfaced through the error toast.
        throw FormatException(NovaStrings.lookup(english, 'message303'));
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
                Duration(
                    seconds: (result?['expires_in'] as num?)?.toInt() ?? 600),
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
          NovaStrings.lookup(context.read<AppState>().english, 'message296'),
        );
        return;
      }
      if (status == 'pending') {
        final retryMs =
            ((flow['interval'] as int? ?? 5) * 1000).clamp(3000, 30000);
        _schedulePoll(Duration(milliseconds: retryMs));
        return;
      }
      setState(() {
        _flow = {...flow, 'status': status ?? 'error'};
      });
      NoorToast.show(
        context,
        NovaStrings.lookup(context.read<AppState>().english, 'message304'),
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
          NovaStrings.lookup(
              english, 'message305', {'p0': watchlist, 'p1': history}),
        );
      }
    } catch (error) {
      if (mounted) NoorToast.show(context, _friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _unlink() async {
    final app = context.read<AppState>();
    if (!await confirmSettingsAction(context,
        title: app.tr('message306'),
        message: app.tr('message307', {'p0': widget.title}),
        confirm: app.tr('message308'),
        cancel: app.tr('cancel'))) return;
    await app.unlinkService(widget.service);
    if (mounted) {
      NoorToast.show(
        context,
        NovaStrings.lookup(context.read<AppState>().english, 'message309'),
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
    // Task 122-c F4: scoped select — rebuilds when the UI language or THIS
    // service's linked entry is replaced (link/unlink/profile refresh).
    final (english, linked) =
        context.select<AppState, (bool, Map<String, dynamic>?)>(
            (app) => (app.english, app.linkedServices[widget.service]));
    final waiting = _flow?['status'] == 'waiting';
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ServiceIcon(icon: widget.icon),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        style: Theme.of(context).textTheme.titleMedium),
                    SizedBox(height: 3),
                    Text(widget.subtitle,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              if (linked != null)
                Icon(LucideIcons.circleCheck,
                    color: Theme.of(context).colorScheme.secondary),
            ],
          ),
          SizedBox(height: 14),
          if (linked != null) ...[
            Row(
              children: [
                if ((linked['avatar']?.toString() ?? '').isNotEmpty) ...[
                  CircleAvatar(
                    radius: 17,
                    backgroundImage: NetworkImage(linked['avatar'].toString()),
                  ),
                  SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${NovaStrings.lookup(english, 'message310')}  ${linked['username'] ?? widget.title}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (linked['lastSyncedAt'] is num)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(top: 3),
                          child: Text(
                            '${NovaStrings.lookup(english, 'message311')} · ${_formatSyncTime(linked['lastSyncedAt'] as num)}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (widget.service == 'anilist' || widget.service == 'mal') ...[
              SizedBox(height: 8),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  if (linked['animeCount'] is num)
                    _ProfileStat(
                      NovaStrings.lookup(english, 'message312'),
                      '${(linked['animeCount'] as num).toInt()}',
                    ),
                  if (linked['episodesWatched'] is num)
                    _ProfileStat(
                      NovaStrings.lookup(english, 'message313'),
                      '${(linked['episodesWatched'] as num).toInt()}',
                    ),
                  if (linked['meanScore'] is num)
                    _ProfileStat(
                      NovaStrings.lookup(english, 'message314'),
                      (linked['meanScore'] as num).toStringAsFixed(1),
                    ),
                ],
              ),
            ],
            SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _syncing ? null : _sync,
                  icon: _syncing
                      ? SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(LucideIcons.refreshCw),
                  label: Text(NovaStrings.lookup(english, 'message315')),
                ),
                TextButton.icon(
                  onPressed: _unlink,
                  icon: Icon(LucideIcons.unlink),
                  label: Text(NovaStrings.lookup(english, 'message308')),
                ),
              ],
            ),
          ] else if (waiting && _flow?['kind'] == 'browser') ...[
            Text(
              NovaStrings.lookup(english, 'message316', {'p0': widget.title}),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SizedBox(height: 10),
            Row(
              children: [
                SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    NovaStrings.lookup(english, 'message317'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Text(
              widget.service == 'anilist'
                  ? (NovaStrings.lookup(english, 'message318'))
                  : (NovaStrings.lookup(english, 'message319')),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SizedBox(height: 6),
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
                      hintText: NovaStrings.lookup(english, 'message320'),
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => unawaited(_submitCode()),
                  ),
                ),
                SizedBox(width: 8),
                FilledButton(
                  onPressed: _submittingCode ? null : _submitCode,
                  child: _submittingCode
                      ? SizedBox.square(
                          dimension: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(NovaStrings.lookup(english, 'message321')),
                ),
              ],
            ),
            SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: _cancelFlow,
                child: Text(NovaStrings.lookup(english, 'cancel')),
              ),
            ),
            SizedBox(height: 4),
            Text(
              NovaStrings.lookup(english, 'message322', {'p0': widget.title}),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ] else if (waiting && _flow?['kind'] == 'pkce') ...[
            Text(
              _traktMethod == 'direct'
                  ? (NovaStrings.lookup(english, 'message323'))
                  : (NovaStrings.lookup(english, 'message324')),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SizedBox(height: 10),
            Row(
              children: [
                SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    NovaStrings.lookup(english, 'message317'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Text(
              NovaStrings.lookup(english, 'message319'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SizedBox(height: 6),
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
                      hintText: NovaStrings.lookup(english, 'message320'),
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => unawaited(_submitCode()),
                  ),
                ),
                SizedBox(width: 8),
                FilledButton(
                  onPressed: _submittingCode ? null : _submitCode,
                  child: _submittingCode
                      ? SizedBox.square(
                          dimension: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(NovaStrings.lookup(english, 'message321')),
                ),
              ],
            ),
            SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: _cancelFlow,
                child: Text(NovaStrings.lookup(english, 'cancel')),
              ),
            ),
            SizedBox(height: 4),
            Text(
              _traktMethod == 'direct'
                  ? (NovaStrings.lookup(english, 'message325'))
                  : (NovaStrings.lookup(english, 'message326')),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ] else if (waiting) ...[
            Text(
              NovaStrings.lookup(english, 'message327', {'p0': widget.title}),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SizedBox(height: 8),
            SelectableText(
              _flow?['user_code']?.toString() ?? '',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Theme.of(context).colorScheme.secondary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                  ),
            ),
            SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(
                          text: _flow?['user_code']?.toString() ?? ''),
                    );
                    if (!mounted) return;
                    NoorToast.show(
                      this.context,
                      NovaStrings.lookup(english, 'message328'),
                    );
                  },
                  icon: Icon(LucideIcons.copy),
                  label: Text(NovaStrings.lookup(english, 'message329')),
                ),
                OutlinedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(_flow?['verification_url']?.toString() ?? ''),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: Icon(LucideIcons.externalLink),
                  label: Text(NovaStrings.lookup(english, 'message330')),
                ),
                TextButton(
                  onPressed: _cancelFlow,
                  child: Text(NovaStrings.lookup(english, 'cancel')),
                ),
              ],
            ),
            SizedBox(height: 6),
            Text(
              NovaStrings.lookup(english, 'message317'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _start,
                icon: _busy
                    ? SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(LucideIcons.link),
                label: Text(
                  NovaStrings.lookup(
                      english, 'message331', {'p0': widget.title}),
                ),
              ),
            ),
            if (widget.service == 'trakt' &&
                linked == null &&
                _flow?['status'] == null &&
                _traktMethodLoaded) ...[
              SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ChoiceChip(
                    label: Text(NovaStrings.lookup(english, 'message332')),
                    selected: _traktMethod == 'direct',
                    onSelected: (_) => unawaited(_pickTraktMethod('direct'))),
                ChoiceChip(
                    label: Text(NovaStrings.lookup(english, 'message333')),
                    selected: _traktMethod == 'relay',
                    onSelected: (_) => unawaited(_pickTraktMethod('relay'))),
              ]),
              SizedBox(height: 6),
              Text(
                _traktMethod == 'direct'
                    ? (NovaStrings.lookup(english, 'message334'))
                    : (NovaStrings.lookup(english, 'message335')),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
            if (_flow?['status'] != null)
              TextButton.icon(
                onPressed: _start,
                icon: Icon(LucideIcons.refreshCw),
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
          color: Theme.of(context).colorScheme.secondary.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(9),
          border:
              Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.secondary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            SizedBox(width: 5),
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
          NovaStrings.lookup(app.english, 'message336'),
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
    if (!await confirmSettingsAction(context,
        title: app.tr('message337'),
        message: app.tr('message338'),
        confirm: app.tr('message308'),
        cancel: app.tr('cancel'))) return;
    await app.disconnectDebrid();
    if (mounted) {
      NoorToast.show(
        context,
        NovaStrings.lookup(app.english, 'message339'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Task 122-c F4: scoped select — the Debrid card reads only these four.
    final (english, service, connected, user) =
        context.select<AppState, (bool, String?, bool, Map<String, dynamic>?)>(
            (app) => (
                  app.english,
                  app.api.debridService,
                  app.api.debridService != null && app.api.debridApiKey != null,
                  app.debridUser,
                ));
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _ServiceIcon(icon: LucideIcons.zap),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Debrid',
                        style: Theme.of(context).textTheme.titleMedium),
                    SizedBox(height: 3),
                    Text(
                      NovaStrings.lookup(english, 'message340'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (connected)
                Icon(LucideIcons.circleCheck,
                    color: Theme.of(context).colorScheme.secondary),
            ],
          ),
          SizedBox(height: 14),
          if (connected) ...[
            Text(
              '${_serviceName(service)}${user?['username'] == null ? '' : ' · ${user!['username']}'}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (user?['premium'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '${NovaStrings.lookup(english, 'message341')}: ${user!['premium']}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: _busy ? null : _remove,
                icon: Icon(LucideIcons.unlink),
                label: Text(NovaStrings.lookup(english, 'message291')),
              ),
            ),
          ] else ...[
            DropdownButtonFormField<String>(
              initialValue: _service,
              decoration: InputDecoration(
                  labelText: NovaStrings.lookup(english, 'message342')),
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
            SizedBox(height: 10),
            TextField(
              controller: _key,
              obscureText: true,
              autocorrect: false,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: NovaStrings.lookup(english, 'message343'),
                hintText: NovaStrings.lookup(english, 'message344'),
              ),
            ),
            SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _busy ? null : _save,
                icon: _busy
                    ? SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(LucideIcons.shieldCheck),
                label: Text(NovaStrings.lookup(english, 'message295')),
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
          color: Theme.of(context).colorScheme.secondary.withValues(alpha: .11),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: Theme.of(context).colorScheme.secondary),
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
