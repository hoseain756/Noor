/// Liquid-glass primitives shared by the detail page's floating controls:
/// the season dropdown pill, the sort chip, the view toggle and the
/// expandable action menu.
///
/// The pill surface wears the OLD detail back-pill recipe (user mandate,
/// Task 120: the pre-118 glow background for the search button, the
/// navigation bar and the episode toolbar): blur backdrop over a black/55
/// fill with a 1px white/15 ring and a soft black drop shadow — mirroring
/// `shared/widgets/glass_navigation.dart` and `features/shell/glass_dock.dart`
/// which swapped the same day. Only the shape changes (rounded pill instead
/// of circle).
///
/// [showGlassMenu] is the Flutter idiom replacing the web's Radix
/// DropdownMenu portal: a root overlay with an outside-tap barrier, Escape
/// handling and viewport-clamped positioning under the anchor.
library;

import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/horse_theme.dart';

/// The glass-dock recipe as a pill/rounded-rect surface. Children paint on
/// top of the blurred backdrop; the caller supplies ink/labels.
class GlassPillSurface extends StatelessWidget {
  const GlassPillSurface({
    super.key,
    required this.child,
    this.borderRadius = 999,
    this.blurSigma,
  });

  final Widget child;
  final double borderRadius;

  /// Defaults to the dock blur ladder (12 < 600px viewport, else 14).
  final double? blurSigma;

  @override
  Widget build(BuildContext context) {
    final blur =
        blurSigma ?? (MediaQuery.sizeOf(context).width < 600 ? 12.0 : 14.0);
    final radius = BorderRadius.circular(borderRadius);
    return DecoratedBox(
      // 1px white/15 ring painted above the clipped glass + the old
      // back-pill soft shadow — the pre-118 decoration verbatim.
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: Colors.white.withValues(alpha: .15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .35),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            // Glass backdrop: blur over the black/55 fill — the old
            // back-pill recipe verbatim (no tint sheen, no saturate, no
            // inset hairlines).
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: ColoredBox(color: Colors.black.withValues(alpha: .55)),
              ),
            ),
            // Content on top of the glass stack — the NON-positioned child
            // (it defines the pill's intrinsic size; the fill layers adapt).
            child,
          ],
        ),
      ),
    );
  }
}

/// Menu content: receives the panel's `close` function — call it with the
/// value to complete [showGlassMenu] with (null = dismissed).
typedef GlassMenuBuilder<T> = Widget Function(void Function(T? value) close);

/// Opens a glass dropdown panel anchored under [anchor] (a rect in global
/// coordinates). Closes on outside tap and Escape; completes with the value
/// the menu content passed to `close` (null when dismissed).
Future<T?> showGlassMenu<T>({
  required BuildContext context,
  required Rect anchor,
  required GlassMenuBuilder<T> builder,
  double width = 240,
  double gap = 8,
  double? maxHeight,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final completer = Completer<T?>();
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (menuContext) => _GlassMenuRoute<T>(
      anchor: anchor,
      width: width,
      gap: gap,
      maxHeight: maxHeight ?? MediaQuery.sizeOf(menuContext).height * 0.6,
      builder: builder,
      onClose: (value) {
        if (!completer.isCompleted) completer.complete(value);
        entry.remove();
      },
    ),
  );
  overlay.insert(entry);
  return completer.future;
}

class _GlassMenuRoute<T> extends StatefulWidget {
  const _GlassMenuRoute({
    required this.anchor,
    required this.width,
    required this.gap,
    required this.maxHeight,
    required this.builder,
    required this.onClose,
  });

  final Rect anchor;
  final double width;
  final double gap;
  final double maxHeight;
  final GlassMenuBuilder<T> builder;
  final void Function(T? value) onClose;

  @override
  State<_GlassMenuRoute<T>> createState() => _GlassMenuRouteState<T>();
}

class _GlassMenuRouteState<T> extends State<_GlassMenuRoute<T>> {
  late final FocusNode _escapeNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Grab focus so the keyboard Escape reaches the panel's handler.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _escapeNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _escapeNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose(null);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screen = media.size;
    const edge = 12.0;
    // Start-align with the anchor, clamped inside the viewport.
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final double start =
        (rtl ? screen.width - widget.anchor.right : widget.anchor.left).clamp(
            edge,
            (screen.width - edge - widget.width).clamp(edge, double.infinity));
    final top = (widget.anchor.bottom + widget.gap)
        .clamp(edge, (screen.height - edge).clamp(edge, double.infinity));
    return Stack(
      children: [
        // Outside tap closes (barrier over the whole app below the panel).
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onClose(null),
            child: const SizedBox.expand(),
          ),
        ),
        PositionedDirectional(
          start: start,
          top: top,
          width: widget.width,
          child: Focus(
            focusNode: _escapeNode,
            onKeyEvent: _onKey,
            child: _GlassMenuPanel(
              maxHeight: widget.maxHeight,
              child: widget.builder(widget.onClose),
            ),
          ),
        ),
      ],
    );
  }
}

class _GlassMenuPanel extends StatelessWidget {
  const _GlassMenuPanel({required this.maxHeight, required this.child});

  final double maxHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(16));
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .45),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: ColoredBox(
            // bg-elevated/95 → HorseTheme.surface (#131617) at .95.
            color: HorseTheme.surface.withValues(alpha: .95),
            child: Material(
              type: MaterialType.transparency,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(6),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One menu row: 44dp min height, rounded-xl hover/highlight, 14px w500 ink.
class GlassMenuItem extends StatelessWidget {
  const GlassMenuItem({
    super.key,
    required this.leading,
    required this.label,
    required this.onTap,
  });

  final Widget leading;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: AlignmentDirectional.centerStart,
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: HorseTheme.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
