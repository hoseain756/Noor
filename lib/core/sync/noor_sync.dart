/// Accountless device sync for Noor.
///
/// There is no account: a UUID v4 generated once per installation and kept in
/// secure storage (`noor.device.id`) *is* the identity. Bucket payloads live in
/// the `noor_sync` table (one row per device/bucket, revision-counter based)
/// and device presence in `noor_devices`. Rows are written directly to
/// Postgres through the Supabase session pooler with the least-privilege
/// `noor_app` role, which can only touch those two tables.
///
/// The session pooler on port 5432 supports prepared statements, so the
/// default (extended) query protocol is used — no simple query mode needed.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:postgres/postgres.dart';
import 'package:uuid/uuid.dart';

/// Device-scoped key/value sync over a direct Postgres connection.
///
/// Every method swallows errors (debugPrint + `false`/`null`) so callers never
/// have to guard against network failures; local data always stays usable.
class NoorSyncService {
  NoorSyncService._();

  static final NoorSyncService instance = NoorSyncService._();
  factory NoorSyncService() => instance;

  /// Sync bucket names shared by the app and the sync payload layout.
  static const String bucketSettings = 'settings';
  static const String bucketLibrary = 'library';
  static const String bucketLists = 'lists';
  static const String bucketWatchlist = 'watchlist';
  static const String bucketHistory = 'history';
  static const String bucketAddons = 'addons';

  static const List<String> buckets = <String>[
    bucketSettings,
    bucketLibrary,
    bucketLists,
    bucketWatchlist,
    bucketHistory,
    bucketAddons,
  ];

  static const String _deviceIdKey = 'noor.device.id';

  Endpoint _endpoint() => Endpoint(
        host: 'aws-1-eu-central-1.pooler.supabase.com',
        port: 5432,
        database: 'postgres',
        username: 'noor_app.hcyysnagdumpviromdzl',
        password: 'NoorSync_9f4k2m7xQz',
      );

  Connection? _connection;
  Future<Connection>? _connecting;
  String? _deviceId;
  final Map<String, int> _lastKnownRev = {};

  /// Human readable device label used for the `noor_devices` registry row.
  String get deviceName => 'Noor ${Platform.operatingSystem}';

  String get platform => Platform.operatingSystem;

  /// UUID v4 device identity, generated once and persisted in secure storage.
  Future<String?> deviceId() async {
    final cached = _deviceId;
    if (cached != null) return cached;
    try {
      const storage = FlutterSecureStorage();
      var id = await storage.read(key: _deviceIdKey);
      if (id == null || id.isEmpty) {
        id = const Uuid().v4();
        await storage.write(key: _deviceIdKey, value: id);
      }
      _deviceId = id;
      return id;
    } catch (error) {
      debugPrint('NoorSync: unable to load device id: $error');
      return null;
    }
  }

  /// Revision of the last successful [pushBucket] for [bucket], if known.
  int? lastKnownRev(String bucket) => _lastKnownRev[bucket];

  /// Upserts [data] into the device's [bucket] row, bumping `rev` server-side
  /// (`INSERT … ON CONFLICT (device_id, bucket) DO UPDATE`), and refreshes the
  /// device heartbeat row. Returns whether the write succeeded.
  Future<bool> pushBucket(String bucket, Map<String, dynamic> data) async {
    final device = await deviceId();
    if (device == null) return false;
    final rev = await _run<int?>((connection) async {
      final result = await connection.execute(
        Sql.named(
          'INSERT INTO noor_sync (device_id, bucket, data, rev, updated_at) '
          'VALUES (@device_id, @bucket, @data::jsonb, 1, now()) '
          'ON CONFLICT (device_id, bucket) DO UPDATE '
          'SET data = EXCLUDED.data, rev = noor_sync.rev + 1, '
          'updated_at = now() '
          'RETURNING rev',
        ),
        parameters: {
          'device_id': device,
          'bucket': bucket,
          'data': data,
        },
      );
      if (result.isEmpty) return null;
      return (result.first.toColumnMap()['rev'] as num?)?.toInt();
    }, 'pushBucket($bucket)');
    if (rev == null) return false;
    _lastKnownRev[bucket] = rev;
    await _heartbeatWith(device);
    return true;
  }

  /// Reads the device's [bucket] row as `{data, rev}` (plus `updated_at`),
  /// or `null` when the bucket does not exist / the query failed.
  Future<Map<String, dynamic>?> pullBucket(String bucket) async {
    final device = await deviceId();
    if (device == null) return null;
    return _run<Map<String, dynamic>?>((connection) async {
      final result = await connection.execute(
        Sql.named(
          'SELECT data, rev, updated_at FROM noor_sync '
          'WHERE device_id = @device_id AND bucket = @bucket '
          'LIMIT 1',
        ),
        parameters: {'device_id': device, 'bucket': bucket},
      );
      if (result.isEmpty) return null;
      final row = result.first.toColumnMap();
      final data = row['data'];
      return <String, dynamic>{
        'data': data is String ? jsonDecode(data) : data,
        'rev': (row['rev'] as num?)?.toInt() ?? 0,
        if (row['updated_at'] is DateTime) 'updated_at': row['updated_at'],
      };
    }, 'pullBucket($bucket)');
  }

  /// Current revision counter for the device's [bucket] row, or `null`.
  Future<int?> bucketRev(String bucket) async {
    final device = await deviceId();
    if (device == null) return null;
    return _run<int?>((connection) async {
      final result = await connection.execute(
        Sql.named(
          'SELECT rev FROM noor_sync '
          'WHERE device_id = @device_id AND bucket = @bucket LIMIT 1',
        ),
        parameters: {'device_id': device, 'bucket': bucket},
      );
      if (result.isEmpty) return null;
      return (result.first.toColumnMap()['rev'] as num?)?.toInt();
    }, 'bucketRev($bucket)');
  }

  /// `updated_at` of the device's [bucket] row (last cloud write), or `null`.
  Future<DateTime?> lastSyncAt(String bucket) async {
    final device = await deviceId();
    if (device == null) return null;
    return _run<DateTime?>((connection) async {
      final result = await connection.execute(
        Sql.named(
          'SELECT updated_at FROM noor_sync '
          'WHERE device_id = @device_id AND bucket = @bucket LIMIT 1',
        ),
        parameters: {'device_id': device, 'bucket': bucket},
      );
      if (result.isEmpty) return null;
      return result.first.toColumnMap()['updated_at'] as DateTime?;
    }, 'lastSyncAt($bucket)');
  }

  /// Refreshes the `noor_devices` heartbeat row (`last_seen_at = now()`).
  Future<void> heartbeat() async {
    final device = await deviceId();
    if (device == null) return;
    await _heartbeatWith(device);
  }

  /// Deletes the device's [bucket] row from the cloud. Local data is kept.
  Future<bool> deleteBucket(String bucket) async {
    final device = await deviceId();
    if (device == null) return false;
    return await _run<bool>((connection) async {
          await connection.execute(
            Sql.named(
              'DELETE FROM noor_sync '
              'WHERE device_id = @device_id AND bucket = @bucket',
            ),
            parameters: {'device_id': device, 'bucket': bucket},
          );
          _lastKnownRev.remove(bucket);
          return true;
        }, 'deleteBucket($bucket)') ??
        false;
  }

  /// Closes the shared connection (called when the owning scope is disposed).
  Future<void> close() async {
    final connection = _connection;
    _connection = null;
    _connecting = null;
    _lastKnownRev.clear();
    if (connection == null) return;
    try {
      await connection.close();
    } catch (_) {
      // Closing a dead connection must never surface to callers.
    }
  }

  Future<void> _heartbeatWith(String device) => _run<bool?>((connection) async {
        await _upsertDevice(connection, device);
        return true;
      }, 'heartbeat');

  Future<void> _upsertDevice(Connection connection, String device) async {
    await connection.execute(
      Sql.named(
        'INSERT INTO noor_devices (device_id, name, platform, created_at, '
        'last_seen_at) VALUES (@device_id, @name, @platform, now(), now()) '
        'ON CONFLICT (device_id) DO UPDATE '
        'SET last_seen_at = now(), name = EXCLUDED.name, '
        'platform = EXCLUDED.platform',
      ),
      parameters: {
        'device_id': device,
        'name': deviceName,
        'platform': platform,
      },
    );
  }

  Future<Connection> _connect() {
    final existing = _connection;
    if (existing != null) return Future.value(existing);
    return _connecting ??= _open();
  }

  Future<Connection> _open() async {
    try {
      final connection = await Connection.open(
        _endpoint(),
        settings: const ConnectionSettings(
          sslMode: SslMode.require,
          connectTimeout: Duration(seconds: 15),
          applicationName: 'noor-mobile',
        ),
      );
      _connection = connection;
      return connection;
    } catch (_) {
      _connecting = null;
      rethrow;
    }
  }

  Future<void> _discard(Connection connection) async {
    if (identical(_connection, connection)) {
      _connection = null;
      _connecting = null;
    }
    try {
      await connection.close();
    } catch (_) {
      // Ignore — the socket is already unusable.
    }
  }

  /// Runs [action] on the shared connection, retrying once on a fresh
  /// connection after a failure. Never throws; returns `null` on failure.
  Future<T?> _run<T>(
    Future<T?> Function(Connection connection) action,
    String label,
  ) async {
    for (var attempt = 1; attempt <= 2; attempt++) {
      Connection? connection;
      try {
        connection = await _connect();
        return await action(connection);
      } catch (error) {
        debugPrint('NoorSync: $label failed (attempt $attempt): $error');
        if (connection != null) await _discard(connection);
      }
    }
    return null;
  }
}
