import 'package:flutter_test/flutter_test.dart';
import 'package:noor_mobile/features/shell/dock_tab.dart';
import 'package:noor_mobile/features/shell/noor_dock_tabs.dart';

void main() {
  group('Noor dock tab set', () {
    test('five tabs in Settings|Library|Kids|Anime|Home visual order, both directions',
        () {
      final ltr = noorDockTabsFor(hideAnime: false, rtl: false);
      expect(
        ltr.map((t) => t.id).toList(),
        ['settings', 'library', 'kids', 'anime', 'home'],
      );
      final rtl = noorDockTabsFor(hideAnime: false, rtl: true);
      expect(
        rtl.map((t) => t.id).toList(),
        ['home', 'anime', 'kids', 'library', 'settings'],
      );
    });

    test('hide-anime drops only the Anime tab, order preserved', () {
      expect(
        noorDockTabsFor(hideAnime: true, rtl: false).map((t) => t.id).toList(),
        ['settings', 'library', 'kids', 'home'],
      );
      expect(
        noorDockTabsFor(hideAnime: true, rtl: true).map((t) => t.id).toList(),
        ['home', 'kids', 'library', 'settings'],
      );
    });

    test('index ↔ tab id mapping round-trips for every shell view', () {
      for (var i = 0; i < 5; i++) {
        expect(noorDockIndexForTabId(noorDockTabIdForIndex(i)), i);
      }
      expect(noorDockTabIdForIndex(0), DockTab.homeId);
      expect(noorDockTabIdForIndex(3), 'library');
      expect(noorDockTabIdForIndex(4), DockTab.settingsId);
      expect(noorDockIndexForTabId('unknown'), 4); // everything else → Settings
    });

    test('library tab carries the bilingual labels the shell already used', () {
      final library =
          kNoorDockTabs.firstWhere((tab) => tab.id == 'library');
      expect(library.label(arabic: false), 'My Library');
      expect(library.label(arabic: true), 'مكتبتي');
      expect(library.view, 'library');
    });
  });
}
