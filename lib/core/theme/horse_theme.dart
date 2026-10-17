import 'package:nova_mobile/core/theme/nova_theme.dart';
export 'nova_theme.dart';

/// Compatibility for stored preferences and external callers during migration.
abstract final class HorseTheme {
  static const bpWide = 700.0;
  static const canvas = NovaColors.ink;
  static const surface = NovaColors.graphite;
  static const raised = NovaColors.surfaceHigh;
  static const line = NovaColors.divider;
  static const gold = NovaColors.redSoft;
  static const ink = NovaColors.white;
  static const muted = NovaColors.mist;
  static final dark = NovaTheme.dark;
}
