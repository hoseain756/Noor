import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:nova_mobile/core/version.dart';

/// Guards the user-visible version constants against drift from pubspec.yaml.
///
/// The settings screen renders [noorVersionLabel] WITHOUT package_info_plus,
/// so this test is the only thing keeping the two in sync: bumping
/// pubspec.yaml without lib/core/version.dart (or vice versa) fails here.
void main() {
  test('appVersion/appBuild stay pinned to pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull,
        reason: 'pubspec.yaml must carry version: x.y.z+build');
    expect(
        '${match!.group(1)}.${match.group(2)}.${match.group(3)}', noorVersion);
    expect(int.parse(match.group(4)!), noorBuild);
    expect(noorVersionLabel, '$noorVersion+$noorBuild');
  });
}
