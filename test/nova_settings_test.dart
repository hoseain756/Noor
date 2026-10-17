import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:nova_mobile/core/api/noor_api.dart';
import 'package:nova_mobile/core/data/catalog_repository.dart';
import 'package:nova_mobile/core/models/addon.dart';
import 'package:nova_mobile/core/state/app_state.dart';
import 'package:nova_mobile/core/theme/nova_theme.dart';
import 'package:nova_mobile/l10n/nova_strings.dart';
import 'package:nova_mobile/features/settings/addons_page.dart';
import 'package:nova_mobile/features/settings/integrations_page.dart';
import 'package:nova_mobile/features/settings/settings_page.dart';
import 'package:nova_mobile/features/settings/settings_display_page.dart';
import 'package:nova_mobile/features/settings/settings_personalization_page.dart';
import 'package:nova_mobile/features/settings/settings_preferences_page.dart';
import 'package:nova_mobile/features/settings/stats_page.dart';

class _SettingsApp extends AppState {
  _SettingsApp(NoorApi api) : super(api, CatalogRepository(api)) {
    english = true;
  }
  @override
  Future<void> setLanguage(bool value) async {
    english = value;
    webSettings = {...webSettings, 'uiLanguage': value ? 'en' : 'ar'};
    notifyListeners();
  }

  @override
  Future<void> setSetting(String key, dynamic value) async {
    webSettings = {...webSettings, key: value};
    notifyListeners();
  }

  @override
  Future<void> setAddonEnabled(String id, bool enabled) async {
    addons = addons
        .map((a) => a.id == id ? a.copyWith(enabled: enabled) : a)
        .toList();
    notifyListeners();
  }

  @override
  Future<void> reorderAddons(int oldIndex, int newIndex) async {
    final sorted = List.of(addons)..sort((a, b) => a.order.compareTo(b.order));
    if (oldIndex < newIndex) newIndex--;
    final moved = sorted.removeAt(oldIndex);
    sorted.insert(newIndex, moved);
    addons = [
      for (var i = 0; i < sorted.length; i++) sorted[i].copyWith(order: i)
    ];
    notifyListeners();
  }
}

Widget _harness(_SettingsApp app, Widget page,
        {double scale = 1, bool light = false}) =>
    ChangeNotifierProvider<AppState>.value(
        value: app,
        child: Builder(builder: (context) {
          final english = context.watch<AppState>().english;
          return MaterialApp(
              theme: english
                  ? (light ? NovaTheme.light : NovaTheme.dark)
                  : NovaTheme.build(light ? Brightness.light : Brightness.dark,
                      arabic: true),
              locale: Locale(english ? 'en' : 'ar'),
              supportedLocales: const [Locale('en'), Locale('ar')],
              localizationsDelegates: const [
                NovaStrings.delegate,
                ...GlobalMaterialLocalizations.delegates
              ],
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: page);
        }));

void main() {
  testWidgets(
      'search finds a setting category and language changes direction live',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = _SettingsApp(NoorApi());
    await tester.pumpWidget(_harness(app, const SettingsPage()));
    await tester.enterText(find.byType(TextField), 'language');
    await tester.pump();
    expect(find.text('Language'), findsOneWidget);
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPersonalizationPage), findsOneWidget);
    await tester.tap(find.text('Arabic'));
    await tester.pumpAndSettle();
    expect(app.english, isFalse);
    expect(app.webSettings['uiLanguage'], 'ar');
    expect(
        Directionality.of(
            tester.element(find.byType(SettingsPersonalizationPage))),
        TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(360, 800), const Size(1200, 800)]) {
    for (final english in [true, false]) {
      testWidgets(
          'settings fit $size with 200% text, ${english ? 'LTR' : 'RTL'}',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = _SettingsApp(NoorApi())..english = english;
        await tester.pumpWidget(
            _harness(app, const SettingsPage(), scale: 2, light: english));
        await tester.pump();
        expect(tester.takeException(), isNull);
        for (final page in const <Widget>[
          SettingsPreferencesPage(subtitles: false),
          SettingsPreferencesPage(subtitles: true),
          SettingsDisplayPage(),
          SettingsDisplayPage(kidsOnly: true),
          SettingsPersonalizationPage(section: 'language'),
          SettingsPersonalizationPage(section: 'appearance'),
          IntegrationsPage(),
          AddonsPage(),
          StatsPage(),
        ]) {
          await tester
              .pumpWidget(_harness(app, page, scale: 2, light: english));
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: '${page.runtimeType} at $size');
          await tester.drag(
              find.byType(Scrollable).first, const Offset(0, -3000));
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'Scrolled ${page.runtimeType} at $size');
        }
      });
    }
  }

  testWidgets(
      'addon priority controls update order and enable state independently',
      (tester) async {
    tester.view.physicalSize = const Size(600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = _SettingsApp(NoorApi())
      ..addons = const [
        Addon(
            id: 'a',
            name: 'Catalog A',
            transportUrl: 'https://a.example/manifest.json',
            manifest: {},
            order: 0),
        Addon(
            id: 'b',
            name: 'Catalog B',
            transportUrl: 'https://b.example/manifest.json',
            manifest: {},
            order: 1),
      ];
    await tester.pumpWidget(_harness(app, const AddonsPage()));
    await tester.pump();
    await tester.ensureVisible(find.byTooltip('Move down').first);
    await tester.tap(find.byTooltip('Move down').first);
    await tester.pump();
    expect(app.addons.first.id, 'b');
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(app.addons.first.enabled, isFalse);
    expect(app.addons.last.enabled, isTrue);
    expect(tester.takeException(), isNull);
  });
}
