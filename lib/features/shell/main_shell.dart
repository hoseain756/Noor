import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';
import '../../shared/widgets/glass_navigation.dart';
import '../anime/anime_page.dart';
import '../calendar/calendar_page.dart';
import '../catalog/catalog_browser_page.dart';
import '../home/home_page.dart';
import '../kids/kids_page.dart';
import '../library/library_page.dart';
import '../live_tv/live_tv_page.dart';
import '../settings/addons_page.dart';
import '../settings/settings_page.dart';
import '../settings/stats_page.dart';
import 'dock_tab.dart';
import 'glass_dock.dart';
import 'noor_dock_tabs.dart';
import 'search_sheet.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selected = 0;
  bool _chromeVisible = true;
  double _scrollDelta = 0;
  bool _tabletNavVisible = false;

  void _selectTab(int index) {
    if (index == _selected) {
      if (!_chromeVisible) setState(() => _chromeVisible = true);
      return;
    }
    setState(() {
      _selected = index;
      _chromeVisible = true;
      _scrollDelta = 0;
    });
  }

  /// Scroll auto-hide for the shared chrome (search button + glass dock).
  ///
  /// This shell-level NotificationListener already observes every page's
  /// primary scrollable (the pages are the IndexedStack children), which is
  /// the per-page `GlassDockScrollHide` wiring done once; the resulting flag
  /// is fed to `GlassDock.hidden`, which owns its own hide animation. The
  /// `dockAutoHide` web setting is honored here, exactly as before.
  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification is! ScrollUpdateNotification) return false;
    if (context.read<AppState>().webSettings['dockAutoHide'] == false) {
      _scrollDelta = 0;
      if (!_chromeVisible) setState(() => _chromeVisible = true);
      return false;
    }

    if (notification.metrics.pixels <=
        notification.metrics.minScrollExtent + 1) {
      _scrollDelta = 0;
      if (!_chromeVisible) setState(() => _chromeVisible = true);
      return false;
    }

    final delta = notification.scrollDelta ?? 0;
    if (delta > 0) {
      _scrollDelta = _scrollDelta > 0 ? _scrollDelta + delta : delta;
      if (_scrollDelta >= 10 && _chromeVisible) {
        setState(() => _chromeVisible = false);
        _scrollDelta = 0;
      }
    } else if (delta < 0) {
      _scrollDelta = _scrollDelta < 0 ? _scrollDelta + delta : delta;
      if (_scrollDelta <= -8 && !_chromeVisible) {
        setState(() => _chromeVisible = true);
        _scrollDelta = 0;
      }
    }
    return false;
  }

  Future<void> _openSearch() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: HorseTheme.surface,
        builder: (_) => const SearchSheet(),
      );

  void _openSecondary(Widget page) {
    setState(() => _tabletNavVisible = false);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final size = MediaQuery.sizeOf(context);
    // RESPONSIVE DECISION (Task 107-d): Noor already ships a distinct tablet
    // layout at ≥840px (hamburger → slide-in side panel with every primary
    // tab + secondary page). That panel plays the role the web dock's
    // ≥1024px side rail plays, so the glass dock mounts on PHONE widths only
    // (<840) — Noor's own breakpoint convention — and the tablet navigation
    // is untouched.
    final tabletLayout = size.width >= 840;
    final dockTabs = noorDockTabsFor(
      // The Anime tab is PERMANENT (user mandate, Task 111): no filter drops
      // it. `hideContent.anime` only filters anime content rows on pages.
      // `kidsMode` is a dormant web-sync flag with no mobile behavior, so the
      // kids tab filter and kidsZoom are intentionally not wired.
      rtl: !app.english,
    );
    final dockActiveId = noorDockTabIdForIndex(_selected);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220);
    final pages = [
      HomePage(active: _selected == 0),
      const AnimePage(),
      const KidsPage(),
      const LibraryPage(),
      SettingsPage(onOpenLibrary: () => _selectTab(3)),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Re-assert the transparent system bars whenever the shell is visible
      // — the player's immersive mode rewrites the global overlay style, and
      // this restores the edge-to-edge glass look on return (main.dart only
      // runs once per launch).
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Positioned.fill(
                child: Center(
                  child: SizedBox(
                    width: math.min(size.width, 1600),
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _onScroll,
                      child: IndexedStack(
                        index: _selected,
                        children: pages,
                      ),
                    ),
                  ),
                ),
              ),
              if (_selected != 4)
                Positioned(
                  // User mandate (Task 115): the glass search button sits at
                  // the PHYSICAL top-right in both locales; on tablets it
                  // clears the hamburger button (right: 16, 48px wide).
                  right: tabletLayout ? 76 : 16,
                  top: 12,
                  child: IgnorePointer(
                    ignoring: !_chromeVisible,
                    child: AnimatedSlide(
                      offset:
                          _chromeVisible ? Offset.zero : const Offset(0, -1.25),
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      child: AnimatedOpacity(
                        opacity: _chromeVisible ? 1 : 0,
                        duration: duration,
                        child: GlassSearchButton(
                          tooltip: app.english ? 'Search' : 'بحث',
                          onPressed: _openSearch,
                        ),
                      ),
                    ),
                  ),
                ),
              if (tabletLayout)
                Positioned(
                  top: 12,
                  right: 16,
                  child: Material(
                    color: HorseTheme.surface.withValues(alpha: .94),
                    shape: const CircleBorder(
                        side: BorderSide(color: HorseTheme.line)),
                    child: IconButton(
                      tooltip: app.english ? 'Open navigation' : 'فتح التنقل',
                      onPressed: () => setState(
                          () => _tabletNavVisible = !_tabletNavVisible),
                      icon: Icon(_tabletNavVisible
                          ? Icons.close_rounded
                          : Icons.menu_rounded),
                    ),
                  ),
                ),
              if (!tabletLayout)
                // The glass dock (Harbor web port): one sliding pill, scrub
                // gesture, size ladder, safe area and its own hidden animation
                // — so it is NOT wrapped in another AnimatedSlide/Opacity pair.
                // Player/detail pages are pushed as full routes on top of the
                // shell, which unmounts the dock (the web `showChrome` rule).
                PositionedDirectional(
                  start: 0,
                  end: 0,
                  bottom: 0,
                  child: GlassDock(
                    tabs: dockTabs,
                    activeId: dockActiveId,
                    onTabSelected: (DockTab tab) =>
                        _selectTab(noorDockIndexForTabId(tab.view)),
                    languageCode: app.english ? 'en' : 'ar',
                    hidden: !_chromeVisible,
                  ),
                ),
              if (tabletLayout && _tabletNavVisible) ...[
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _tabletNavVisible = false),
                    child:
                        ColoredBox(color: Colors.black.withValues(alpha: .42)),
                  ),
                ),
                AnimatedPositionedDirectional(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  start: 12,
                  top: 68,
                  bottom: 12,
                  width: 286,
                  child: _TabletNavigation(
                    selected: _selected,
                    english: app.english,
                    onClose: () => setState(() => _tabletNavVisible = false),
                    onTabSelected: _selectTab,
                    onPageSelected: _openSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TabletNavigation extends StatelessWidget {
  const _TabletNavigation({
    required this.selected,
    required this.english,
    required this.onClose,
    required this.onTabSelected,
    required this.onPageSelected,
  });

  final int selected;
  final bool english;
  final VoidCallback onClose;
  final ValueChanged<int> onTabSelected;
  final ValueChanged<Widget> onPageSelected;

  @override
  Widget build(BuildContext context) {
    final primary = english
        ? const ['Home', 'Anime', 'Kids', 'My Library', 'Settings']
        : const ['الرئيسية', 'أنمي', 'الأطفال', 'مكتبتي', 'الإعدادات'];
    final secondary = <(IconData, String, Widget)>[
      (
        Icons.explore_outlined,
        english ? 'Discover' : 'اكتشف',
        const CatalogBrowserPage(mode: CatalogBrowseMode.discover)
      ),
      (
        Icons.movie_outlined,
        english ? 'Movies' : 'الأفلام',
        const CatalogBrowserPage(mode: CatalogBrowseMode.movies)
      ),
      (
        Icons.tv_outlined,
        english ? 'Series' : 'المسلسلات',
        const CatalogBrowserPage(mode: CatalogBrowseMode.shows)
      ),
      (
        Icons.grid_view_rounded,
        english ? 'Add-on catalogs' : 'كتالوجات الإضافات',
        const CatalogBrowserPage(mode: CatalogBrowseMode.catalogs)
      ),
      (
        Icons.live_tv_outlined,
        english ? 'Live TV' : 'البث المباشر',
        const LiveTvPage()
      ),
      (
        Icons.calendar_month_outlined,
        english ? 'Calendar' : 'التقويم',
        const CalendarPage()
      ),
      (
        Icons.query_stats_rounded,
        english ? 'Viewing statistics' : 'إحصائيات المشاهدة',
        const StatsPage()
      ),
      (
        Icons.extension_outlined,
        english ? 'Add-ons' : 'الإضافات',
        const AddonsPage()
      ),
    ];
    const icons = [
      Icons.home_rounded,
      Icons.auto_awesome_rounded,
      Icons.child_care_rounded,
      Icons.video_library_rounded,
      Icons.settings_rounded,
    ];
    return Material(
      elevation: 16,
      color: HorseTheme.surface,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(18, 12, 8, 12),
            child: Row(
              children: [
                const Icon(Icons.brightness_7_rounded, color: HorseTheme.gold),
                const SizedBox(width: 10),
                Expanded(
                    child: Text('Noor',
                        style: Theme.of(context).textTheme.titleLarge)),
                IconButton(
                    tooltip: english ? 'Close navigation' : 'إغلاق التنقل',
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(10),
              children: [
                for (var index = 0; index < primary.length; index++)
                  _NavigationItem(
                    icon: icons[index],
                    label: primary[index],
                    selected: selected == index,
                    onTap: () => onTabSelected(index),
                  ),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(14, 18, 14, 8),
                  child: Text(english ? 'MORE' : 'المزيد',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: HorseTheme.muted, letterSpacing: 1.1)),
                ),
                for (final item in secondary)
                  _NavigationItem(
                    icon: item.$1,
                    label: item.$2,
                    selected: false,
                    onTap: () => onPageSelected(item.$3),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem(
      {required this.icon,
      required this.label,
      required this.selected,
      required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: ListTile(
          minLeadingWidth: 28,
          minTileHeight: 48,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          selected: selected,
          selectedTileColor: HorseTheme.gold.withValues(alpha: .15),
          leading:
              Icon(icon, color: selected ? HorseTheme.gold : HorseTheme.muted),
          title: Text(label,
              style: TextStyle(
                  color: selected ? HorseTheme.gold : HorseTheme.ink,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
          onTap: onTap,
        ),
      );
}
