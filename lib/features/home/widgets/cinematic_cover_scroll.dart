import 'package:flutter/material.dart';

/// A full-width, stationary hero which the opaque content physically covers.
/// Only the transform listens to scrolling; network, rails and artwork do not
/// rebuild every frame. Once covered, the first sliver is naturally culled.
class CinematicCoverScroll extends StatefulWidget {
  const CinematicCoverScroll(
      {super.key,
      required this.hero,
      required this.heroHeight,
      required this.slivers,
      this.storageKey});
  final Widget hero;
  final double heroHeight;
  final List<Widget> slivers;
  final PageStorageKey<String>? storageKey;
  @override
  State<CinematicCoverScroll> createState() => _CinematicCoverScrollState();
}

class _CinematicCoverScrollState extends State<CinematicCoverScroll> {
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return CustomScrollView(
      key: widget.storageKey,
      controller: _scroll,
      slivers: [
        SliverToBoxAdapter(
          child: AnimatedBuilder(
            animation: _scroll,
            child: RepaintBoundary(
                child: SizedBox(
                    height: widget.heroHeight,
                    width: double.infinity,
                    child: widget.hero)),
            builder: (context, child) {
              final offset = _scroll.hasClients
                  ? _scroll.offset.clamp(0.0, widget.heroHeight)
                  : 0.0;
              final covered = offset / widget.heroHeight;
              return Transform.translate(
                offset: Offset(0, offset),
                child: Transform.scale(
                  alignment: Alignment.topCenter,
                  scale: reducedMotion ? 1 : 1 - covered * .025,
                  child: Opacity(
                      opacity: reducedMotion ? 1 : 1 - covered * .18,
                      child: child),
                ),
              );
            },
          ),
        ),
        DecoratedSliver(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadiusDirectional.vertical(
                top: Radius.circular(32)),
          ),
          sliver: SliverMainAxisGroup(slivers: widget.slivers),
        ),
      ],
    );
  }
}
