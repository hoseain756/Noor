# Repository Guidelines

## Project Structure

This repository is the NOVA Flutter app. App startup and composition live in `lib/app` and `lib/main.dart`; shared state, APIs, caches, themes, and playback services live in `lib/core`. Screen groups are organized by feature under `lib/features` (for example `home`, `media`, `player`, and `settings`), with reusable UI in `lib/shared`. Keep brand assets and fonts in `assets/`, English and Arabic ARB sources in `lib/l10n/`, tests in `test/`, and product, design, and migration notes in `docs/`. Platform-specific configuration belongs in `android/` and `ios/`; maintenance scripts belong in `tool/`.

## Build, Test, and Development

- `flutter pub get` resolves the pinned dependencies in `pubspec.lock`.
- `flutter analyze` runs the repository's `flutter_lints` rules.
- `flutter test` runs unit and widget tests; use `flutter test test/<name>_test.dart` for a focused file.
- `dart format lib test` formats Dart sources. Check without modifying files with `dart format --output=none --set-exit-if-changed lib test`.
- `python tool/generate_nova_l10n.py` regenerates `lib/l10n/nova_messages.g.dart` from the ARB files.
- `flutter build apk --release` builds Android; `flutter build ios --release` requires macOS and Xcode.

Never launch an emulator. For interactive device checks, use an already-connected physical device only when requested; otherwise rely on analysis and tests.

## Code Style and Localization

Use standard Dart formatting, two-space indentation, `UpperCamelCase` for types, `lowerCamelCase` for members, and `snake_case.dart` filenames. Follow nearby feature patterns, keep widgets and state narrowly scoped, and prefer shared components over duplicated UI. Add user-facing copy to both `lib/l10n/app_en.arb` and `lib/l10n/app_ar.arb`, then run the generator; do not edit generated `nova_messages.g.dart` directly. Preserve RTL-aware layout and direction-sensitive behavior.

## Testing

Tests use Flutter's `flutter_test` framework and are named `*_test.dart`. Add focused unit or widget coverage for behavior changed, including Arabic/English and light/dark variants for UI changes where applicable. No numeric coverage threshold is configured; run the relevant tests and `flutter analyze` before submitting.

## Commits and Pull Requests

History generally uses Conventional Commit subjects such as `feat(player): ...`, `fix(torrent): ...`, and `perf(app): ...`; keep subjects specific and concise. A pull request should explain user-visible behavior, list validation commands and results, link related issues when available, and include before/after screenshots for UI changes. Note any platform or device checks that could not be performed.

## Configuration and Sensitive Data

Do not commit private signing keys, tokens, or personal provider credentials. The README notes that the checked-in Android release build uses a debug signing key; it is not suitable for store distribution.
