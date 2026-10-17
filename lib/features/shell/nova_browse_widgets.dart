import 'package:nova_mobile/shared/widgets/nova_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/models/media_item.dart';
import '../../shared/widgets/image_decode.dart';

/// Shared editorial hierarchy for NOVA's browse destinations. The generous
/// title area wraps instead of assuming a fixed title/toolbar height.
class NovaBrowseHeader extends StatelessWidget {
  const NovaBrowseHeader(
      {super.key,
      required this.title,
      required this.subtitle,
      this.eyebrow,
      this.actions = const [],
      this.compact = false});
  final String title;
  final String subtitle;
  final String? eyebrow;
  final List<Widget> actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(24, compact ? 16 : 32, 24, 24),
      child: LayoutBuilder(builder: (context, constraints) {
        final copy =
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (eyebrow != null) ...[
            Text(eyebrow!,
                style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.secondary,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
          ],
          Text(title,
              style: theme.textTheme.headlineLarge
                  ?.copyWith(fontWeight: FontWeight.w800, height: 1.2)),
          const SizedBox(height: 8),
          ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Text(subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.65))),
        ]);
        if (constraints.maxWidth < 680 || actions.isEmpty) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                copy,
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: copy),
          const SizedBox(width: 24),
          Flexible(child: Wrap(spacing: 8, runSpacing: 8, children: actions)),
        ]);
      }),
    );
  }
}

/// Static skeletons intentionally avoid a page-wide perpetual shimmer.
class NovaBrowseSkeleton extends StatelessWidget {
  const NovaBrowseSkeleton({super.key, this.rows = false});
  final bool rows;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return ExcludeSemantics(
        child: rows
            ? ListView.separated(
                padding: const EdgeInsets.all(24),
                itemCount: 6,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (_, __) => Container(
                    height: 104,
                    decoration: BoxDecoration(
                        color: color, borderRadius: BorderRadius.circular(20))),
              )
            : GridView.builder(
                padding: const EdgeInsets.all(24),
                itemCount: 12,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    childAspectRatio: .61,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 24),
                itemBuilder: (_, __) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                          child: Container(
                              decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(16)))),
                      const SizedBox(height: 12),
                      Container(height: 12, width: 112, color: color),
                      const SizedBox(height: 8),
                      Container(height: 8, width: 64, color: color),
                    ]),
              ));
  }
}

/// An editorial lead title, sized by its content even with enlarged text.
class NovaBrowseFeature extends StatelessWidget {
  const NovaBrowseFeature(
      {super.key,
      required this.item,
      required this.label,
      required this.actionLabel,
      required this.onOpen});
  final MediaItem item;
  final String label;
  final String actionLabel;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 32),
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 640;
        final artwork = ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: AspectRatio(
                aspectRatio: wide ? 1.45 : 16 / 9,
                child: NovaNetworkImage(item.background ?? item.poster ?? '',
                    fit: BoxFit.cover,
                    cacheWidth: imageCacheWidth(
                        context,
                        wide
                            ? constraints.maxWidth * .5
                            : constraints.maxWidth),
                    errorBuilder: (_, __, ___) => ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Icon(LucideIcons.film,
                            size: 64, color: theme.colorScheme.secondary)))));
        final copy = Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
              wide ? 32 : 0, wide ? 8 : 20, 0, 8),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.secondary)),
            const SizedBox(height: 8),
            Text(item.name,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            if (item.description?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Text(item.description!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
                onPressed: onOpen,
                icon: const Icon(LucideIcons.play, size: 18),
                label: Text(actionLabel)),
          ]),
        );
        return wide
            ? Row(children: [Expanded(child: artwork), Expanded(child: copy)])
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [artwork, copy]);
      }),
    );
  }
}

/// Same logical spacing for both directions, with generous touch/focus bounds.
class NovaBrowseDestination extends StatelessWidget {
  const NovaBrowseDestination(
      {super.key,
      required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                Icon(icon,
                    color: Theme.of(context).colorScheme.secondary, size: 24),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(title,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(subtitle,
                          style: Theme.of(context).textTheme.bodySmall),
                    ])),
                const SizedBox(width: 8),
                Icon(
                    Directionality.of(context) == TextDirection.rtl
                        ? LucideIcons.chevronLeft
                        : LucideIcons.chevronRight,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ])),
        ),
      );
}
