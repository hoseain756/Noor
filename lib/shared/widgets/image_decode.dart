import 'package:flutter/widgets.dart';

/// Logical-width → pixel `cacheWidth` for network images (Task 136 perf pass).
///
/// Every poster/still/logo in the app used to decode at its DOWNLOAD
/// resolution (TMDB serves w342–w1280, AniList up to 460px) and held the
/// full-res texture even when drawn at 122 logical px. On a low-end device
/// that is megabytes of dead texture memory per screen, constant GC churn
/// and slow decodes on the UI thread path. Passing `cacheWidth` makes the
/// codec downsample at decode time — identical visuals, a fraction of the
/// memory, much faster first paint.
///
/// [logicalWidth] is the on-screen width in logical pixels (the box width,
/// not the image's natural width). The result is that width scaled by the
/// device pixel ratio (clamped to a sane band) so one code path serves
/// 40px logos and 800px hero art.
int imageCacheWidth(BuildContext context, double logicalWidth) {
  final dpr = MediaQuery.devicePixelRatioOf(context);
  final px = (logicalWidth.clamp(64.0, 1280.0) * dpr).round();
  return px < 96 ? 96 : px;
}
