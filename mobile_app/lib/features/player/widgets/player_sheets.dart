import 'package:flutter/material.dart';

import '../../../core/theme/horse_theme.dart';
import '../engine/playback_engine.dart';

/// Dark-glass bottom sheets used by the player (settings, tracks, episodes,
/// streams). They belong to the app's design language; only the on-video
/// chrome follows the cinematic reference.

Future<T?> showPlayerSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: HorseTheme.raised,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: builder,
  );
}

class SheetScaffold extends StatelessWidget {
  const SheetScaffold({
    super.key,
    required this.title,
    required this.child,
    this.footer,
  });

  final String title;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .72,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.of(context).pop(),
                      child: const SizedBox(
                        width: 34,
                        height: 34,
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Flexible(child: child),
                if (footer != null) ...[
                  const SizedBox(height: 14),
                  footer!,
                ],
              ],
            ),
          ),
        ),
      );
}

// ── Settings ───────────────────────────────────────────────────────────────

class PlayerSettingsSheet extends StatelessWidget {
  const PlayerSettingsSheet({
    super.key,
    required this.english,
    required this.speed,
    required this.fit,
    required this.audioLabel,
    required this.subtitleLabel,
    required this.hasEpisodes,
    required this.onSpeed,
    required this.onFit,
    required this.onOpenAudio,
    required this.onOpenSubtitles,
    required this.onOpenEpisodes,
  });

  final bool english;
  final double speed;
  final BoxFit fit;
  final String audioLabel;
  final String subtitleLabel;
  final bool hasEpisodes;
  final ValueChanged<double> onSpeed;
  final ValueChanged<BoxFit> onFit;
  final VoidCallback onOpenAudio;
  final VoidCallback onOpenSubtitles;
  final VoidCallback onOpenEpisodes;

  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    final entries = [
      _SheetEntry(
        icon: Icons.graphic_eq_rounded,
        label: english ? 'Audio track' : 'المسار الصوتي',
        value: audioLabel,
        onTap: onOpenAudio,
      ),
      _SheetEntry(
        icon: Icons.subtitles_outlined,
        label: english ? 'Subtitles' : 'الترجمة',
        value: subtitleLabel,
        onTap: onOpenSubtitles,
      ),
      if (hasEpisodes)
        _SheetEntry(
          icon: Icons.format_list_bulleted_rounded,
          label: english ? 'Episodes' : 'الحلقات',
          value: '',
          onTap: onOpenEpisodes,
        ),
    ];

    return SheetScaffold(
      title: english ? 'Playback settings' : 'إعدادات التشغيل',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel(english ? 'Speed' : 'السرعة'),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 2.6,
              children: [
                for (final value in _speeds)
                  _SelectChip(
                    label: '${value == 1.0 ? '1' : value}×',
                    selected: (speed - value).abs() < .01,
                    onTap: () => onSpeed(value),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _SectionLabel(english ? 'Video fit' : 'ملاءمة الفيديو'),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 2.2,
              children: [
                _SelectChip(
                  label: english ? 'Fit' : 'احتواء',
                  selected: fit == BoxFit.contain,
                  onTap: () => onFit(BoxFit.contain),
                ),
                _SelectChip(
                  label: english ? 'Fill' : 'ملء',
                  selected: fit == BoxFit.cover,
                  onTap: () => onFit(BoxFit.cover),
                ),
                _SelectChip(
                  label: english ? 'Stretch' : 'تمديد',
                  selected: fit == BoxFit.fill,
                  onTap: () => onFit(BoxFit.fill),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final entry in entries)
              _EntryTile(
                icon: entry.icon,
                label: entry.label,
                value: entry.value,
                onTap: entry.onTap,
              ),
          ],
        ),
      ),
    );
  }
}

class _SheetEntry {
  const _SheetEntry({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: .8,
        ),
      );
}

class _SelectChip extends StatelessWidget {
  const _SelectChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected
            ? HorseTheme.gold.withValues(alpha: .18)
            : Colors.white.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? HorseTheme.gold : Colors.white70,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      );
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: Icon(icon, size: 20, color: Colors.white70),
        title: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        subtitle: value.isEmpty
            ? null
            : Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          size: 20,
          color: Colors.white24,
        ),
        onTap: onTap,
      );
}

// ── Track pickers ──────────────────────────────────────────────────────────

class AudioTracksSheet extends StatelessWidget {
  const AudioTracksSheet({
    super.key,
    required this.english,
    required this.tracks,
    required this.selected,
    required this.onPick,
  });

  final bool english;
  final List<AudioTrack> tracks;
  final AudioTrack selected;
  final ValueChanged<AudioTrack> onPick;

  String _label(AudioTrack track) {
    final parts = <String>[
      if (track.title?.isNotEmpty == true) track.title!,
      if (track.language?.isNotEmpty == true) track.language!,
      if (track.codec?.isNotEmpty == true) track.codec!,
      if (track.channelscount != null) '${track.channelscount}ch',
    ];
    if (parts.isEmpty) {
      return english ? 'Track ${track.id}' : 'مسار ${track.id}';
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: english ? 'Audio track' : 'المسار الصوتي',
      child: tracks.isEmpty
          ? _EmptyNote(
              english
                  ? 'No selectable audio tracks in this stream.'
                  : 'لا توجد مسارات صوتية قابلة للاختيار في هذا المصدر.',
            )
          : ListView.separated(
              shrinkWrap: true,
              itemCount: tracks.length,
              separatorBuilder: (_, __) =>
                  const Divider(color: HorseTheme.line, height: 1),
              itemBuilder: (context, index) {
                final track = tracks[index];
                final isSelected = track.id == selected.id;
                return ListTile(
                  dense: true,
                  selected: isSelected,
                  leading: Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 20,
                    color: isSelected ? HorseTheme.gold : Colors.white38,
                  ),
                  title: Text(
                    _label(track),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  onTap: () {
                    onPick(track);
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
    );
  }
}

class SubtitleTracksSheet extends StatelessWidget {
  const SubtitleTracksSheet({
    super.key,
    required this.english,
    required this.tracks,
    required this.selected,
    required this.onPick,
  });

  final bool english;
  final List<SubtitleTrack> tracks;
  final SubtitleTrack selected;
  final ValueChanged<SubtitleTrack> onPick;

  String _label(SubtitleTrack track) {
    final parts = <String>[
      if (track.title?.isNotEmpty == true) track.title!,
      if (track.language?.isNotEmpty == true) track.language!,
      if (track.codec?.isNotEmpty == true) track.codec!.toUpperCase(),
    ];
    if (parts.isEmpty) {
      return english ? 'Track ${track.id}' : 'مسار ${track.id}';
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final off = SubtitleTrack.no();
    final offSelected = selected.id == off.id;
    return SheetScaffold(
      title: english ? 'Subtitles' : 'الترجمة',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            dense: true,
            selected: offSelected,
            leading: Icon(
              offSelected
                  ? Icons.radio_button_checked
                  : Icons.subtitles_off_outlined,
              size: 20,
              color: offSelected ? HorseTheme.gold : Colors.white38,
            ),
            title: Text(
              english ? 'Off' : 'إيقاف',
              style: const TextStyle(fontSize: 14),
            ),
            onTap: () {
              onPick(off);
              Navigator.of(context).pop();
            },
          ),
          const Divider(color: HorseTheme.line, height: 1),
          Flexible(
            child: tracks.isEmpty
                ? _EmptyNote(
                    english
                        ? 'No embedded subtitle tracks in this stream.'
                        : 'لا توجد ترجمات مدمجة في هذا المصدر.',
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: tracks.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: HorseTheme.line, height: 1),
                    itemBuilder: (context, index) {
                      final track = tracks[index];
                      if (track.id == 'no' || track.id == 'auto') {
                        return const SizedBox.shrink();
                      }
                      final isSelected = track.id == selected.id;
                      return ListTile(
                        dense: true,
                        selected: isSelected,
                        leading: Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 20,
                          color: isSelected ? HorseTheme.gold : Colors.white38,
                        ),
                        title: Text(
                          _label(track),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                        onTap: () {
                          onPick(track);
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 26),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white38, fontSize: 13),
        ),
      );
}

// ── Episodes ───────────────────────────────────────────────────────────────

class EpisodesSheet extends StatelessWidget {
  const EpisodesSheet({
    super.key,
    required this.english,
    required this.episodes,
    required this.currentVideoId,
    required this.onPick,
  });

  final bool english;
  final List<Map<String, dynamic>> episodes;
  final String currentVideoId;
  final ValueChanged<Map<String, dynamic>> onPick;

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: english ? 'Episodes' : 'الحلقات',
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: episodes.length,
        separatorBuilder: (_, __) =>
            const Divider(color: HorseTheme.line, height: 1),
        itemBuilder: (context, index) {
          final episode = episodes[index];
          final season = (episode['season'] as num?)?.toInt() ?? 0;
          final number = (episode['episode'] as num?)?.toInt() ?? 0;
          final name =
              (episode['name'] ?? episode['title'] ?? '').toString().trim();
          final id = (episode['id'] ?? '').toString();
          final isCurrent = id == currentVideoId;
          return ListTile(
            dense: true,
            selected: isCurrent,
            leading: Container(
              width: 44,
              alignment: Alignment.center,
              child: Text(
                number == 0 ? '$index' : '$number',
                style: TextStyle(
                  color: isCurrent ? HorseTheme.gold : Colors.white54,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            title: Text(
              name.isEmpty
                  ? (english ? 'Episode $number' : 'الحلقة $number')
                  : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: season > 0
                ? Text(
                    english ? 'S$season' : 'الموسم $season',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 12),
                  )
                : null,
            trailing: isCurrent
                ? const Icon(Icons.play_arrow_rounded,
                    size: 20, color: HorseTheme.gold)
                : null,
            onTap: isCurrent ? null : () {
              Navigator.of(context).pop();
              onPick(episode);
            },
          );
        },
      ),
    );
  }
}

// ── Streams ────────────────────────────────────────────────────────────────

class StreamsSheet extends StatelessWidget {
  const StreamsSheet({
    super.key,
    required this.english,
    required this.streams,
    required this.selectedIndex,
    required this.onPick,
  });

  final bool english;
  final List<Map<String, dynamic>> streams;
  final int selectedIndex;
  final ValueChanged<Map<String, dynamic>> onPick;

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: english ? 'Choose a stream' : 'اختر مصدر التشغيل',
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: streams.length,
        separatorBuilder: (_, __) =>
            const Divider(color: HorseTheme.line, height: 1),
        itemBuilder: (context, index) {
          final stream = streams[index];
          final title = (stream['title'] ??
                  stream['name'] ??
                  stream['description'] ??
                  'Stream')
              .toString()
              .split('\n')
              .first;
          final isSelected = index == selectedIndex;
          return ListTile(
            dense: true,
            selected: isSelected,
            leading: Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.play_circle_outline_rounded,
              color: isSelected ? HorseTheme.gold : HorseTheme.muted,
              size: 22,
            ),
            title: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: Text(
              stream['addonName']?.toString() ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            onTap: isSelected ? null : () {
              Navigator.of(context).pop();
              onPick(stream);
            },
          );
        },
      ),
    );
  }
}
