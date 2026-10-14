import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/media_item.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';
import 'noor_toast.dart';

/// Long-press "quick look" for any media card (movie / series / anime).
///
/// The page behind blurs and dims, the tapped card's poster scales up to the
/// center with its title and year underneath, and a floating rounded menu
/// appears below with the quick actions (watch / add to library / mark as
/// watched) — matching the reference sheet style: dark rounded rows, icon on
/// the far side, label on the reading side, dismiss by tapping the backdrop.
Future<void> showMediaQuickLook(
  BuildContext context, {
  required MediaItem item,
  required VoidCallback onOpen,
}) async {
  HapticFeedback.mediumImpact();
  await Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => _QuickLookPage(item: item, onOpen: onOpen),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: child,
      ),
    ),
  );
}

class _QuickLookPage extends StatefulWidget {
  const _QuickLookPage({required this.item, required this.onOpen});

  final MediaItem item;
  final VoidCallback onOpen;

  @override
  State<_QuickLookPage> createState() => _QuickLookPageState();
}

class _QuickLookPageState extends State<_QuickLookPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  /// The card block grows in from ~82% with a soft overshoot; the menu rides
  /// in with a small upward slide. Reverse plays on close before the pop.
  late final Animation<double> _scale = Tween<double>(begin: .82, end: 1)
      .animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
      );
  late final Animation<Offset> _menuSlide =
      Tween<Offset>(begin: const Offset(0, .16), end: Offset.zero).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    await _controller.reverse();
    if (mounted) Navigator.of(context).pop();
  }

  /// Watch = close, then open the detail page exactly like a regular tap.
  void _watch() {
    Navigator.of(context).pop();
    widget.onOpen();
  }

  Future<void> _toggleLibrary(bool inLibrary) async {
    final app = context.read<AppState>();
    final english = app.english;
    await app.toggleWatchlist(widget.item);
    if (!mounted) return;
    NoorToast.show(
      context,
      inLibrary
          ? (english ? 'Removed from library' : 'تمت الإزالة من المكتبة')
          : (english ? 'Added to library' : 'تمت الإضافة إلى المكتبة'),
    );
    Navigator.of(context).pop();
  }

  Future<void> _markWatched(bool watched) async {
    final app = context.read<AppState>();
    final english = app.english;
    if (watched) {
      NoorToast.show(
        context,
        english ? 'Already marked as watched' : 'مُحددة كمشاهدة بالفعل',
      );
      return;
    }
    await app.recordPlayback(widget.item, positionMs: 1, durationMs: 0);
    if (!mounted) return;
    NoorToast.show(
      context,
      english ? 'Marked as watched' : 'تم التحديد كمشاهد',
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final app = context.watch<AppState>();
    final english = app.english;
    final item = widget.item;
    final inLibrary = app.contains(item);
    final watched = app.history.any((h) => h.item.id == item.id);
    // Reference sheet: poster ≈ 58% of the screen width, 2:3, radius 20.
    final posterWidth = (size.width * .58).clamp(180.0, 260.0).toDouble();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Blurred, dimmed backdrop — tap anywhere to dismiss.
          GestureDetector(
            onTap: _close,
            excludeFromSemantics: true,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(color: Colors.black.withValues(alpha: .62)),
            ),
          ),
          SafeArea(
            child: Center(
              child: reduceMotion
                  ? _content(
                      context,
                      english: english,
                      inLibrary: inLibrary,
                      watched: watched,
                      posterWidth: posterWidth,
                    )
                  : ScaleTransition(
                      scale: _scale,
                      child: _content(
                        context,
                        english: english,
                        inLibrary: inLibrary,
                        watched: watched,
                        posterWidth: posterWidth,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(
    BuildContext context, {
    required bool english,
    required bool inLibrary,
    required bool watched,
    required double posterWidth,
  }) {
    final item = widget.item;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The enlarged poster card.
        Container(
          width: posterWidth,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .55),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: AspectRatio(
              aspectRatio: .68,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: HorseTheme.raised),
                  if (item.poster != null)
                    Image.network(
                      item.poster!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(
                          Icons.movie_outlined,
                          size: 44,
                          color: HorseTheme.gold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        // Title + year under the card.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            item.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
        ),
        if (item.releaseInfo?.isNotEmpty == true) ...[
          const SizedBox(height: 4),
          Text(
            item.releaseInfo!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: HorseTheme.muted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 22),
        // The floating rounded action menu.
        SlideTransition(
          position: _menuSlide,
          child: _QuickMenu(
            rows: [
              _QuickMenuRow(
                icon: Icons.play_arrow_rounded,
                label: english ? 'Watch' : 'مشاهدة',
                onTap: _watch,
              ),
              _QuickMenuRow(
                icon: inLibrary
                    ? Icons.check_rounded
                    : Icons.add_rounded,
                label: inLibrary
                    ? (english ? 'Remove from library' : 'إزالة من المكتبة')
                    : (english ? 'Add to library' : 'إضافة للمكتبة'),
                onTap: () => _toggleLibrary(inLibrary),
              ),
              _QuickMenuRow(
                icon: watched
                    ? Icons.check_circle_rounded
                    : Icons.check_circle_outline_rounded,
                label: watched
                    ? (english ? 'Watched' : 'تمت المشاهدة')
                    : (english ? 'Mark as watched' : 'تحديد كمشاهد'),
                onTap: () => _markWatched(watched),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickMenuRow {
  const _QuickMenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// The reference menu: one dark rounded container of full-width rows,
/// label on the reading side and the icon on the far side, hairline
/// dividers between rows.
class _QuickMenu extends StatelessWidget {
  const _QuickMenu({required this.rows});

  final List<_QuickMenuRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      constraints: const BoxConstraints(maxWidth: 420),
      decoration: BoxDecoration(
        color: HorseTheme.raised.withValues(alpha: .97),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: HorseTheme.line.withValues(alpha: .8)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    height: 1,
                    color: HorseTheme.line.withValues(alpha: .55),
                  ),
                ),
              _buildRow(context, rows[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, _QuickMenuRow row) {
    return Semantics(
      button: true,
      label: row.label,
      child: InkWell(
        onTap: row.onTap,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                // Reading side (right in Arabic, left in English).
                Expanded(
                  child: Text(
                    row.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: HorseTheme.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Far side icon — sits at the left edge in Arabic, exactly
                // like the reference sheet.
                Icon(row.icon, size: 22, color: HorseTheme.ink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
