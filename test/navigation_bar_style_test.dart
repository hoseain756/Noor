import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:nova_mobile/core/api/noor_api.dart';
import 'package:nova_mobile/core/data/catalog_repository.dart';
import 'package:nova_mobile/core/state/app_state.dart';
import 'package:nova_mobile/core/theme/nova_theme.dart';
import 'package:nova_mobile/features/settings/navigation_bar_style_page.dart';
import 'package:nova_mobile/features/settings/settings_personalization_page.dart';
import 'package:nova_mobile/features/shell/glass_dock.dart';
import 'package:nova_mobile/features/shell/noor_dock_tabs.dart';
import 'package:nova_mobile/l10n/nova_strings.dart';

class _TestAppState extends AppState {
  _TestAppState(NoorApi api) : super(api, CatalogRepository(api));

  @override
  Future<void> setSetting(String key, dynamic value) async {
    webSettings = {...webSettings, key: value};
    notifyListeners();
  }
}

ThemeData _theme({required bool english, required bool light}) => english
    ? (light ? NovaTheme.light : NovaTheme.dark)
    : NovaTheme.build(light ? Brightness.light : Brightness.dark, arabic: true);

Widget _dockHarness({
  required NavigationBarStyle style,
  required bool english,
  required bool light,
  required Size size,
  required double textScale,
  ValueChanged<String>? onSelected,
}) {
  return MaterialApp(
    theme: _theme(english: english, light: light),
    locale: Locale(english ? 'en' : 'ar'),
    supportedLocales: const [Locale('en'), Locale('ar')],
    localizationsDelegates: const [
      NovaStrings.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(size: size, textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Directionality(
      textDirection: english ? TextDirection.ltr : TextDirection.rtl,
      child: Scaffold(
        body: Stack(
          children: [
            PositionedDirectional(
              start: 0,
              end: 0,
              bottom: 0,
              child: GlassDock(
                tabs: noorDockTabsFor(rtl: !english),
                activeId: 'anime',
                onTabSelected: (tab) => onSelected?.call(tab.id),
                languageCode: english ? 'en' : 'ar',
                style: style,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _settingsHarness(_TestAppState app, Widget page,
    {required bool light, double textScale = 1}) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: Builder(
      builder: (context) {
        final english = context.watch<AppState>().english;
        return MaterialApp(
          theme: _theme(english: english, light: light),
          locale: Locale(english ? 'en' : 'ar'),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            NovaStrings.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: page,
        );
      },
    ),
  );
}

void main() {
  const phone = Size(390, 844);
  final tabLabels = <bool, List<String>>{
    true: ['Home', 'Anime', 'Kids', 'My Library', 'Settings'],
    false: ['الرئيسية', 'الأنمي', 'الأطفال', 'مكتبتي', 'الإعدادات'],
  };

  for (final style in NavigationBarStyle.values) {
    for (final english in [true, false]) {
      for (final light in [true, false]) {
        testWidgets(
            '${style.name} dock: tabs, labels, semantics and RTL — ${english ? 'English LTR' : 'Arabic RTL'}, ${light ? 'light' : 'dark'}, 200% text',
            (tester) async {
          tester.view.physicalSize = phone;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final picked = <String>[];
          final semantics = tester.ensureSemantics();
          await tester.pumpWidget(_dockHarness(
            style: style,
            english: english,
            light: light,
            size: phone,
            textScale: 2,
            onSelected: picked.add,
          ));
          await tester.pumpAndSettle();

          expect(find.byType(FocusableActionDetector), findsNWidgets(5));
          for (var i = 0; i < tabLabels[english]!.length; i++) {
            final label = tabLabels[english]![i];
            final id =
                const ['home', 'anime', 'kids', 'library', 'settings'][i];
            expect(find.bySemanticsLabel(label), findsOneWidget);
            expect(
              tester.getSize(find.byKey(ValueKey('dock-tab-$id'))).height,
              greaterThanOrEqualTo(44),
            );
            if (style == NavigationBarStyle.classic) {
              expect(find.text(label), findsOneWidget);
              expect(find.byTooltip(label), findsNothing);
            } else {
              expect(find.text(label), findsNothing);
              expect(find.byTooltip(label), findsOneWidget);
            }
          }

          final homeX =
              tester.getCenter(find.byKey(const ValueKey('dock-tab-home'))).dx;
          final settingsX = tester
              .getCenter(find.byKey(const ValueKey('dock-tab-settings')))
              .dx;
          if (english) {
            expect(homeX, lessThan(settingsX));
          } else {
            expect(homeX, greaterThan(settingsX));
          }

          await tester.tap(find.byKey(const ValueKey('dock-tab-home')));
          await tester.pump(const Duration(milliseconds: 100));
          expect(picked, ['home']);
          expect(tester.takeException(), isNull);
          semantics.dispose();
        });
      }
    }
  }

  test('Mini sizing keeps large side insets and 48dp tab height', () {
    final sizing = glassDockSizing(
      viewport: phone,
      style: NavigationBarStyle.mini,
    );
    expect(sizing.barHeight, 56);
    expect(sizing.tabHeight, 48);
    expect((phone.width - sizing.barWidth) / 2, greaterThanOrEqualTo(24));
  });

  testWidgets('Appearance opens live style preview and saves choice on rebuild',
      (tester) async {
    tester.view.physicalSize = phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = NoorApi();
    final app = _TestAppState(api)..english = true;
    await tester.pumpWidget(_settingsHarness(
      app,
      const SettingsPersonalizationPage(section: 'appearance'),
      light: true,
      textScale: 2,
    ));

    await tester.ensureVisible(find.text('Navigation bar style'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Navigation bar style'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBarStylePage), findsOneWidget);

    GlassDock preview() => tester.widget<GlassDock>(
        find.byKey(const ValueKey('navigation-style-preview-bar')));
    expect(preview().style, NavigationBarStyle.classic);

    final compactOption =
        find.byKey(const ValueKey('navigation-style-option-compact'));
    final styleScrollable = find.descendant(
      of: find.byType(NavigationBarStylePage),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      compactOption,
      200,
      scrollable: styleScrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(compactOption);
    await tester.pumpAndSettle();
    expect(app.webSettings['navigationBarStyle'], 'compact');
    await tester.drag(styleScrollable, const Offset(0, 1200));
    await tester.pumpAndSettle();
    expect(preview().style, NavigationBarStyle.compact);

    await tester.pumpWidget(
        _settingsHarness(app, const NavigationBarStylePage(), light: true));
    await tester.pumpAndSettle();
    expect(app.webSettings['navigationBarStyle'], 'compact');
    expect(preview().style, NavigationBarStyle.compact);
    expect(tester.takeException(), isNull);
  });
}
