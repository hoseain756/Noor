import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_theme.dart';
import '../../l10n/nova_strings.dart';
import '../../shared/widgets/nova_brand.dart';

class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key, required this.onComplete});
  final VoidCallback onComplete;
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = NovaStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
        body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 840;
      final intro =
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const NovaBrand(width: 160),
        const SizedBox(height: 48),
        Text(s.text('welcomeTitle'),
            style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 24),
        Text(s.text('welcomeBody'),
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 32),
        Wrap(spacing: 16, runSpacing: 16, children: [
          for (final icon in [
            LucideIcons.film,
            LucideIcons.tv,
            LucideIcons.sparkles
          ])
            DecoratedBox(
                decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20)),
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child:
                        Icon(icon, color: scheme.onPrimaryContainer, size: 32)))
        ]),
      ]);
      final choices =
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.text('language'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        SegmentedButton<bool>(segments: [
          ButtonSegment(value: false, label: Text(s.text('arabicLanguage'))),
          ButtonSegment(value: true, label: Text(s.text('englishLanguage')))
        ], selected: {
          app.english
        }, onSelectionChanged: (value) => app.setLanguage(value.first)),
        const SizedBox(height: 32),
        Text(s.text('appearance'),
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final mode in ['dark', 'light', 'system'])
            ChoiceChip(
                label: Text(s.text(mode)),
                selected: (app.webSettings['themeMode'] ?? 'dark') == mode,
                onSelected: (_) => app.setSetting('themeMode', mode))
        ]),
        const SizedBox(height: 32),
        FilledButton.icon(
            onPressed: onComplete,
            icon: const Icon(LucideIcons.play),
            label: Text(s.text('startExploring'))),
        const SizedBox(height: 16),
        Text(s.text('welcomePrivacy'),
            style: Theme.of(context).textTheme.bodySmall),
      ]);
      return Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: SingleChildScrollView(
                padding:
                    EdgeInsets.all(NovaSpace.gutter(constraints.maxWidth) + 8),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                            Expanded(child: intro),
                            const SizedBox(width: 64),
                            Expanded(child: choices)
                          ])
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [intro, const SizedBox(height: 48), choices]),
              )));
    })));
  }
}
