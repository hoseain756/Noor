import 'package:flutter/material.dart';

import '../../../core/theme/horse_theme.dart';

/// The home gold-bar section header: a 3×19 rounded gold accent bar, a 10px
/// gap, then the rail title in `titleLarge` — extracted verbatim from the
/// three identical copies that lived in the continue-watching rails (local,
/// linked, and the linked skeleton; evidence audit 121-a1). The generic
/// [MediaRail] header is a separate implementation in shared/ and stays
/// untouched.
///
/// The caller owns the surrounding horizontal padding (the CW rails pad
/// with the rail gutter, `EdgeInsets.symmetric(horizontal: railPad)`).
class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader({super.key, required this.title});

  /// Pre-localized rail title (`english ? 'en' : 'ar'` at the call site,
  /// matching the shared-widget convention — no language flag here).
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 19,
          decoration: BoxDecoration(
            color: HorseTheme.gold,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
      ],
    );
  }
}
