import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/features/shell/dock_tab.dart';
import 'package:nova_mobile/features/shell/noor_dock_tabs.dart';

void main() {
  group('Noor dock tab set', () {
    test('five tabs preserve logical order so Directionality mirrors them once',
        () {
      final ltr = noorDockTabsFor(rtl: false);
      expect(
        ltr.map((t) => t.id).toList(),
        ['home', 'anime', 'kids', 'library', 'settings'],
      );
      final rtl = noorDockTabsFor(rtl: true);
      expect(
        rtl.map((t) => t.id).toList(),
        ['home', 'anime', 'kids', 'library', 'settings'],
      );
    });

    test('the Anime tab is permanent — no filter drops it (user mandate)', () {
      // Task 111: hideContent.anime must never remove the dock button again.
      // There is no hide parameter anymore; assert the tab in every build.
      expect(noorDockTabsFor(rtl: false).map((t) => t.id), contains('anime'));
      expect(noorDockTabsFor(rtl: true).map((t) => t.id), contains('anime'));
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
      final library = kNoorDockTabs.firstWhere((tab) => tab.id == 'library');
      expect(library.label(arabic: false), 'My Library');
      expect(library.label(arabic: true), 'مكتبتي');
      expect(library.view, 'library');
    });
  });
}
