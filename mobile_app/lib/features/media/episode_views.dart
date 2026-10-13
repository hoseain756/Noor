import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/theme/horse_theme.dart';

typedef EpisodeSelected = void Function(Map<String, dynamic> episode);

String episodeNumberLabel(Map<String, dynamic> episode,
    {required bool english}) {
  final season = (episode['season'] as num?)?.toInt();
  final number = (episode['episode'] as num?)?.toInt();
  if (season != null && number != null) return 'S$season E$number';
  if (number != null) return english ? 'Episode $number' : 'الحلقة $number';
  return english ? 'Episode' : 'حلقة';
}

class EpisodeList extends StatelessWidget {
  const EpisodeList({
    super.key,
    required this.episodes,
    required this.selectedId,
    required this.english,
    required this.onSelected,
    this.watchedEpisodeIds = const {},
    this.blurUnwatched = false,
  });

  final List<Map<String, dynamic>> episodes;
  final String? selectedId;
  final bool english;
  final EpisodeSelected onSelected;
  final Set<String> watchedEpisodeIds;
  final bool blurUnwatched;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final episode in episodes)
            _EpisodeListTile(
              episode: episode,
              selected: episode['id'] == selectedId,
              english: english,
              blurred:
                  _blurThisEpisode(episode, watchedEpisodeIds, blurUnwatched),
              onTap: () => onSelected(episode),
            ),
        ],
      );
}

class EpisodeGrid extends StatelessWidget {
  const EpisodeGrid({
    super.key,
    required this.episodes,
    required this.selectedId,
    required this.english,
    required this.onSelected,
    this.watchedEpisodeIds = const {},
    this.blurUnwatched = false,
  });

  final List<Map<String, dynamic>> episodes;
  final String? selectedId;
  final bool english;
  final EpisodeSelected onSelected;
  final Set<String> watchedEpisodeIds;
  final bool blurUnwatched;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final count = constraints.maxWidth < 440
              ? 2
              : constraints.maxWidth < 900
                  ? 3
                  : 4;
          const gap = 10.0;
          final tileWidth = math.max(
            1.0,
            (constraints.maxWidth - gap * (count - 1)) / count,
          );
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final episode in episodes)
                SizedBox(
                  width: tileWidth,
                  child: _EpisodeCard(
                    episode: episode,
                    selected: episode['id'] == selectedId,
                    english: english,
                    blurred: _blurThisEpisode(
                        episode, watchedEpisodeIds, blurUnwatched),
                    onTap: () => onSelected(episode),
                  ),
                ),
            ],
          );
        },
      );
}

class _EpisodeListTile extends StatelessWidget {
  const _EpisodeListTile({
    required this.episode,
    required this.selected,
    required this.english,
    required this.blurred,
    required this.onTap,
  });

  final Map<String, dynamic> episode;
  final bool selected;
  final bool english;
  final bool blurred;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 9),
        decoration: BoxDecoration(
          color: HorseTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? HorseTheme.gold : HorseTheme.line,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final imageWidth = math.min(180.0, constraints.maxWidth * .36);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _EpisodeStill(
                        episode: episode, width: imageWidth, blurred: blurred),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _EpisodeMetadata(episode: episode, english: english),
                          const SizedBox(height: 5),
                          Text(
                            _episodeTitle(episode, english),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: selected ? HorseTheme.gold : null,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          if ((episode['released'] ?? episode['releaseInfo'])
                              is String)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                (episode['released'] ?? episode['releaseInfo'])
                                    .toString(),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: HorseTheme.muted),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    required this.episode,
    required this.selected,
    required this.english,
    required this.blurred,
    required this.onTap,
  });

  final Map<String, dynamic> episode;
  final bool selected;
  final bool english;
  final bool blurred;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: HorseTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? HorseTheme.gold : HorseTheme.line,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _EpisodeStill(episode: episode, blurred: blurred),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(10, 9, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _EpisodeMetadata(episode: episode, english: english),
                      const SizedBox(height: 5),
                      Text(
                        _episodeTitle(episode, english),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: selected ? HorseTheme.gold : null,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _episodeDescription(episode, english),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: HorseTheme.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _EpisodeMetadata extends StatelessWidget {
  const _EpisodeMetadata({required this.episode, required this.english});

  final Map<String, dynamic> episode;
  final bool english;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 9,
        runSpacing: 3,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              episodeNumberLabel(episode, english: english),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: HorseTheme.gold,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star_rounded, size: 15, color: HorseTheme.gold),
              const SizedBox(width: 2),
              Text(
                _episodeRating(episode),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ],
      );
}

class _EpisodeStill extends StatelessWidget {
  const _EpisodeStill(
      {required this.episode, this.width, this.blurred = false});

  final Map<String, dynamic> episode;
  final double? width;
  final bool blurred;

  @override
  Widget build(BuildContext context) {
    final image =
        (episode['thumbnail'] ?? episode['poster'] ?? episode['image'])
            ?.toString();
    final content = image == null || image.isEmpty
        ? _fallback()
        : Image.network(
            image,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _fallback(),
          );
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: HorseTheme.canvas,
        borderRadius: BorderRadius.circular(9),
      ),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: blurred
            ? ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
                child: content,
              )
            : content,
      ),
    );
  }

  Widget _fallback() => const ColoredBox(
        color: HorseTheme.canvas,
        child: Center(
          child: Icon(Icons.movie_outlined, color: HorseTheme.muted, size: 24),
        ),
      );
}

String _episodeTitle(Map<String, dynamic> episode, bool english) =>
    (episode['name'] ?? episode['title'] ?? '').toString().trim().isNotEmpty
        ? (episode['name'] ?? episode['title']).toString().trim()
        : (english ? 'Episode' : 'حلقة');

String _episodeDescription(Map<String, dynamic> episode, bool english) =>
    (episode['overview'] ?? episode['description'] ?? episode['summary'] ?? '')
            .toString()
            .trim()
            .isNotEmpty
        ? (episode['overview'] ?? episode['description'] ?? episode['summary'])
            .toString()
            .trim()
        : (english ? 'No description available' : 'لا يوجد وصف');

String _episodeRating(Map<String, dynamic> episode) {
  final value =
      episode['rating'] ?? episode['imdbRating'] ?? episode['vote_average'];
  if (value is num) return value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return '—';
}

bool _blurThisEpisode(
  Map<String, dynamic> episode,
  Set<String> watchedIds,
  bool blurUnwatched,
) {
  final id = episode['id']?.toString();
  return blurUnwatched && (id == null || !watchedIds.contains(id));
}
