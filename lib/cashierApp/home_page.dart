import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../waiterApp/models.dart';
import '../waiterApp/waiter_models.dart';
import '../waiterApp/services/api_service.dart';
import '../waiterApp/services/socket_service.dart';
import '../shared/sound_service.dart';
import '../shared/globals.dart';
import '../waiterApp/pages/get_order_page.dart' as waiter_order;
import 'widgets/bill_out_modal.dart';
import '../waiterApp/widgets/transfer_table_modal.dart';
import '../waiterApp/widgets/edit_order_bottom_sheet.dart';
import '../waiterApp/widgets/menu_picker_sheet.dart';
import '../shared/settings_sheet.dart';
import '../shared/app_translations.dart';
import '../shared/lan_broadcast_service.dart';
import '../shared/background_service.dart';
import '../shared/offline_sync_service.dart';
import '../shared/widgets/offline_order_badge.dart';
import '../shared/widgets/offline_sync_banner.dart';
import '../shared/update_dialog.dart';

class SettlementData {
  final String paymentMethod;
  final double discountAmount;
  final double grandTotal;
  final double amountPaid;
  final String? paymentRef;
  final String? remarks;

  const SettlementData({
    required this.paymentMethod,
    required this.discountAmount,
    required this.grandTotal,
    required this.amountPaid,
    this.paymentRef,
    this.remarks,
  });
}

Widget _buildStatusChip(int status) {
  String label;
  Color color;
  switch (status) {
    case 1:
      label = 'settled'.tr;
      color = const Color(0xFF2E8B57);
      break;
    case 2:
      label = 'confirmed'.tr;
      color = const Color(0xFFDAA520);
      break;
    case 3:
      label = 'pending'.tr;
      color = const Color(0xFF0C0E2B);
      break;
    case -1:
      label = 'cancelled'.tr;
      color = Colors.red.shade700;
      break;
    default:
      label = 'unknown'.tr;
      color = Colors.grey;
  }

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.grey.withOpacity(0.1)),
    ),
    child: Text(
      label,
      style: GoogleFonts.urbanist(
        color: color,
        fontWeight: FontWeight.w900,
        fontSize: 10,
        letterSpacing: 0.5,
        height: 1.1,
      ),
    ),
  );
}

Widget _buildPaymentMethodBadge(String method) {
  IconData icon;
  Color color;
  Color bgColor;
  final upper = method.toUpperCase();
  switch (upper) {
    case 'GCASH':
      icon = Icons.account_balance_wallet_rounded;
      color = const Color(0xFF007DFE);
      bgColor = const Color(0xFF007DFE).withValues(alpha: 0.1);
      break;
    case 'MAYA':
      icon = Icons.wallet_rounded;
      color = const Color(0xFF059669);
      bgColor = const Color(0xFF059669).withValues(alpha: 0.1);
      break;
    case 'CARD':
      icon = Icons.credit_card_rounded;
      color = const Color(0xFF7C3AED);
      bgColor = const Color(0xFF7C3AED).withValues(alpha: 0.1);
      break;
    default:
      icon = Icons.payments_rounded;
      color = const Color(0xFF0C0E2B);
      bgColor = const Color(0xFF0C0E2B).withValues(alpha: 0.08);
  }

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(
          upper,
          style: GoogleFonts.urbanist(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 10.5,
            letterSpacing: 0.5,
          ),
        ),
      ],
    ),
  );
}

class CashierHomePage extends StatefulWidget {
  const CashierHomePage({super.key});

  @override
  State<CashierHomePage> createState() => _CashierHomePageState();
}

class _CashierHomePageState extends State<CashierHomePage> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isLoading = true;
  String? _errorMessage;
  List<WaiterOrder> _orders = [];
  List<MenuItem> _menuItems = [];
  List<WaiterTable> _tables = [];
  String _floorFilter = 'all'; // 'all', 'gf', '2f'
  // 'gf', '2f', or null (unscoped). Set per-account by an admin via the
  // FLOOR column on user_info. Unlike waiterApp, this does NOT default to
  // symmetric behavior — a branch typically wants its ground-floor cashier
  // to settle everything (unscoped), and only a satellite floor cashier
  // locked to just that floor's tables.
  String? _floorScope;
  final Set<int> _joinedOrderIds = {};
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final Set<int> _pinnedOrderIds = {};
  final Set<int> _unacknowledgedOrderIds = {};
  final List<WaiterOrder> _alertOrdersQueue = [];
  bool _alertIsAddedItems = false;
  
  VoidCallback? _disposeOrderUpdated;
  VoidCallback? _disposeOrderItemsAdded;
  VoidCallback? _disposeOrderCreated;
  VoidCallback? _disposeLanOrderCreated;
  VoidCallback? _disposeLanOrderItemsAdded;

  // Socket events arrive in bursts (the backend re-broadcasts every order on
  // connect and on any change). Coalesce the follow-up full refresh, guard
  // against overlapping refreshes, and only raise "new order" alerts once the
  // first load is done — otherwise the reconnect backlog floods the queue.
  Timer? _socketRefreshTimer;
  Timer? _pollTimer;
  bool _isLoadingData = false;
  bool _hasLoadedOrdersOnce = false;
  final Set<int> _alertedOrderIds = {};
  // An offline order's id changes once it syncs (negative temp id -> real
  // server id assigned by the backend), but its order_no (client-generated,
  // e.g. ORD-20260915-...) stays the same across that transition. Tracking
  // it too — alongside id — stops the order from being re-alerted as
  // "newly appeared" under its new real id once internet returns and the
  // REST refresh (_applyFreshOrders) or the real socket sees it again; the
  // cashier already alerted on it via the LAN-broadcast fallback while it
  // was still unsynced.
  final Set<String> _alertedOrderNos = {};
  // Last total item quantity this device already alerted on, per order — an
  // `order_items_added` event has no natural one-shot dedup like
  // `order_created` does (_alertedOrderIds), but the LAN-broadcast fallback
  // re-sends the same unsynced add_items action's snapshot every ~10s while
  // offline (see _rebroadcastPendingOrdersOverLan). Without this, each
  // identical resend re-fired the alert popup/sound forever. Tracks summed
  // quantity rather than items.length — adding more of a menu item ALREADY
  // on the order merges into that item's existing qty server-side instead of
  // appending a new line, so item count alone doesn't change even though
  // something genuinely was added.
  final Map<int, double> _lastAlertedItemsQty = {};
  static const int _maxAlertQueue = 15;

  double _totalQuantity(WaiterOrder order) =>
      order.items.fold<double>(0, (sum, item) => sum + item.quantity);

  void _updateRepeatingTtsAnnouncement() {
    if (_alertOrdersQueue.isEmpty) {
      SoundService.stopRepeatingAlert();
      return;
    }

    final descriptions = <String>[];
    // Put newest orders FIRST so the latest incoming order is announced immediately
    for (final order in _alertOrdersQueue.reversed) {
      final desc = _getSpeechTableDescription(order.tableNumber, order.orderType);
      if (!descriptions.contains(desc)) {
        descriptions.add(desc);
      }
    }

    if (descriptions.isEmpty) {
      SoundService.stopRepeatingAlert();
      return;
    }

    String speechText;
    if (descriptions.length == 1) {
      speechText = 'New order for ${descriptions[0]}';
    } else if (descriptions.length == 2) {
      speechText = 'New orders for ${descriptions[0]} and ${descriptions[1]}';
    } else if (descriptions.length == 3) {
      speechText = 'New orders for ${descriptions[0]}, ${descriptions[1]}, and ${descriptions[2]}';
    } else if (descriptions.length == 4) {
      speechText = 'New orders for ${descriptions[0]}, ${descriptions[1]}, ${descriptions[2]}, and ${descriptions[3]}';
    } else {
      // 5 or more tables: Announce the newest tables prominently + count of other pending tables
      final newestTwo = [descriptions[0], descriptions[1]];
      final remainingCount = descriptions.length - 2;
      speechText = 'New order for ${newestTwo[0]} and ${newestTwo[1]}, with $remainingCount other pending tables';
    }
    SoundService.startRepeatingAlert(speechText);
  }

  void _acknowledgeOrder([int? orderId]) {
    if (!mounted) return;
    if (orderId == null) {
      _acknowledgeAllOrders();
      return;
    }
    setState(() {
      _unacknowledgedOrderIds.remove(orderId);
      _alertOrdersQueue.removeWhere((o) => o.id == orderId);
    });
    if (_alertOrdersQueue.isEmpty) {
      SoundService.stopRepeatingAlert();
    } else {
      _updateRepeatingTtsAnnouncement();
    }
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  void _acknowledgeAllOrders() {
    if (!mounted) return;
    SoundService.stopRepeatingAlert();
    setState(() {
      _unacknowledgedOrderIds.clear();
      _alertOrdersQueue.clear();
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  bool _isGroundFloorOrder(WaiterOrder order) {
    final numStr = (order.tableNumber ?? '').toUpperCase().trim();
    final roomMatch = RegExp(r'\bROOM\s*[-_]?\s*([0-9]+)\b').firstMatch(numStr);
    if (roomMatch != null) {
      final roomNum = int.tryParse(roomMatch.group(1) ?? '');
      if (roomNum != null && roomNum >= 1 && roomNum <= 13) return false;
    }
    return true;
  }

  // Realtime order events (socket + REST-poll fallback) arrive branch-wide,
  // not floor-scoped, so a floor-locked cashier account must filter them
  // itself before alerting. Orders with no table (e.g. takeout) aren't tied
  // to a floor, so they always stay visible — otherwise _isGroundFloorOrder's
  // "no room match => ground floor" default would silently suppress a 2F
  // cashier's own takeout-order alert.
  bool _isOrderVisibleForFloorScope(WaiterOrder order) {
    if (_floorScope != 'gf' && _floorScope != '2f') return true;
    final tableNumber = order.tableNumber;
    if (tableNumber == null || tableNumber.trim().isEmpty) return true;
    final wantGf = _floorScope == 'gf';
    return _isGroundFloorOrder(order) == wantGf;
  }

  // Same heuristic as _isGroundFloorOrder, applied to a WaiterTable instead
  // of an order — needed to floor-scope `_tables` itself (used for settle/
  // transfer lookups), separately from the order-list floor filter above.
  bool _isGroundFloorTable(WaiterTable table) {
    final numStr = table.number.toUpperCase().trim();
    final roomMatch = RegExp(r'\bROOM\s*[-_]?\s*([0-9]+)\b').firstMatch(numStr);
    if (roomMatch != null) {
      final roomNum = int.tryParse(roomMatch.group(1) ?? '');
      if (roomNum != null && roomNum >= 1 && roomNum <= 13) return false;
    }
    return true;
  }

  List<WaiterTable> _applyFloorScope(List<WaiterTable> tables) {
    if (_floorScope != 'gf' && _floorScope != '2f') return tables;
    final wantGf = _floorScope == 'gf';
    return tables.where((t) => _isGroundFloorTable(t) == wantGf).toList();
  }

  Future<void> _loadFloorScope() async {
    final userData = await ApiService.getUserData();
    if (!mounted) return;
    setState(() {
      _floorScope = userData['floor'];
      if (_floorScope == 'gf' || _floorScope == '2f') {
        _floorFilter = _floorScope!;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Tell the background service the UI is up front, before the first real
    // lifecycle callback — otherwise a brand-new alert firing in the window
    // between app launch and the first didChangeAppLifecycleState call would
    // still show the banner even though the app is plainly already open.
    BackgroundServiceManager.reportUiForeground(true);
    OfflineSyncService.instance.addDataSyncedListener(_onDataSynced);
    // Floor scope must be known before the first table fetch resolves, so a
    // floor-scoped account never briefly renders the other floor's tables.
    _loadFloorScope().then((_) => _loadData()).then((_) => _checkPendingBackgroundAlerts());
    _initializeSocket();
    BackgroundServiceManager.ensureStarted();
    checkAndPromptAppUpdate(context);
    languageNotifier.addListener(_onLanguageChanged);
    // Belt-and-suspenders: socket_io_client has NO real HTTP-polling fallback
    // on native platforms (io_transports.dart hardcodes WebSocketTransport
    // regardless of the configured transport list) — so on a network that
    // blocks WebSocket upgrades (common on corporate/hotel firewalls), the
    // socket can never connect, full stop, no matter what the backend does.
    // Poll REST fast enough to feel close to realtime on those networks; skip
    // the extra fetch entirely once the socket is actually connected, since
    // _scheduleSocketRefresh already keeps things in sync then.
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && !SocketService.isConnected) _pollOrdersOnly();
    });
  }

  void _onDataSynced() {
    if (mounted) {
      debugPrint('[CASHIER] Sync completed event received, refreshing data...');
      _loadData(showSpinner: false);
    }
  }

  /// Requested flow: the background service's wake alert (ringtone, screen
  /// on, full-screen notification) is only step one — once the app is
  /// actually opened, it should ALSO show the normal in-app popup + TTS
  /// announcement, same as if the order had arrived while the app was
  /// already open. The background isolate and this UI isolate are separate
  /// Dart isolates with no shared memory, so PendingForegroundAlerts (a tiny
  /// SharedPreferences-backed handoff) is what lets this side know an alert
  /// already fired in the background and still needs its foreground half.
  /// Runs once, right after the first load — by then _orders has the fresh
  /// data needed to build a real alert card instead of a stale/empty one.
  Future<void> _checkPendingBackgroundAlerts() async {
    final pendingIds = await PendingForegroundAlerts.takeAll();
    if (pendingIds.isEmpty || !mounted) return;
    final matches = _orders.where((o) => pendingIds.contains(o.id) && (o.status == 2 || o.status == 3)).toList();
    if (matches.isEmpty) return;
    setState(() {
      for (final order in matches) {
        // Side effect only (marks id/order_no as seen) — this alert always
        // shows regardless of the boolean, but without this a later
        // reconnect-backlog redelivery of the same order_created event
        // would pass _shouldAlert's own check and fire a second time.
        _shouldAlert(order);
        _unacknowledgedOrderIds.add(order.id);
        _enqueueAlert(order, addedItems: false);
      }
    });
    _updateRepeatingTtsAnnouncement();
  }

  void _onLanguageChanged() {
    if (mounted) {
      _loadData();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    OfflineSyncService.instance.removeDataSyncedListener(_onDataSynced);
    SoundService.stopRepeatingAlert();
    languageNotifier.removeListener(_onLanguageChanged);
    _socketRefreshTimer?.cancel();
    _pollTimer?.cancel();
    _cleanupSocket();
    _searchController.dispose();
    super.dispose();
  }

  // Tells the background service whether the UI is actually visible right
  // now, so its wake-alert banner only fires when it's genuinely needed —
  // app backgrounded/swiped away, or the screen turned off while the app was
  // open. AppLifecycleState.resumed is the only state where the user could
  // actually see the in-app popup, so every other state means "show the
  // banner instead."
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    BackgroundServiceManager.reportUiForeground(state == AppLifecycleState.resumed);
  }

  Future<void> _loadData({bool showSpinner = true}) async {
    // Never let socket-triggered background refreshes stack up.
    if (_isLoadingData) return;
    _isLoadingData = true;

    if (showSpinner) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final ordersFuture = ApiService.getWaiterOrders();
      final tablesFuture = ApiService.getTables();
      final menuFuture = ApiService.getMenuItems();

      final results = await Future.wait([ordersFuture, tablesFuture, menuFuture]);
      final ordersResult = results[0];
      final tablesResult = results[1];
      final menuResult = results[2];
      
      if (ordersResult['unauthorized'] == true || tablesResult['unauthorized'] == true || menuResult['unauthorized'] == true) {
        await _redirectToLogin();
        return;
      }

      if (ordersResult['success'] == true) {
        final ordersData = List<Map<String, dynamic>>.from(ordersResult['data']);
        List<WaiterTable> loadedTables = _tables;
        List<MenuItem> loadedMenu = _menuItems;

        if (tablesResult['success'] == true && tablesResult['data'] is List) {
          loadedTables = List<Map<String, dynamic>>.from(tablesResult['data']).map(WaiterTable.fromApi).toList();
        }
        if (menuResult['success'] == true && menuResult['data'] is List) {
          loadedMenu = List<Map<String, dynamic>>.from(menuResult['data']).map(MenuItem.fromApi).toList();
        }

        _applyFreshOrders(ordersData, extra: () {
          _tables = _applyFloorScope(loadedTables);
          _menuItems = loadedMenu;
          _isLoading = false;
        });
        _syncSocketOrderRooms();
      } else {
        setState(() {
          if (_orders.isEmpty && _tables.isEmpty) {
            _errorMessage = ordersResult['error'] ?? 'Failed to load orders';
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        if (_orders.isEmpty && _tables.isEmpty) {
          _errorMessage = 'Error loading data: ${e.toString()}';
        }
        _isLoading = false;
      });
      debugPrint('❌ Error in _loadData: $e');
    } finally {
      _isLoadingData = false;
    }
  }

  /// Lightweight poll for the fast (1s) fallback timer used when the socket
  /// isn't connected: orders only, no tables/menu refetch, so that cadence
  /// doesn't re-download the whole menu on every tick.
  Future<void> _pollOrdersOnly() async {
    if (_isLoadingData) return;
    _isLoadingData = true;
    try {
      final ordersResult = await ApiService.getWaiterOrders();
      if (ordersResult['unauthorized'] == true) {
        await _redirectToLogin();
        return;
      }
      if (ordersResult['success'] == true) {
        final ordersData = List<Map<String, dynamic>>.from(ordersResult['data']);
        _applyFreshOrders(ordersData);
        _syncSocketOrderRooms();
      }
    } catch (e) {
      debugPrint('❌ Error in _pollOrdersOnly: $e');
    } finally {
      _isLoadingData = false;
    }
  }

  /// Shared by [_loadData] and [_pollOrdersOnly]: replaces [_orders], keeps
  /// the alert queue's copies fresh, and raises the same alert / TTS / modal
  /// for any order this fetch turns up that we didn't already know about —
  /// the REST-poll equivalent of a missed `order_created` socket event.
  /// [extra] runs inside the same setState for callers that also update other
  /// fields (tables, menu, loading flag).
  void _applyFreshOrders(List<Map<String, dynamic>> ordersData, {VoidCallback? extra}) {
    final previousIds = _orders.map((o) => o.id).toSet();
    // Total item quantity before this refresh, so an order we already knew
    // about can still be detected as "items were added" below — previousIds
    // alone only tells us the order itself isn't new. Quantity, not
    // items.length: adding more of a menu item already on the order merges
    // into that item's qty rather than appending a new line.
    final previousItemQty = {for (final o in _orders) o.id: _totalQuantity(o)};
    final freshOrders = ordersData.map(WaiterOrder.fromApi).toList();
    // Skip on the very first load (everything is "new" then) and skip
    // settled orders (history, not something to alert about). Materialized
    // eagerly (not left as a lazy Iterable) since the predicate has a side
    // effect (_shouldAlert) that must run exactly once per order.
    final newlyAppeared = _hasLoadedOrdersOnce
        ? freshOrders
            .where((o) => !previousIds.contains(o.id) && (o.status == 2 || o.status == 3))
            .where(_isOrderVisibleForFloorScope)
            .where((o) => _shouldAlert(o))
            .toList()
        : const <WaiterOrder>[];

    // The REST poll above only ever catches a missed `order_created` socket
    // event (a brand-new order id). When the socket is down and a waiter
    // adds items to an order the cashier ALREADY knows about, nothing here
    // detected that — only the live `order_items_added` socket event did,
    // and that never arrives either while the socket is disconnected. Catch
    // it the same way: an order we already know about whose total quantity
    // grew. Reuses _lastAlertedItemsQty (also used by the socket path) so a
    // repeat poll of the same unacknowledged growth doesn't re-alert.
    final itemsAddedOrders = _hasLoadedOrdersOnce
        ? freshOrders.where((o) {
            if (!previousIds.contains(o.id)) return false;
            if (o.status != 2 && o.status != 3) return false;
            if (!_isOrderVisibleForFloorScope(o)) return false;
            final previousQty = previousItemQty[o.id];
            final currentQty = _totalQuantity(o);
            if (previousQty == null || currentQty <= previousQty) return false;
            if (_lastAlertedItemsQty[o.id] == currentQty) return false;
            _lastAlertedItemsQty[o.id] = currentQty;
            return true;
          }).toList()
        : const <WaiterOrder>[];

    setState(() {
      _orders = freshOrders;
      for (int i = 0; i < _alertOrdersQueue.length; i++) {
        final fresh = _orders.firstWhere((o) => o.id == _alertOrdersQueue[i].id, orElse: () => _alertOrdersQueue[i]);
        if (fresh.items.isNotEmpty) {
          _alertOrdersQueue[i] = fresh;
        }
      }
      for (final order in newlyAppeared) {
        debugPrint('✓ Poll: new order ${order.id} (socket missed it)');
        _unacknowledgedOrderIds.add(order.id);
        _enqueueAlert(order, addedItems: false);
      }
      for (final order in itemsAddedOrders) {
        debugPrint('✓ Poll: items added to order ${order.id} (socket missed it)');
        _unacknowledgedOrderIds.add(order.id);
        _enqueueAlert(order, addedItems: true);
      }
      extra?.call();
    });
    _hasLoadedOrdersOnce = true;
    if (newlyAppeared.isNotEmpty || itemsAddedOrders.isNotEmpty) {
      _updateRepeatingTtsAnnouncement();
    }
  }

  Future<void> _redirectToLogin() async {
    await ApiService.logout();
    if (!mounted) return;
    refreshAppAuth();
  }

  /// Manual refresh — wired to the refresh button next to the settings/logout
  /// action in the AppBar. Full reload, no blocking spinner, brief snackbar.
  bool _isManualRefreshing = false;
  Future<void> _manualRefresh() async {
    if (_isManualRefreshing) return;
    setState(() => _isManualRefreshing = true);
    try {
      await _loadData(showSpinner: false);
    } finally {
      if (mounted) setState(() => _isManualRefreshing = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 1),
          content: Text('Refreshed'),
        ),
      );
  }

  Future<void> _initializeSocket() async {
    try {
      await SocketService.initialize();
      SocketService.joinCashier();

      _disposeOrderUpdated?.call();
      _disposeOrderUpdated = SocketService.addOrderUpdateListener((data) {
        if (!mounted) return;
        _handleSocketOrderEvent(data, isFullUpdate: true, eventType: 'order_updated');
      });

      _disposeOrderItemsAdded?.call();
      _disposeOrderItemsAdded = SocketService.addOrderItemsAddedListener((data) {
        if (!mounted) return;
        _handleSocketOrderEvent(data, isFullUpdate: false, eventType: 'order_items_added');
      });

      _disposeOrderCreated?.call();
      _disposeOrderCreated = SocketService.addOrderCreatedListener((data) {
        if (!mounted) return;
        _handleSocketOrderEvent(data, isFullUpdate: true, eventType: 'order_created');
      });

      // LAN fallback: same handler, just fed from a WiFi-local broadcast
      // instead of the cloud socket — see lan_broadcast_service.dart.
      _disposeLanOrderCreated?.call();
      _disposeLanOrderCreated = LanBroadcastService.instance.addOrderCreatedListener((data) {
        if (!mounted) return;
        _handleSocketOrderEvent(data, isFullUpdate: true, eventType: 'order_created');
      });

      _disposeLanOrderItemsAdded?.call();
      _disposeLanOrderItemsAdded = LanBroadcastService.instance.addOrderItemsAddedListener((data) {
        if (!mounted) return;
        _handleSocketOrderEvent(data, isFullUpdate: false, eventType: 'order_items_added');
      });

      _syncSocketOrderRooms();
    } catch (e) {
      debugPrint('Error initializing socket in cashier_home_page: $e');
    }
  }

  void _handleSocketOrderEvent(Map<String, dynamic> data, {bool isFullUpdate = false, String eventType = ''}) {
    if (!mounted) return;

    debugPrint('🔔 Socket event received ($eventType, isFullUpdate: $isFullUpdate): ${data.keys.toList()}');

    // Ignore other branches' realtime traffic. The backend broadcasts to
    // per-branch rooms, but stays a defensive check for shared-room fallback.
    if (!_isForThisBranch(data)) {
      debugPrint('↪︎ Socket event for another branch — ignored');
      return;
    }

    final rawOrderData = data['order'];
    final orderData = rawOrderData is Map
        ? Map<String, dynamic>.from(rawOrderData)
        : Map<String, dynamic>.from(data);

    if (orderData['order_id'] == null && orderData['orderId'] != null) {
      orderData['order_id'] = orderData['orderId'];
    }
    // The socket payload carries the authoritative id at the top level
    // (`{ order_id, order, timestamp }`); the nested `order` object may not
    // repeat it. Fall back through the common key spellings.
    orderData['order_id'] ??= data['order_id'] ??
        orderData['id'] ??
        orderData['ORDER_ID'] ??
        orderData['ORDERID'] ??
        data['orderId'];
    if (orderData['order_no'] == null && data['order_no'] != null) {
      orderData['order_no'] = data['order_no'];
    }

    final orderIdRaw = orderData['order_id'];
    final orderId = orderIdRaw is int ? orderIdRaw : int.tryParse(orderIdRaw?.toString() ?? '');
    debugPrint('🔔 Socket Event - Order ID: $orderId, Items in event: ${(orderData['items'] as List?)?.length ?? 0}');
    
    if (orderId == null) {
      debugPrint('❌ Socket event - Could not parse order ID');
      return;
    }

    final existingIndex = _orders.indexWhere((o) => o.id == orderId);
    final isNewOrder = existingIndex == -1;

    try {
      final normalized = _normalizeSocketOrder(orderData);
      final updatedOrder = WaiterOrder.fromApi(normalized);


      // Queue order for alert and update repeating voice announcement.
      // A genuinely new order always arrives as an `order_created` event; an
      // unknown order from `order_updated` is the reconnect backlog or another
      // branch's traffic (the backend broadcasts globally), so it must not
      // alert. Alert each order at most once.
      if (eventType == 'order_created' &&
          _isOrderVisibleForFloorScope(updatedOrder) &&
          _shouldAlert(updatedOrder)) {
        setState(() {
          _unacknowledgedOrderIds.add(updatedOrder.id);
          _enqueueAlert(updatedOrder, addedItems: false);
        });
        _updateRepeatingTtsAnnouncement();
      } else if (!isNewOrder &&
          (eventType == 'order_items_added' || data['items_added'] != null)) {
        final currentQty = _totalQuantity(updatedOrder);
        if (_lastAlertedItemsQty[updatedOrder.id] != currentQty) {
          _lastAlertedItemsQty[updatedOrder.id] = currentQty;
          setState(() {
            _unacknowledgedOrderIds.add(updatedOrder.id);
            _enqueueAlert(updatedOrder, addedItems: true);
          });
          _updateRepeatingTtsAnnouncement();
        }
      }

      // An unknown order from a plain `order_updated` / `order_items_added` is
      // almost always the reconnect backlog or another branch's traffic (the
      // backend broadcasts globally). Don't splice it in — the debounced
      // _loadData (branch-scoped) is the source of truth for which orders
      // exist. Only `order_created` adds a new order locally.
      if (existingIndex == -1 && eventType != 'order_created') {
        _scheduleSocketRefresh();
        return;
      }

      setState(() {
        if (existingIndex == -1) {
          debugPrint('✓ Socket: Adding new order $orderId');
          _orders = [..._orders, updatedOrder];
        } else {
          final existingOrder = _orders[existingIndex];
          
          List<WaiterOrderItem> finalItems;
          if (isFullUpdate) {
            finalItems = updatedOrder.items;
          } else {
            // MERGE logic for incremental updates
            final Map<int, WaiterOrderItem> itemMap = {
              for (var item in existingOrder.items) if (item.id != null) item.id!: item
            };
            
            for (var newItem in updatedOrder.items) {
              if (newItem.id != null) {
                itemMap[newItem.id!] = newItem;
              }
            }
            
            finalItems = itemMap.values.toList();
            final socketItemsWithoutIds = updatedOrder.items.where((it) => it.id == null).toList();
            finalItems.addAll(socketItemsWithoutIds);
          }
          
          if (!isFullUpdate && updatedOrder.items.isEmpty) {
            finalItems = existingOrder.items;
          }

          final mergedOrder = updatedOrder.copyWith(items: finalItems);
          final nextOrders = List<WaiterOrder>.from(_orders);
          nextOrders[existingIndex] = mergedOrder;
          _orders = nextOrders;
          for (int i = 0; i < _alertOrdersQueue.length; i++) {
            if (_alertOrdersQueue[i].id == updatedOrder.id) {
              _alertOrdersQueue[i] = mergedOrder;
            }
          }
        }
      });
      _syncSocketOrderRooms();

      // While offline, this device's own poll/refresh fallback re-reads its
      // local cache and replaces `_orders` wholesale — an order that only
      // ever lived in memory (arrived via LAN broadcast, never created
      // here) would get wiped on the very next cycle and flicker in and
      // out. Persist it locally so that fallback sees it too.
      if (OfflineSyncService.instance.isOffline) {
        unawaited(OfflineSyncService.instance.upsertCachedOrder(normalized));
      }

      // Background refresh to guarantee DB sync for tables & totals — debounced
      // so a burst of socket events triggers at most one refetch.
      _scheduleSocketRefresh();
    } catch (e) {
      debugPrint('❌ Error updating order from socket: $e');
    }
  }

  /// True unless the event clearly belongs to a different branch. Reads the
  /// branch id from the top-level payload or the nested order object; when
  /// neither is present (older backend) we can't tell, so we let it through.
  bool _isForThisBranch(Map<String, dynamic> data) {
    final myBranch = SocketService.branchId;
    if (myBranch == null) return true;
    final order = data['order'];
    final raw = data['branch_id'] ??
        data['branchId'] ??
        (order is Map ? (order['branch_id'] ?? order['BRANCH_ID'] ?? order['branchId']) : null);
    if (raw == null) return true;
    final eventBranch = raw is int ? raw : int.tryParse(raw.toString());
    return eventBranch == null || eventBranch == myBranch;
  }

  void _scheduleSocketRefresh() {
    _socketRefreshTimer?.cancel();
    _socketRefreshTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) _loadData(showSpinner: false);
    });
  }

  /// Add/refresh an order in the alert queue, keeping it bounded so a burst of
  /// events can't grow it without limit. Call inside setState.
  void _enqueueAlert(WaiterOrder order, {required bool addedItems}) {
    _alertIsAddedItems = addedItems;
    _alertOrdersQueue.removeWhere((o) => o.id == order.id);
    _alertOrdersQueue.add(order);
    if (_alertOrdersQueue.length > _maxAlertQueue) {
      _alertOrdersQueue.removeRange(0, _alertOrdersQueue.length - _maxAlertQueue);
    }
  }

  /// True the first time this order is seen, by either id or order_no —
  /// and records both so it isn't alerted again. Checking order_no as well
  /// as id is what stops an offline order from getting a second "new order"
  /// alert once it syncs and reappears under its real server id (see
  /// _alertedOrderNos above).
  bool _shouldAlert(WaiterOrder order) {
    final alreadyKnownById = !_alertedOrderIds.add(order.id);
    final orderNo = order.orderNo;
    final alreadyKnownByOrderNo =
        orderNo != null && orderNo.isNotEmpty && !_alertedOrderNos.add(orderNo);
    return !(alreadyKnownById || alreadyKnownByOrderNo);
  }

  String _getSpeechTableDescription(String? rawTable, String? orderType) {
    final clean = (rawTable ?? '').trim();
    if (clean.isEmpty) {
      final type = (orderType ?? 'Table').trim();
      return type.toLowerCase().contains('table') ? type : 'Table $type';
    }
    final lower = clean.toLowerCase();
    if (lower.startsWith('table') || lower.startsWith('room') || lower.startsWith('vip') || lower.startsWith('bar')) {
      return clean;
    }
    return 'Table $clean';
  }



  Map<String, dynamic> _normalizeSocketOrder(Map<String, dynamic> data) {
    final normalized = Map<String, dynamic>.from(data);
    if (normalized['order_id'] == null && normalized['orderId'] != null) normalized['order_id'] = normalized['orderId'];
    if (normalized['order_no'] == null && normalized['orderNo'] != null) normalized['order_no'] = normalized['orderNo'];
    if (normalized['table_id'] == null && normalized['tableId'] != null) normalized['table_id'] = normalized['tableId'];
    if (normalized['table_number'] == null && normalized['tableNumber'] != null) normalized['table_number'] = normalized['tableNumber'];
    if (normalized['grand_total'] == null && normalized['grandTotal'] != null) normalized['grand_total'] = normalized['grandTotal'];
    if (normalized['subtotal'] == null && normalized['subTotal'] != null) normalized['subtotal'] = normalized['subTotal'];
    if (normalized['service_charge'] == null && normalized['serviceCharge'] != null) normalized['service_charge'] = normalized['serviceCharge'];
    if (normalized['payment_method'] == null && normalized['paymentMethod'] != null) normalized['payment_method'] = normalized['paymentMethod'];
    if (normalized['items'] is List) {
      normalized['items'] = (normalized['items'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    }
    return normalized;
  }

  void _cleanupSocket() {
    SocketService.leaveCashier();
    for (final id in _joinedOrderIds) {
      SocketService.leaveOrder(id);
    }
    _joinedOrderIds.clear();
    _disposeOrderUpdated?.call();
    _disposeOrderItemsAdded?.call();
    _disposeOrderCreated?.call();
    _disposeLanOrderCreated?.call();
    _disposeLanOrderItemsAdded?.call();
  }

  void _syncSocketOrderRooms() {
    final activeIds = _orders.map((order) => order.id).toSet();
    for (final id in activeIds.difference(_joinedOrderIds)) {
      SocketService.joinOrder(id);
      _joinedOrderIds.add(id);
    }
    for (final id in _joinedOrderIds.difference(activeIds).toList()) {
      SocketService.leaveOrder(id);
      _joinedOrderIds.remove(id);
    }
  }

  List<WaiterOrder> _filterByFloor(List<WaiterOrder> orders) {
    if (_floorFilter == 'gf') {
      return orders.where(_isGroundFloorOrder).toList();
    } else if (_floorFilter == '2f') {
      return orders.where((o) => !_isGroundFloorOrder(o)).toList();
    }
    return orders;
  }

  Future<void> _settleOrder(WaiterOrder order) async {
    // A negative id means this order only exists as a local temp record —
    // either this device created it offline and hasn't synced yet, or it
    // arrived from another device via LAN broadcast and was never created
    // here at all. Either way, settling it now would queue an update_status
    // action against an id the server has never heard of, which can never
    // resolve once back online (the temp->real id mapping is only ever
    // learned by whichever device actually ran create_order). Block it
    // until the order lands for real — it already shows the "Not synced"
    // badge as the visible cue why.
    if (order.id < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This order hasn\'t synced to the server yet — please wait a moment and try again.',
          ),
          backgroundColor: Color(0xFFD97706),
        ),
      );
      return;
    }

    final settlement = await showModalBottomSheet<SettlementData?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (context) => _SettleOrderSheet(order: order),
    );

    if (settlement == null) return;

    setState(() => _isLoading = true);

    try {
      final result = await ApiService.updateWaiterOrderStatus(
        orderId: order.id,
        status: 1,
        paymentMethod: settlement.paymentMethod,
        discountAmount: settlement.discountAmount,
        grandTotal: settlement.grandTotal,
        amountPaid: settlement.amountPaid,
        paymentRef: settlement.paymentRef,
        remarks: settlement.remarks,
      );

      if (result['success'] == true) {
        await _loadData(showSpinner: false);
        // _loadData no-ops (and leaves _isLoading untouched) if a background
        // poll happens to already be in flight when this call fires — reset
        // it explicitly rather than depending on that call actually having
        // run, or this spinner can get stuck forever until the app restarts.
        if (mounted) {
          setState(() => _isLoading = false);
        }
        if (mounted && _unacknowledgedOrderIds.isEmpty) {
          final isOffline = result['is_offline'] == true;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isOffline
                    ? 'Order settled locally (Offline). Will auto-sync when online.'
                    : 'Order settled successfully',
              ),
              backgroundColor: isOffline ? const Color(0xFFD97706) : Colors.green,
            ),
          );
        }
      } else {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['error'] ?? 'Failed to settle order'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<MenuItem?> _showMenuPicker(BuildContext context) async {
    return showModalBottomSheet<MenuItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (context) => MenuPickerSheet(menuItems: _menuItems),
    );
  }

  Future<List<EditableOrderItem>?> _showEditOrderSheet(
    WaiterOrder order,
    List<EditableOrderItem> editableItems,
  ) async {
    return showModalBottomSheet<List<EditableOrderItem>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (context) {
        return EditOrderBottomSheet(
          title: 'Edit Order',
          subtitle: order.orderNo ?? 'Order #${order.id}',
          menuItems: _menuItems,
          initialItems: editableItems,
          onPickMenuItem: _showMenuPicker,
          onCancel: () {
            Navigator.pop(context);
          },
          onSave: (_) {},
        );
      },
    );
  }

  // Same online-only semantics as waiterApp's edit order (the underlying
  // ApiService.replaceOrderItems has no offline queue support) — editing is
  // a rarer, less time-critical action than creating/adding orders, so this
  // intentionally doesn't get its own offline fallback.
  Future<void> _editOrder(WaiterOrder order) async {
    if (order.id < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This order hasn\'t synced to the server yet — please wait a moment and try again.',
          ),
          backgroundColor: Color(0xFFD97706),
        ),
      );
      return;
    }

    if (_menuItems.isEmpty) {
      final menuResult = await ApiService.getMenuItems();
      if (menuResult['unauthorized'] == true) {
        await _redirectToLogin();
        return;
      }
      if (menuResult['success'] == true) {
        final menuData = List<Map<String, dynamic>>.from(menuResult['data']);
        setState(() {
          _menuItems = menuData.map(MenuItem.fromApi).toList();
        });
      }
    }

    if (_menuItems.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No menu items available to edit this order.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final editableItems = order.items
        .where((item) => item.menuId != null)
        .map((item) => EditableOrderItem(
              menuId: item.menuId!,
              name: item.name,
              quantity: item.quantity,
              unitPrice: item.unitPrice,
              status: item.status,
            ))
        .toList();

    if (editableItems.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No editable items found for this order.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final updatedItems = await _showEditOrderSheet(order, editableItems);

    if (updatedItems == null) return;
    if (updatedItems.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order must have at least one item.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (updatedItems.any((item) => item.menuId == null)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a menu for all items.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final payload = updatedItems.map((item) {
      return {
        'menu_id': item.menuId,
        'qty': item.quantity,
        'unit_price': item.unitPrice,
        'status': item.status,
      };
    }).toList();

    final result = await ApiService.replaceOrderItems(
      orderId: order.id,
      items: payload,
    );

    if (result['unauthorized'] == true) {
      await _redirectToLogin();
      return;
    }

    if (result['success'] == true) {
      await _loadData(showSpinner: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order updated'), backgroundColor: Colors.green),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['error'] ?? 'Failed to update order'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Cancelling reuses the same status-update endpoint Settle already calls
  // (status: -1 instead of 1) — the backend already fully handles it
  // (frees the table, reverses inventory deductions), same as the existing
  // cancel button in the admin web panel.
  Future<void> _cancelOrder(WaiterOrder order) async {
    if (order.id < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This order hasn\'t synced to the server yet — please wait a moment and try again.',
          ),
          backgroundColor: Color(0xFFD97706),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel order?'),
        content: Text('Are you sure you want to cancel ${order.orderNo ?? 'order #${order.id}'}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, cancel'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await ApiService.updateWaiterOrderStatus(
      orderId: order.id,
      status: -1,
    );

    if (result['unauthorized'] == true) {
      await _redirectToLogin();
      return;
    }

    if (result['success'] == true) {
      await _loadData(showSpinner: false);
      if (mounted) {
        final isOffline = result['is_offline'] == true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isOffline ? 'Order cancelled locally (Offline). Will auto-sync when online.' : 'Order cancelled'),
            backgroundColor: isOffline ? const Color(0xFFD97706) : Colors.red,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['error'] ?? 'Failed to cancel order'), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<WaiterOrder> _filterAndSortOrders(List<WaiterOrder> orders) {
    List<WaiterOrder> filtered = orders;
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = orders.where((order) {
        final orderNo = (order.orderNo ?? '#${order.id}').toLowerCase();
        final table = (order.tableNumber?.toString() ?? '').toLowerCase();
        return orderNo.contains(query) || table.contains(query);
      }).toList();
    }

    filtered.sort((a, b) {
      final aPinned = _pinnedOrderIds.contains(a.id);
      final bPinned = _pinnedOrderIds.contains(b.id);
      if (aPinned != bPinned) return aPinned ? -1 : 1;
      return 0;
    });

    return filtered;
  }

  List<WaiterOrder> _filterOrders(List<WaiterOrder> orders) {
    List<WaiterOrder> filtered = orders;
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = orders.where((order) {
        final orderNo = (order.orderNo ?? '#${order.id}').toLowerCase();
        final table = (order.tableNumber?.toString() ?? '').toLowerCase();
        return orderNo.contains(query) || table.contains(query);
      }).toList();
    }

    // Sort by ID descending to show latest at the top
    filtered.sort((a, b) => b.id.compareTo(a.id));

    return filtered;
  }

  void _togglePinOrder(int orderId) {
    setState(() {
      if (_pinnedOrderIds.contains(orderId)) {
        _pinnedOrderIds.remove(orderId);
      } else {
        _pinnedOrderIds.add(orderId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F6F0),
        appBar: AppBar(title: const Text('Cashier App')),
        body: const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0C0E2B)))),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F6F0),
        appBar: AppBar(title: const Text('Cashier App')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 16)),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => _loadData(),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0C0E2B), foregroundColor: Colors.white),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final unsettledOrders = _orders.where((o) => o.status == 2 || o.status == 3).toList();
    final settledOrders = _orders.where((o) => o.status == 1).toList();
    // History tab shows settled AND cancelled orders together (so a
    // cancelled order stays visible instead of vanishing) — kept separate
    // from settledOrders/totalCollected so a cancelled order's total never
    // counts toward collected revenue.
    final historyOrders = _orders.where((o) => o.status == 1 || o.status == -1).toList();
    // Header badges/pills must reflect the same floor scope as the list
    // rendered below them — otherwise a floor-locked cashier sees e.g.
    // "Unsettled: 12" while the cards underneath only show their own floor.
    final scopedUnsettledCount = _filterByFloor(unsettledOrders).length;
    final scopedHistoryCount = _filterByFloor(historyOrders).length;
    final totalCollected = _filterByFloor(settledOrders).fold(0.0, (sum, o) => sum + o.grandTotal);
    final screenWidth = MediaQuery.of(context).size.width;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape || screenWidth >= 800;

    return DefaultTabController(
      length: 2,
      child: Stack(
        children: [
          Scaffold(
            key: _scaffoldKey,
        backgroundColor: const Color(0xFFF5F6F0),
        appBar: AppBar(
          title: Text(
            'cashier_dashboard'.tr,
            style: GoogleFonts.urbanist(
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              fontSize: 18,
              color: const Color(0xFF1A1C18),
            ),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 2,
          actions: [
            ValueListenableBuilder<String?>(
              valueListenable: SoundService.activeAlertTextNotifier,
              builder: (context, activeAlert, _) {
                if (activeAlert == null) return const SizedBox.shrink();
                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: ElevatedButton.icon(
                    onPressed: () => _acknowledgeOrder(),
                    icon: const Icon(Icons.stop_circle_rounded, size: 16, color: Colors.white),
                    label: Text(
                      'Stop Alert',
                      style: GoogleFonts.urbanist(fontWeight: FontWeight.w900, fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      elevation: 2,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                );
              },
            ),
            ValueListenableBuilder<bool>(
              valueListenable: SoundService.isMutedNotifier,
              builder: (context, isMuted, _) {
                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: isMuted
                        ? Colors.grey.withValues(alpha: 0.15)
                        : const Color(0xFFD97706).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    tooltip: isMuted ? 'Sound alerts muted (Click to unmute)' : 'Sound alerts active (Click to mute)',
                    onPressed: () {
                      SoundService.toggleMute();
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 2),
                          content: Text(
                            SoundService.isMuted ? 'Notification sounds muted' : 'Notification sounds enabled',
                          ),
                        ),
                      );
                    },
                    icon: Icon(
                      isMuted ? Icons.notifications_off_rounded : Icons.notifications_active_rounded,
                      color: isMuted ? Colors.grey : const Color(0xFFD97706),
                      size: 20,
                    ),
                  ),
                );
              },
            ),
            Container(
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0C0E2B).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                tooltip: 'Refresh',
                onPressed: _isManualRefreshing ? null : _manualRefresh,
                icon: _isManualRefreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF0C0E2B),
                        ),
                      )
                    : const Icon(Icons.refresh, color: Color(0xFF0C0E2B), size: 20),
              ),
            ),
            Container(
              margin: const EdgeInsets.only(right: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF0C0E2B).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: () async {
                  await showAppSettingsSheet(
                    context: context,
                    onLogout: () async {
                      await ApiService.logout();
                      if (mounted) refreshAppAuth();
                    },
                  );
                },
                icon: const Icon(Icons.settings_rounded, color: Color(0xFF0C0E2B), size: 20),
              ),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(isLandscape ? 58 : 138),
            child: isLandscape
                ? Container(
                    height: 58,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        top: BorderSide(color: Colors.grey.withValues(alpha: 0.08)),
                        bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.12)),
                      ),
                    ),
                    child: Row(
                      children: [
                        // Navigation Tabs
                        SizedBox(
                          width: 250,
                          child: TabBar(
                            labelColor: const Color(0xFF0C0E2B),
                            unselectedLabelColor: Colors.grey.shade500,
                            indicatorColor: const Color(0xFF0C0E2B),
                            indicatorWeight: 3.5,
                            indicatorSize: TabBarIndicatorSize.label,
                            labelStyle: GoogleFonts.urbanist(fontWeight: FontWeight.w900, letterSpacing: 0.8, fontSize: 13),
                            tabs: [
                              Tab(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('unsettled'.tr),
                                    if (scopedUnsettledCount > 0) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0C0E2B),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          '$scopedUnsettledCount',
                                          style: GoogleFonts.urbanist(
                                            color: Colors.white,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Tab(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('history'.tr),
                                    if (scopedHistoryCount > 0) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          '$scopedHistoryCount',
                                          style: GoogleFonts.urbanist(
                                            color: Colors.grey.shade700,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Container(height: 26, width: 1.2, color: Colors.grey.shade200),
                        const SizedBox(width: 14),

                        // Stats pills
                        _buildLandscapeStatPill(
                          label: 'READY TO SETTLE',
                          value: scopedUnsettledCount.toString(),
                          icon: Icons.assignment_turned_in_rounded,
                          color: const Color(0xFF0C0E2B),
                          bgColor: const Color(0xFF0C0E2B).withValues(alpha: 0.07),
                        ),
                        const SizedBox(width: 10),
                        _buildLandscapeStatPill(
                          label: 'COLLECTED',
                          value: '₱${formatPrice(totalCollected)}',
                          icon: Icons.account_balance_wallet_rounded,
                          color: const Color(0xFF059669),
                          bgColor: const Color(0xFF059669).withValues(alpha: 0.08),
                        ),

                        const Spacer(),

                        // Search
                        SizedBox(
                          width: screenWidth > 1150 ? 300 : 230,
                          height: 38,
                          child: _buildSearchTextField(isCompact: true),
                        ),
                      ],
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                        child: Row(
                          children: [
                            _buildQuickStat(
                              label: 'ready_to_settle'.tr,
                              value: scopedUnsettledCount.toString(),
                              icon: Icons.assignment_turned_in_rounded,
                              color: const Color(0xFF0C0E2B),
                              isCompact: true,
                            ),
                            const SizedBox(width: 10),
                            _buildQuickStat(
                              label: 'collected'.tr,
                              value: '₱${formatPrice(totalCollected)}',
                              icon: Icons.account_balance_wallet_rounded,
                              color: const Color(0xFF059669),
                              isCompact: true,
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                        child: SizedBox(
                          height: 38,
                          child: _buildSearchTextField(isCompact: true),
                        ),
                      ),
                      TabBar(
                        labelColor: const Color(0xFF0C0E2B),
                        unselectedLabelColor: Colors.grey,
                        indicatorColor: const Color(0xFF0C0E2B),
                        indicatorWeight: 3.5,
                        indicatorSize: TabBarIndicatorSize.label,
                        labelStyle: GoogleFonts.urbanist(fontWeight: FontWeight.w900, letterSpacing: 1, fontSize: 13),
                        tabs: [
                          Tab(text: 'unsettled'.tr),
                          Tab(text: 'history'.tr),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
        body: Column(
          children: [
            const OfflineSyncBanner(),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFF5F6F0),
                  image: DecorationImage(
                    image: AssetImage('assets/images/menubackground.png'),
                    fit: BoxFit.cover,
                    opacity: 0.15,
                  ),
                ),
                child: TabBarView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    _buildOrderList(_filterAndSortOrders(unsettledOrders), isHistory: false),
                    _buildOrderList(_filterOrders(historyOrders), isHistory: true),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      if (_alertOrdersQueue.isNotEmpty)
        Builder(
          builder: (context) {
            final ordersToDisplay = _alertOrdersQueue.map((queued) {
              final fresh = _orders.firstWhere((o) => o.id == queued.id, orElse: () => queued);
              return fresh.items.isNotEmpty ? fresh : queued;
            }).toList();

            return _CenterOrderAlertModal(
              orders: ordersToDisplay,
              isAddedItems: _alertIsAddedItems,
              onAcknowledgeSingle: (orderId) => _acknowledgeOrder(orderId),
              onAcknowledgeAll: () => _acknowledgeAllOrders(),
            );
          },
        ),
    ],
  ),
);
  }

  Widget _buildLandscapeStatPill({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.18), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.urbanist(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                  color: color.withValues(alpha: 0.75),
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                value,
                style: GoogleFonts.urbanist(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                  color: color,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchTextField({bool isCompact = false}) {
    return TextField(
      controller: _searchController,
      onChanged: (value) {
        setState(() {
          _searchQuery = value;
        });
      },
      decoration: InputDecoration(
        hintText: 'search_hint'.tr,
        hintStyle: GoogleFonts.urbanist(
          color: Colors.grey.shade400,
          fontWeight: FontWeight.w600,
          fontSize: isCompact ? 13 : 15,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: const Color(0xFF0C0E2B).withValues(alpha: 0.6),
          size: isCompact ? 18 : 22,
        ),
        suffixIcon: _searchQuery.isNotEmpty
            ? GestureDetector(
                onTap: () {
                  _searchController.clear();
                  FocusScope.of(context).unfocus();
                  setState(() => _searchQuery = '');
                },
                child: Icon(
                  Icons.clear_rounded,
                  color: Colors.grey.shade400,
                  size: isCompact ? 16 : 20,
                ),
              )
            : null,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: isCompact ? 8 : 14),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(isCompact ? 12 : 22),
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2), width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(isCompact ? 12 : 22),
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2), width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(isCompact ? 12 : 22),
          borderSide: const BorderSide(color: Color(0xFF0C0E2B), width: 1.8),
        ),
      ),
      style: GoogleFonts.urbanist(
        fontSize: isCompact ? 13 : 15,
        fontWeight: FontWeight.w600,
        color: const Color(0xFF1A1C18),
      ),
    );
  }

  Widget _buildQuickStat({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    bool isCompact = false,
  }) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: isCompact ? 6 : 10,
          horizontal: isCompact ? 12 : 16,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(isCompact ? 14 : 24),
          border: Border.all(color: Colors.grey.withOpacity(0.08), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(isCompact ? 6 : 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color.withOpacity(0.15), color.withOpacity(0.08)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: isCompact ? 18 : 24),
            ),
            SizedBox(width: isCompact ? 8 : 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.urbanist(
                      fontSize: isCompact ? 10 : 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      style: GoogleFonts.urbanist(
                        fontSize: isCompact ? 16 : 22,
                        fontWeight: FontWeight.w900,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderList(List<WaiterOrder> orders, {required bool isHistory}) {
    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 80, color: const Color(0xFF0C0E2B).withOpacity(0.2)),
            const SizedBox(height: 16),
            Text(
              isHistory ? 'NO SETTLED ORDERS' : 'NO PENDING SETTLEMENTS',
              style: TextStyle(
                color: const Color(0xFF0C0E2B).withOpacity(0.4),
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    if (isHistory) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
        itemCount: orders.length,
        itemBuilder: (context, index) {
          return _HistoryOrderListItem(
            order: orders[index],
          );
        },
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = screenWidth > 1300 ? 4 : (screenWidth > 950 ? 3 : (screenWidth > 600 ? 2 : 1));
    double spacing = 16;
    double padding = 20;
    double cardWidth = (screenWidth - (padding * 2) - (spacing * (crossAxisCount - 1))) / crossAxisCount;

    final displayOrders = _filterByFloor(orders);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isHistory && _floorScope == null) ...[
            _buildFloorFilterChips(orders),
            const SizedBox(height: 16),
          ],
          if (displayOrders.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 60),
                child: Column(
                  children: [
                    Icon(
                      Icons.table_bar_outlined,
                      size: 64,
                      color: const Color(0xFF0C0E2B).withValues(alpha: 0.2),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No orders in this floor filter',
                      style: GoogleFonts.urbanist(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Wrap(
              spacing: spacing,
              runSpacing: 16,
              children: displayOrders.map((order) {
                return SizedBox(
                  width: cardWidth,
                  child: _AnimatedOrderCard(
                    key: ValueKey('order_${order.id}'),
                    order: order,
                    isHistory: isHistory,
                    tables: _tables,
                    menuItems: _menuItems,
                    isGroundFloor: _isGroundFloorOrder(order),
                    onSettle: () => _settleOrder(order),
                    onEdit: () => _editOrder(order),
                    onCancel: () => _cancelOrder(order),
                    isPinned: _pinnedOrderIds.contains(order.id),
                    onPin: () => _togglePinOrder(order.id),
                    onRefresh: () => _loadData(showSpinner: false),
                    isUnacknowledged: _unacknowledgedOrderIds.contains(order.id),
                    onAcknowledge: () => _acknowledgeOrder(order.id),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildFloorFilterChips(List<WaiterOrder> allUnsettledOrders) {
    final allCount = allUnsettledOrders.length;
    final gfCount = allUnsettledOrders.where(_isGroundFloorOrder).length;
    final secondFloorCount = allUnsettledOrders.where((o) => !_isGroundFloorOrder(o)).length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildFloorChip(key: 'all', label: 'All Floors', count: allCount, icon: Icons.table_bar_rounded),
          _buildFloorChip(key: 'gf', label: 'Ground Floor', count: gfCount, icon: Icons.storefront_rounded),
          _buildFloorChip(key: '2f', label: '2nd Floor', count: secondFloorCount, icon: Icons.stairs_rounded),
        ],
      ),
    );
  }

  Widget _buildFloorChip({
    required String key,
    required String label,
    required int count,
    required IconData icon,
  }) {
    final isSelected = _floorFilter == key;
    const navy = Color(0xFF0C0E2B);
    return Container(
      margin: const EdgeInsets.only(right: 10),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: () => setState(() => _floorFilter = key),
          borderRadius: BorderRadius.circular(24),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: isSelected
                  ? const LinearGradient(colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)])
                  : null,
              color: isSelected ? null : Colors.white,
              border: Border.all(
                color: isSelected ? navy : Colors.grey.shade300,
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: isSelected ? navy.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: isSelected ? const Color(0xFFE8C468) : Colors.grey.shade700),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: GoogleFonts.urbanist(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : Colors.grey.shade800,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white.withValues(alpha: 0.2) : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: GoogleFonts.urbanist(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryOrderListItem extends StatefulWidget {
  final WaiterOrder order;

  const _HistoryOrderListItem({required this.order});

  @override
  State<_HistoryOrderListItem> createState() => _HistoryOrderListItemState();
}

class _HistoryOrderListItemState extends State<_HistoryOrderListItem> {
  bool _isExpanded = false;

  String _formatOrderDateTime(DateTime? dt, String? orderNo) {
    final gmt8 = widget.order.gmt8DateTime;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final month = months[gmt8.month - 1];
    final day = gmt8.day.toString().padLeft(2, '0');
    final year = gmt8.year;
    final hour12 = gmt8.hour == 0 ? 12 : (gmt8.hour > 12 ? gmt8.hour - 12 : gmt8.hour);
    final minute = gmt8.minute.toString().padLeft(2, '0');
    final second = gmt8.second.toString().padLeft(2, '0');
    final period = gmt8.hour >= 12 ? 'PM' : 'AM';

    final nowGmt8 = DateTime.now().toUtc().add(const Duration(hours: 8));
    final isToday = gmt8.year == nowGmt8.year && gmt8.month == nowGmt8.month && gmt8.day == nowGmt8.day;
    final prefix = isToday ? 'Today' : '$month $day, $year';
    return '$prefix  •  $hour12:$minute:$second $period';
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0C0E2B);
    const emeraldColor = Color(0xFF059669);
    final order = widget.order;
    final isCancelled = order.status == -1;
    final statusColor = isCancelled ? Colors.red.shade700 : emeraldColor;
    final isCash = (order.paymentMethod ?? 'CASH').toUpperCase() == 'CASH';
    final effectivePaid = order.amountPaid > 0 ? order.amountPaid : order.grandTotal;
    final changeAmount = (effectivePaid - order.grandTotal).clamp(0.0, double.infinity);

    final rawTableName = (order.tableNumber ?? '').trim();
    final tableDisplay = rawTableName.isEmpty
        ? 'Dine-In'
        : (rawTableName.toLowerCase().startsWith('table') ? rawTableName : 'Table $rawTableName');

    final items = order.items;
    final displayItems = _isExpanded ? items : items.take(4).toList();
    final hasMoreItems = items.length > 4;

    final subtotal = order.subtotal > 0
        ? order.subtotal
        : (order.grandTotal - order.serviceCharge + order.discountAmount);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. TOP HEADER
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: emeraldColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.receipt_long_rounded, color: emeraldColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              order.orderNo ?? '#${order.id}',
                              style: GoogleFonts.urbanist(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF0F172A),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(isCancelled ? Icons.cancel_rounded : Icons.check_circle_rounded, size: 11, color: statusColor),
                                const SizedBox(width: 4),
                                Text(
                                  isCancelled ? 'CANCELLED' : 'SETTLED',
                                  style: GoogleFonts.urbanist(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w900,
                                    color: statusColor,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          OfflineOrderBadge(orderId: order.id),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.schedule_rounded, size: 13, color: Colors.grey.shade500),
                          const SizedBox(width: 5),
                          Text(
                            _formatOrderDateTime(order.encodedDt, order.orderNo),
                            style: GoogleFonts.urbanist(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Table badge & order type
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.chair_alt_rounded, size: 13, color: primaryColor),
                          const SizedBox(width: 5),
                          Text(
                            tableDisplay,
                            style: GoogleFonts.urbanist(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (order.orderType != null && order.orderType!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        order.orderType!.toUpperCase(),
                        style: GoogleFonts.urbanist(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey.shade500,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFF1F5F9)),

          // 2. ITEMIZED BREAKDOWN
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'ORDERED ITEMS (${items.length})',
                      style: GoogleFonts.urbanist(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.grey.shade500,
                        letterSpacing: 1.2,
                      ),
                    ),
                    if (order.encodedByName != null && order.encodedByName!.trim().isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_outline_rounded, size: 12, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(
                            'Server: ${order.encodedByName}',
                            style: GoogleFonts.urbanist(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                // Items list
                ...displayItems.map((item) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            '${item.quantity.toInt()}x',
                            style: GoogleFonts.urbanist(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: primaryColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  item.name,
                                  style: GoogleFonts.urbanist(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF1E293B),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (item.remarks != null && item.remarks!.trim().isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '(${item.remarks})',
                                  style: GoogleFonts.urbanist(
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '₱${formatPrice(item.lineTotal)}',
                          style: GoogleFonts.urbanist(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0D9488),
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                if (order.serviceCharge > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'ROOM',
                            style: GoogleFonts.urbanist(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFFD97706),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Room Charge',
                            style: GoogleFonts.urbanist(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '₱${formatPrice(order.serviceCharge)}',
                          style: GoogleFonts.urbanist(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFFD97706),
                          ),
                        ),
                      ],
                    ),
                  ),

                if (hasMoreItems)
                  GestureDetector(
                    onTap: () => setState(() => _isExpanded = !_isExpanded),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 2),
                      child: Row(
                        children: [
                          Text(
                            _isExpanded
                                ? 'Show less'
                                : '+ ${items.length - 4} more items (Tap to show all)',
                            style: GoogleFonts.urbanist(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF2563EB),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                            size: 14,
                            color: const Color(0xFF2563EB),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFF1F5F9)),

          // 3. FINANCIAL SUMMARY & SETTLEMENT FOOTER
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: const BoxDecoration(
              color: Color(0xFFFAFAFA),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Financial breakdown pills
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Subtotal: ₱${formatPrice(subtotal)}',
                          style: GoogleFonts.urbanist(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        if (order.discountAmount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.local_offer_rounded, size: 10.5, color: Colors.red.shade700),
                                const SizedBox(width: 3),
                                Text(
                                  'Disc: -₱${formatPrice(order.discountAmount)}',
                                  style: GoogleFonts.urbanist(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        // Tendered / Amount Paid Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: primaryColor.withValues(alpha: 0.15)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isCash ? Icons.payments_rounded : Icons.account_balance_wallet_rounded,
                                size: 12,
                                color: primaryColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isCash ? 'Tendered: ₱${formatPrice(effectivePaid)}' : 'Paid: ₱${formatPrice(effectivePaid)}',
                                style: GoogleFonts.urbanist(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: primaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Change Badge (Highlighted in green with icon)
                        if (changeAmount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: emeraldColor.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: emeraldColor.withValues(alpha: 0.35)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.change_circle_rounded, size: 13, color: emeraldColor),
                                const SizedBox(width: 4),
                                Text(
                                  'Change: ₱${formatPrice(changeAmount)}',
                                  style: GoogleFonts.urbanist(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w900,
                                    color: emeraldColor,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        if (!isCash && order.paymentRef != null && order.paymentRef!.trim().isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Text(
                              'Ref: ${order.paymentRef}',
                              style: GoogleFonts.urbanist(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                      ],
                    ),

                    // Grand total
                    Row(
                      children: [
                        Text(
                          'TOTAL PAID: ',
                          style: GoogleFonts.urbanist(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            color: Colors.grey.shade500,
                            letterSpacing: 0.6,
                          ),
                        ),
                        Text(
                          '₱${formatPrice(order.grandTotal)}',
                          style: GoogleFonts.urbanist(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Actions & Payment Method row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (order.paymentMethod != null)
                      _buildPaymentMethodBadge(order.paymentMethod!)
                    else
                      const SizedBox.shrink(),

                    // View Receipt button
                    SizedBox(
                      height: 34,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          BillOutModal.show(
                            context,
                            order: order,
                            onSettle: () {},
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primaryColor,
                          side: BorderSide(color: Colors.grey.shade300, width: 1.2),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.receipt_long_rounded, size: 14),
                        label: Text(
                          'View Statement / Receipt',
                          style: GoogleFonts.urbanist(fontSize: 12, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CenterOrderAlertModal extends StatefulWidget {
  final List<WaiterOrder> orders;
  final bool isAddedItems;
  final void Function(int orderId) onAcknowledgeSingle;
  final VoidCallback onAcknowledgeAll;

  const _CenterOrderAlertModal({
    required this.orders,
    this.isAddedItems = false,
    required this.onAcknowledgeSingle,
    required this.onAcknowledgeAll,
  });

  @override
  State<_CenterOrderAlertModal> createState() => _CenterOrderAlertModalState();
}

class _CenterOrderAlertModalState extends State<_CenterOrderAlertModal>
    with SingleTickerProviderStateMixin {
  static const primaryColor = Color(0xFF0C0E2B);
  static const secondaryColor = Color(0xFF1B1E4A);
  static const goldAccent = Color(0xFFFBBF24);
  static const amberAccent = Color(0xFFD97706);

  late final AnimationController _bellController;
  late final Animation<double> _bellAnimation;

  @override
  void initState() {
    super.initState();
    _bellController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..repeat(reverse: true);

    // Realistic ringing swing: swings from -0.22 radians to +0.22 radians (approx -13 deg to +13 deg)
    _bellAnimation = Tween<double>(begin: -0.22, end: 0.22).animate(
      CurvedAnimation(parent: _bellController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _bellController.dispose();
    super.dispose();
  }

  String _formatTableForDisplay(String? rawTable, String? orderType) {
    final clean = (rawTable ?? '').trim();
    if (clean.isEmpty) {
      final type = (orderType ?? 'Table').trim();
      return type.toLowerCase().contains('table') ? type : 'Table $type';
    }
    final lower = clean.toLowerCase();
    if (lower.startsWith('table') || lower.startsWith('room') || lower.startsWith('vip') || lower.startsWith('bar')) {
      return clean;
    }
    return 'Table $clean';
  }

  @override
  Widget build(BuildContext context) {
    final isMulti = widget.orders.length > 1;

    return Material(
      color: Colors.black.withValues(alpha: 0.6),
      child: Center(
        child: Container(
          width: isMulti ? 440 : 390,
          constraints: BoxConstraints(
            maxWidth: isMulti ? 480 : 420,
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: primaryColor.withValues(alpha: 0.25), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 36,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: goldAccent.withValues(alpha: 0.18),
                blurRadius: 24,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Navy Header Bar with Animated Ringing Bell
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [primaryColor, secondaryColor],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    // Animated Ringing Bell Badge
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: AnimatedBuilder(
                        animation: _bellAnimation,
                        builder: (context, child) {
                          return Transform.rotate(
                            angle: _bellAnimation.value,
                            alignment: Alignment.topCenter,
                            child: child,
                          );
                        },
                        child: const Icon(
                          Icons.notifications_active_rounded,
                          color: goldAccent,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isMulti
                                ? '${widget.orders.length} NEW ORDERS RECEIVED!'
                                : (widget.isAddedItems ? 'ORDER UPDATED' : 'NEW ORDER RECEIVED!'),
                            style: GoogleFonts.urbanist(
                              color: goldAccent,
                              fontWeight: FontWeight.w900,
                              fontSize: isMulti ? 14 : 13,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isMulti
                                ? 'Orders pending across ${widget.orders.length} tables'
                                : (widget.orders.first.orderNo ?? '#${widget.orders.first.id}'),
                            style: GoogleFonts.urbanist(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isMulti)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: goldAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: goldAccent.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          '${widget.orders.length} PENDING',
                          style: GoogleFonts.urbanist(
                            color: goldAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // 2. Body Section
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: isMulti
                      ? _buildMultiOrdersView(context)
                      : _buildSingleOrderView(context, widget.orders.first),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- SINGLE ORDER VIEW ---
  Widget _buildSingleOrderView(
    BuildContext context,
    WaiterOrder order,
  ) {
    final tableDisplay = _formatTableForDisplay(order.tableNumber, order.orderType);
    final totalStr = formatPrice(order.grandTotal);
    final items = order.items;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Table Display Badge
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.table_restaurant_rounded, color: goldAccent, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'TABLE / ROOM',
                    style: GoogleFonts.urbanist(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade600,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
              Text(
                tableDisplay,
                style: GoogleFonts.urbanist(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: primaryColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Section Header: Order Items
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ORDER ITEMS',
                style: GoogleFonts.urbanist(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade600,
                  letterSpacing: 0.8,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  order.serviceCharge > 0 ? '${items.length} items + Room' : '${items.length} items',
                  style: GoogleFonts.urbanist(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),

        // Order Items List
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxHeight: 230),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: Text(
                        'No items in order',
                        style: GoogleFonts.urbanist(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const ClampingScrollPhysics(),
                    itemCount: items.length + (order.serviceCharge > 0 ? 1 : 0),
                    separatorBuilder: (context, index) => Divider(
                      height: 8,
                      thickness: 0.6,
                      color: Colors.grey.shade200,
                    ),
                    itemBuilder: (context, index) {
                      if (index < items.length) {
                        final item = items[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: primaryColor.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${item.quantity.toInt()}x',
                                  style: GoogleFonts.urbanist(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: primaryColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
                                      style: GoogleFonts.urbanist(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF1E293B),
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (item.remarks != null && item.remarks!.trim().isNotEmpty)
                                      Text(
                                        item.remarks!.trim(),
                                        style: GoogleFonts.urbanist(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey.shade500,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '₱${formatPrice(item.lineTotal)}',
                                style: GoogleFonts.urbanist(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF0D9488),
                                ),
                              ),
                            ],
                          ),
                        );
                      } else {
                        // Room Charge row
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'ROOM',
                                  style: GoogleFonts.urbanist(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFFD97706),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Room Charge',
                                  style: GoogleFonts.urbanist(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF1E293B),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '₱${formatPrice(order.serviceCharge)}',
                                style: GoogleFonts.urbanist(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFFD97706),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                    },
                  ),
          ),
        ),
        const SizedBox(height: 10),

        // Total Amount Row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    'TOTAL DUE',
                    style: GoogleFonts.urbanist(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: Colors.grey.shade500,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      order.serviceCharge > 0 ? '${items.length} items + Room' : '${items.length} items',
                      style: GoogleFonts.urbanist(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                '₱$totalStr',
                style: GoogleFonts.urbanist(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: amberAccent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Acknowledge Button
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton.icon(
            onPressed: widget.onAcknowledgeAll,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.check_circle_rounded, color: goldAccent, size: 18),
            label: Text(
              'Acknowledge',
              style: GoogleFonts.urbanist(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- MULTI-ORDERS VIEW ---
  Widget _buildMultiOrdersView(
    BuildContext context,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Scrollable list of order cards
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxHeight: 380),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const ClampingScrollPhysics(),
              itemCount: widget.orders.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final order = widget.orders[index];
                final tableDisplay = _formatTableForDisplay(order.tableNumber, order.orderType);
                final orderNo = order.orderNo ?? '#${order.id}';
                final items = order.items;

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: Table badge and order number
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: primaryColor.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(Icons.table_restaurant_rounded, color: goldAccent, size: 16),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                tableDisplay,
                                style: GoogleFonts.urbanist(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: primaryColor,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Text(
                              orderNo,
                              style: GoogleFonts.urbanist(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Items list preview
                      if (items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            'Order received',
                            style: GoogleFonts.urbanist(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        )
                      else
                        ...items.take(4).map((item) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: primaryColor.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${item.quantity.toInt()}x',
                                    style: GoogleFonts.urbanist(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      color: primaryColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    item.name,
                                    style: GoogleFonts.urbanist(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF1E293B),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '₱${formatPrice(item.lineTotal)}',
                                  style: GoogleFonts.urbanist(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0D9488),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      if (items.length > 4)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '+ ${items.length - 4} more items',
                            style: GoogleFonts.urbanist(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade500,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      if (order.serviceCharge > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'ROOM',
                                  style: GoogleFonts.urbanist(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFFD97706),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Room Charge',
                                  style: GoogleFonts.urbanist(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF1E293B),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '₱${formatPrice(order.serviceCharge)}',
                                style: GoogleFonts.urbanist(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFFD97706),
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 6),
                      Divider(height: 8, thickness: 0.6, color: Colors.grey.shade200),
                      const SizedBox(height: 4),

                      // Subtotal & Individual Acknowledge Button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(
                                'DUE: ',
                                style: GoogleFonts.urbanist(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                              Text(
                                '₱${formatPrice(order.grandTotal)}',
                                style: GoogleFonts.urbanist(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: amberAccent,
                                ),
                              ),
                            ],
                          ),
                          OutlinedButton.icon(
                            onPressed: () => widget.onAcknowledgeSingle(order.id),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: primaryColor,
                              side: BorderSide(color: primaryColor.withValues(alpha: 0.25)),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: const Size(0, 30),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.check_rounded, size: 13, color: amberAccent),
                            label: Text(
                              'Acknowledge',
                              style: GoogleFonts.urbanist(fontSize: 11, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Primary Action: Acknowledge All
        SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton.icon(
            onPressed: widget.onAcknowledgeAll,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.done_all_rounded, color: goldAccent, size: 20),
            label: Text(
              'Acknowledge All (${widget.orders.length} Orders)',
              style: GoogleFonts.urbanist(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AnimatedOrderCard extends StatefulWidget {
  final WaiterOrder order;
  final bool isHistory;
  final VoidCallback onSettle;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final bool isGroundFloor;
  final bool isPinned;
  final VoidCallback onPin;
  final Future<void> Function() onRefresh;
  final List<WaiterTable> tables;
  final List<MenuItem> menuItems;
  final bool isUnacknowledged;
  final VoidCallback? onAcknowledge;

  const _AnimatedOrderCard({
    super.key,
    required this.order,
    required this.isHistory,
    required this.onSettle,
    required this.onEdit,
    required this.onCancel,
    required this.isGroundFloor,
    required this.isPinned,
    required this.onPin,
    required this.onRefresh,
    required this.tables,
    required this.menuItems,
    this.isUnacknowledged = false,
    this.onAcknowledge,
  });

  @override
  State<_AnimatedOrderCard> createState() => _AnimatedOrderCardState();
}

class _AnimatedOrderCardState extends State<_AnimatedOrderCard> {
  bool _isHovered = false;

  // Base per-session room-charge rate for this order's table. Used to break
  // down the room-charge total on the card so the cashier/customer can see
  // WHY it's ₱6,000 (e.g. ₱1,500 × 4) instead of being surprised by it once
  // a waiter has extended the room charge one or more times. Comes on the
  // order payload; falls back to the tables list if an older payload omits it.
  double get _roomChargeRate {
    if (widget.order.roomCharge > 0) return widget.order.roomCharge;
    final tid = widget.order.tableId;
    if (tid == null) return 0;
    for (final t in widget.tables) {
      if (t.id == tid) return t.roomCharge;
    }
    return 0;
  }

  // How many room-charge units the current service charge represents, when
  // it divides evenly into the base rate (in 0.5 steps, to match the
  // half-session qty admin's manual order can create); null when it doesn't
  // (e.g. an extra manual service charge was mixed in) so we just show the total.
  double? get _roomChargeUnits {
    final rate = _roomChargeRate;
    final total = widget.order.serviceCharge;
    if (rate <= 0 || total <= 0) return null;
    final q = total / rate;
    final rounded = (q * 2).round() / 2;
    if (rounded >= 0.5 && (q - rounded).abs() < 0.01) return rounded;
    return null;
  }

  String _formatRoomChargeUnits(double v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0C0E2B);
    const secondaryColor = Color(0xFF1B1E4A);

    final rawTableName = (widget.order.tableNumber ?? '').trim();
    String tableLabel = 'Table';
    String roomOrNumber = rawTableName;
    if (roomOrNumber.toLowerCase().startsWith('table')) {
      roomOrNumber = roomOrNumber.substring(5).trim();
    }
    if (roomOrNumber.isEmpty) {
      tableLabel = 'Type';
      roomOrNumber = widget.order.orderType ?? 'Dine-In';
    }

    final items = widget.order.items;
    final previewItems = items.take(3).toList();
    final remainingCount = items.length - previewItems.length;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        transform: _isHovered ? (Matrix4.identity()..translate(0, -3, 0)) : Matrix4.identity(),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: widget.isUnacknowledged
                ? const Color(0xFFDC2626)
                : (widget.isPinned
                    ? const Color(0xFFD97706)
                    : (_isHovered ? primaryColor.withValues(alpha: 0.4) : const Color(0xFFE2E8F0))),
            width: widget.isUnacknowledged ? 2.5 : (widget.isPinned ? 2 : 1.2),
          ),
          boxShadow: [
            BoxShadow(
              color: widget.isUnacknowledged
                  ? const Color(0xFFDC2626).withValues(alpha: 0.25)
                  : (widget.isPinned
                      ? const Color(0xFFD97706).withValues(alpha: 0.15)
                      : (_isHovered ? Colors.black.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.03))),
              blurRadius: widget.isUnacknowledged ? 18 : (_isHovered ? 16 : 8),
              offset: Offset(0, _isHovered ? 6 : 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 0. Active Repeating Voice Announcement Alert Banner
            if (widget.isUnacknowledged)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFDC2626), Color(0xFFB91C1C)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.volume_up_rounded, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'NEW ORDER ALERT',
                        style: GoogleFonts.urbanist(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: widget.onAcknowledge,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_rounded, color: Color(0xFFDC2626), size: 13),
                            const SizedBox(width: 4),
                            Text(
                              'Acknowledge',
                              style: GoogleFonts.urbanist(
                                color: const Color(0xFFDC2626),
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // 1. Sleek Compact Header (2-Line Table Name)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [primaryColor, secondaryColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: widget.isUnacknowledged
                    ? BorderRadius.zero
                    : const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.table_restaurant_rounded, color: Color(0xFFFBBF24), size: 16),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Line 1: Table Label & Order No
                        Row(
                          children: [
                            Text(
                              tableLabel,
                              style: GoogleFonts.urbanist(
                                color: const Color(0xFFFBBF24), // Distinct Gold / Amber color for "Table"
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '•',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                widget.order.orderNo ?? '#${widget.order.id}',
                                style: GoogleFonts.urbanist(
                                  color: Colors.white60,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                  letterSpacing: 0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 1),
                        // Line 2: Room / Table Number
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                roomOrNumber,
                                style: GoogleFonts.urbanist(
                                  color: Colors.white, // Crisp White for the room/number
                                  fontWeight: FontWeight.w900,
                                  fontSize: 17,
                                  letterSpacing: 0.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                widget.isGroundFloor ? 'GF' : '2F',
                                style: GoogleFonts.urbanist(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 10,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            if (!widget.isHistory) ...[
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: widget.onPin,
                                borderRadius: BorderRadius.circular(6),
                                child: Icon(
                                  widget.isPinned ? Icons.star_rounded : Icons.star_border_rounded,
                                  color: widget.isPinned ? const Color(0xFFFBBF24) : Colors.white38,
                                  size: 17,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildStatusChip(widget.order.status),
                      const SizedBox(height: 4),
                      OfflineOrderBadge(orderId: widget.order.id),
                    ],
                  ),
                ],
              ),
            ),

            // 2. Compact Items Summary (Max 3 items preview)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No items in order',
                        style: GoogleFonts.urbanist(fontSize: 13, color: Colors.grey.shade400, fontStyle: FontStyle.italic),
                      ),
                    )
                  else ...[
                    ...previewItems.map((item) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: primaryColor.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${item.quantity.toInt()}x',
                                style: GoogleFonts.urbanist(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w900,
                                  color: primaryColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.name,
                                style: GoogleFonts.urbanist(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF1E293B),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '₱${formatPrice(item.lineTotal)}',
                              style: GoogleFonts.urbanist(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0D9488), // Distinct Teal/Emerald color for item prices
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    if (widget.order.serviceCharge > 0)
                      Builder(
                        builder: (context) {
                          const gold = Color(0xFFD97706);
                          final rate = _roomChargeRate;
                          final units = _roomChargeUnits;
                          final showBreakdown = rate > 0 && units != null && units >= 1;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: gold.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'ROOM',
                                    style: GoogleFonts.urbanist(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      color: gold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              'Room Charge',
                                              style: GoogleFonts.urbanist(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w800,
                                                color: gold,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (showBreakdown && units > 1) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: gold.withValues(alpha: 0.14),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                '×${_formatRoomChargeUnits(units)}',
                                                style: GoogleFonts.urbanist(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w900,
                                                  color: gold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      if (showBreakdown)
                                        Text(
                                          units > 1
                                              ? 'Base ₱${formatPrice(rate)} + ${_formatRoomChargeUnits(units - 1)} extension${units - 1 == 1 ? '' : 's'} (₱${formatPrice(rate)} × ${_formatRoomChargeUnits(units)})'
                                              : 'Base rate ₱${formatPrice(rate)}',
                                          style: GoogleFonts.urbanist(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey.shade500,
                                          ),
                                          maxLines: 2,
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '₱${formatPrice(widget.order.serviceCharge)}',
                                  style: GoogleFonts.urbanist(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: gold,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    if (remainingCount > 0)
                      InkWell(
                        onTap: () {
                          BillOutModal.show(
                            context,
                            order: widget.order,
                            onSettle: widget.onSettle,
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2, bottom: 2),
                          child: Row(
                            children: [
                              Text(
                                '+ $remainingCount more items',
                                style: GoogleFonts.urbanist(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF2563EB),
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.arrow_forward_ios_rounded, size: 10, color: Color(0xFF2563EB)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),

            const Divider(height: 1, color: Color(0xFFF1F5F9)),

            // 3. Compact Total & Action Row (1-Row Design)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            'TOTAL DUE',
                            style: GoogleFonts.urbanist(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: Colors.grey.shade500,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              widget.order.serviceCharge > 0
                                  ? '${items.length} items + Room'
                                  : '${items.length} items',
                              style: GoogleFonts.urbanist(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '₱${formatPrice(widget.order.grandTotal)}',
                        style: GoogleFonts.urbanist(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFFD97706), // Distinct vibrant Amber/Gold for TOTAL DUE
                        ),
                      ),
                    ],
                  ),
                  if (!widget.isHistory) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        // Transfer Table (Lipat Mesa)
                        if (widget.order.tableId != null) ...[
                          SizedBox(
                            height: 36,
                            width: 36,
                            child: OutlinedButton(
                              onPressed: () async {
                                final rawName = (widget.order.tableNumber ?? '').trim();
                                final currentName = rawName.isEmpty
                                    ? (widget.order.orderType ?? 'Dine-In')
                                    : (rawName.toLowerCase().startsWith('table')
                                        ? rawName
                                        : 'Table $rawName');
                                final transferred = await showTransferTableModal(
                                  context: context,
                                  orderId: widget.order.id,
                                  currentTableName: currentName,
                                  currentTableId: widget.order.tableId,
                                  allTables: widget.tables,
                                );
                                if (transferred == true && mounted) {
                                  await widget.onRefresh();
                                }
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: primaryColor,
                                side: BorderSide(color: Colors.grey.shade300),
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Icon(Icons.swap_horiz_rounded, size: 18),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        // Bill Out
                        Expanded(
                          flex: 1,
                          child: SizedBox(
                            height: 36,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                BillOutModal.show(
                                  context,
                                  order: widget.order,
                                  onSettle: widget.onSettle,
                                );
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: primaryColor,
                                side: BorderSide(color: Colors.grey.shade300),
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.receipt_long_outlined, size: 14),
                              label: Text(
                                'Bill Out',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.urbanist(fontWeight: FontWeight.w800, fontSize: 12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Add Items
                        Expanded(
                          flex: 1,
                          child: SizedBox(
                            height: 36,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                WaiterTable targetTable;
                                final found = widget.tables.where((t) => t.id == widget.order.tableId).toList();
                                if (found.isNotEmpty) {
                                  targetTable = found.first;
                                } else {
                                  targetTable = WaiterTable(
                                    id: widget.order.tableId ?? 0,
                                    number: widget.order.tableNumber ?? 'Dine-In',
                                    capacity: 4,
                                    status: 2,
                                  );
                                }
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => waiter_order.GetOrderPage(
                                      table: targetTable,
                                      menuItems: widget.menuItems,
                                      existingOrder: widget.order,
                                    ),
                                  ),
                                );
                                if (mounted) await widget.onRefresh();
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: primaryColor,
                                side: BorderSide(color: Colors.grey.shade300),
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.add_rounded, size: 15),
                              label: Text(
                                'Add',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.urbanist(fontWeight: FontWeight.w800, fontSize: 12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Edit
                        Expanded(
                          flex: 1,
                          child: SizedBox(
                            height: 36,
                            child: OutlinedButton.icon(
                              onPressed: widget.onEdit,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: primaryColor,
                                side: BorderSide(color: Colors.grey.shade300),
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.edit_outlined, size: 14),
                              label: Text(
                                'Edit',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.urbanist(fontWeight: FontWeight.w800, fontSize: 12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Settle
                        Expanded(
                          flex: 1,
                          child: SizedBox(
                            height: 36,
                            child: ElevatedButton.icon(
                              onPressed: widget.onSettle,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.zero,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.payments_rounded, size: 15),
                              label: Text(
                                'Settle',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.urbanist(fontWeight: FontWeight.w900, fontSize: 12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
        ),
        // Circular X button floating at the top-right corner, matching
        // waiterApp's table-card cancel button — only for active orders.
        if (!widget.isHistory)
          Positioned(
            top: -8,
            right: -8,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 3,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: widget.onCancel,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Icon(Icons.close_rounded, size: 16, color: Colors.red.shade700),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SettleOrderSheet extends StatefulWidget {
  final WaiterOrder order;
  const _SettleOrderSheet({required this.order});
  @override
  State<_SettleOrderSheet> createState() => _SettleOrderSheetState();
}

class _SettleOrderSheetState extends State<_SettleOrderSheet> {
  String _selectedPaymentMethod = 'CASH';
  final TextEditingController _discountController = TextEditingController();
  final TextEditingController _tenderedController = TextEditingController();
  final TextEditingController _refController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();

  double _manualDiscount = 0.0;
  double _cashTendered = 0.0;

  // How many room-charge units the service charge represents, when it divides
  // evenly into the table's base ROOM_CHARGE (in 0.5 steps, to match the
  // half-session qty admin's manual order can create); null otherwise. Lets
  // the sheet spell out WHY the room charge total is what it is after
  // extensions.
  double? get _roomChargeUnits {
    final rate = widget.order.roomCharge;
    final total = widget.order.serviceCharge;
    if (rate <= 0 || total <= 0) return null;
    final q = total / rate;
    final rounded = (q * 2).round() / 2;
    if (rounded >= 0.5 && (q - rounded).abs() < 0.01) return rounded;
    return null;
  }

  String _formatRoomChargeUnits(double v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  void initState() {
    super.initState();
    _discountController.addListener(_onDiscountChanged);
    _tenderedController.addListener(_onTenderedChanged);
  }

  void _onDiscountChanged() {
    final val = double.tryParse(_discountController.text.trim()) ?? 0.0;
    setState(() {
      _manualDiscount = val > 0 ? val : 0.0;
    });
  }

  void _onTenderedChanged() {
    final val = double.tryParse(_tenderedController.text.trim()) ?? 0.0;
    setState(() {
      _cashTendered = val > 0 ? val : 0.0;
    });
  }

  @override
  void dispose() {
    _discountController.dispose();
    _tenderedController.dispose();
    _refController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0C0E2B);
    const secondaryColor = Color(0xFF1B1E4A);
    const emerald = Color(0xFF059669);
    const gold = Color(0xFFD97706);

    final itemsSubtotal = widget.order.items.fold<double>(0, (sum, it) => sum + it.lineTotal);
    final roomCharge = widget.order.serviceCharge;
    final itemsBase = itemsSubtotal > 0 ? itemsSubtotal : (widget.order.subtotal > 0 ? widget.order.subtotal : (widget.order.grandTotal - roomCharge));
    final totalBeforeDiscount = itemsBase + roomCharge;
    final effectiveDiscount = _manualDiscount.clamp(0.0, totalBeforeDiscount);
    final finalAmountDue = (totalBeforeDiscount - effectiveDiscount).clamp(0.0, double.infinity);
    final isCash = _selectedPaymentMethod == 'CASH';
    final hasTendered = _cashTendered > 0;
    final isInsufficient = hasTendered && _cashTendered < finalAmountDue;
    final isMissingTendered = !hasTendered;
    final canComplete = hasTendered && (_cashTendered >= finalAmountDue);
    final change = _cashTendered - finalAmountDue;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
      decoration: const BoxDecoration(
        color: Color(0xFFF5F6F0),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sheet Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [primaryColor, secondaryColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ORDER SETTLEMENT',
                            style: GoogleFonts.urbanist(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.order.orderNo ?? '#${widget.order.id}',
                            style: GoogleFonts.urbanist(
                              fontSize: 15,
                              color: const Color(0xFFE8C468),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.chair_alt_rounded, color: Colors.white, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                widget.order.tableNumber != null ? 'Table ${widget.order.tableNumber}' : 'Dine-In',
                                style: GoogleFonts.urbanist(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.of(context).pop(null),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                              ),
                              child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Scrollable Body
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. BILL ITEMS SUMMARY
                  Text(
                    roomCharge > 0
                        ? 'BILL ITEMS (${widget.order.items.length}) + ROOM CHARGE'
                        : 'BILL ITEMS (${widget.order.items.length})',
                    style: GoogleFonts.urbanist(fontSize: 12.5, fontWeight: FontWeight.w900, color: Colors.grey.shade600, letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.withOpacity(0.15)),
                    ),
                    child: Column(
                      children: [
                        ...widget.order.items.map((item) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Text(
                                '${item.quantity % 1 == 0 ? item.quantity.toInt() : item.quantity}x',
                                style: GoogleFonts.urbanist(fontWeight: FontWeight.w900, color: primaryColor, fontSize: 14.5),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item.name,
                                  style: GoogleFonts.urbanist(fontSize: 14.5, fontWeight: FontWeight.w700, color: const Color(0xFF1A1C18)),
                                ),
                              ),
                              Text(
                                '₱${formatPrice(item.lineTotal)}',
                                style: GoogleFonts.urbanist(fontSize: 14.5, fontWeight: FontWeight.w800, color: const Color(0xFF1A1C18)),
                              ),
                            ],
                          ),
                        )),
                        if (roomCharge > 0) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFD97706).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'ROOM',
                                    style: GoogleFonts.urbanist(fontWeight: FontWeight.w900, color: const Color(0xFFD97706), fontSize: 11.5),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _roomChargeUnits != null && _roomChargeUnits! > 1
                                            ? 'Room Charge (${widget.order.tableNumber ?? 'VIP Room'})  ×${_formatRoomChargeUnits(_roomChargeUnits!)}'
                                            : 'Room Charge (${widget.order.tableNumber ?? 'VIP Room'})',
                                        style: GoogleFonts.urbanist(fontSize: 14.5, fontWeight: FontWeight.w800, color: const Color(0xFFD97706)),
                                      ),
                                      if (_roomChargeUnits != null && widget.order.roomCharge > 0)
                                        Text(
                                          _roomChargeUnits! > 1
                                              ? 'Base ₱${formatPrice(widget.order.roomCharge)} + ${_formatRoomChargeUnits(_roomChargeUnits! - 1)} extension${_roomChargeUnits! - 1 == 1 ? '' : 's'}  (₱${formatPrice(widget.order.roomCharge)} × ${_formatRoomChargeUnits(_roomChargeUnits!)})'
                                              : 'Base rate ₱${formatPrice(widget.order.roomCharge)}',
                                          style: GoogleFonts.urbanist(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500),
                                        ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '₱${formatPrice(roomCharge)}',
                                  style: GoogleFonts.urbanist(fontSize: 14.5, fontWeight: FontWeight.w800, color: const Color(0xFFD97706)),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const Divider(height: 20),
                        if (roomCharge > 0) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Items Subtotal', style: GoogleFonts.urbanist(fontSize: 13.5, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                              Text('₱${formatPrice(itemsBase)}', style: GoogleFonts.urbanist(fontSize: 14.5, fontWeight: FontWeight.w700)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _roomChargeUnits != null && _roomChargeUnits! > 1 && widget.order.roomCharge > 0
                                    ? 'Room Charge (₱${formatPrice(widget.order.roomCharge)} × ${_formatRoomChargeUnits(_roomChargeUnits!)})'
                                    : 'Room Charge',
                                style: GoogleFonts.urbanist(fontSize: 13.5, fontWeight: FontWeight.w700, color: const Color(0xFFD97706)),
                              ),
                              Text('₱${formatPrice(roomCharge)}', style: GoogleFonts.urbanist(fontSize: 14.5, fontWeight: FontWeight.w800, color: const Color(0xFFD97706))),
                            ],
                          ),
                          const Divider(height: 16),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(roomCharge > 0 ? 'Total Subtotal' : 'Subtotal', style: GoogleFonts.urbanist(fontSize: 14.5, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
                            Text('₱${formatPrice(totalBeforeDiscount)}', style: GoogleFonts.urbanist(fontSize: 16.5, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // 2. PAYMENT METHOD SELECTOR
                  Text(
                    'PAYMENT METHOD',
                    style: GoogleFonts.urbanist(fontSize: 12.5, fontWeight: FontWeight.w900, color: Colors.grey.shade600, letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildPaymentOption(method: 'CASH', icon: Icons.payments_rounded, label: 'Cash', primaryColor: primaryColor),
                      const SizedBox(width: 8),
                      _buildPaymentOption(method: 'GCASH', icon: Icons.account_balance_wallet_rounded, label: 'GCash', primaryColor: primaryColor),
                      const SizedBox(width: 8),
                      _buildPaymentOption(method: 'MAYA', icon: Icons.wallet_rounded, label: 'Maya', primaryColor: primaryColor),
                      const SizedBox(width: 8),
                      _buildPaymentOption(method: 'CARD', icon: Icons.credit_card_rounded, label: 'Card', primaryColor: primaryColor),
                    ],
                  ),

                  // 3. AMOUNT RECEIVED / TENDERED (REQUIRED FOR ALL PAYMENT METHODS)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isCash ? 'CASH TENDERED (₱)' : '$_selectedPaymentMethod AMOUNT PAID (₱)',
                        style: GoogleFonts.urbanist(fontSize: 12.5, fontWeight: FontWeight.w900, color: Colors.grey.shade600, letterSpacing: 1.2),
                      ),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _tenderedController.text = formatPrice(finalAmountDue);
                            _cashTendered = finalAmountDue;
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: emerald.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: emerald.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.flash_on_rounded, size: 14, color: emerald),
                              const SizedBox(width: 4),
                              Text(
                                'Exact: ₱${formatPrice(finalAmountDue)}',
                                style: GoogleFonts.urbanist(fontSize: 11.5, fontWeight: FontWeight.w800, color: emerald),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isInsufficient
                            ? Colors.red.shade400
                            : (isMissingTendered ? Colors.amber.shade700.withValues(alpha: 0.6) : emerald),
                        width: isMissingTendered ? 1.2 : 1.8,
                      ),
                    ),
                    child: TextField(
                      controller: _tenderedController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        TextInputFormatter.withFunction((oldValue, newValue) {
                          if (newValue.text.isEmpty) return newValue;
                          final regEx = RegExp(r'^\d*\.?\d{0,2}$');
                          return regEx.hasMatch(newValue.text) ? newValue : oldValue;
                        }),
                      ],
                      style: GoogleFonts.urbanist(fontSize: 24, fontWeight: FontWeight.w900, color: primaryColor),
                      decoration: InputDecoration(
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(left: 16, right: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '₱',
                                style: GoogleFonts.urbanist(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: emerald,
                                ),
                              ),
                            ],
                          ),
                        ),
                        hintText: isCash ? 'Enter cash received' : 'Enter amount received via $_selectedPaymentMethod',
                        hintStyle: GoogleFonts.urbanist(fontSize: 18, color: Colors.grey.shade400),
                        suffixIcon: _cashTendered > 0
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                                onPressed: () => _tenderedController.clear(),
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),

                  if (isInsufficient)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, left: 4),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline_rounded, size: 15, color: Colors.red.shade700),
                          const SizedBox(width: 6),
                          Text(
                            isCash
                                ? 'Insufficient cash (needs ₱${formatPrice(finalAmountDue - _cashTendered)} more)'
                                : 'Insufficient amount (needs ₱${formatPrice(finalAmountDue - _cashTendered)} more)',
                            style: GoogleFonts.urbanist(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.red.shade700),
                          ),
                        ],
                      ),
                    ),

                  // 4. PAYMENT REFERENCE (Only for NON-CASH)
                  if (!isCash) ...[
                    const SizedBox(height: 14),
                    Text(
                      '$_selectedPaymentMethod REFERENCE / APPROVAL # (OPTIONAL)',
                      style: GoogleFonts.urbanist(fontSize: 12.5, fontWeight: FontWeight.w900, color: Colors.grey.shade600, letterSpacing: 1.2),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.withOpacity(0.15)),
                      ),
                      child: TextField(
                        controller: _refController,
                        style: GoogleFonts.urbanist(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1A1C18)),
                        decoration: InputDecoration(
                          prefixIcon: Icon(Icons.tag_rounded, color: Colors.grey.shade500, size: 20),
                          hintText: 'e.g. 1002 9384 2831 / Ref No.',
                          hintStyle: GoogleFonts.urbanist(fontSize: 14.5, color: Colors.grey.shade400),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),

                  // 5. MANUAL DISCOUNT / PROMO (OPTIONAL) - Relocated below payment so cashiers don't confuse it with Cash Tendered
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.local_offer_outlined, size: 16, color: _manualDiscount > 0 ? Colors.amber.shade800 : Colors.grey.shade600),
                          const SizedBox(width: 6),
                          Text(
                            'MANUAL DISCOUNT (OPTIONAL)',
                            style: GoogleFonts.urbanist(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                              color: _manualDiscount > 0 ? Colors.amber.shade900 : Colors.grey.shade600,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                      if (_manualDiscount > 0)
                        InkWell(
                          onTap: () {
                            _discountController.clear();
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Clear Discount',
                              style: GoogleFonts.urbanist(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.red.shade700),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _manualDiscount > 0 ? Colors.amber.shade600 : Colors.grey.withOpacity(0.15),
                        width: _manualDiscount > 0 ? 1.5 : 1,
                      ),
                    ),
                    child: TextField(
                      controller: _discountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        TextInputFormatter.withFunction((oldValue, newValue) {
                          if (newValue.text.isEmpty) return newValue;
                          final regEx = RegExp(r'^\d*\.?\d{0,2}$');
                          return regEx.hasMatch(newValue.text) ? newValue : oldValue;
                        }),
                      ],
                      style: GoogleFonts.urbanist(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _manualDiscount > 0 ? Colors.amber.shade900 : primaryColor,
                      ),
                      decoration: InputDecoration(
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(left: 14, right: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.discount_rounded,
                                size: 18,
                                color: _manualDiscount > 0 ? Colors.amber.shade800 : Colors.grey.shade400,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '-₱',
                                style: GoogleFonts.urbanist(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: _manualDiscount > 0 ? Colors.amber.shade800 : Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        hintText: '0.00 (Senior, PWD, or Promo discount)',
                        hintStyle: GoogleFonts.urbanist(fontSize: 13.5, color: Colors.grey.shade400),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // 6. RECEIPT REMARKS / NOTES (OPTIONAL)
                  Text(
                    'RECEIPT REMARKS / NOTES (OPTIONAL)',
                    style: GoogleFonts.urbanist(fontSize: 12.5, fontWeight: FontWeight.w900, color: Colors.grey.shade600, letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.withOpacity(0.15)),
                    ),
                    child: TextField(
                      controller: _remarksController,
                      style: GoogleFonts.urbanist(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1A1C18)),
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.edit_note_rounded, color: Colors.grey.shade500, size: 20),
                        hintText: 'e.g. Senior ID #1234 / Remarks',
                        hintStyle: GoogleFonts.urbanist(fontSize: 14.5, color: Colors.grey.shade400),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Settlement Summary & Confirmation Bar
          Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (effectiveDiscount > 0)
                            Row(
                              children: [
                                Text(
                                  'Subtotal: ₱${formatPrice(totalBeforeDiscount)}',
                                  style: GoogleFonts.urbanist(
                                    fontSize: 13,
                                    decoration: TextDecoration.lineThrough,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '-₱${formatPrice(effectiveDiscount)}',
                                  style: GoogleFonts.urbanist(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                              ],
                            ),
                          Text(
                            'NET AMOUNT TO PAY',
                            style: GoogleFonts.urbanist(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                              color: Colors.grey.shade600,
                              letterSpacing: 1,
                            ),
                          ),
                          Text(
                            '₱${formatPrice(finalAmountDue)}',
                            style: GoogleFonts.urbanist(
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              color: gold,
                            ),
                          ),
                          // CHANGE AMOUNT DISPLAYED UNDER NET AMOUNT TO PAY
                          if (hasTendered && canComplete) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: emerald.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: emerald.withValues(alpha: 0.35)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_circle_rounded, size: 16, color: emerald),
                                  const SizedBox(width: 6),
                                  Text(
                                    isCash
                                        ? 'CHANGE: '
                                        : (change > 0 ? 'CHANGE: ' : 'PAID: '),
                                    style: GoogleFonts.urbanist(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w900,
                                      color: emerald,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  Text(
                                    isCash
                                        ? '₱${formatPrice(change.clamp(0.0, double.infinity))}'
                                        : (change > 0 ? '₱${formatPrice(change)}' : '₱${formatPrice(_cashTendered)}'),
                                    style: GoogleFonts.urbanist(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w900,
                                      color: emerald,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else if (hasTendered && isInsufficient) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.red.shade300),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.error_outline_rounded, size: 16, color: Colors.red.shade700),
                                  const SizedBox(width: 6),
                                  Text(
                                    'SHORT: ',
                                    style: GoogleFonts.urbanist(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.red.shade700,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  Text(
                                    '₱${formatPrice(finalAmountDue - _cashTendered)}',
                                    style: GoogleFonts.urbanist(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.red.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _selectedPaymentMethod == 'CASH'
                                  ? Icons.payments_rounded
                                  : (_selectedPaymentMethod == 'CARD'
                                      ? Icons.credit_card_rounded
                                      : Icons.account_balance_wallet_rounded),
                              size: 16,
                              color: primaryColor,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _selectedPaymentMethod,
                              style: GoogleFonts.urbanist(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(null),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            foregroundColor: Colors.grey.shade600,
                          ),
                          child: Text(
                            'CANCEL',
                            style: GoogleFonts.urbanist(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 2,
                        child: Container(
                          height: 54,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: canComplete
                                ? const LinearGradient(colors: [primaryColor, secondaryColor])
                                : null,
                            color: canComplete ? null : Colors.grey.shade400,
                            boxShadow: canComplete
                                ? [
                                    BoxShadow(
                                      color: primaryColor.withOpacity(0.3),
                                      blurRadius: 12,
                                      offset: const Offset(0, 6),
                                    ),
                                  ]
                                : null,
                          ),
                          child: ElevatedButton(
                            onPressed: canComplete
                                ? () {
                                    final effectivePaid = _cashTendered;

                                    final settlementData = SettlementData(
                                      paymentMethod: _selectedPaymentMethod,
                                      discountAmount: effectiveDiscount,
                                      grandTotal: finalAmountDue,
                                      amountPaid: effectivePaid,
                                      paymentRef: _refController.text.trim().isNotEmpty
                                          ? _refController.text.trim()
                                          : (_remarksController.text.trim().isNotEmpty ? _remarksController.text.trim() : null),
                                      remarks: _remarksController.text.trim().isNotEmpty
                                          ? _remarksController.text.trim()
                                          : null,
                                    );
                                    Navigator.of(context).pop(settlementData);
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shadowColor: Colors.transparent,
                              disabledBackgroundColor: Colors.grey.shade400,
                              disabledForegroundColor: Colors.white70,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  canComplete ? Icons.check_circle_rounded : Icons.lock_outline_rounded,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isMissingTendered
                                      ? (isCash ? 'ENTER CASH TENDERED' : 'ENTER AMOUNT PAID')
                                      : (isInsufficient ? (isCash ? 'INSUFFICIENT CASH' : 'INSUFFICIENT AMOUNT') : 'COMPLETE SETTLEMENT'),
                                  style: GoogleFonts.urbanist(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentOption({
    required String method,
    required IconData icon,
    required String label,
    required Color primaryColor,
  }) {
    final isSelected = _selectedPaymentMethod == method;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedPaymentMethod = method),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? primaryColor.withOpacity(0.08) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? primaryColor : Colors.grey.withOpacity(0.15),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: isSelected ? primaryColor : Colors.grey.shade400, size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                style: GoogleFonts.urbanist(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w800,
                  color: isSelected ? primaryColor : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
