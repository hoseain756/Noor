import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'magnet_opener.dart';

/// Listens for `magnet:` VIEW intents forwarded by the Android side over
/// the `noor/links` EventChannel and opens the torrent flow automatically.
///
/// Covers both cold starts (link captured before Flutter was ready and
/// delivered on first listen) and warm starts (onNewIntent while running).
class MagnetLinkListener extends StatefulWidget {
  const MagnetLinkListener({super.key, required this.child});

  final Widget child;

  @override
  State<MagnetLinkListener> createState() => _MagnetLinkListenerState();
}

class _MagnetLinkListenerState extends State<MagnetLinkListener> {
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
    if (!data.toLowerCase().startsWith('magnet:')) return;
    if (!mounted) return;
    unawaited(openMagnetFlow(context, initialMagnet: data));
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
