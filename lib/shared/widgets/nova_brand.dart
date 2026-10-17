import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Original supplied artwork; the wordmark is never retyped.
class NovaBrand extends StatelessWidget {
  const NovaBrand(
      {super.key, this.width = 144, this.symbolOnly = false, this.onDark});
  final double width;
  final bool symbolOnly;
  final bool? onDark;
  @override
  Widget build(BuildContext context) {
    final dark = onDark ?? Theme.of(context).brightness == Brightness.dark;
    final asset = symbolOnly
        ? 'icon_red'
        : dark
            ? 'lockup_for_dark_bg'
            : 'lockup_for_light_bg';
    return Semantics(
        label: 'NOVA',
        image: true,
        child: ExcludeSemantics(
            child: SvgPicture.asset('assets/brand/svg/$asset.svg',
                width: width, fit: BoxFit.contain, matchTextDirection: false)));
  }
}
