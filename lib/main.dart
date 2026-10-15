import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'app/noor_app.dart';
import 'core/api/noor_api.dart';
import 'core/data/catalog_repository.dart';
import 'core/state/app_state.dart';
import 'core/theme/system_bars.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // media_kit (libmpv) init — Task 127: without this the first Player()
  // construction throws ('MediaKit.ensureInitialized must be called…') inside
  // the player route's first frame, which in release paints the full-screen
  // grey/white error box instead of the player. Idempotent.
  MediaKit.ensureInitialized();
  // Edge-to-edge (user mandate, Tasks 115/117): the app draws behind a fully
  // transparent status bar (battery/signal/clock) and navigation bar — the
  // full-screen glass look. Boot default matches the dark Horse canvas; the
  // shell re-asserts the style via AnnotatedRegion, derived from the live
  // theme brightness, so it also survives the player's immersive toggling.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
      noorSystemBarOverlayStyle(Brightness.dark));
  final api = NoorApi();
  final appState = AppState(api, CatalogRepository(api));
  runApp(NoorApp(state: appState));
}
