import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/state/app_state.dart';
import '../../shared/widgets/noor_toast.dart';
import 'magnet_opener.dart';

/// Listens for VIEW intents forwarded by the Android side over the
/// `noor/links` EventChannel and routes them by scheme:
///
///  - `magnet:…`  → opens the torrent flow automatically.
///  - `noor://callback?code=…&state=…` → completes the Trakt browser PKCE
///    handshake (see NoorApi.completeTraktLink) and mirrors the result into
///    app state + a toast, wherever the user happens to be in the app.
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
        'no_pending_flow' => 'انتهت صلاحية طلب الربط — ابدأ من جديد.',
        _ => 'تعذر إكمال ربط Trakt.',
      };

  String _englishReason(String? reason) => switch (reason) {
        'access_denied' => 'Approval was denied on Trakt.',
        'state_mismatch' =>
          'Invalid link response (state mismatch) — please retry.',
        'exchange_failed' => 'Token exchange with Trakt failed — retry.',
        'no_pending_flow' => 'The pending link expired — start again.',
        _ => 'Could not finish linking Trakt.',
      };

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
