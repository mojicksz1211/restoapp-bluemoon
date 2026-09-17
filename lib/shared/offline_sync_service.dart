import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'app_config.dart';
import 'lan_broadcast_service.dart';
import 'offline_db.dart';

enum SyncStatus {
  online,
  offline,
  syncing,
}

class OfflineAction {
  final String id;
  final String type; // 'create_order', 'update_status', 'add_items', 'transfer_table', 'extend_room_charge'
  final int orderId; // Temporary negative ID or real ID
  final int? tempId;
  final DateTime createdAt;
  final Map<String, dynamic> payload;
  // How many times this specific action has failed to sync, and why the
  // most recent attempt failed — lets the sync engine skip an action that's
  // permanently broken (e.g. references a deleted menu item) after enough
  // retries, instead of retrying it forever on every single pass.
  final int retryCount;
  final String? lastError;

  OfflineAction({
    required this.id,
    required this.type,
    required this.orderId,
    this.tempId,
    required this.createdAt,
    required this.payload,
    this.retryCount = 0,
    this.lastError,
  });

  OfflineAction copyWith({int? retryCount, String? lastError}) {
    return OfflineAction(
      id: id,
      type: type,
      orderId: orderId,
      tempId: tempId,
      createdAt: createdAt,
      payload: payload,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'order_id': orderId,
        if (tempId != null) 'temp_id': tempId,
        'created_at': createdAt.toIso8601String(),
        'payload': payload,
        'retry_count': retryCount,
        if (lastError != null) 'last_error': lastError,
      };

  factory OfflineAction.fromJson(Map<String, dynamic> json) {
    return OfflineAction(
      id: json['id']?.toString() ?? UniqueKey().toString(),
      type: json['type']?.toString() ?? '',
      orderId: (json['order_id'] as num?)?.toInt() ?? 0,
      tempId: (json['temp_id'] as num?)?.toInt(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      payload: json['payload'] is Map ? Map<String, dynamic>.from(json['payload']) : {},
      retryCount: (json['retry_count'] as num?)?.toInt() ?? 0,
      lastError: json['last_error']?.toString(),
    );
  }
}

/// OfflineSyncService manages:
/// 1. Connectivity / Internet reachability detection to moonctgroup.com
/// 2. Persistent caching of Tables, Menu, Categories, and Orders
/// 3. Offline Action Queue for orders created/updated without internet
/// 4. Auto-Sync engine that uploads pending actions once internet is back
class OfflineSyncService {
  OfflineSyncService._();
  static final OfflineSyncService instance = OfflineSyncService._();

  // Legacy SharedPreferences keys — no longer written to, kept only so
  // `_migrateFromSharedPreferencesIfNeeded()` can find and import any data
  // left over from before the move to a real local database (offline_db.dart).
  static const String _queueKey = 'offline_sync_queue_v1';
  static const String _tablesCacheKey = 'offline_cached_tables_v1';
  static const String _menuCacheKey = 'offline_cached_menu_v1';
  static const String _categoriesCacheKey = 'offline_cached_categories_v1';
  static const String _ordersCacheKey = 'offline_cached_orders_v1';
  static const String _migratedToSqliteFlagKey = 'offline_sqlite_migrated_v1';

  // State Notifiers
  final ValueNotifier<SyncStatus> statusNotifier = ValueNotifier<SyncStatus>(SyncStatus.online);
  final ValueNotifier<int> pendingCountNotifier = ValueNotifier<int>(0);
  final ValueNotifier<DateTime?> lastSyncTimeNotifier = ValueNotifier<DateTime?>(null);

  // In-memory action queue
  final List<OfflineAction> _queue = [];
  bool _initialized = false;
  bool _isSyncing = false;
  Timer? _healthProbeTimer;
  Timer? _lanRebroadcastTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // Listeners for when data has been successfully synced
  final List<VoidCallback> _dataSyncedCallbacks = [];

  void addDataSyncedListener(VoidCallback callback) {
    if (!_dataSyncedCallbacks.contains(callback)) {
      _dataSyncedCallbacks.add(callback);
    }
  }

  void removeDataSyncedListener(VoidCallback callback) {
    _dataSyncedCallbacks.remove(callback);
  }

  bool get isOnline => statusNotifier.value == SyncStatus.online;
  bool get isOffline => statusNotifier.value == SyncStatus.offline;
  bool get isSyncing => statusNotifier.value == SyncStatus.syncing;
  int get pendingCount => pendingCountNotifier.value;

  /// Generate a unique negative temporary order ID for offline-created orders
  int generateTempOrderId() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final randomSuffix = math.Random().nextInt(900) + 100;
    // Produces a unique negative integer like -172591234
    final val = -((nowMs % 100000000) * 10 + (randomSuffix % 10));
    return val;
  }

  /// Initialize the service, restore queue, and start reachability monitoring
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _migrateFromSharedPreferencesIfNeeded();
    await _restoreQueue();
    _startReachabilityProbe();
    _startConnectivityListener();

    // Trigger initial probe immediately
    unawaited(probeReachability());
  }

  /// One-time import of any data left in the old SharedPreferences JSON-blob
  /// cache into the new SQLite-backed store, so a tablet that was mid
  /// offline-session when this update installs doesn't lose pending orders.
  /// Runs at most once per device (guarded by [_migratedToSqliteFlagKey]).
  Future<void> _migrateFromSharedPreferencesIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_migratedToSqliteFlagKey) == true) return;

    try {
      await _migrateLegacyKey(prefs, _queueKey, OfflineDb.syncQueue);
      await _migrateLegacyKey(prefs, _tablesCacheKey, OfflineDb.cachedTables);
      await _migrateLegacyKey(prefs, _menuCacheKey, OfflineDb.cachedMenuItems);
      await _migrateLegacyKey(prefs, _categoriesCacheKey, OfflineDb.cachedCategories);
      await _migrateLegacyKey(prefs, _ordersCacheKey, OfflineDb.cachedOrders);
    } catch (e) {
      debugPrint('[OFFLINE SYNC] Migration to local database failed: $e');
    } finally {
      // Mark done even on partial failure — retrying forever risks
      // duplicating rows that already made it across on a prior attempt.
      await prefs.setBool(_migratedToSqliteFlagKey, true);
    }
  }

  Future<void> _migrateLegacyKey(SharedPreferences prefs, String legacyKey, String table) async {
    final raw = prefs.getString(legacyKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    final List decoded = jsonDecode(raw);
    final items = decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (items.isNotEmpty) {
      await OfflineDb.instance.replaceList(table, items);
      debugPrint('[OFFLINE SYNC] Migrated ${items.length} row(s) from $legacyKey to $table');
    }
    await prefs.remove(legacyKey);
  }

  /// Probe actual internet reachability to moonctgroup.com
  Future<bool> probeReachability() async {
    try {
      final baseUrl = await AppConfig.getBaseUrl();
      // Use the public /api/health endpoint — no auth required, minimal payload,
      // and no 401 noise in the browser console unlike protected endpoints.
      final uri = Uri.parse('$baseUrl/api/health');
      
      final response = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 4));

      // Any 2xx/3xx/4xx response means the server is reachable.
      // 5xx or timeout means server is down or no internet.
      if (response.statusCode >= 200 && response.statusCode < 500) {
        _setOnline();
        return true;
      } else {
        _setOffline();
        return false;
      }
    } catch (e) {
      _setOffline();
      return false;
    }
  }


  void _setOnline() {
    if (statusNotifier.value != SyncStatus.syncing) {
      if (statusNotifier.value != SyncStatus.online) {
        debugPrint('[OFFLINE SYNC] Reachability restored: ONLINE');
        statusNotifier.value = SyncStatus.online;
      }
    }
    // If there are pending actions, auto-sync immediately!
    if (_queue.isNotEmpty && !_isSyncing) {
      syncPendingActions();
    }
  }

  void _setOffline() {
    if (statusNotifier.value != SyncStatus.offline) {
      debugPrint('[OFFLINE SYNC] Reachability lost: OFFLINE');
      statusNotifier.value = SyncStatus.offline;
    }
  }

  void _startReachabilityProbe() {
    _healthProbeTimer?.cancel();
    // Probe every 10 seconds — stays as a backstop even with the
    // connectivity listener below, since a link-layer "connected" event
    // (WiFi associated) doesn't guarantee the backend is actually reachable.
    _healthProbeTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      await probeReachability();
    });

    // Re-announce pending orders over the LAN on its own, slower timer —
    // deliberately decoupled from the 10s reachability probe above. With
    // several orders queued at once (each broadcast = 4 attempts x 2
    // addresses = 8 packets), tying this to the same 10s cadence produced a
    // sustained burst of dozens of packets/minute from one device, which
    // real-world testing showed a WiFi AP can start silently dropping under
    // load (one test round went from a reliable stream to ~99% packet loss
    // with several orders queued vs. a single order in an earlier, clean
    // run). The original broadcast(s) may have gone out before a peer tablet
    // was even running, or been lost outright (UDP broadcast has no
    // delivery guarantee), so this still needs to repeat — just at a gentler
    // rate that's less likely to trip AP-side broadcast throttling.
    _lanRebroadcastTimer?.cancel();
    _lanRebroadcastTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (isOffline) {
        unawaited(_rebroadcastPendingOrdersOverLan());
      }
    });
  }

  /// Re-sends every currently-queued create_order/add_items action over the
  /// LAN, using the matching cached order as the payload.
  ///
  /// An order can have BOTH a still-unsynced create_order and a later
  /// add_items queued at once (create it offline, then add more items to it,
  /// still offline). This resends BOTH pending states every tick rather than
  /// picking just one per order — a prior version deduped to "first action
  /// type wins" per order, which meant create_order always won (it's always
  /// enqueued before that order's own add_items) and the add_items broadcast
  /// only ever went out once, at the moment it was enqueued. If that single
  /// attempt was lost — common on a weak link — the cashier's "items added"
  /// alert never got a periodic retry: the order's data still quietly
  /// updated (an order_created re-send for an already-known order still
  /// merges in the latest items), but the popup/sound never fired, since
  /// only an `order_items_added` event triggers that alert.
  Future<void> _rebroadcastPendingOrdersOverLan() async {
    if (_queue.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final branchIdRaw = prefs.getString('branch_id');
      final branchId = branchIdRaw == null ? null : int.tryParse(branchIdRaw);
      final userId = prefs.getString('user_id');
      final cachedOrders = await getCachedOrders();
      if (cachedOrders == null) return;

      final ordersNeedingCreate = <int>{};
      final ordersNeedingItemsAdded = <int>{};
      for (final action in _queue) {
        if (action.type == 'create_order') {
          ordersNeedingCreate.add(action.orderId);
        } else if (action.type == 'add_items') {
          ordersNeedingItemsAdded.add(action.orderId);
        }
      }

      Map<String, dynamic>? findOrder(int orderId) {
        for (final o in cachedOrders) {
          final id = (o['order_id'] ?? o['IDNo'] ?? o['id'] as num?)?.toInt();
          if (id == orderId) return o;
        }
        return null;
      }

      for (final orderId in ordersNeedingCreate) {
        final order = findOrder(orderId);
        if (order == null) continue;
        await LanBroadcastService.instance.broadcastOrderCreated({
          'branch_id': branchId,
          'order_id': orderId,
          'order_no': order['order_no'],
          'encoded_by': userId,
          'order': order,
        });
      }
      for (final orderId in ordersNeedingItemsAdded) {
        final order = findOrder(orderId);
        if (order == null) continue;
        await LanBroadcastService.instance.broadcastOrderItemsAdded({
          'branch_id': branchId,
          'order_id': orderId,
          'encoded_by': userId,
          'items_added': true,
          'order': order,
        });
      }
    } catch (e) {
      debugPrint('[OFFLINE SYNC] Error rebroadcasting over LAN: $e');
    }
  }

  /// Reprobes immediately on any OS-level connectivity change (WiFi/mobile
  /// data coming up) instead of waiting for the next 10s timer tick — this
  /// is what makes "back online" feel instant rather than laggy.
  void _startConnectivityListener() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      final hasLink = results.any((r) => r != ConnectivityResult.none);
      if (hasLink) {
        debugPrint('[OFFLINE SYNC] Connectivity link detected — probing reachability immediately');
        unawaited(probeReachability());
      }
    });
  }

  // ===========================================================================
  // QUEUE MANAGEMENT
  // ===========================================================================

  Future<void> _restoreQueue() async {
    try {
      final rows = await OfflineDb.instance.readList(OfflineDb.syncQueue);
      _queue.clear();
      for (final item in rows) {
        _queue.add(OfflineAction.fromJson(item));
      }
      pendingCountNotifier.value = _queue.length;
      debugPrint('[OFFLINE SYNC] Restored ${_queue.length} pending actions from local database');
    } catch (e) {
      debugPrint('[OFFLINE SYNC] Error restoring queue: $e');
    }
  }

  Future<void> _flushQueue() async {
    try {
      await OfflineDb.instance.replaceList(
        OfflineDb.syncQueue,
        _queue.map((a) => a.toJson()).toList(),
      );
      pendingCountNotifier.value = _queue.length;
    } catch (e) {
      debugPrint('[OFFLINE SYNC] Error flushing queue: $e');
    }
  }

  Future<void> enqueueAction({
    required String type,
    required int orderId,
    int? tempId,
    required Map<String, dynamic> payload,
  }) async {
    final action = OfflineAction(
      id: 'act_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(9999)}',
      type: type,
      orderId: orderId,
      tempId: tempId,
      createdAt: DateTime.now(),
      payload: payload,
    );

    _queue.add(action);
    await _flushQueue();
    debugPrint('[OFFLINE SYNC] Enqueued action: ${action.type} for order ${action.orderId}. Total in queue: ${_queue.length}');

    // If online, attempt to sync immediately
    if (isOnline && !_isSyncing) {
      unawaited(syncPendingActions());
    }
  }

  List<OfflineAction> getQueue() => List.unmodifiable(_queue);

  /// Whether [orderId] (a real positive server id or a still-unsynced
  /// negative temp id — either way, however the order is identified in the
  /// UI right now) has any action still waiting in the sync queue. Drives
  /// the "not synced yet" badge on order cards.
  bool hasPendingActionsForOrder(int orderId) {
    return _queue.any((a) => a.orderId == orderId);
  }

  // ===========================================================================
  // LOCAL CACHE ACCESS
  // ===========================================================================

  Future<void> saveCachedTables(List<Map<String, dynamic>> tables) async {
    try {
      await OfflineDb.instance.replaceList(OfflineDb.cachedTables, tables);
    } catch (e) {
      debugPrint('[OFFLINE CACHE] Error saving tables: $e');
    }
  }

  Future<List<Map<String, dynamic>>?> getCachedTables() async {
    try {
      final rows = await OfflineDb.instance.readList(OfflineDb.cachedTables);
      if (rows.isNotEmpty) return rows;
    } catch (e) {
      debugPrint('[OFFLINE CACHE] Error reading tables: $e');
    }
    return null;
  }

  Future<void> saveCachedMenu(List<Map<String, dynamic>> menu) async {
    try {
      await OfflineDb.instance.replaceList(OfflineDb.cachedMenuItems, menu);
    } catch (e) {
      debugPrint('[OFFLINE CACHE] Error saving menu: $e');
    }
  }

  Future<List<Map<String, dynamic>>?> getCachedMenu() async {
    try {
      final rows = await OfflineDb.instance.readList(OfflineDb.cachedMenuItems);
      if (rows.isNotEmpty) return rows;
    } catch (e) {
      debugPrint('[OFFLINE CACHE] Error reading menu: $e');
    }
    return null;
  }

  Future<void> saveCachedCategories(List<Map<String, dynamic>> categories) async {
    try {
      await OfflineDb.instance.replaceList(OfflineDb.cachedCategories, categories);
    } catch (e) {
      debugPrint('[OFFLINE CACHE] Error saving categories: $e');
    }
  }

  Future<List<Map<String, dynamic>>?> getCachedCategories() async {
    try {
      final rows = await OfflineDb.instance.readList(OfflineDb.cachedCategories);
      if (rows.isNotEmpty) return rows;
    } catch (e) {
      debugPrint('[OFFLINE CACHE] Error reading categories: $e');
    }
    return null;
  }

  Future<void> saveCachedOrders(List<Map<String, dynamic>> orders) async {
    try {
      await OfflineDb.instance.replaceList(OfflineDb.cachedOrders, orders);
    } catch (e) {
      debugPrint('[OFFLINE CACHE] Error saving orders: $e');
    }
  }

  Future<List<Map<String, dynamic>>?> getCachedOrders() async {
    try {
      final rows = await OfflineDb.instance.readList(OfflineDb.cachedOrders);
      if (rows.isNotEmpty) return rows;
    } catch (e) {
      debugPrint('[OFFLINE CACHE] Error reading orders: $e');
    }
    return null;
  }

  // ===========================================================================
  // OPTIMISTIC LOCAL MODIFICATIONS (Run instantly while offline)
  // ===========================================================================

  /// Insert an offline-created order into local cache so it appears immediately
  Future<void> addLocalOfflineOrder(Map<String, dynamic> order) async {
    final orders = (await getCachedOrders()) ?? [];
    // Prepend new offline order to the list
    orders.insert(0, order);
    await saveCachedOrders(orders);

    // If order has a tableId, update table status to occupied (2)
    final tableId = (order['table_id'] as num?)?.toInt();
    if (tableId != null) {
      await updateLocalTableStatus(tableId, 2);
    }
  }

  /// Merges an order this device learned about from a peer (LAN broadcast)
  /// or the realtime socket into the local cache — as opposed to
  /// [addLocalOfflineOrder], which is for orders *this* device created.
  /// Without this, an order that only ever lived in `_orders` (in-memory)
  /// gets silently wiped the next time this device's own offline poll
  /// fallback replaces its order list from cache, since that cache never
  /// had it — the order would flicker in and out every ~2s instead of
  /// staying put. Safe to call repeatedly for the same order (upsert, not
  /// append), since e.g. the LAN broadcast is deliberately re-sent.
  Future<void> upsertCachedOrder(Map<String, dynamic> order) async {
    final orders = (await getCachedOrders()) ?? [];
    final id = (order['order_id'] ?? order['IDNo'] ?? order['id'] as num?)?.toInt();
    if (id == null) return;

    final index = orders.indexWhere((o) {
      final oid = (o['order_id'] ?? o['IDNo'] ?? o['id'] as num?)?.toInt();
      return oid == id;
    });
    if (index == -1) {
      orders.insert(0, order);
    } else {
      orders[index] = order;
    }
    await saveCachedOrders(orders);

    final tableId = (order['table_id'] as num?)?.toInt();
    if (tableId != null) {
      await updateLocalTableStatus(tableId, 2);
    }
  }

  /// Update order status in local cache (e.g. 1=Settled, 2=Confirmed)
  Future<void> updateLocalOrderStatus({
    required int orderId,
    required int status,
    String? paymentMethod,
    double? discountAmount,
    double? grandTotal,
    double? amountPaid,
    String? paymentRef,
    String? remarks,
  }) async {
    final orders = (await getCachedOrders()) ?? [];
    int? tableIdToFree;

    for (int i = 0; i < orders.length; i++) {
      final o = orders[i];
      final id = (o['order_id'] ?? o['IDNo'] ?? o['id'] as num?)?.toInt();
      if (id == orderId) {
        final updated = Map<String, dynamic>.from(o);
        updated['status'] = status;
        if (paymentMethod != null) updated['payment_method'] = paymentMethod;
        if (discountAmount != null) updated['discount_amount'] = discountAmount;
        if (grandTotal != null) updated['grand_total'] = grandTotal;
        if (amountPaid != null) updated['amount_paid'] = amountPaid;
        if (paymentRef != null) updated['payment_ref'] = paymentRef;
        if (remarks != null) updated['remarks'] = remarks;

        if (status == 1 || status == -1) {
          // Settled (1) or Cancelled (-1): table should be freed — matches
          // the backend's own status-update handler.
          tableIdToFree = (updated['table_id'] as num?)?.toInt();
        }
        orders[i] = updated;
        break;
      }
    }

    await saveCachedOrders(orders);

    if (tableIdToFree != null) {
      await updateLocalTableStatus(tableIdToFree, 1); // 1 = Available
    }
  }

  /// Update table status in local cache (1 = Available, 2 = Occupied)
  Future<void> updateLocalTableStatus(int tableId, int status) async {
    final tables = (await getCachedTables()) ?? [];
    for (int i = 0; i < tables.length; i++) {
      final t = tables[i];
      final id = (t['id'] ?? t['IDNo'] as num?)?.toInt();
      if (id == tableId) {
        final updated = Map<String, dynamic>.from(t);
        updated['status'] = status;
        tables[i] = updated;
        break;
      }
    }
    await saveCachedTables(tables);
  }

  /// Add items to existing order in local cache
  Future<void> addItemsToLocalOrder(int orderId, List<Map<String, dynamic>> newItems) async {
    final orders = (await getCachedOrders()) ?? [];
    for (int i = 0; i < orders.length; i++) {
      final o = orders[i];
      final id = (o['order_id'] ?? o['IDNo'] ?? o['id'] as num?)?.toInt();
      if (id == orderId) {
        final updated = Map<String, dynamic>.from(o);
        final currentItems = List<Map<String, dynamic>>.from(updated['items'] ?? []);
        currentItems.addAll(newItems);
        updated['items'] = currentItems;

        // Recompute subtotal & grandTotal
        double itemsTotal = 0;
        for (final item in currentItems) {
          final qty = (item['qty'] as num?)?.toDouble() ?? 1.0;
          final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
          itemsTotal += (qty * price);
        }
        updated['subtotal'] = itemsTotal;
        final tax = (updated['tax_amount'] as num?)?.toDouble() ?? 0.0;
        final service = (updated['service_charge'] as num?)?.toDouble() ?? 0.0;
        final discount = (updated['discount_amount'] as num?)?.toDouble() ?? 0.0;
        updated['grand_total'] = itemsTotal + tax + service - discount;

        orders[i] = updated;
        break;
      }
    }
    await saveCachedOrders(orders);
  }

  /// Transfer table in local cache
  Future<void> transferLocalTableOrder(int orderId, int targetTableId) async {
    final orders = (await getCachedOrders()) ?? [];
    int? oldTableId;

    for (int i = 0; i < orders.length; i++) {
      final o = orders[i];
      final id = (o['order_id'] ?? o['IDNo'] ?? o['id'] as num?)?.toInt();
      if (id == orderId) {
        final updated = Map<String, dynamic>.from(o);
        oldTableId = (updated['table_id'] as num?)?.toInt();
        updated['table_id'] = targetTableId;
        orders[i] = updated;
        break;
      }
    }
    await saveCachedOrders(orders);

    // Free old table, occupy new table
    if (oldTableId != null) {
      await updateLocalTableStatus(oldTableId, 1);
    }
    await updateLocalTableStatus(targetTableId, 2);
  }

  /// Extend room charge in local cache. `qty` is in 0.5 steps, matching
  /// admin's manual-order room charge stepper.
  Future<void> extendLocalRoomCharge(int orderId, {double qty = 1.0}) async {
    final orders = (await getCachedOrders()) ?? [];
    for (int i = 0; i < orders.length; i++) {
      final o = orders[i];
      final id = (o['order_id'] ?? o['IDNo'] ?? o['id'] as num?)?.toInt();
      if (id == orderId) {
        final updated = Map<String, dynamic>.from(o);
        final tableId = (updated['table_id'] as num?)?.toInt();
        double roomCharge = 0.0;
        if (tableId != null) {
          final tables = await getCachedTables();
          final table = tables?.firstWhere(
            (t) => (t['id'] ?? t['IDNo']) == tableId,
            orElse: () => {},
          );
          roomCharge = (table?['room_charge'] as num?)?.toDouble() ?? 0.0;
        }

        final currentService = (updated['service_charge'] as num?)?.toDouble() ?? 0.0;
        final newService = currentService + (roomCharge * qty);
        updated['service_charge'] = newService;

        final subtotal = (updated['subtotal'] as num?)?.toDouble() ?? 0.0;
        final tax = (updated['tax_amount'] as num?)?.toDouble() ?? 0.0;
        final discount = (updated['discount_amount'] as num?)?.toDouble() ?? 0.0;
        updated['grand_total'] = subtotal + tax + newService - discount;

        orders[i] = updated;
        break;
      }
    }
    await saveCachedOrders(orders);
  }

  // ===========================================================================
  // AUTO-SYNC ENGINE
  // ===========================================================================

  // An action that's failed this many times in a row is skipped on
  // automatic passes (still visible in the queue/pendingCount) rather than
  // retried every single pass — avoids hammering a permanently-broken
  // request (e.g. one referencing a since-deleted menu item).
  static const int _maxAutoRetries = 8;

  /// Process all pending actions in the queue and sync them to moonctgroup.com.
  ///
  /// Actions are grouped by order (temp or real id) and each order's chain
  /// is processed independently: a rejected request only halts *that
  /// order's* remaining actions (recorded for retry) — other orders keep
  /// syncing. A thrown exception (timeout, socket error — i.e. we likely
  /// just went offline) still aborts the whole pass immediately, since
  /// every other group would fail identically.
  Future<bool> syncPendingActions() async {
    if (_isSyncing) return false;
    if (_queue.isEmpty) {
      statusNotifier.value = SyncStatus.online;
      return true;
    }

    _isSyncing = true;
    statusNotifier.value = SyncStatus.syncing;
    debugPrint('[AUTO SYNC] Starting sync for ${_queue.length} pending actions...');

    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('access_token') ?? '';
    final baseUrl = await AppConfig.getBaseUrl();

    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (accessToken.isNotEmpty) 'Authorization': 'Bearer $accessToken',
    };

    // Seed from the persisted mapping so a `create_order` that synced (and
    // was removed from the queue) in a prior app session/pass still
    // resolves correctly for any of its dependents left in the queue.
    final Map<int, int> tempToRealMap = await OfflineDb.instance.readAllIdMappings();
    bool networkDown = false;

    final actionsToProcess = List<OfflineAction>.from(_queue);
    final groupOrder = <int>[];
    final groups = <int, List<OfflineAction>>{};
    for (final action in actionsToProcess) {
      final key = action.orderId;
      final group = groups[key];
      if (group == null) {
        groupOrder.add(key);
        groups[key] = [action];
      } else {
        group.add(action);
      }
    }

    groupLoop:
    for (final key in groupOrder) {
      for (final action in groups[key]!) {
        if (action.retryCount >= _maxAutoRetries) {
          debugPrint('[AUTO SYNC] Skipping ${action.type} for order ${action.orderId} — '
              'failed $_maxAutoRetries+ times (${action.lastError}).');
          continue;
        }

        bool success;
        try {
          success = await _executeSyncAction(
            action: action,
            baseUrl: baseUrl,
            headers: headers,
            tempToRealMap: tempToRealMap,
          );
        } catch (e) {
          debugPrint('[AUTO SYNC] Network error syncing ${action.type} for order ${action.orderId}: $e');
          await _recordActionFailure(action, e.toString());
          networkDown = true;
          break groupLoop;
        }

        if (success) {
          _queue.removeWhere((a) => a.id == action.id);
          await _flushQueue();
          debugPrint('[AUTO SYNC] Synced ${action.type} for order ${action.orderId}. Remaining: ${_queue.length}');
        } else {
          debugPrint('[AUTO SYNC] ${action.type} for order ${action.orderId} was rejected — '
              'will retry this order later, continuing with others.');
          await _recordActionFailure(action, 'Server rejected the request');
          break; // stop this order's chain, move on to the next order
        }
      }
    }

    _isSyncing = false;
    lastSyncTimeNotifier.value = DateTime.now();

    if (_queue.isEmpty) {
      statusNotifier.value = SyncStatus.online;
      debugPrint('[AUTO SYNC] All actions synced successfully! moonctgroup.com is up to date.');

      // Notify UI listeners to reload latest cloud data
      for (final callback in List<VoidCallback>.from(_dataSyncedCallbacks)) {
        try {
          callback();
        } catch (e) {
          debugPrint('[AUTO SYNC] Error in sync callback: $e');
        }
      }
      return true;
    } else {
      statusNotifier.value = networkDown ? SyncStatus.offline : SyncStatus.online;
      return false;
    }
  }

  /// Records a failed sync attempt on [action] (bumps its retry count and
  /// remembers why) and persists the queue.
  Future<void> _recordActionFailure(OfflineAction action, String error) async {
    final index = _queue.indexWhere((a) => a.id == action.id);
    if (index == -1) return;
    _queue[index] = _queue[index].copyWith(
      retryCount: _queue[index].retryCount + 1,
      lastError: error,
    );
    await _flushQueue();
  }

  Future<bool> _executeSyncAction({
    required OfflineAction action,
    required String baseUrl,
    required Map<String, String> headers,
    required Map<int, int> tempToRealMap,
  }) async {
    // Resolve target order ID (remapping temp ID if needed)
    int targetOrderId = action.orderId;
    if (tempToRealMap.containsKey(targetOrderId)) {
      targetOrderId = tempToRealMap[targetOrderId]!;
    }

    switch (action.type) {
      case 'create_order':
        final url = Uri.parse('$baseUrl/api/orders');
        final body = Map<String, dynamic>.from(action.payload);

        final response = await http
            .post(url, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 12));

        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            final realIdRaw = data['data']?['order_id'] ?? data['data']?['orderId'];
            final realId = (realIdRaw as num?)?.toInt();
            if (realId != null) {
              if (action.tempId != null) {
                tempToRealMap[action.tempId!] = realId;
                await OfflineDb.instance.setIdMapping(action.tempId!, realId);
              }
              tempToRealMap[action.orderId] = realId;
              if (action.orderId != action.tempId) {
                await OfflineDb.instance.setIdMapping(action.orderId, realId);
              }
              final alreadyExists = data['data']?['already_exists'] == true;
              debugPrint('[AUTO SYNC] Remapped temp order ID ${action.orderId} -> Real Server ID $realId'
                  '${alreadyExists ? ' (idempotent — order already existed on server)' : ''}');
            }
            return true;
          }
        }
        return false;


      case 'update_status':
        final url = Uri.parse('$baseUrl/api/waiter/orders/$targetOrderId/status');
        final body = Map<String, dynamic>.from(action.payload);

        final response = await http
            .patch(url, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 12));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          return data['success'] == true;
        }
        return false;

      case 'add_items':
        final url = Uri.parse('$baseUrl/api/orders/$targetOrderId/items');
        final body = Map<String, dynamic>.from(action.payload);

        final response = await http
            .post(url, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 12));

        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = jsonDecode(response.body);
          return data['success'] == true;
        }
        return false;

      case 'transfer_table':
        final url = Uri.parse('$baseUrl/api/waiter/orders/$targetOrderId/transfer-table');
        final body = Map<String, dynamic>.from(action.payload);

        final response = await http
            .post(url, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 12));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          return data['success'] == true;
        }
        return false;

      case 'extend_room_charge':
        final url = Uri.parse('$baseUrl/api/waiter/orders/$targetOrderId/extend-room-charge');
        final body = Map<String, dynamic>.from(action.payload);

        final response = await http
            .post(url, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 12));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          return data['success'] == true;
        }
        return false;

      default:
        debugPrint('[AUTO SYNC] Unknown action type: ${action.type}');
        return true; // Skip unrecognized action
    }
  }

  void dispose() {
    _healthProbeTimer?.cancel();
    _lanRebroadcastTimer?.cancel();
    _connectivitySubscription?.cancel();
    statusNotifier.dispose();
    pendingCountNotifier.dispose();
    lastSyncTimeNotifier.dispose();
  }
}
