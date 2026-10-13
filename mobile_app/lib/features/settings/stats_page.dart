import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/app_state.dart';
import '../../core/theme/horse_theme.dart';

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final english = app.english;
    return Scaffold(
      appBar: AppBar(
        title: Text(english ? 'Viewing statistics' : 'إحصائيات المشاهدة'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Text(
            english ? 'Your time with Horse' : 'رحلتك مع Horse',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            english
                ? 'Numbers from this device and your synced library.'
                : 'أرقام من هذا الجهاز ومكتبتك المتزامنة.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: HorseTheme.muted),
          ),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 620 ? 3 : 1;
              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisExtent: 132,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: [
                  _Metric(
                    icon: Icons.play_circle_outline_rounded,
                    value: '${app.watchedCount}',
                    label: english ? 'Recent titles' : 'عناوين شاهدتها',
                  ),
                  _Metric(
                    icon: Icons.schedule_rounded,
                    value: app.watchedHours.toStringAsFixed(1),
                    label: english ? 'Hours played' : 'ساعات المشاهدة',
                  ),
                  _Metric(
                    icon: Icons.extension_rounded,
                    value: '${app.addons.where((e) => e.enabled).length}',
                    label: english ? 'Active add-ons' : 'إضافات نشطة',
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          if (app.history.isNotEmpty) ...[
            Text(
              english ? 'Recent activity' : 'آخر المشاهدات',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            for (final item in app.history.take(12))
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                leading: const Icon(
                  Icons.movie_outlined,
                  color: HorseTheme.gold,
                ),
                title: Text(
                  item.item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  MaterialLocalizations.of(context).formatMediumDate(
                    DateTime.fromMillisecondsSinceEpoch(item.watchedAt),
                  ),
                ),
              ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: app.clearHistory,
                icon: const Icon(Icons.delete_outline_rounded),
                label: Text(english ? 'Clear history' : 'مسح السجل'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: HorseTheme.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: HorseTheme.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: HorseTheme.gold, size: 22),
        const Spacer(),
        Text(value, style: Theme.of(context).textTheme.headlineSmall),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}
