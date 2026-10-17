import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Accessible in-app feedback, using the shared NOVA snackbar theme.
class NoorToast {
  NoorToast._();
  static void show(BuildContext context, String message, {bool error = false}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      duration: Duration(seconds: error ? 5 : 3),
      content: Semantics(
          liveRegion: true,
          child: Row(children: [
            Icon(error ? LucideIcons.circleAlert : LucideIcons.circleCheck,
                color: Theme.of(context).colorScheme.onInverseSurface,
                size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ])),
    ));
  }
}
