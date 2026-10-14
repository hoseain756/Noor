import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../core/state/app_state.dart';
import '../core/theme/horse_theme.dart';
import '../features/shell/main_shell.dart';
import '../features/torrent/magnet_link_handler.dart';

class NoorApp extends StatelessWidget {
  const NoorApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: state,
      child: Consumer<AppState>(
        builder: (context, app, _) => MaterialApp(
          title: 'Noor',
          debugShowCheckedModeBanner: false,
          theme: HorseTheme.dark,
          locale: Locale(app.english ? 'en' : 'ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const MagnetLinkListener(child: _LaunchGate()),
        ),
      ),
    );
  }
}

class _LaunchGate extends StatefulWidget {
  const _LaunchGate();

  @override
  State<_LaunchGate> createState() => _LaunchGateState();
}

class _LaunchGateState extends State<_LaunchGate> {
  String? _startupError;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await context.read<AppState>().initialize();
    } catch (error) {
      if (mounted) setState(() => _startupError = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.initialized) {
      if (_startupError != null) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _NoorMark(size: 68),
                  const SizedBox(height: 20),
                  Text(
                    state.english ? 'Noor could not start' : 'تعذر بدء Noor',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _startupError!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      setState(() => _startupError = null);
                      _initialize();
                    },
                    child: Text(state.english ? 'Try again' : 'إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _NoorMark(size: 68),
              SizedBox(height: 18),
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: HorseTheme.gold,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return const MainShell();
  }
}

class _NoorMark extends StatelessWidget {
  const _NoorMark({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size * .28),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE2BF90), HorseTheme.gold, Color(0xFF8D6034)],
      ),
      boxShadow: [
        BoxShadow(
          color: HorseTheme.gold.withValues(alpha: .18),
          blurRadius: 24,
          spreadRadius: 1,
        ),
      ],
    ),
    child: Icon(
      Icons.brightness_7_rounded,
      color: const Color(0xFF1C140C),
      size: size * .5,
    ),
  );
}
