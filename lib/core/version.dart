/// Single source of truth for the user-visible version string.
///
/// Hand-maintained on purpose: rendering the version must not depend on a
/// plugin (package_info_plus) or an async FutureBuilder on every settings
/// screen. test/version_pin_test.dart pins these constants against
/// pubspec.yaml's `version:` line, so the two can never drift apart
/// silently — every bump edits BOTH in the same commit.
library;

const String noorVersion = '1.2.41';
const int noorBuild = 45;

/// Display form, e.g. `1.2.38+42`.
const String noorVersionLabel = '$noorVersion+$noorBuild';
