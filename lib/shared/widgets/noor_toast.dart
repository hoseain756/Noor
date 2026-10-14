import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/horse_theme.dart';

/// Netflix-dark toast: a small floating pill near the bottom of the screen
/// that flashes in above the glass navigation, lingers briefly, then fades
/// away on its own — never steals focus and never blocks touches.
///
/// Used for one-shot confirmations ("Code copied", "Key verified") and
/// lightweight errors across the app.
class NoorToast {
  NoorToast._();

  static OverlayEntry? _active;

  /// Shows [message] as a flash toast. A new toast instantly replaces the
  /// previous one. [error] switches the accent from gold to soft red and
  /// keeps the pill on screen a little longer.
  static void show(
    BuildContext context,
    String message, {
    bool error = false,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final direction = Directionality.of(context);
    _active?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastView(
        message: message,
        error: error,
        direction: direction,
        onRemove: () {
          if (_active == entry) _active = null;
          entry.remove();
        },
      ),
    );
    _active = entry;
    overlay.insert(entry);
  }
}

class _ToastView extends StatefulWidget {
  const _ToastView({
    required this.message,
    required this.error,
    required this.direction,
    required this.onRemove,
  });

  final String message;
  final bool error;
  final TextDirection direction;
  final VoidCallback onRemove;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    reverseDuration: const Duration(milliseconds: 260),
  );

  late final Animation<double> _fade =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.4),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _timer = Timer(
      Duration(milliseconds: widget.error ? 3000 : 2200),
      _dismiss,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    _timer?.cancel();
    try {
      await _controller.reverse();
    } catch (_) {}
    if (mounted) widget.onRemove();
  }

  @override
  Widget build(BuildContext context) {
    final accent =
        widget.error ? const Color(0xFFFF8178) : HorseTheme.gold;
    return Positioned(
      left: 0,
      right: 0,
      // Above the glass dock (tallest phone class tops out at 84 + safe
      // bottom) plus a little air.
      bottom: MediaQuery.paddingOf(context).bottom + 92,
      child: Directionality(
        textDirection: widget.direction,
        child: IgnorePointer(
          child: SafeArea(
            top: false,
            child: Center(
              child: FadeTransition(
                opacity: _fade,
                child: SlideTransition(
                  position: _slide,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 440),
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 11),
                    decoration: BoxDecoration(
                      color: const Color(0xFF191D1E).withValues(alpha: .97),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: accent.withValues(alpha: .38),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .45),
                          blurRadius: 22,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.error
                              ? Icons.error_outline_rounded
                              : Icons.check_circle_rounded,
                          size: 18,
                          color: accent,
                        ),
                        const SizedBox(width: 9),
                        Flexible(
                          child: Text(
                            widget.message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: HorseTheme.ink,
                                  height: 1.25,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
