import 'package:flutter/material.dart';

import 'app/horse_app.dart';
import 'core/api/horse_api.dart';
import 'core/data/catalog_repository.dart';
import 'core/state/app_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final api = HorseApi();
  final appState = AppState(api, CatalogRepository(api));
  runApp(HorseApp(state: appState));
}
