import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/media_item.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';
import '../../core/track/track_link.dart';
import '../../shared/widgets/image_decode.dart';
import '../../shared/widgets/noor_toast.dart';

/// Anime tracking sheet: pick a watch status, nudge the episodes-watched
/// counter and set a 0–10 score — saved to EVERY linked tracker the item can
/// reach (AniList by its media id, MyAnimeList by idMal), each independent.
///
/// Preloads the current remote entries so the controls open on the real
/// provider state; supports "remove from list" (deletes pure planning rows,
/// never entries carrying progress or scores).
Future<void> showAnimeTrackerSheet(BuildContext context, MediaItem item) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TrackerSheet(item: item),
  );
}

class _TrackerSheet extends StatefulWidget {
  const _TrackerSheet({required this.item});

  final MediaItem item;

  @override
  State<_TrackerSheet> createState() => _TrackerSheetState();
}

class _TrackerSheetState extends State<_TrackerSheet> {
  static const _statusLabels = <AnimeTrackStatus, (String, String)>{
    AnimeTrackStatus.watching: ('Watching', 'أشاهده'),
    AnimeTrackStatus.completed: ('Completed', 'أكملته'),
    AnimeTrackStatus.planning: ('Plan to watch', 'أنوي مشاهدته'),
    AnimeTrackStatus.paused: ('Paused', 'متوقف مؤقتًا'),
    AnimeTrackStatus.dropped: ('Dropped', 'ألقيتُه'),
    AnimeTrackStatus.rewatching: ('Rewatching', 'أعيد مشاهدته'),
  };

  AnimeTrackStatus? _status;
  int _progress = 0;
  double _score = 0;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _preload();
  }

  Future<void> _preload() async {
    final app = context.read<AppState>();
    try {
      final preview = await app.api.animeTrackerPreview(
        anilistId: widget.item.anilistId,
        malId: widget.item.idMal,
      );
      // Prefer AniList's state, fall back to MAL's.
      final entry = (preview['anilist'] ?? preview['mal']) as Map?;
      if (!mounted) return;
      setState(() {
        if (entry != null) {
          final statusName = entry['status']?.toString();
          _status = AnimeTrackStatus.values
              .where((s) => s.name == statusName)
              .firstOrNull;
          _progress = (entry['progress'] as num?)?.toInt() ?? 0;
          _score = (entry['score10'] as num?)?.toDouble() ?? 0;
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final app = context.read<AppState>();
    setState(() => _saving = true);
    final outcomes = await app.saveAnimeEntry(
      item: widget.item,
      status: _status,
      progress: _status == null ? null : _progress,
      score10: _score > 0 ? _score : null,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    final english = app.english;
    final anyOk = outcomes.values.contains(true);
    final allFail = outcomes.isNotEmpty && !anyOk;
    if (outcomes.isEmpty) {
      NoorToast.show(
        context,
        english
            ? 'Link AniList or MyAnimeList in Integrations first.'
            : 'اربط AniList أو MyAnimeList من صفحة التكاملات أولًا.',
        error: true,
      );
      return;
    }
    NoorToast.show(
      context,
      allFail
          ? (english
              ? 'Could not reach the tracker — try again.'
              : 'تعذر الوصول للموقع — أعد المحاولة.')
          : (english ? 'Anime list updated.' : 'تم تحديث قائمة الأنمي.'),
      error: allFail,
    );
    if (anyOk) Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    if (_saving) return;
    final app = context.read<AppState>();
    setState(() {
      _saving = true;
      _status = null;
      _progress = 0;
      _score = 0;
    });
    final outcomes = await app.saveAnimeEntry(item: widget.item);
    if (!mounted) return;
    setState(() => _saving = false);
    final english = app.english;
    final anyOk = outcomes.values.contains(true);
    NoorToast.show(
      context,
      anyOk
          ? (english ? 'Removed from your lists.' : 'تمت الإزالة من قوائمك.')
          : (english
              ? 'Could not reach the tracker — try again.'
              : 'تعذر الوصول للموقع — أعد المحاولة.'),
      error: !anyOk,
    );
    if (anyOk) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final english = app.english;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: HorseTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: HorseTheme.line),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (widget.item.poster != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        widget.item.poster!,
                        width: 46,
                        height: 64,
                        fit: BoxFit.cover,
                        // Task 136: decode at the 46px thumbnail size.
                        cacheWidth: imageCacheWidth(context, 46),
                        errorBuilder: (_, __, ___) => const SizedBox(width: 46),
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              if (app.api.isLinked('anilist') || app.api.isLinked('mal')) ...[
                const SizedBox(height: 4),
                Text(
                  english
                      ? 'Saved to every connected tracker.'
                      : 'يُحفظ في كل المواقع المرتبطة.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: HorseTheme.muted,
                      ),
                ),
              ],
              const SizedBox(height: 14),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else ...[
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final entry in _statusLabels.entries)
                      ChoiceChip(
                        label: Text(
                          english ? entry.value.$1 : entry.value.$2,
                        ),
                        selected: _status == entry.key,
                        onSelected: (_) => setState(() => _status = entry.key),
                      ),
                  ],
                ),
                if (_status != null &&
                    _status != AnimeTrackStatus.completed) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          english ? 'Episodes watched' : 'الحلقات المُشاهدة',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      IconButton.outlined(
                        onPressed: _progress > 0
                            ? () => setState(() => _progress--)
                            : null,
                        icon: const Icon(Icons.remove_rounded, size: 19),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        child: Text(
                          '$_progress',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton.outlined(
                        onPressed: () => setState(() => _progress++),
                        icon: const Icon(Icons.add_rounded, size: 19),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        english ? 'Score (0–10)' : 'التقييم (من 0 إلى 10)',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      _score > 0 ? _score.toStringAsFixed(0) : '—',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: HorseTheme.gold,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
                Slider(
                  value: _score,
                  min: 0,
                  max: 10,
                  divisions: 10,
                  onChanged: (value) => setState(() => _score = value),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox.square(
                                dimension: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_rounded),
                        label: Text(
                          english ? 'Save to lists' : 'حفظ في القوائم',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    TextButton.icon(
                      onPressed: _saving ? null : _remove,
                      icon: const Icon(Icons.playlist_remove_rounded),
                      label: Text(english ? 'Remove' : 'إزالة'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
