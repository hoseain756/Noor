/// Harbor web → Flutter port — dock tab model, per-direction order arrays,
/// tab filtering and the pure active-tab helpers.
///
/// Provenance: translated from Harbor web `src/components/harbor/chrome/nav-items.tsx`
/// (`DockTab`, `DOCK_TABS`, `DOCK_ORDER`, `dockTabsFor`, `dockDirectionFor`,
/// `dockTabLabel`) and from the pure helpers `tabIdForView` / `activeTabId` in
/// `src/components/harbor/chrome/glass-dock.tsx` (fetched verbatim by Task
/// 107-a, audited by Task 107-b).
///
/// The model is intentionally app-agnostic: tab ids and views are plain
/// strings so the host app (Noor) can add its own tabs (e.g. Library) and map
/// its own navigation stack onto the dock without this file depending on it.
/// See INTEGRATION_NOTES.md for the wiring recipe.
library;

import 'package:nova_mobile/l10n/nova_strings.dart';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// One bottom-dock tab: identity (`id`), destination (`view`), bilingual
/// labels and the outline/filled icon pair used by the 150ms cross-fade.
class DockTab {
  const DockTab({
    required this.id,
    required this.view,
    required this.labelEn,
    required this.labelAr,
    required this.iconOutline,
    required this.iconFilled,
  });

  /// Stable identifier (web `data-tab` / `DockTabId`). Canonical values live
  /// in [DockTab] constants below; hosts may add their own ids.
  final String id;

  /// Destination the host navigates to when the tab is activated (web
  /// `resetTo({kind: 'view', view: …})`).
  final String view;

  final String labelEn;
  final String labelAr;

  /// Outline glyph shown at rest (lucide `strokeWidth: 1.8` equivalent).
  final IconData iconOutline;

  /// Filled glyph shown while active / scrub-previewed (lucide `fill`
  /// equivalent).
  final IconData iconFilled;

  /// Web `dockTabLabel(tab, lang)`: Arabic label when the language is Arabic.
  String label({required bool arabic}) => arabic ? labelAr : labelEn;

  // Canonical tab ids (web DockTabId union).
  static const settingsId = 'settings';
  static const kidsId = 'kids';
  static const animeId = 'anime';
  static const homeId = 'home';

  /// Home is the fallback active tab when a stack walk finds no view frame
  /// (web `activeTabId` fallback).
  static const fallbackId = homeId;
}

/// The four Harbor tabs in LOGICAL order (web `DOCK_TABS` declaration order:
/// settings | kids | anime | home).
final List<DockTab> kDockTabs = [
  DockTab(
    id: DockTab.settingsId,
    view: 'settings',
    labelEn: NovaStrings.lookup(true, 'settings'),
    labelAr: NovaStrings.lookup(false, 'settings'),
    iconOutline: LucideIcons.settings,
    iconFilled: LucideIcons.settings,
  ),
  DockTab(
    id: DockTab.kidsId,
    view: 'kids',
    labelEn: NovaStrings.lookup(true, 'message774'),
    labelAr: NovaStrings.lookup(false, 'message774'),
    iconOutline: LucideIcons.baby,
    iconFilled: LucideIcons.baby,
  ),
  DockTab(
    id: DockTab.animeId,
    view: 'anime',
    labelEn: NovaStrings.lookup(true, 'message775'),
    labelAr: NovaStrings.lookup(false, 'message775'),
    iconOutline: LucideIcons.sparkles,
    iconFilled: LucideIcons.sparkles,
  ),
  DockTab(
    id: DockTab.homeId,
    view: 'home',
    labelEn: NovaStrings.lookup(true, 'message421'),
    labelAr: NovaStrings.lookup(false, 'message421'),
    iconOutline: LucideIcons.house,
    iconFilled: LucideIcons.house,
  ),
];

/// Explicit per-direction on-screen order (web `DOCK_ORDER`).
///
/// The web flex row follows the document direction, so `ltr` lays its array
/// left-to-right and `rtl` lays its array right-to-left — BOTH yield the same
/// visual order: Settings | Kids | Anime | Home, Home always far-right.
/// A Flutter `Row` inside the ambient `Directionality` behaves identically,
/// which is why these arrays must be applied WITHOUT any extra flip (never
/// double-flip by reversing again for RTL).
const List<String> kDockOrderLtr = [
  DockTab.settingsId,
  DockTab.kidsId,
  DockTab.animeId,
  DockTab.homeId,
];
const List<String> kDockOrderRtl = [
  DockTab.homeId,
  DockTab.animeId,
  DockTab.kidsId,
  DockTab.settingsId,
];

/// Web `dockTabsFor(settings, lang)`: filter the tab pool, then emit the tabs
/// in the explicit per-direction order.
///
/// - Kids Mode keeps only Home + Kids (Settings sits behind the parent gate).
/// - `hideAnime` removes the Anime tab.
/// - Relative order from [kDockOrderLtr] / [kDockOrderRtl] is preserved.
List<DockTab> dockTabsFor({
  required bool kidsMode,
  required bool hideAnime,
  required bool rtl,
}) {
  final byId = {for (final tab in kDockTabs) tab.id: tab};
  final order = rtl ? kDockOrderRtl : kDockOrderLtr;
  return [
    for (final id in order)
      if (byId[id] != null &&
          !(kidsMode && id != DockTab.homeId && id != DockTab.kidsId) &&
          !(hideAnime && id == DockTab.animeId))
        byId[id]!,
  ];
}

/// Web `dockDirectionFor(lang)` regex (`/^ar(-|_|$)/i`): true for Arabic
/// language codes. The DOCK itself takes its direction from the ambient
/// `Directionality` — this helper only decides labels/order for hosts that
/// carry the language separately.
bool dockIsArabicLanguage(String? languageCode) =>
    languageCode != null &&
    RegExp(r'^ar(-|_|$)', caseSensitive: false).hasMatch(languageCode);

/// Web `dockTabLabel(tab, lang)`.
String dockTabLabel(DockTab tab, {required bool arabic}) =>
    tab.label(arabic: arabic);

/// Web `tabIdForView(view)`: map any view id to the dock tab that represents
/// it. `anime` / `kids` / `home` map to themselves; EVERYTHING else (settings,
/// hub pages, catalogs, live TV, calendar, …) maps to Settings so the Settings
/// tab stays lit while browsing pages pushed on top of it.
///
/// [extraViewIds] lets the host extend the map (e.g. Noor's `library` → its
/// Library tab id) without forking the function.
String dockTabIdForView(
  String view, {
  Map<String, String> extraViewIds = const {},
}) {
  final mapped = extraViewIds[view];
  if (mapped != null) return mapped;
  return switch (view) {
    DockTab.animeId => DockTab.animeId,
    DockTab.kidsId => DockTab.kidsId,
    DockTab.homeId => DockTab.homeId,
    _ => DockTab.settingsId,
  };
}

/// One navigation-stack frame, reduced to what the dock needs (web `Frame`:
/// `kind === 'view'` frames carry a view id; everything else — detail, player,
/// overlays — is a pass-through in the active-tab walk).
class DockNavFrame {
  const DockNavFrame({required this.isView, this.view = ''});

  /// A frame that IS a view destination (web `{kind: 'view', view: …}`).
  const DockNavFrame.ofView(this.view) : isView = true;

  /// Any non-view frame (detail page, player, modal, …).
  const DockNavFrame.other()
      : isView = false,
        view = '';

  final bool isView;
  final String view;
}

/// Web `activeTabId(stack)`: walk the navigation stack from the TOP down and
/// return the dock tab of the first view frame; falls back to Home when the
/// stack contains no view frame at all.
///
/// [stack] is ordered bottom → top (first element = deepest frame).
String dockActiveTabId(
  List<DockNavFrame> stack, {
  Map<String, String> extraViewIds = const {},
}) {
  for (final frame in stack.reversed) {
    if (frame.isView) {
      return dockTabIdForView(frame.view, extraViewIds: extraViewIds);
    }
  }
  return DockTab.fallbackId;
}
