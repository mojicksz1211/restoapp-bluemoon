import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local SQLite store backing [OfflineSyncService] — replaces the old
/// SharedPreferences JSON-blob cache so offline data (tables, menu,
/// categories, orders, the pending sync queue) is held in a real on-device
/// database rather than a single serialized string per cache.
///
/// Every generic table has the same shape — `(id INTEGER PRIMARY KEY
/// AUTOINCREMENT, raw_json TEXT NOT NULL)` — because each cache is still
/// conceptually "an ordered list of JSON objects", exactly like the
/// SharedPreferences arrays it replaces. [replaceList]/[readList] preserve
/// insertion order via the autoincrement id, so callers see the same
/// ordering contract as before. `sync_queue` rows carry their own
/// `retry_count`/`last_error` inside that JSON (see `OfflineAction`), so no
/// schema change was needed for that. [idMap] (schema v2) is the one
/// purpose-built table — a persisted temp->real order id mapping.
class OfflineDb {
  OfflineDb._();
  static final OfflineDb instance = OfflineDb._();

  static const String _dbFileName = 'offline_store.db';
  static const int _schemaVersion = 2;

  // Every cache OfflineSyncService manages, one generic table each.
  static const String cachedTables = 'cached_tables';
  static const String cachedMenuItems = 'cached_menu_items';
  static const String cachedCategories = 'cached_categories';
  static const String cachedOrders = 'orders';
  static const String syncQueue = 'sync_queue';

  static const List<String> _genericTables = [
    cachedTables,
    cachedMenuItems,
    cachedCategories,
    cachedOrders,
    syncQueue,
  ];

  // Persisted temp->real order id mapping (schema v2) — added since sync
  // engines need to survive the app being killed mid-sync, so a device
  // resuming after a crash can still resolve a queued action's temp order
  // id to the real one a prior, now-vanished in-memory pass already learned.
  static const String idMap = 'id_map';

  Database? _db;

  /// Test-only hook: when set, the database opens at this path instead of
  /// the real on-device location — pass `inMemoryDatabasePath` in tests so
  /// each run starts from a clean slate rather than a file left on disk.
  @visibleForTesting
  static String? testOverridePath;

  /// Test-only: closes and drops the cached handle so the next access
  /// reopens (honoring a just-set [testOverridePath]).
  @visibleForTesting
  Future<void> resetForTest() async {
    await _db?.close();
    _db = null;
  }

  Future<Database> get _database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path = testOverridePath ?? p.join(await getDatabasesPath(), _dbFileName);
    return openDatabase(
      path,
      version: _schemaVersion,
      onCreate: (db, version) async {
        for (final table in _genericTables) {
          await db.execute(
            'CREATE TABLE $table (id INTEGER PRIMARY KEY AUTOINCREMENT, raw_json TEXT NOT NULL)',
          );
        }
        await _createIdMapTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createIdMapTable(db);
        }
      },
    );
  }

  Future<void> _createIdMapTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $idMap (
        temp_id INTEGER PRIMARY KEY,
        real_id INTEGER NOT NULL,
        synced_at TEXT NOT NULL
      )
    ''');
  }

  /// Replaces the entire contents of [table] with [items], in order.
  Future<void> replaceList(String table, List<Map<String, dynamic>> items) async {
    if (kIsWeb) return;
    final db = await _database;
    await db.transaction((txn) async {
      await txn.delete(table);
      final batch = txn.batch();
      for (final item in items) {
        batch.insert(table, {'raw_json': jsonEncode(item)});
      }
      await batch.commit(noResult: true);
    });
  }

  /// Reads every row of [table] back, in the order it was inserted.
  Future<List<Map<String, dynamic>>> readList(String table) async {
    if (kIsWeb) return [];
    final db = await _database;
    final rows = await db.query(table, orderBy: 'id ASC');
    return rows
        .map((row) => Map<String, dynamic>.from(jsonDecode(row['raw_json'] as String) as Map))
        .toList();
  }

  /// Records that offline temp order id [tempId] became real server id
  /// [realId] once its `create_order` action synced. Persisted (unlike an
  /// in-memory map) so a queued action still referencing [tempId] resolves
  /// correctly even if the app was killed before that action itself synced.
  Future<void> setIdMapping(int tempId, int realId) async {
    if (kIsWeb) return;
    final db = await _database;
    await db.insert(
      idMap,
      {
        'temp_id': tempId,
        'real_id': realId,
        'synced_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// All known temp->real order id mappings, keyed by temp id.
  Future<Map<int, int>> readAllIdMappings() async {
    if (kIsWeb) return {};
    final db = await _database;
    final rows = await db.query(idMap);
    return {
      for (final row in rows) (row['temp_id'] as int): (row['real_id'] as int),
    };
  }
}
