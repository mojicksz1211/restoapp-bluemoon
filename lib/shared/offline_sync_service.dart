import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'app_config.dart';

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

  OfflineAction({
    required this.id,
    required this.type,
    required this.orderId,
    this.tempId,
    required this.createdAt,
    required this.payload,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'order_id': orderId,
        if (tempId != null) 'temp_id': tempId,
        'created_at': createdAt.toIso8601String(),
        'payload': payload,
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

  // Storage Keys
  static const String _queueKey = 'offline_sync_queue_v1';
  static const String _tablesCacheKey = 'offline_cached_tables_v1';
  static const String _menuCacheKey = 'offline_cached_menu_v1';
  static const String _categoriesCacheKey = 'offline_cached_categories_v1';
  static const String _ordersCacheKey = 'offline_cached_orders_v1';

  // State Notifiers
  final ValueNotifier<SyncStatus> statusNotifier = ValueNotifier<SyncStatus>(SyncStatus.online);
  final ValueNotifier<int> pendingCountNotifier = ValueNotifier<int>(0);
  final ValueNotifier<DateTime?> lastSyncTimeNotifier = ValueNotifier<DateTime?>(null);

  // In-memory action queue
  final List<OfflineAction> _queue = [];
  bool _initialized = false;
  bool _isSyncing = false;
  Timer? _healthProbeTimer;

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

    await _restoreQueue();
    _startReachabilityProbe();

    // Trigger initial probe immediately
    unawaited(probeReachability());
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
    // Probe every 10 seconds
    _healthProbeTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      await probeReachability();
    });
  }

  // ===========================================================================
  // QUEUE MANAGEMENT
  // ===========================================================================

  Future<void> _restoreQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_queueKey);
      if (raw != null && raw.isNotEmpty) {
        final List decoded = jsonDecode(raw);
        _queue.clear();
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            _queue.add(OfflineAction.fromJson(item));
          }
        }
        pendingCountNotifier.value = _queue.length;
        debugPrint('[OFFLINE SYNC] Restored ${_queue.length} pending actions from disk');
      }
    } catch (e) {
      debugPrint('[OFFLINE SYNC] Error restoring queue: $e');
    }
  }

  Future<void> _flushQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_queue.isEmpty) {
        await prefs.remove(_queueKey);
      } else {
        final encoded = jsonEncode(_queue.map((a) => a.toJson()).toList());
        await prefs.setString(_queueKey, encoded);
      }
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

  // ===========================================================================
  // LOCAL CACHE ACCESS
  // ===========================================================================

  Future<void> saveCachedTables(List<Map<String, dynamic>> tables) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tablesCacheKey, jsonEncode(tables));
    } catch (e) {
      debugPrint('[OFFLINE CACHE] Error saving tables: $e');
    }
  }

  Future<List<Map<String, dynamic>>?> getCachedTables() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_tablesCacheKey);
      if (raw != null && raw.isNotEmpty) {
        final List decoded = jsonDecode(raw);
        return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('[OFFLINE CACHE] Error reading tables: $e');
    }
    return null;
  }

  Future<void> saveCachedMenu(List<Map<String, dynamic>> menu) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_menuCacheKey, jsonEncode(menu));
    } catch (e) {
      debugPrint('[OFFLINE CACHE] Error saving menu: $e');
    }
  }

  Future<List<Map<String, dynamic>>?> getCachedMenu() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_menuCacheKey);
      if (raw != null && raw.isNotEmpty) {
        final List decoded = jsonDecode(raw);
        return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('[OFFLINE CACHE] Error reading menu: $e');
    }
    return null;
  }

  Future<void> saveCachedCategories(List<Map<String, dynamic>> categories) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_categoriesCacheKey, jsonEncode(categories));
    } catch (e) {
      debugPrint('[OFFLINE CACHE] Error saving categories: $e');
    }
  }

  Future<List<Map<String, dynamic>>?> getCachedCategories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_categoriesCacheKey);
      if (raw != null && raw.isNotEmpty) {
        final List decoded = jsonDecode(raw);
        return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('[OFFLINE CACHE] Error reading categories: $e');
    }
    return null;
  }

  Future<void> saveCachedOrders(List<Map<String, dynamic>> orders) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_ordersCacheKey, jsonEncode(orders));
    } catch (e) {
      debugPrint('[OFFLINE CACHE] Error saving orders: $e');
    }
  }

  Future<List<Map<String, dynamic>>?> getCachedOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_ordersCacheKey);
      if (raw != null && raw.isNotEmpty) {
        final List decoded = jsonDecode(raw);
        return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
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

        if (status == 1) {
          // Settled: Table should be freed
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

  /// Process all pending actions in the queue and sync them to moonctgroup.com
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

    // Mapping of temporary local order IDs to real server order IDs
    final Map<int, int> tempToRealMap = {};
    bool hasErrors = false;

    // Process actions sequentially (FIFO)
    final actionsToProcess = List<OfflineAction>.from(_queue);

    for (final action in actionsToProcess) {
      try {
        final success = await _executeSyncAction(
          action: action,
          baseUrl: baseUrl,
          headers: headers,
          tempToRealMap: tempToRealMap,
        );

        if (success) {
          _queue.removeWhere((a) => a.id == action.id);
          await _flushQueue();
          debugPrint('[AUTO SYNC] Successfully synced action: ${action.type}. Remaining: ${_queue.length}');
        } else {
          debugPrint('[AUTO SYNC] Action ${action.type} returned failure. Pausing sync.');
          hasErrors = true;
          break; // Stop and retry later on network recovery
        }
      } catch (e) {
        debugPrint('[AUTO SYNC] Error syncing action ${action.type}: $e');
        hasErrors = true;
        break; // Network or server failure; retain remaining queue
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
      if (hasErrors) {
        statusNotifier.value = SyncStatus.offline;
      } else {
        statusNotifier.value = SyncStatus.online;
      }
      return false;
    }
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
              }
              tempToRealMap[action.orderId] = realId;
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
    statusNotifier.dispose();
    pendingCountNotifier.dispose();
    lastSyncTimeNotifier.dispose();
  }
}
