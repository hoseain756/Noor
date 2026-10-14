import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api/noor_api.dart';
import '../../core/state/app_state.dart';
import '../../shared/widgets/noor_toast.dart';
import 'magnet_opener.dart';

/// Listens for VIEW intents forwarded by the Android side over the
/// `noor/links` EventChannel and routes them by scheme:
///
///  - `magnet:…`  → opens the torrent flow automatically.
///  - `noor://callback?code=…&state=…` → legacy Trakt PKCE return.
///  - `https://<registered redirect host>/?code=…&state=…` → primary Trakt
///    PKCE return (Android App Links) — see NoorApi.completeTraktLink.
///
/// All Trakt returns finish through the same handshake anywhere in the app;
/// relay-based completions (the app polling the web companion) are surfaced
/// here too via [AppState.traktLinkEvent].
///
/// Covers both cold starts (link captured before Flutter was ready and
/// delivered on first listen) and warm starts (onNewIntent while running).
class IncomingLinkListener extends StatefulWidget {
  const IncomingLinkListener({super.key, required this.child});

  final Widget child;

  @override
  State<IncomingLinkListener> createState() => _IncomingLinkListenerState();
}

class _IncomingLinkListenerState extends State<IncomingLinkListener> {
  StreamSubscription<Object?>? _sub;

  int _seenTraktLinkEventAt = 0;

  @override
  void initState() {
    super.initState();
    try {
      _sub = const EventChannel('noor/links')
          .receiveBroadcastStream()
          .listen(_onLink, onError: (Object _) {
        // The channel only exists on Android; silence any platform noise.
      });
    } catch (_) {
      // Platform channel unavailable (e.g. tests) — ignore.
    }
  }

  void _onLink(Object? data) {
    if (data is! String) return;
    final lower = data.toLowerCase();
    if (lower.startsWith('magnet:')) {
      if (!mounted) return;
      unawaited(openMagnetFlow(context, initialMagnet: data));
      return;
    }
    if (lower.startsWith('noor://')) {
      unawaited(_completeTrakt(data));
      return;
    }
    if (lower.startsWith('https://') && NoorApi.isTraktHttpsReturn(data)) {
      unawaited(_completeTrakt(data));
    }
  }

  /// Finishes the Trakt PKCE round-trip and announces it. Runs regardless of
  /// the current screen so the callback is never lost when the linking sheet
  /// is closed; the sheet itself rebuilds from [AppState.linkedServices].
  Future<void> _completeTrakt(String link) async {
    final app = context.read<AppState>();
    final result = await app.api.completeTraktLink(link);
    final status = result['status']?.toString();
    final reason = result['reason']?.toString();
    if (status != 'success' && reason == 'no_pending_flow') {
      // Duplicate callback after the flow already finished — stay silent
      // unless the link never actually completed.
      if (app.api.isLinked('trakt')) return;
    }
    if (!mounted) return;
    if (status == 'success') {
      await app.saveLinkedService('trakt', <String, dynamic>{
        'linked': true,
        'linkedAt': DateTime.now().millisecondsSinceEpoch,
        if (result['username'] != null) 'username': result['username'],
      });
      if (!mounted) return;
      NoorToast.show(
        context,
        app.english
            ? 'Trakt account connected.'
            : 'تم ربط حساب Trakt.',
      );
      return;
    }
    if (!mounted) return;
    NoorToast.show(
      context,
      app.english ? _englishReason(reason) : _arabicReason(reason),
      error: true,
    );
  }

  String _arabicReason(String? reason) => switch (reason) {
        'access_denied' => 'تم رفض الموافقة في Trakt.',
        'state_mismatch' =>
          'استجابة ربط غير صالحة (state mismatch) — أعد المحاولة.',
        'exchange_failed' => 'فشل تبادل الرمز مع Trakt — أعد المحاولة.',
        'flow_expired' => 'انتهت مهلة طلب الربط — ابدأ من جديد.',
        'no_pending_flow' => 'انتهت صلاحية طلب الربط — ابدأ من جديد.',
        'network_error' => 'انقطاع شبكة أثناء ربط Trakt — أعد المحاولة.',
        _ => 'تعذر إكمال ربط Trakt.',
      };

  String _englishReason(String? reason) => switch (reason) {
        'access_denied' => 'Approval was denied on Trakt.',
        'state_mismatch' =>
          'Invalid link response (state mismatch) — please retry.',
        'exchange_failed' => 'Token exchange with Trakt failed — retry.',
        'flow_expired' => 'The pending link timed out — start again.',
        'no_pending_flow' => 'The pending link expired — start again.',
        'network_error' => 'Network hiccup during Trakt linking — retry.',
        _ => 'Could not finish linking Trakt.',
      };

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Relay-based completions (the app polling the web companion while the
    // user is anywhere in the app) announce themselves through app state;
    // surface each new event exactly once as a toast.
    final app = context.watch<AppState>();
    final event = app.traktLinkEvent;
    if (event != null) {
      final at = (event['at'] as num?)?.toInt() ?? 0;
      if (at > _seenTraktLinkEventAt && at > app.seenTraktLinkEventAt) {
        _seenTraktLinkEventAt = at;
        app.seenTraktLinkEventAt = at;
        final ok = event['ok'] == true;
        final reason = event['reason']?.toString();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (ok) {
            NoorToast.show(
              context,
              app.english
                  ? 'Trakt account connected.'
                  : 'تم ربط حساب Trakt.',
            );
          } else {
            NoorToast.show(
              context,
              app.english ? _englishReason(reason) : _arabicReason(reason),
              error: true,
            );
          }
        });
      }
    }
    return widget.child;
  }
}
