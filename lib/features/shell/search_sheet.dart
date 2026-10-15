import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/media_item.dart';
import '../../core/state/app_state.dart';
import '../../shared/widgets/poster_card.dart';
import '../calendar/calendar_page.dart';
import '../catalog/catalog_browser_page.dart';
import '../live_tv/live_tv_page.dart';
import '../media/media_detail_page.dart';
import '../settings/addons_page.dart';
import '../settings/stats_page.dart';

class SearchSheet extends StatefulWidget {
  const SearchSheet({super.key});

  @override
  State<SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<SearchSheet> {
  final _controller = TextEditingController();
  Timer? _timer;
  bool _loading = false;
  List<MediaItem> _results = [];
  String? _error;

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _timer?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _results = [];
        _error = null;
      });
      return;
    }
    _timer = Timer(
      const Duration(milliseconds: 350),
      () => _search(value.trim()),
    );
  }

  Future<void> _search(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final catalogs = context.read<AppState>().catalogs;
    final results = await Future.wait(
      [
        catalogs.catalog('movie', 'top', extras: {'search': query}),
        catalogs.catalog('series', 'top', extras: {'search': query}),
      ].map((job) async {
        try {
          return await job;
        } catch (_) {
          return <MediaItem>[];
        }
      }),
    );
    if (!mounted) return;
    final seen = <String>{};
    setState(() {
      _results = results
          .expand((e) => e)
          .where((e) => seen.add(e.id))
          .take(30)
          .toList();
      _loading = false;
      _error = _results.isEmpty
          ? (context.read<AppState>().english
              ? 'No titles found.'
              : 'لم يتم العثور على عناوين.')
          : null;
    });
  }

  void _openPage(Widget page) {
    final navigator = Navigator.of(context, rootNavigator: true);
    navigator.pop();
    navigator.push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    // Scoped select (122 follow-up): the sheet only needs the UI language,
    // so AppState notifications no longer rebuild this whole modal.
    final english = context.select<AppState, bool>((a) => a.english);
    final height = MediaQuery.sizeOf(context).height * .92;
    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: english
                    ? 'Search movies and series'
                    : 'ابحث عن فيلم أو مسلسل',
              ),
            ),
            if (_controller.text.trim().length < 2) ...[
              const SizedBox(height: 14),
              Text(
                english ? 'Browse Noor' : 'تصفّح Noor',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 2,
                children: [
                  _BrowseShortcut(
                    icon: Icons.explore_outlined,
                    label: english ? 'Discover' : 'اكتشف',
                    onTap: () => _openPage(const CatalogBrowserPage(
                        mode: CatalogBrowseMode.discover)),
                  ),
                  _BrowseShortcut(
                    icon: Icons.movie_outlined,
                    label: english ? 'Movies' : 'الأفلام',
                    onTap: () => _openPage(const CatalogBrowserPage(
                        mode: CatalogBrowseMode.movies)),
                  ),
                  _BrowseShortcut(
                    icon: Icons.tv_outlined,
                    label: english ? 'Series' : 'المسلسلات',
                    onTap: () => _openPage(const CatalogBrowserPage(
                        mode: CatalogBrowseMode.shows)),
                  ),
                  _BrowseShortcut(
                    icon: Icons.grid_view_rounded,
                    label: english ? 'Catalogs' : 'الكتالوجات',
                    onTap: () => _openPage(const CatalogBrowserPage(
                        mode: CatalogBrowseMode.catalogs)),
                  ),
                  _BrowseShortcut(
                    icon: Icons.live_tv_outlined,
                    label: english ? 'Live TV' : 'البث المباشر',
                    onTap: () => _openPage(const LiveTvPage()),
                  ),
                  _BrowseShortcut(
                    icon: Icons.calendar_month_outlined,
                    label: english ? 'Calendar' : 'التقويم',
                    onTap: () => _openPage(const CalendarPage()),
                  ),
                  _BrowseShortcut(
                    icon: Icons.query_stats_rounded,
                    label: english ? 'Your stats' : 'إحصائياتك',
                    onTap: () => _openPage(const StatsPage()),
                  ),
                  _BrowseShortcut(
                    icon: Icons.extension_outlined,
                    label: english ? 'Add-ons' : 'الإضافات',
                    onTap: () => _openPage(const AddonsPage()),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.only(top: 8, bottom: 20),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 150,
                  mainAxisExtent: 286,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 14,
                ),
                itemCount: _results.length,
                itemBuilder: (context, index) => PosterCard(
                  item: _results[index],
                  width: double.infinity,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => MediaDetailPage(item: _results[index]),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrowseShortcut extends StatelessWidget {
  const _BrowseShortcut(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ActionChip(
        avatar: Icon(icon, size: 17),
        label: Text(label),
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
      );
}
