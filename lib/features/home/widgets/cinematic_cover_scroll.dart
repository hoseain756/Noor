import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

typedef CinematicHeroBuilder = Widget Function(
    ValueListenable<double> contentVisibility);

/// Keeps the cinematic artwork behind the independently scrolling content.
/// The hero is a fixed bottom layer; the scroll view begins with a clear
/// spacer and its opaque, rounded surface then moves up over the artwork.
class CinematicCoverScroll extends StatefulWidget {
  const CinematicCoverScroll(
      {super.key,
      required this.heroBuilder,
      required this.heroHeight,
      required this.slivers,
      this.storageKey});
  final CinematicHeroBuilder heroBuilder;
  final double heroHeight;
  final List<Widget> slivers;
  final PageStorageKey<String>? storageKey;

  @override
  State<CinematicCoverScroll> createState() => _CinematicCoverScrollState();
}

class _CinematicCoverScrollState extends State<CinematicCoverScroll> {
  final _scroll = ScrollController();
  late final ValueNotifier<double> _contentVisibility;

  @override
  void initState() {
    super.initState();
    _contentVisibility = ValueNotifier(1);
    _scroll.addListener(_updateContentVisibility);
  }

  @override
  void didUpdateWidget(covariant CinematicCoverScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.heroHeight != widget.heroHeight) {
      _updateContentVisibility();
    }
  }

  void _updateContentVisibility() {
    final height = widget.heroHeight;
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    final visibility =
        height <= 0 ? 0.0 : (1 - offset / height).clamp(0.0, 1.0);
    if ((_contentVisibility.value - visibility).abs() > .001) {
      _contentVisibility.value = visibility;
    }
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_updateContentVisibility)
      ..dispose();
    _contentVisibility.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final heroHeight = widget.heroHeight;
    final surface = Theme.of(context).colorScheme.surface;
    return CinematicLayerStack(
      key: const ValueKey('cinematic-layer-stack'),
      children: [
        // FIX: the hero is deliberately the first (bottom-most) Stack layer.
        PositionedDirectional(
          top: 0,
          start: 0,
          end: 0,
          height: heroHeight,
          child: ValueListenableBuilder<double>(
            valueListenable: _contentVisibility,
            child: RepaintBoundary(
              child: widget.heroBuilder(_contentVisibility),
            ),
            builder: (context, visibility, child) => IgnorePointer(
              // The hero accepts taps at the top. Once the surface begins to
              // move, its controls stop competing with scrolling content.
              ignoring: visibility < .999,
              child: child,
            ),
          ),
        ),
        // FIX: the scroll view is the last (top-most) Stack layer. Its
        // transparent spacer preserves the hero's layout height; the opaque
        // DecoratedSliver is what physically covers the artwork as it rises.
        CustomScrollView(
          key: widget.storageKey,
          controller: _scroll,
          slivers: [
            SliverToBoxAdapter(child: SizedBox(height: heroHeight)),
            DecoratedSliver(
              key: const ValueKey('cinematic-content-surface'),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: const BorderRadiusDirectional.vertical(
                    top: Radius.circular(32)),
              ),
              sliver: SliverMainAxisGroup(slivers: widget.slivers),
            ),
          ],
        ),
      ],
    );
  }
}

/// A full-size, ordered layer host for the stationary hero and scroll view.
/// It paints in child order like Stack, and hit-tests every layer so a tap on
/// the transparent hero spacer can still reach hero controls while the page
/// is at scroll offset zero. The hero becomes IgnorePointer as soon as scroll
/// content moves; the scrollable then owns those gestures.
class CinematicLayerStack extends MultiChildRenderObjectWidget {
  const CinematicLayerStack({super.key, required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCinematicLayerStack();
}

class _RenderCinematicLayerStack extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, StackParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, StackParentData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! StackParentData) {
      child.parentData = StackParentData();
    }
  }

  @override
  void performLayout() {
    size = constraints.constrain(Size(
      constraints.hasBoundedWidth ? constraints.maxWidth : 0,
      constraints.hasBoundedHeight ? constraints.maxHeight : 0,
    ));
    final childConstraints = BoxConstraints.tight(size);
    RenderBox? child = firstChild;
    while (child != null) {
      final parentData = child.parentData! as StackParentData;
      if (parentData.isPositioned) {
        child.layout(parentData.positionedChildConstraints(size),
            parentUsesSize: true);
        final dx = parentData.left ??
            (parentData.right == null
                ? 0.0
                : size.width - parentData.right! - child.size.width);
        final dy = parentData.top ??
            (parentData.bottom == null
                ? 0.0
                : size.height - parentData.bottom! - child.size.height);
        parentData.offset = Offset(dx, dy);
      } else {
        child.layout(childConstraints, parentUsesSize: true);
        parentData.offset = Offset.zero;
      }
      child = childAfter(child);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    var hit = false;
    RenderBox? child = lastChild;
    while (child != null) {
      final parentData = child.parentData! as StackParentData;
      hit = result.addWithPaintOffset(
            offset: parentData.offset,
            position: position,
            hitTest: (result, transformed) =>
                child!.hitTest(result, position: transformed),
          ) ||
          hit;
      child = childBefore(child);
    }
    return hit;
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final offset = (child.parentData! as StackParentData).offset;
    transform.translateByDouble(offset.dx, offset.dy, 0, 1);
  }
}
