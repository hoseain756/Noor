import 'package:flutter/material.dart';

import '../../core/theme/horse_theme.dart';

/// Animated linear-gradient shimmer box. Honors `MediaQuery.
/// disableAnimationsOf` by rendering a static base fill.
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
  });

  final double? width;
  final double? height;
  final BorderRadiusGeometry? borderRadius;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(12);
    Widget box = LayoutBuilder(
      builder: (context, constraints) {
        final width = widget.width ?? constraints.maxWidth;
        final height = widget.height ?? constraints.maxHeight;
        final size = Size(width, height);
        if (MediaQuery.disableAnimationsOf(context)) {
          return _skeletonBase(size, radius);
        }
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final phase = _controller.value * 2 - 1; // -1..1 sweep
            return _skeletonBase(
              size,
              radius,
              gradient: LinearGradient(
                begin: Alignment(phase - 1, 0),
                end: Alignment(phase + 1, 0),
                colors: const [
                  HorseTheme.raised,
                  HorseTheme.line,
                  HorseTheme.raised,
                ],
                stops: const [0.35, 0.5, 0.65],
              ),
            );
          },
        );
      },
    );
    if (widget.width != null || widget.height != null) {
      box = SizedBox(
        width: widget.width,
        height: widget.height,
        child: box,
      );
    }
    return box;
  }

  Widget _skeletonBase(Size size, BorderRadiusGeometry radius,
      {Gradient? gradient}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: gradient,
        color: gradient == null ? HorseTheme.raised : null,
      ),
      child: SizedBox(width: size.width, height: size.height),
    );
  }
}
