import 'package:flutter/material.dart';

import 'app/noor_app.dart';
import 'core/api/noor_api.dart';
import 'core/data/catalog_repository.dart';
import 'core/state/app_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final api = NoorApi();
  final appState = AppState(api, CatalogRepository(api));
  runApp(NoorApp(state: appState));
}
