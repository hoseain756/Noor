import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/app_state.dart';
import '../torrent/torrent_service.dart';

/// Periodically resets the app's TRANSIENT storage on a user-configured
/// interval (Settings → Data & privacy → cache reset, default 12 h):
///
///  - downloaded torrent temp files (`<documents>/torrents/<hash>` — the
///    multi-GB payload users actually feel),
///  - the in-memory Flutter image cache (posters reload fresh).
///
/// Never touches user data (library, history, settings, tokens) and never
/// deletes the ACTIVE torrent's files while a stream is running. The reset
/// timestamp lives OUTSIDE the synced settings blob (plain SharedPreferences
/// key) because it is runtime bookkeeping, not a user preference.
class CacheResetService {
  CacheResetService._();

  static final CacheResetService instance = CacheResetService._();

  /// SharedPreferences key of the last reset timestamp (epoch ms).
  static const String _lastResetKey = 'noor.cacheResetAtMs';

  /// Default interval when the user never chose one (12 h — user spec).
  static const int defaultHours = 12;

  Timer? _timer;
  bool _busy = false;
  AppState? _app;

  /// Reads the configured interval from the live settings map (0 = off).
  /// Tolerates stored doubles/strings defensively; unknown shapes fall
  /// back to [defaultHours].
  static int hoursFromSettings(Map<String, dynamic> settings) {
    final raw = settings['cacheResetHours'];
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? defaultHours;
    return defaultHours;
  }

  /// Pure scheduling decision (unit-tested): a reset is due when the
  /// feature is enabled (hours > 0) and the interval has elapsed since the
  /// last reset. A missing/invalid timestamp (first run) counts as due.
  static bool isDue({
    required int? lastResetMs,
    required int hours,
    DateTime? now,
  }) {
    if (hours <= 0) return false;
    if (lastResetMs == null || lastResetMs <= 0) return true;
    final reference = now ?? DateTime.now();
    final last = DateTime.fromMillisecondsSinceEpoch(lastResetMs);
    return reference.difference(last) >= Duration(hours: hours);
  }

  /// Starts the periodic check: one check right away (this also covers
  /// intervals that elapsed while the app was closed) plus a 30-minute
  /// tick. Called once from the app root; repeat calls are no-ops that
  /// only refresh the settings source.
  void start(AppState app) {
    _app = app;
    if (_timer != null) return;
    unawaited(_check());
    _timer = Timer.periodic(const Duration(minutes: 30), (_) => _check());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _app = null;
  }

  Future<void> _check() async {
    if (_busy) return;
    _busy = true;
    try {
      final app = _app;
      if (app == null) return;
      final prefs = await SharedPreferences.getInstance();
      final due = isDue(
        lastResetMs: prefs.getInt(_lastResetKey),
        hours: hoursFromSettings(app.webSettings),
      );
      if (due) await performReset(prefs: prefs);
    } catch (_) {
      // A failed reset must never crash the app — the next tick retries.
    } finally {
      _busy = false;
    }
  }

  /// Runs one reset pass and returns the number of bytes freed from disk.
  /// The image cache clears instantly; torrent temp dirs are deleted one by
  /// one (each hash first removed from the native engine when registered),
  /// skipping the ACTIVE hash so a running stream is never pulled out from
  /// under the player. Always stamps the reset time on success or failure —
  /// a failed pass should not loop every tick.
  Future<int> performReset({SharedPreferences? prefs}) async {
    final preferences = prefs ?? await SharedPreferences.getInstance();
    var freed = 0;
    try {
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
    } catch (_) {
      // Image cache is best-effort.
    }
    try {
      final docs = await getApplicationDocumentsDirectory();
      final root = Directory('${docs.path}/torrents');
      final activeHash = TorrentService.instance.activeInfoHash;
      if (await root.exists()) {
        await for (final entity in root.list()) {
          if (entity is! Directory) continue;
          final hash = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
          if (hash == activeHash) continue;
          try {
            await TorrentService.instance.remove(hash, deleteFiles: true);
          } catch (_) {
            // Not registered in the engine — the disk cleanup below suffices.
          }
          try {
            freed += await _dirSize(entity);
            await entity.delete(recursive: true);
          } catch (_) {
            // Vanished mid-pass or locked — skip this one.
          }
        }
      }
    } catch (_) {
      // Storage unavailable — keep the timestamp anyway so we do not spin.
    }
    await preferences.setInt(
      _lastResetKey,
      DateTime.now().millisecondsSinceEpoch,
    );
    return freed;
  }

  static Future<int> _dirSize(Directory dir) async {
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {
          // File vanished mid-scan — ignore.
        }
      }
    }
    return total;
  }
}
