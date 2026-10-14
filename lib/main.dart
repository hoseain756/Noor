import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/noor_app.dart';
import 'core/api/noor_api.dart';
import 'core/data/catalog_repository.dart';
import 'core/state/app_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Edge-to-edge (user mandate, Task 115): the app draws behind a fully
  // transparent status bar (battery/signal/clock) and navigation bar — the
  // full-screen glass look. The shell re-asserts this style via
  // AnnotatedRegion, so it also survives the player's immersive toggling.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  ));
  final api = NoorApi();
  final appState = AppState(api, CatalogRepository(api));
  runApp(NoorApp(state: appState));
}
