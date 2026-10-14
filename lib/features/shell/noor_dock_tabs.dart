/// Noor's glass-dock tab set: the app-agnostic dock model from `dock_tab.dart`
/// mapped onto Noor's real top-level destinations.
///
/// Integration decisions (Task 107-d, revised Task 111):
///  - Noor HAS all five top-level views (Home / Anime / Kids / My Library /
///    Settings), so the four Harbor tabs keep their slots and My Library joins
///    the dock — it was previously unreachable from the phone bar (only the
///    Settings page shortcut and the tablet side panel linked to it).
///  - Visual order stays Settings | Library | Kids | Anime | Home in BOTH
///    languages (Home far-right, like the Harbor web dock). The per-direction
///    order arrays are applied at list-build time and are never re-flipped by
///    the ambient `Directionality` (the Row already mirrors itself in RTL).
///  - USER MANDATE (Task 111): the Anime tab is a PERMANENT dock destination.
///    The earlier `hideContent.anime`-drops-the-tab behavior is reverted —
///    synced/legacy settings could silently remove the button, which users
///    read as a bug ("the Anime button is missing"). `hideContent.anime`
///    keeps filtering anime CONTENT rows on home/catalogs, but the tab itself
///    no longer disappears. This deliberately diverges from the web dock's
///    hide-anime filter.
///  - `webSettings['kidsMode']` is a dormant web-sync flag with no mobile
///    behavior, so the web's kids-mode tab filter is intentionally NOT wired
///    and the dock's `kidsZoom` stays 1.0 (see MainShell).
library;

import 'package:flutter/material.dart';

import 'dock_tab.dart';
import 'glass_dock.dart';

/// Noor's dock tab pool: the four Harbor tabs + My Library (labels/icons
/// match the tablet side panel).
const List<DockTab> kNoorDockTabs = [
  ...kDockTabs,
  DockTab(
    id: 'library',
    view: 'library',
    labelEn: 'My Library',
    labelAr: 'مكتبتي',
    iconOutline: Icons.video_library_outlined,
    iconFilled: Icons.video_library,
  ),
];

/// On-screen order, left → right: Settings | Library | Kids | Anime | Home.
const List<String> kNoorDockOrderLtr = [
  DockTab.settingsId,
  'library',
  DockTab.kidsId,
  DockTab.animeId,
  DockTab.homeId,
];

/// Same visual order for RTL rows (a Row under RTL `Directionality` lays its
/// array out right → left).
const List<String> kNoorDockOrderRtl = [
  DockTab.homeId,
  DockTab.animeId,
  DockTab.kidsId,
  'library',
  DockTab.settingsId,
];

/// Builds Noor's dock tabs: explicit per-direction order. The Anime tab is
/// permanent (user mandate, Task 111) — no filter ever drops it. Never
/// reverse the result for RTL.
List<DockTab> noorDockTabsFor({required bool rtl}) {
  final byId = {for (final tab in kNoorDockTabs) tab.id: tab};
  final order = rtl ? kNoorDockOrderRtl : kNoorDockOrderLtr;
  return [for (final id in order) if (byId[id] != null) byId[id]!];
}

/// MainShell `_selected` index → dock tab id (IndexedStack order: home, anime,
/// kids, library, settings).
String noorDockTabIdForIndex(int index) => switch (index) {
      0 => DockTab.homeId,
      1 => DockTab.animeId,
      2 => DockTab.kidsId,
      3 => 'library',
      _ => DockTab.settingsId,
    };

/// Dock tab id → MainShell `_selected` index.
int noorDockIndexForTabId(String id) => switch (id) {
      DockTab.homeId => 0,
      DockTab.animeId => 1,
      DockTab.kidsId => 2,
      'library' => 3,
      _ => 4,
    };

/// Bottom clearance page content must reserve so nothing hides behind the
/// floating dock — the web `--nav-clearance` formula (bar height + bottom
/// offset + safe bottom + 16px air), resolved for the current window class.
///
/// Mirrors MainShell's mount rule: the dock exists only below Noor's existing
/// 840px tablet breakpoint; at/above it the legacy 76px + safe-bottom air is
/// kept so tablet pages do not change.
double glassDockContentClearance(BuildContext context) {
  final media = MediaQuery.of(context);
  final safe = media.padding.bottom;
  if (media.size.width >= 840) return 76 + safe;
  final sizing = glassDockSizing(
    viewport: media.size,
    safePadding: media.padding,
  );
  return sizing.contentClearance(safeBottom: safe);
}
