import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../waiterApp/models.dart';
import '../waiterApp/waiter_models.dart';
import '../waiterApp/services/api_service.dart';
import '../waiterApp/services/socket_service.dart';
import '../shared/sound_service.dart';
import '../shared/floor_utils.dart';
import '../shared/globals.dart';
import '../waiterApp/pages/get_order_page.dart' as waiter_order;
import '../waiterApp/widgets/extend_room_charge_dialog.dart';
import '../waiterApp/widgets/room_charge_history.dart';
import '../waiterApp/widgets/room_time_warning.dart';
import '../waiterApp/pages/take_out_launcher.dart';
import '../waiterApp/pages/quick_menu_page.dart' show QuickMenuBrand;
import 'widgets/order_details_sheet.dart';
import 'widgets/activity_log_view.dart';
import '../waiterApp/widgets/transfer_table_modal.dart';
import '../waiterApp/widgets/edit_order_bottom_sheet.dart';
import '../waiterApp/widgets/menu_picker_sheet.dart';
import '../shared/settings_sheet.dart';
import '../shared/app_translations.dart';
import '../shared/lan_broadcast_service.dart';
import '../shared/background_service.dart';
import '../shared/offline_sync_service.dart';
import '../shared/widgets/offline_order_badge.dart';
import '../shared/widgets/card_cancel_button.dart';
import '../shared/widgets/offline_sync_banner.dart';
import '../shared/widgets/loading_overlay.dart';
import '../shared/widgets/cancel_order_dialog.dart';
import '../shared/widgets/floating_result.dart';
import '../shared/widgets/centered_section_header.dart';
import '../shared/widgets/sliding_segments.dart';
import '../shared/update_dialog.dart';
import '../shared/widgets/blurred_dialog.dart';

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
  // Bumped whenever orders change, so the Activity tab refreshes itself.
  final ValueNotifier<int> _activitySignal = ValueNotifier<int>(0);
  final TextEditingController _searchController = TextEditingController();
  final Set<int> _pinnedOrderIds = {};
  final Set<int> _unacknowledgedOrderIds = {};
  final List<WaiterOrder> _alertOrdersQueue = [];
  // Why each queued order is alerting (items added / edited, cancelled, room
  // charge changed). An order missing here is a brand-new order.
  final Map<int, _OrderAlertInfo> _alertInfo = {};
  // This tablet's own user id — the cashier isn't alerted about its own changes.
  String? _myUserId;
  // Orders this cashier just changed itself (settle, edit, cancel, add, room
  // charge, transfer): the REST poll can't tell who changed an order, so it
  // ignores these for a short while instead of alerting about our own action.
  final Map<int, DateTime> _selfChangedAt = {};
  // The last REST snapshot of each order. The poll compares against this,
  // not [_orders] — socket events merge partial payloads into [_orders]
  // (some carry no items or service charge), which would look like changes.
  Map<int, WaiterOrder> _lastRestById = {};
  // State (status / room charge / items) each order was last alerted for, so
  // the poll doesn't repeat a change the socket already announced.
  final Map<int, String> _alertedStateSig = {};
  
  VoidCallback? _disposeOrderUpdated;
  VoidCallback? _disposeOrderItemsAdded;
  VoidCallback? _disposeOrderCreated;
  VoidCallback? _disposeLanOrderCreated;
  VoidCallback? _disposeLanOrderItemsAdded;
  VoidCallback? _disposeTableUpdated;
  // A refresh asked for while another was running (e.g. right after a
  // transfer / cancel): run it once that one finishes instead of dropping it,
  // or the freed room keeps showing Occupied.
  bool _reloadRequested = false;
  // Counts fallback-poll ticks; tables are refetched on every 3rd one.
  int _pollTick = 0;

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

    // One phrase per kind of alert, newest order first.
    final byKind = <_AlertKind, List<String>>{};
    final seen = <String>{};
    for (final order in _alertOrdersQueue.reversed) {
      final desc = _getSpeechTableDescription(order.tableNumber, order.orderType);
      if (!seen.add(desc)) continue;
      final kind = _alertInfo[order.id]?.kind ?? _AlertKind.newOrder;
      byKind.putIfAbsent(kind, () => []).add(desc);
    }

    if (byKind.isEmpty) {
      SoundService.stopRepeatingAlert();
      return;
    }

    const phrases = {
      _AlertKind.newOrder: ('New order', 'New orders'),
      _AlertKind.itemsAdded: ('Additional order', 'Additional orders'),
      _AlertKind.itemsEdited: ('Order edited', 'Orders edited'),
      _AlertKind.cancelled: ('Order cancelled', 'Orders cancelled'),
      _AlertKind.roomCharge: ('Room charge updated', 'Room charges updated'),
      _AlertKind.transferred: ('Table transfer', 'Table transfers'),
    };
    final parts = <String>[
      for (final kind in _AlertKind.values)
        if (byKind[kind] != null)
          _speechFor(byKind[kind]!, singular: phrases[kind]!.$1, plural: phrases[kind]!.$2),
    ];
    SoundService.startRepeatingAlert(parts.join('. '));
  }

  String _speechFor(List<String> tables, {required String singular, required String plural}) {
    switch (tables.length) {
      case 1:
        return '$singular for ${tables[0]}';
      case 2:
        return '$plural for ${tables[0]} and ${tables[1]}';
      case 3:
        return '$plural for ${tables[0]}, ${tables[1]}, and ${tables[2]}';
      case 4:
        return '$plural for ${tables[0]}, ${tables[1]}, ${tables[2]}, and ${tables[3]}';
      default:
        // 5 or more tables: the newest two by name + count of the rest
        return '$singular for ${tables[0]} and ${tables[1]}, with ${tables.length - 2} other pending tables';
    }
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
      _alertInfo.remove(orderId);
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
      _alertInfo.clear();
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  bool _isGroundFloorOrder(WaiterOrder order) =>
      _isGroundFloorFor(order.floor, order.tableNumber);

  bool _isGroundFloorFor(String? floor, String? tableNumber) {
    // The order's own floor (from its creator's account) wins over the
    // table-name heuristic below.
    final orderFloor = normalizeFloor(floor);
    if (orderFloor != null) return orderFloor == kFloorGround;
    final numStr = (tableNumber ?? '').toUpperCase().trim();
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
    final orderFloor = normalizeFloor(order.floor);
    if (orderFloor != null) return orderFloor == _floorScope;
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
      _myUserId = userData['user_id']?.toString();
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
    _roomTimeWarnings.start();
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
    _roomTimeWarnings.dispose();
    _activitySignal.dispose();
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
    if (state == AppLifecycleState.resumed) _roomTimeWarnings.check();
  }

  // "15 minutes left" popup for rooms with a room charge.
  late final RoomTimeWarningController _roomTimeWarnings = RoomTimeWarningController(
    orders: () => _orders.where(_isOrderVisibleForFloorScope),
    context: () => mounted ? context : null,
    fallbackRateFor: (order) {
      if (order.roomCharge > 0) return order.roomCharge;
      for (final t in _tables) {
        if (t.id == order.tableId) return t.roomCharge;
      }
      return 0;
    },
    onExtend: _extendRoomCharge,
  );

  Future<void> _loadData({bool showSpinner = true}) async {
    // Never let socket-triggered background refreshes stack up — but don't
    // drop this one either: it runs again once the current one is done, and
    // callers awaiting it (after a transfer / cancel) wait for that.
    if (_isLoadingData) {
      _reloadRequested = true;
      while (mounted && (_isLoadingData || _reloadRequested)) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return;
    }
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
        _activitySignal.value++;
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
      _finishLoading();
    }
  }

  void _finishLoading() {
    _isLoadingData = false;
    if (_reloadRequested && mounted) {
      _reloadRequested = false;
      unawaited(_loadData(showSpinner: false));
    }
  }

  /// Lightweight poll for the fast (1s) fallback timer used when the socket
  /// isn't connected: orders only, no tables/menu refetch, so that cadence
  /// doesn't re-download the whole menu on every tick.
  Future<void> _pollOrdersOnly() async {
    if (_isLoadingData) return;
    _isLoadingData = true;
    try {
      // Tables too, every 3rd tick: with the socket down there's no
      // table_updated event to say a room was freed.
      final withTables = (_pollTick++ % 3) == 0;
      final results = await Future.wait([
        ApiService.getWaiterOrders(),
        if (withTables) ApiService.getTables(),
      ]);
      final ordersResult = results[0];
      if (ordersResult['unauthorized'] == true) {
        await _redirectToLogin();
        return;
      }
      if (ordersResult['success'] == true) {
        final ordersData = List<Map<String, dynamic>>.from(ordersResult['data']);
        final tablesResult = withTables ? results[1] : null;
        final freshTables = tablesResult != null &&
                tablesResult['success'] == true &&
                tablesResult['data'] is List
            ? List<Map<String, dynamic>>.from(tablesResult['data']).map(WaiterTable.fromApi).toList()
            : null;
        _applyFreshOrders(
          ordersData,
          extra: freshTables == null ? null : () => _tables = _applyFloorScope(freshTables),
        );
        _syncSocketOrderRooms();
      }
    } catch (e) {
      debugPrint('❌ Error in _pollOrdersOnly: $e');
    } finally {
      _finishLoading();
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
    final previousById = {for (final o in _orders) o.id: o};
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
            if (_isRecentSelfChange(o.id)) return false;
            // Lines removed too → that's an edit (handled below), not just additions.
            final restBefore = _lastRestById[o.id];
            if (restBefore != null &&
                WaiterOrder.addedItemsBetween(o, restBefore).isNotEmpty) {
              return false;
            }
            final previousQty = previousItemQty[o.id];
            final currentQty = _totalQuantity(o);
            if (previousQty == null || currentQty <= previousQty) return false;
            if (_lastAlertedItemsQty[o.id] == currentQty) return false;
            _lastAlertedItemsQty[o.id] = currentQty;
            return true;
          }).toList()
        : const <WaiterOrder>[];

    // Edits, cancels and room-charge changes the socket missed, against the
    // previous REST snapshot (complete data, unlike socket-merged [_orders]).
    final changeAlerts = <(WaiterOrder, _OrderAlertInfo)>[];
    if (_hasLoadedOrdersOnce) {
      final addedIds = itemsAddedOrders.map((o) => o.id).toSet();
      for (final o in freshOrders) {
        final before = _lastRestById[o.id];
        if (before == null || (before.status != 2 && before.status != 3)) continue;
        if (addedIds.contains(o.id) || _isRecentSelfChange(o.id)) continue;
        if (!_isOrderVisibleForFloorScope(o)) continue;
        if (_alertedStateSig[o.id] == _orderStateSig(o)) continue; // socket already told us
        _OrderAlertInfo? info;
        if (o.status == -1) {
          info = const _OrderAlertInfo(_AlertKind.cancelled);
        } else if ((o.status == 2 || o.status == 3) &&
            o.tableId != null &&
            before.tableId != null &&
            o.tableId != before.tableId) {
          info = _OrderAlertInfo(
            _AlertKind.transferred,
            fromTable: before.tableNumber,
            toTable: o.tableNumber,
          );
        } else if (o.status == 2 || o.status == 3) {
          final removed = WaiterOrder.addedItemsBetween(o, before);
          if (removed.isNotEmpty) {
            info = _OrderAlertInfo(
              _AlertKind.itemsEdited,
              added: WaiterOrder.addedItemsBetween(before, o),
              removed: removed,
            );
          } else if ((o.serviceCharge - before.serviceCharge).abs() > 0.005) {
            info = _OrderAlertInfo(
              _AlertKind.roomCharge,
              roomChargeFrom: before.serviceCharge,
              roomChargeTo: o.serviceCharge,
            );
          }
        }
        if (info != null) changeAlerts.add((o, info));
      }
    }
    _lastRestById = {for (final o in freshOrders) o.id: o};

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
        _enqueueAlert(
          order,
          addedItems: true,
          newItems: WaiterOrder.addedItemsBetween(previousById[order.id], order),
        );
      }
      for (final (order, info) in changeAlerts) {
        debugPrint('✓ Poll: ${info.kind.name} on order ${order.id} (socket missed it)');
        _unacknowledgedOrderIds.add(order.id);
        _enqueueAlert(order, info: info);
      }
      extra?.call();
    });
    _hasLoadedOrdersOnce = true;
    if (newlyAppeared.isNotEmpty || itemsAddedOrders.isNotEmpty || changeAlerts.isNotEmpty) {
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
      // Blocking loader so the tap clearly did something. A refresh is often
      // over in a blink, so keep it up for a minimum of 700ms or the card
      // would just flash.
      await runWithLoader<void>(
        context,
        message: 'Refreshing…',
        task: () => Future.wait<void>([
          _loadData(showSpinner: false),
          Future<void>.delayed(const Duration(milliseconds: 700)),
        ]),
      );
    } finally {
      if (mounted) setState(() => _isManualRefreshing = false);
    }
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

      // A room freed / taken (transfer, settle, cancel — by anyone): the
      // server broadcasts it to the role rooms; without this the cashier only
      // saw it on its next full refresh.
      _disposeTableUpdated?.call();
      _disposeTableUpdated = SocketService.addTableUpdateListener((data) {
        if (!mounted) return;
        _handleSocketTableEvent(data);
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

  /// `table_updated` from the server — same handling as waiterApp's.
  void _handleSocketTableEvent(Map<String, dynamic> data) {
    final rawTableData = data['table'];
    final tableData = rawTableData is Map
        ? Map<String, dynamic>.from(rawTableData)
        : Map<String, dynamic>.from(data);
    final action = (data['action'] ?? tableData['action'])?.toString() ?? 'updated';
    tableData['id'] ??= tableData['table_id'] ?? data['table_id'];
    tableData['table_number'] ??= tableData['tableNumber'];
    tableData['capacity'] ??= tableData['CAPACITY'];
    tableData['status'] ??= tableData['STATUS'];

    final tableIdRaw = tableData['id'];
    final tableId = tableIdRaw is int ? tableIdRaw : int.tryParse(tableIdRaw?.toString() ?? '');
    if (tableId == null) return;
    if (!_isForThisBranch({'branch_id': tableData['branch_id'] ?? tableData['BRANCH_ID'] ?? data['branch_id']})) {
      return;
    }

    try {
      setState(() {
        if (action == 'deleted') {
          _tables = _tables.where((t) => t.id != tableId).toList();
          return;
        }
        final updatedTable = WaiterTable.fromApi(tableData);
        final index = _tables.indexWhere((t) => t.id == tableId);
        _tables = _applyFloorScope(index == -1
            ? [..._tables, updatedTable]
            : [for (final t in _tables) t.id == tableId ? updatedTable : t]);
      });
    } catch (e) {
      debugPrint('Error updating table from socket in cashier_home_page: $e');
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
    _activitySignal.value++;

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
      final parsed = WaiterOrder.fromApi(normalized);
      final updatedOrder = existingIndex == -1
          ? parsed
          : _orders[existingIndex].keepRoomChargesIn(parsed, normalized);
      // `order_created` also fires for orders that arrive already settled —
      // Loyverse receipt imports and the admin's Manual Order / Upload
      // Receipt, often for a past day. Those are history, not something for
      // the cashier to act on (same rule as the REST poll in _applyFreshOrders).
      final isActiveOrder = updatedOrder.status == 2 || updatedOrder.status == 3;
      // What a tablet changed and who (newer backends) — our own changes don't alert.
      final rawChange = orderData['change'] ?? data['change'];
      final change = rawChange is Map ? Map<String, dynamic>.from(rawChange) : null;
      final byMe = change != null &&
          _myUserId != null &&
          change['by']?.toString() == _myUserId;

      // Queue order for alert and update repeating voice announcement.
      // A genuinely new order always arrives as an `order_created` event; an
      // unknown order from `order_updated` is the reconnect backlog or another
      // branch's traffic (the backend broadcasts globally), so it must not
      // alert. Alert each order at most once.
      if (eventType == 'order_created' &&
          isActiveOrder &&
          _isOrderVisibleForFloorScope(updatedOrder) &&
          _shouldAlert(updatedOrder)) {
        setState(() {
          _unacknowledgedOrderIds.add(updatedOrder.id);
          _enqueueAlert(updatedOrder, addedItems: false);
        });
        _updateRepeatingTtsAnnouncement();
      } else if (!isNewOrder &&
          !byMe &&
          (eventType == 'order_items_added' || data['items_added'] != null)) {
        final currentQty = _totalQuantity(updatedOrder);
        if (_lastAlertedItemsQty[updatedOrder.id] != currentQty) {
          _lastAlertedItemsQty[updatedOrder.id] = currentQty;
          final newItems = WaiterOrder.addedItemsBetween(_orders[existingIndex], updatedOrder);
          setState(() {
            _unacknowledgedOrderIds.add(updatedOrder.id);
            _enqueueAlert(
              updatedOrder,
              info: _OrderAlertInfo(
                _AlertKind.itemsAdded,
                added: newItems,
                byName: change?['by_name']?.toString(),
              ),
            );
          });
          _updateRepeatingTtsAnnouncement();
        }
      } else if (!isNewOrder &&
          !byMe &&
          eventType == 'order_updated' &&
          change != null &&
          _isOrderVisibleForFloorScope(updatedOrder)) {
        // Edited / cancelled / room charge changed by a waiter (or another cashier).
        final info = _changeAlertFor(_orders[existingIndex], updatedOrder, change);
        if (info != null) {
          setState(() {
            _unacknowledgedOrderIds.add(updatedOrder.id);
            _enqueueAlert(updatedOrder, info: info);
          });
          _updateRepeatingTtsAnnouncement();
        }
      }

      // An unknown order from a plain `order_updated` / `order_items_added` is
      // almost always the reconnect backlog or another branch's traffic (the
      // backend broadcasts globally). Don't splice it in — the debounced
      // _loadData (branch-scoped) is the source of truth for which orders
      // exist. Only `order_created` adds a new order locally.
      // An already-settled `order_created` (import / manual order) isn't
      // spliced in either: the refresh picks it up for History if it belongs
      // to today.
      if (existingIndex == -1 &&
          (eventType != 'order_created' || !isActiveOrder)) {
        _scheduleSocketRefresh();
        return;
      }

      setState(() {
        if (existingIndex == -1) {
          debugPrint('✓ Socket: Adding new order $orderId');
          _orders = [..._orders, updatedOrder];
          _tables = applyOrderTableChange(_tables, _orders, null, updatedOrder);
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
          // Moved / settled / cancelled: free the room it left right away,
          // even if the server's table_updated event never arrives.
          _tables = applyOrderTableChange(_tables, nextOrders, existingOrder, mergedOrder);
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
  void _enqueueAlert(
    WaiterOrder order, {
    bool addedItems = false,
    List<WaiterOrderItem>? newItems,
    _OrderAlertInfo? info,
  }) {
    final change = info ??
        (addedItems
            ? _OrderAlertInfo(_AlertKind.itemsAdded, added: newItems ?? const [])
            : null);
    final queued = _alertOrdersQueue.any((o) => o.id == order.id);
    final previous = _alertInfo[order.id];
    if (change == null) {
      _alertInfo.remove(order.id);
    } else if (queued && previous == null && change.kind != _AlertKind.cancelled) {
      // Still an unacknowledged NEW order — keep showing it whole.
    } else {
      // Several changes before the cashier acknowledges add up.
      _alertInfo[order.id] = previous == null ? change : previous.mergedWith(change);
    }
    if (change != null) _alertedStateSig[order.id] = _orderStateSig(order);
    _alertOrdersQueue.removeWhere((o) => o.id == order.id);
    _alertOrdersQueue.add(order);
    if (_alertOrdersQueue.length > _maxAlertQueue) {
      _alertOrdersQueue.removeRange(0, _alertOrdersQueue.length - _maxAlertQueue);
      final keep = _alertOrdersQueue.map((o) => o.id).toSet();
      _alertInfo.removeWhere((id, _) => !keep.contains(id));
    }
  }

  /// status | room charge | items — what a change alert was raised for.
  String _orderStateSig(WaiterOrder o) {
    final items = [
      for (final i in o.items) '${i.menuId ?? i.name.toLowerCase()}:${i.quantity}',
    ]..sort();
    return '${o.status}|${o.tableId}|${o.serviceCharge.toStringAsFixed(2)}|${items.join(',')}';
  }

  void _markSelfChange(int orderId) => _selfChangedAt[orderId] = DateTime.now();

  bool _isRecentSelfChange(int orderId) {
    final at = _selfChangedAt[orderId];
    return at != null && DateTime.now().difference(at) < const Duration(seconds: 60);
  }

  /// The notice for a waiter's change to an order we already show, from its
  /// socket event's `change` ({type, by_name, from, to}); null when nothing
  /// the cashier needs to hear about changed.
  _OrderAlertInfo? _changeAlertFor(
    WaiterOrder before,
    WaiterOrder after,
    Map<String, dynamic> change,
  ) {
    final byName = change['by_name']?.toString();
    switch (change['type']?.toString()) {
      case 'items_edited':
        final added = WaiterOrder.addedItemsBetween(before, after);
        final removed = WaiterOrder.addedItemsBetween(after, before);
        if (added.isEmpty && removed.isEmpty) return null;
        return _OrderAlertInfo(_AlertKind.itemsEdited, added: added, removed: removed, byName: byName);
      case 'cancelled':
        final wasActive = before.status == 2 || before.status == 3;
        return wasActive ? _OrderAlertInfo(_AlertKind.cancelled, byName: byName) : null;
      case 'transferred':
        final fromTable = change['from_table']?.toString() ?? before.tableNumber;
        final toTable = change['to_table']?.toString() ?? after.tableNumber;
        return _OrderAlertInfo(
          _AlertKind.transferred,
          fromTable: fromTable,
          toTable: toTable,
          byName: byName,
        );
      case 'room_charge':
        final from = (change['from'] as num?)?.toDouble() ?? before.serviceCharge;
        final to = (change['to'] as num?)?.toDouble() ?? after.serviceCharge;
        if ((from - to).abs() < 0.005) return null;
        return _OrderAlertInfo(
          _AlertKind.roomCharge,
          roomChargeFrom: from,
          roomChargeTo: to,
          byName: byName,
        );
    }
    return null;
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
    _disposeTableUpdated?.call();
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
    _markSelfChange(order.id);
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
      showFloatingResult(
        context,
        title: 'Not synced yet',
        subtitle: 'This order hasn\'t synced to the server yet — please wait a moment and try again.',
        warning: true,
        duration: const Duration(milliseconds: 3200),
      );
      return;
    }

    final settlement = await showBlurredBottomSheet<SettlementData?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (context) => _SettleOrderSheet(order: order),
    );

    if (settlement == null) return;

    if (!mounted) return;

    try {
      // Loader stays up through the settle call AND the list refresh, so the
      // settled card is already gone when it closes. (Replaces the old
      // full-page spinner that blanked the whole cashier screen.)
      final result = await runWithLoader<Map<String, dynamic>>(
        context,
        message: 'Settling order…',
        task: () async {
          final r = await ApiService.updateWaiterOrderStatus(
            orderId: order.id,
            status: 1,
            paymentMethod: settlement.paymentMethod,
            discountAmount: settlement.discountAmount,
            grandTotal: settlement.grandTotal,
            amountPaid: settlement.amountPaid,
            paymentRef: settlement.paymentRef,
            remarks: settlement.remarks,
          );
          if (r['success'] == true) await _loadData(showSpinner: false);
          return r;
        },
      );
      if (!mounted) return;

      if (result['success'] == true) {
        // Skip the toast while a new-order alert is on screen so it can't
        // cover it (same rule the old snackbar followed).
        if (_unacknowledgedOrderIds.isEmpty) {
          final isOffline = result['is_offline'] == true;
          showFloatingResult(
            context,
            title: 'Order Settled',
            subtitle: isOffline
                ? 'Saved offline - will sync when online'
                : (order.orderNo ?? 'Order #${order.id}'),
            warning: isOffline,
          );
        }
      } else {
        showFloatingError(
          context,
          title: 'Order not settled',
          message: (result['error'] ?? 'Failed to settle order').toString(),
        );
      }
    } catch (e) {
      if (mounted) {
        showFloatingError(context, title: 'Order not settled', message: e.toString());
      }
    }
  }

  Future<MenuItem?> _showMenuPicker(BuildContext context) async {
    return showBlurredBottomSheet<MenuItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => MenuPickerSheet(menuItems: _menuItems),
    );
  }

  Future<List<EditableOrderItem>?> _showEditOrderSheet(
    WaiterOrder order,
    List<EditableOrderItem> editableItems,
  ) async {
    return showBlurredBottomSheet<List<EditableOrderItem>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
    _markSelfChange(order.id);
    if (order.id < 0) {
      showFloatingResult(
        context,
        title: 'Not synced yet',
        subtitle: 'This order hasn\'t synced to the server yet — please wait a moment and try again.',
        warning: true,
        duration: const Duration(milliseconds: 3200),
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
        showFloatingError(
          context,
          title: 'Cannot edit order',
          message: 'No menu items available to edit this order.',
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
        showFloatingError(
          context,
          title: 'Cannot edit order',
          message: 'No editable items found for this order.',
        );
      }
      return;
    }

    final updatedItems = await _showEditOrderSheet(order, editableItems);

    if (updatedItems == null) return;
    if (updatedItems.isEmpty) {
      if (mounted) {
        showFloatingError(
          context,
          title: 'Cannot save order',
          message: 'Order must have at least one item.',
        );
      }
      return;
    }

    if (updatedItems.any((item) => item.menuId == null)) {
      if (mounted) {
        showFloatingError(
          context,
          title: 'Cannot save order',
          message: 'Please select a menu for all items.',
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

    if (!mounted) return;
    final result = await runWithLoader<Map<String, dynamic>>(
      context,
      message: 'Updating order…',
      task: () async {
        final r = await ApiService.replaceOrderItems(
          orderId: order.id,
          items: payload,
        );
        if (r['success'] == true) await _loadData(showSpinner: false);
        return r;
      },
    );
    if (!mounted) return;

    if (result['unauthorized'] == true) {
      await _redirectToLogin();
      return;
    }

    if (result['success'] == true) {
      showFloatingResult(
        context,
        title: 'Order Updated',
        subtitle: order.orderNo ?? 'Order #${order.id}',
      );
    } else {
      showFloatingError(
        context,
        title: 'Order not updated',
        message: (result['error'] ?? 'Failed to update order').toString(),
      );
    }
  }

  // Cancelling reuses the same status-update endpoint Settle already calls
  // (status: -1 instead of 1) — the backend already fully handles it
  // (frees the table, reverses inventory deductions), same as the existing
  // cancel button in the admin web panel.
  // Extend a room's charge from the cashier's order card — same flow as the
  // waiter's table card (qty picker -> API -> result dialog).
  Future<void> _extendRoomCharge(WaiterOrder order) async {
    _markSelfChange(order.id);
    if (order.id < 0) {
      showFloatingResult(
        context,
        title: 'Not synced yet',
        subtitle: 'This order hasn\'t synced to the server yet — please wait a moment and try again.',
        warning: true,
        duration: const Duration(milliseconds: 3200),
      );
      return;
    }

    // With room-charge history only the room it's in now is adjusted; rooms
    // it moved out of keep what they were billed.
    final currentRoom = order.currentRoomCharge;
    var rate = currentRoom?.rate ?? order.roomCharge;
    if (rate <= 0) {
      for (final t in _tables) {
        if (t.id == order.tableId) {
          rate = t.roomCharge;
          break;
        }
      }
    }
    final tableName = (order.tableNumber ?? '').trim().isEmpty
        ? 'Room'
        : order.tableNumber!.trim();

    final sessions = await showRoomChargeAdjust(
      context,
      tableName: tableName,
      orderLabel: order.orderNo ?? '#${order.id}',
      roomCharge: rate,
      currentRoomCharge: currentRoom?.amount ?? order.serviceCharge,
      earlierRoomCharge: currentRoom == null ? 0 : order.roomChargesTotal - currentRoom.amount,
    );
    if (sessions == null || !mounted) return;

    final result = await runWithLoader<Map<String, dynamic>>(
      context,
      message: 'Updating room charge…',
      task: () => ApiService.setRoomChargeSessions(orderId: order.id, sessions: sessions),
    );
    if (!mounted) return;

    if (result['unauthorized'] == true) {
      await _redirectToLogin();
      return;
    }

    if (result['success'] == true) {
      final data = result['data'] as Map<String, dynamic>?;
      final newServiceCharge = (data?['service_charge'] as num?)?.toDouble() ??
          (order.serviceCharge + rate * sessions - (currentRoom?.amount ?? order.serviceCharge));
      final added = newServiceCharge - order.serviceCharge;
      final newTotal = (data?['grand_total'] as num?)?.toDouble() ??
          (order.grandTotal + added);
      final units = (data?['room_hours'] as num?)?.toDouble() ?? sessions;

      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.mediumImpact();
      await showRoomChargeExtendedResult(
        context,
        tableName: tableName,
        added: added,
        newRoomCharge: newServiceCharge,
        newGrandTotal: newTotal,
        units: units,
      );
      if (!mounted) return;
      await _loadData(showSpinner: false);
    } else {
      SystemSound.play(SystemSoundType.alert);
      await showExtendRoomChargeError(
        context,
        result['error']?.toString() ?? 'Failed to update room charge',
      );
    }
  }

  // Take-out: the Switch Menu opens with no table; the order lands in Unsettled
  // as "Take Out #N" like any other order.
  Future<void> _openNewTakeOut() async {
    if (_menuItems.isEmpty) {
      showFloatingError(
        context,
        title: 'Menu not loaded',
        message: 'Please refresh and try again.',
      );
      return;
    }
    await openNewTakeOut(context, menuItems: _menuItems, orders: _orders);
    if (!mounted) return;
    await _loadData(showSpinner: false);
  }

  // Take-outs are rare, so this is a quiet outlined button next to the search.
  Widget _buildTakeOutButton({double height = 50}) {
    return SizedBox(
      height: height,
      child: OutlinedButton.icon(
        onPressed: _openNewTakeOut,
        icon: const Icon(Icons.shopping_bag_outlined, size: 18),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF0C0E2B),
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFDDDED3), width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        label: Text(
          'Take Out',
          style: GoogleFonts.urbanist(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Future<void> _cancelOrder(WaiterOrder order) async {
    _markSelfChange(order.id);
    if (order.id < 0) {
      showFloatingResult(
        context,
        title: 'Not synced yet',
        subtitle: 'This order hasn\'t synced to the server yet — please wait a moment and try again.',
        warning: true,
        duration: const Duration(milliseconds: 3200),
      );
      return;
    }

    final tableText = (order.tableNumber ?? '').trim();
    final confirmed = await showCancelOrderConfirm(
      context,
      orderLabel: order.orderNo ?? 'Order #${order.id}',
      tableName: tableText.isEmpty
          ? (order.isTakeOut ? order.takeOutLabel : null)
          : (tableText.toLowerCase().startsWith('table') ? tableText : 'Table $tableText'),
    );
    if (!confirmed) return;

    if (!mounted) return;
    // Loader stays up through the cancel call AND the list refresh, so the
    // card doesn't linger on screen after the waiter has confirmed.
    final result = await runWithLoader<Map<String, dynamic>>(
      context,
      message: 'Cancelling order…',
      task: () async {
        final r = await ApiService.updateWaiterOrderStatus(
          orderId: order.id,
          status: -1,
        );
        if (r['success'] == true) await _loadData(showSpinner: false);
        return r;
      },
    );

    if (result['unauthorized'] == true) {
      await _redirectToLogin();
      return;
    }

    if (result['success'] == true) {
      if (mounted) {
        final isOffline = result['is_offline'] == true;
        showFloatingResult(
          context,
          title: 'Order Cancelled',
          subtitle: isOffline
              ? 'Saved offline - will sync when online'
              : (order.orderNo ?? 'Order #${order.id}'),
          warning: isOffline,
        );
      }
    } else {
      if (mounted) {
        showFloatingError(
          context,
          title: 'Order not cancelled',
          message: (result['error'] ?? 'Failed to cancel order').toString(),
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
    TakeOutNumbers.refresh(_orders);
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
    // The one-row header (tabs | stats | take out | search) needs ~1320px with
    // the three tabs; below that it would squeeze the buttons together, so it
    // stacks instead.
    final wideHeader = screenWidth >= 1340;

    return DefaultTabController(
      length: 3,
      child: Stack(
        children: [
          Scaffold(
            key: _scaffoldKey,
        backgroundColor: const Color(0xFFF5F6F0),
        appBar: AppBar(
          centerTitle: true,
          toolbarHeight: 84,
          // Empty leading as wide as the action buttons so the title block is
          // truly centered on the screen instead of leaning left.
          leadingWidth: 176,
          leading: const SizedBox.shrink(),
          // BLUE MOON • CASHIER (• GROUND FLOOR / 2nd FLOOR when the account is
          // floor-scoped). Shrinks on narrow screens instead of overflowing.
          title: FittedBox(
            fit: BoxFit.scaleDown,
            child: QuickMenuBrand(
              tableLabel: _floorScope == 'gf'
                  ? 'CASHIER  •  GROUND FLOOR'
                  : _floorScope == '2f'
                      ? 'CASHIER  •  2nd FLOOR'
                      : 'CASHIER',
            ),
          ),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
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
                      showFloatingResult(
                        context,
                        title: SoundService.isMuted ? 'Notification sounds muted' : 'Notification sounds enabled',
                        warning: SoundService.isMuted,
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
          // Header block on the cream page: ONE stats card (ready to settle |
          // collected), the search pill, then the sliding tabs. Wide screens
          // squeeze it into a single row.
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(wideHeader ? 78 : 216),
            child: wideHeader
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 460,
                          child: _CashierTabs(
                            unsettledCount: scopedUnsettledCount,
                            historyCount: scopedHistoryCount,
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 400,
                          child: _buildStatsCard(
                            unsettled: scopedUnsettledCount,
                            collected: totalCollected,
                            compact: true,
                          ),
                        ),
                        const Spacer(),
                        if (_floorScope != '2f') ...[
                          const SizedBox(width: 16),
                          _buildTakeOutButton(height: 48),
                        ],
                        const SizedBox(width: 12),
                        SizedBox(
                          width: screenWidth >= 1450 ? 300 : 250,
                          height: 48,
                          child: _buildSearchTextField(isCompact: true),
                        ),
                      ],
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                        child: _buildStatsCard(
                          unsettled: scopedUnsettledCount,
                          collected: totalCollected,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 50,
                                child: _buildSearchTextField(),
                              ),
                            ),
                            if (_floorScope != '2f') ...[
                              const SizedBox(width: 10),
                              _buildTakeOutButton(),
                            ],
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: _CashierTabs(
                          unsettledCount: scopedUnsettledCount,
                          historyCount: scopedHistoryCount,
                        ),
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
                    ActivityLogView(
                      searchQuery: _searchQuery,
                      floorScope: _floorScope,
                      isGroundFloor: _isGroundFloorFor,
                      refreshSignal: _activitySignal,
                    ),
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
              alertInfo: Map.unmodifiable(_alertInfo),
              onAcknowledgeSingle: (orderId) => _acknowledgeOrder(orderId),
              onAcknowledgeAll: () => _acknowledgeAllOrders(),
            );
          },
        ),
    ],
  ),
);
  }

  // One white card, two halves: Ready to settle | Collected. Cleaner than two
  // separate boxes; the pending count turns amber when there is work to do.
  Widget _buildStatsCard({
    required int unsettled,
    required double collected,
    bool compact = false,
  }) {
    const navy = Color(0xFF0C0E2B);
    const amber = Color(0xFFD97706);
    const green = Color(0xFF059669);

    Widget half({
      required String label,
      required String value,
      required IconData icon,
      required Color color,
    }) {
      return Expanded(
        child: Row(
          children: [
            Container(
              width: compact ? 34 : 44,
              height: compact ? 34 : 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: compact ? 18 : 23),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: GoogleFonts.urbanist(
                        fontSize: compact ? 10 : 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: GoogleFonts.urbanist(
                        fontSize: compact ? 20 : 27,
                        fontWeight: FontWeight.w900,
                        color: color,
                        height: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      height: compact ? 56 : 78,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(compact ? 16 : 22),
        border: Border.all(color: const Color(0xFFDDDED3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          half(
            label: 'READY TO SETTLE',
            value: '$unsettled',
            icon: Icons.assignment_turned_in_rounded,
            color: unsettled > 0 ? amber : navy,
          ),
          Container(
            width: 1.2,
            height: compact ? 30 : 44,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: const Color(0xFFDDDED3),
          ),
          half(
            label: 'COLLECTED',
            value: '₱${formatPrice(collected)}',
            icon: Icons.account_balance_wallet_rounded,
            color: green,
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
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 100),
        itemCount: orders.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: CenteredSectionHeader(
                title: 'Settled & Cancelled',
                subtitle: '${orders.length} order(s)',
              ),
            );
          }
          return _HistoryOrderListItem(
            order: orders[index - 1],
            isGroundFloor: _isGroundFloorOrder(orders[index - 1]),
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
                    onExtendRoomCharge: () => _extendRoomCharge(order),
                    onSelfChange: () => _markSelfChange(order.id),
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
  final bool isGroundFloor;

  const _HistoryOrderListItem({required this.order, required this.isGroundFloor});

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
    // Bright status color for the navy header.
    final statusBright = isCancelled ? const Color(0xFFFF6B6B) : const Color(0xFF4ADE80);
    final isCash = (order.paymentMethod ?? 'CASH').toUpperCase() == 'CASH';
    final effectivePaid = order.amountPaid > 0 ? order.amountPaid : order.grandTotal;
    final changeAmount = (effectivePaid - order.grandTotal).clamp(0.0, double.infinity);

    final rawTableName = (order.tableNumber ?? '').trim();
    final tableDisplay = rawTableName.isEmpty
        ? (order.isTakeOut ? order.takeOutLabel : 'Dine-In')
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
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(17)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: statusBright.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.receipt_long_rounded, color: statusBright, size: 22),
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
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusBright.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: statusBright.withValues(alpha: 0.6)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(isCancelled ? Icons.cancel_rounded : Icons.check_circle_rounded, size: 13, color: statusBright),
                                const SizedBox(width: 4),
                                Text(
                                  isCancelled ? 'CANCELLED' : 'SETTLED',
                                  style: GoogleFonts.urbanist(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: statusBright,
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
                          const Icon(Icons.schedule_rounded, size: 14, color: Colors.white54),
                          const SizedBox(width: 5),
                          Text(
                            _formatOrderDateTime(order.encodedDt, order.orderNo),
                            style: GoogleFonts.urbanist(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white70,
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
                        color: const Color(0xFFE8C468).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE8C468).withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.chair_alt_rounded, size: 15, color: Color(0xFFE8C468)),
                          const SizedBox(width: 5),
                          Text(
                            tableDisplay,
                            style: GoogleFonts.urbanist(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFFE8C468),
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
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white54,
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

                    // Full breakdown + payment details of the settled order
                    SizedBox(
                      height: 34,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          OrderDetailsSheet.show(
                            context,
                            order: order,
                            roomChargeRate: order.roomCharge,
                            floorLabel: widget.isGroundFloor ? 'GF' : '2F',
                            isHistory: true,
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
                          'View Details',
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

/// Why an order is in the cashier's alert queue.
enum _AlertKind { newOrder, itemsAdded, itemsEdited, cancelled, roomCharge, transferred }

/// What changed on an order the cashier already had (an order with no entry
/// in the alert map is a brand-new order).
class _OrderAlertInfo {
  final _AlertKind kind;
  final List<WaiterOrderItem> added;
  final List<WaiterOrderItem> removed;
  final double? roomChargeFrom;
  final double? roomChargeTo;
  final String? fromTable;
  final String? toTable;

  /// Username of who made the change — from the socket event; null when the
  /// REST poll found it (the poll can't tell who).
  final String? byName;

  const _OrderAlertInfo(
    this.kind, {
    this.added = const [],
    this.removed = const [],
    this.roomChargeFrom,
    this.roomChargeTo,
    this.fromTable,
    this.toTable,
    this.byName,
  });

  /// Several changes before the cashier acknowledges add up into one notice;
  /// a cancel always wins.
  _OrderAlertInfo mergedWith(_OrderAlertInfo next) {
    if (next.kind == _AlertKind.cancelled || kind == _AlertKind.cancelled) return next;
    const itemKinds = {_AlertKind.itemsAdded, _AlertKind.itemsEdited};
    if (itemKinds.contains(kind) && itemKinds.contains(next.kind)) {
      final onlyAdded = kind == _AlertKind.itemsAdded && next.kind == _AlertKind.itemsAdded;
      return _OrderAlertInfo(
        onlyAdded ? _AlertKind.itemsAdded : _AlertKind.itemsEdited,
        added: WaiterOrder.consolidateItems([...added, ...next.added]),
        removed: WaiterOrder.consolidateItems([...removed, ...next.removed]),
        byName: next.byName ?? byName,
      );
    }
    if (kind == _AlertKind.transferred && next.kind == _AlertKind.transferred) {
      return _OrderAlertInfo(
        _AlertKind.transferred,
        fromTable: fromTable ?? next.fromTable,
        toTable: next.toTable,
        byName: next.byName ?? byName,
      );
    }
    if (kind == _AlertKind.roomCharge && next.kind == _AlertKind.roomCharge) {
      return _OrderAlertInfo(
        _AlertKind.roomCharge,
        roomChargeFrom: roomChargeFrom ?? next.roomChargeFrom,
        roomChargeTo: next.roomChargeTo,
        byName: next.byName ?? byName,
      );
    }
    return next;
  }
}

/// One line in an alert: ordered (0), added (+1) or removed (-1).
class _AlertLine {
  final WaiterOrderItem item;
  final int sign;
  const _AlertLine(this.item, [this.sign = 0]);
}

class _CenterOrderAlertModal extends StatefulWidget {
  final List<WaiterOrder> orders;

  /// Why each order is shown; an order missing here is a brand-new order.
  final Map<int, _OrderAlertInfo> alertInfo;
  final void Function(int orderId) onAcknowledgeSingle;
  final VoidCallback onAcknowledgeAll;

  const _CenterOrderAlertModal({
    required this.orders,
    this.alertInfo = const {},
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
  static const _green = Color(0xFF16A34A);
  static const _red = Color(0xFFDC2626);
  static const _blue = Color(0xFF2563EB);
  static const _ink = Color(0xFF1E293B);

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

  static String _fmtQty(double v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);

  // ── what each order's notice says ─────────────────────────────────────────

  _OrderAlertInfo? _infoOf(WaiterOrder o) => widget.alertInfo[o.id];

  _AlertKind _kindOf(WaiterOrder o) => _infoOf(o)?.kind ?? _AlertKind.newOrder;

  /// "Items added" where we couldn't tell which items: show the whole order.
  bool _addedUnknown(WaiterOrder o) =>
      _kindOf(o) == _AlertKind.itemsAdded && (_infoOf(o)?.added.isEmpty ?? true);

  List<_AlertLine> _linesFor(WaiterOrder order) {
    final info = _infoOf(order);
    switch (_kindOf(order)) {
      case _AlertKind.itemsAdded:
        if (_addedUnknown(order)) return [for (final i in order.items) _AlertLine(i)];
        return [for (final i in info!.added) _AlertLine(i, 1)];
      case _AlertKind.itemsEdited:
        return [
          for (final i in info!.added) _AlertLine(i, 1),
          for (final i in info.removed) _AlertLine(i, -1),
        ];
      case _AlertKind.roomCharge:
      case _AlertKind.transferred:
        return const [];
      case _AlertKind.newOrder:
      case _AlertKind.cancelled:
        return [for (final i in order.items) _AlertLine(i)];
    }
  }

  bool _showsRoomRow(WaiterOrder order) {
    final kind = _kindOf(order);
    return (kind == _AlertKind.newOrder || kind == _AlertKind.cancelled || _addedUnknown(order)) &&
        order.serviceCharge > 0;
  }

  bool _isWaived(WaiterOrder order) => (_infoOf(order)?.roomChargeTo ?? 1) <= 0.005;

  String _singleTitle(WaiterOrder order) {
    switch (_kindOf(order)) {
      case _AlertKind.newOrder:
        return 'NEW ORDER RECEIVED!';
      case _AlertKind.itemsAdded:
        return _addedUnknown(order) ? 'ORDER UPDATED' : 'ITEMS ADDED';
      case _AlertKind.itemsEdited:
        return 'ORDER EDITED';
      case _AlertKind.cancelled:
        return 'ORDER CANCELLED';
      case _AlertKind.roomCharge:
        return _isWaived(order) ? 'ROOM CHARGE WAIVED' : 'ROOM CHARGE UPDATED';
      case _AlertKind.transferred:
        return 'TABLE TRANSFERRED';
    }
  }

  String _sectionLabel(WaiterOrder order) {
    switch (_kindOf(order)) {
      case _AlertKind.newOrder:
        return 'ORDER ITEMS';
      case _AlertKind.itemsAdded:
        return _addedUnknown(order) ? 'ORDER ITEMS' : 'NEWLY ADDED ITEMS';
      case _AlertKind.itemsEdited:
        return 'CHANGES';
      case _AlertKind.cancelled:
        return 'CANCELLED ORDER';
      case _AlertKind.roomCharge:
        return 'ROOM CHARGE';
      case _AlertKind.transferred:
        return 'TABLE TRANSFER';
    }
  }

  /// Small tag next to the table name in the multi-order list.
  (String, Color) _kindTag(WaiterOrder order) {
    switch (_kindOf(order)) {
      case _AlertKind.newOrder:
        return ('NEW', amberAccent);
      case _AlertKind.itemsAdded:
        return ('+ ADDED', _blue);
      case _AlertKind.itemsEdited:
        return ('EDITED', _blue);
      case _AlertKind.cancelled:
        return ('CANCELLED', _red);
      case _AlertKind.roomCharge:
        return (_isWaived(order) ? 'ROOM WAIVED' : 'ROOM CHARGE', amberAccent);
      case _AlertKind.transferred:
        return ('MOVED', _blue);
    }
  }

  String _countLabel(WaiterOrder order) {
    final info = _infoOf(order);
    switch (_kindOf(order)) {
      case _AlertKind.itemsAdded:
        if (!_addedUnknown(order)) {
          final qty = info!.added.fold<double>(0, (s, i) => s + i.quantity);
          return '+${_fmtQty(qty)} added';
        }
        break;
      case _AlertKind.itemsEdited:
        final plus = info!.added.fold<double>(0, (s, i) => s + i.quantity);
        final minus = info.removed.fold<double>(0, (s, i) => s + i.quantity);
        return [
          if (plus > 0) '+${_fmtQty(plus)}',
          if (minus > 0) '−${_fmtQty(minus)}',
        ].join(' / ');
      case _AlertKind.roomCharge:
        return 'Room';
      case _AlertKind.newOrder:
      case _AlertKind.cancelled:
      case _AlertKind.transferred:
        break;
    }
    final n = order.items.length;
    return order.serviceCharge > 0 ? '$n items + Room' : '$n items';
  }

  /// (label, amount, colour, struck-through) for the notice's total line.
  (String, double, Color, bool) _totalFor(WaiterOrder order) {
    final info = _infoOf(order);
    switch (_kindOf(order)) {
      case _AlertKind.newOrder:
        return ('TOTAL DUE', order.grandTotal, amberAccent, false);
      case _AlertKind.itemsAdded:
        if (!_addedUnknown(order)) {
          final sum = info!.added.fold<double>(0, (s, i) => s + i.lineTotal);
          return ('ADDED', sum, _green, false);
        }
        return ('NEW TOTAL DUE', order.grandTotal, amberAccent, false);
      case _AlertKind.itemsEdited:
      case _AlertKind.roomCharge:
        return ('NEW TOTAL DUE', order.grandTotal, amberAccent, false);
      case _AlertKind.transferred:
        return ('TOTAL DUE', order.grandTotal, amberAccent, false);
      case _AlertKind.cancelled:
        return ('CANCELLED', order.grandTotal, _red, true);
    }
  }

  /// "Edited by gf_waiter2", "Cancelled — no payment needed", … or null.
  (String, Color, IconData)? _bannerFor(WaiterOrder order) {
    final info = _infoOf(order);
    final by = info?.byName;
    final byText = by == null || by.isEmpty ? '' : ' by $by';
    switch (_kindOf(order)) {
      case _AlertKind.newOrder:
        return null;
      case _AlertKind.itemsAdded:
        return byText.isEmpty ? null : ('Items added$byText', _blue, Icons.add_circle_outline_rounded);
      case _AlertKind.itemsEdited:
        return ('Order edited$byText', _blue, Icons.edit_note_rounded);
      case _AlertKind.cancelled:
        return ('Cancelled$byText — no payment needed', _red, Icons.cancel_outlined);
      case _AlertKind.roomCharge:
        return (
          _isWaived(order) ? 'Room charge waived$byText' : 'Room charge changed$byText',
          amberAccent,
          Icons.more_time_rounded,
        );
      case _AlertKind.transferred:
        return ('Moved to another table$byText', _blue, Icons.swap_horiz_rounded);
    }
  }

  /// From → to for a table transfer.
  Widget _tableMove(WaiterOrder order, {required bool compact}) {
    final info = _infoOf(order)!;
    final from = (info.fromTable ?? '').trim();
    final to = (info.toTable ?? order.tableNumber ?? '').trim();
    final fontSize = compact ? 12.5 : 15.0;
    Widget name(String text, {required bool current}) => Flexible(
          child: Text(
            text.isEmpty ? '—' : _formatTableForDisplay(text, order.orderType),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.urbanist(
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              color: current ? primaryColor : Colors.grey.shade500,
              decoration: current ? null : TextDecoration.lineThrough,
              decorationColor: Colors.grey.shade500,
            ),
          ),
        );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 2 : 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          name(from, current: false),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Icon(Icons.arrow_forward_rounded, size: compact ? 16 : 20, color: _blue),
          ),
          name(to, current: true),
        ],
      ),
    );
  }

  // ── building blocks ──────────────────────────────────────────────────────

  Widget _tag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: GoogleFonts.urbanist(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _banner(WaiterOrder order, {required bool compact}) {
    final banner = _bannerFor(order);
    if (banner == null) return const SizedBox.shrink();
    final (text, color, icon) = banner;
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: compact ? 6 : 8),
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: compact ? 5 : 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: compact ? 13 : 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.urbanist(
                fontSize: compact ? 10.5 : 11.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineRow(_AlertLine line, {required bool compact}) {
    final item = line.item;
    final added = line.sign > 0;
    final removed = line.sign < 0;
    final badgeColor = added ? _green : (removed ? _red : primaryColor);
    final badge = added
        ? '+${_fmtQty(item.quantity)}'
        : (removed ? '−${_fmtQty(item.quantity)}' : '${_fmtQty(item.quantity)}x');
    final fontSize = compact ? 11.0 : 12.0;
    final remarks = (item.remarks ?? '').trim();
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 2 : 3),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 6, vertical: compact ? 1 : 2),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              badge,
              style: GoogleFonts.urbanist(
                fontSize: fontSize - 1,
                fontWeight: FontWeight.w900,
                color: badgeColor,
              ),
            ),
          ),
          SizedBox(width: compact ? 6 : 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.urbanist(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    color: removed ? Colors.grey.shade500 : _ink,
                    decoration: removed ? TextDecoration.lineThrough : null,
                    decorationColor: Colors.grey.shade500,
                  ),
                ),
                if (!compact && remarks.isNotEmpty)
                  Text(
                    remarks,
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
          SizedBox(width: compact ? 6 : 8),
          Text(
            removed ? '−₱${formatPrice(item.lineTotal)}' : '₱${formatPrice(item.lineTotal)}',
            style: GoogleFonts.urbanist(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: removed ? _red : (added ? _green : const Color(0xFF0D9488)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roomRow(WaiterOrder order, {required bool compact}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 2 : 3),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 5, vertical: compact ? 1 : 2),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'ROOM',
              style: GoogleFonts.urbanist(
                fontSize: compact ? 8 : 9,
                fontWeight: FontWeight.w900,
                color: amberAccent,
              ),
            ),
          ),
          SizedBox(width: compact ? 6 : 8),
          Expanded(
            child: Text(
              'Room Charge',
              style: GoogleFonts.urbanist(
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
          ),
          SizedBox(width: compact ? 6 : 8),
          Text(
            '₱${formatPrice(order.serviceCharge)}',
            style: GoogleFonts.urbanist(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w800,
              color: amberAccent,
            ),
          ),
        ],
      ),
    );
  }

  /// Before → now for a room-charge change.
  Widget _roomChange(WaiterOrder order, {required bool compact}) {
    final info = _infoOf(order)!;
    final from = info.roomChargeFrom ?? 0;
    final to = info.roomChargeTo ?? order.serviceCharge;
    final fontSize = compact ? 11.5 : 13.0;
    Widget row(String label, Widget value) => Padding(
          padding: EdgeInsets.symmetric(vertical: compact ? 2 : 4),
          child: Row(
            children: [
              Text(
                label,
                style: GoogleFonts.urbanist(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
              const Spacer(),
              value,
            ],
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row(
          'Before',
          Text(
            '₱${formatPrice(from)}',
            style: GoogleFonts.urbanist(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade500,
              decoration: TextDecoration.lineThrough,
              decorationColor: Colors.grey.shade500,
            ),
          ),
        ),
        row(
          'Now',
          Text(
            to <= 0.005 ? 'Waived · ₱0.00' : '₱${formatPrice(to)}',
            style: GoogleFonts.urbanist(
              fontSize: fontSize + 1,
              fontWeight: FontWeight.w900,
              color: to <= 0.005 ? _green : amberAccent,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMulti = widget.orders.length > 1;
    final String title;
    if (isMulti) {
      final n = widget.orders.length;
      final newCount = widget.orders.where((o) => _kindOf(o) == _AlertKind.newOrder).length;
      title = newCount == n
          ? '$n NEW ORDERS RECEIVED!'
          : (newCount == 0 ? '$n ORDERS UPDATED' : '$n ORDER ALERTS');
    } else {
      title = _singleTitle(widget.orders.first);
    }

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Blurred, dimmed screen behind the alert, like the app's other popups.
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.4)),
            ),
          ),
          Center(
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
                            title,
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
        ],
      ),
    );
  }

  // --- SINGLE ORDER VIEW ---
  Widget _buildSingleOrderView(BuildContext context, WaiterOrder order) {
    final tableDisplay = order.isTakeOut ? order.takeOutLabel : _formatTableForDisplay(order.tableNumber, order.orderType);
    final kind = _kindOf(order);
    final lines = _linesFor(order);
    final showRoom = _showsRoomRow(order);
    final (totalLabel, totalAmount, totalColor, struck) = _totalFor(order);
    final showNewTotal = kind == _AlertKind.itemsAdded && !_addedUnknown(order);

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
        _banner(order, compact: false),

        // Section header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _sectionLabel(order),
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
                  _countLabel(order),
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

        // Lines
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxHeight: 230),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: kind == _AlertKind.roomCharge
                ? _roomChange(order, compact: false)
                : kind == _AlertKind.transferred
                ? _tableMove(order, compact: false)
                : (lines.isEmpty && !showRoom)
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
                        itemCount: lines.length + (showRoom ? 1 : 0),
                        separatorBuilder: (context, index) => Divider(
                          height: 8,
                          thickness: 0.6,
                          color: Colors.grey.shade200,
                        ),
                        itemBuilder: (context, index) => index < lines.length
                            ? _lineRow(lines[index], compact: false)
                            : _roomRow(order, compact: false),
                      ),
          ),
        ),
        const SizedBox(height: 10),

        // Total
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
              Text(
                totalLabel,
                style: GoogleFonts.urbanist(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: struck ? _red : Colors.grey.shade500,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                '₱${formatPrice(totalAmount)}',
                style: GoogleFonts.urbanist(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: totalColor,
                  decoration: struck ? TextDecoration.lineThrough : null,
                  decorationColor: totalColor,
                ),
              ),
            ],
          ),
        ),
        if (showNewTotal) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'New total due: ₱${formatPrice(order.grandTotal)}',
              style: GoogleFonts.urbanist(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        ],
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
  Widget _buildMultiOrdersView(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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
                final tableDisplay = order.isTakeOut ? order.takeOutLabel : _formatTableForDisplay(order.tableNumber, order.orderType);
                final orderNo = order.orderNo ?? '#${order.id}';
                final kind = _kindOf(order);
                final lines = _linesFor(order);
                final (tagLabel, tagColor) = _kindTag(order);
                final (totalLabel, totalAmount, totalColor, struck) = _totalFor(order);

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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Row(
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
                                Flexible(
                                  child: Text(
                                    tableDisplay,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.urbanist(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                      color: primaryColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                _tag(tagLabel, tagColor),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
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
                      _banner(order, compact: true),
                      if (kind == _AlertKind.roomCharge)
                        _roomChange(order, compact: true)
                      else if (kind == _AlertKind.transferred)
                        _tableMove(order, compact: true)
                      else if (lines.isEmpty)
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
                      else ...[
                        ...lines.take(4).map((line) => _lineRow(line, compact: true)),
                        if (lines.length > 4)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '+ ${lines.length - 4} more items',
                              style: GoogleFonts.urbanist(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade500,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                      ],
                      if (_showsRoomRow(order)) _roomRow(order, compact: true),
                      const SizedBox(height: 6),
                      Divider(height: 8, thickness: 0.6, color: Colors.grey.shade200),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(
                                '$totalLabel: ',
                                style: GoogleFonts.urbanist(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: struck ? _red : Colors.grey.shade500,
                                ),
                              ),
                              Text(
                                '₱${formatPrice(totalAmount)}',
                                style: GoogleFonts.urbanist(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: totalColor,
                                  decoration: struck ? TextDecoration.lineThrough : null,
                                  decorationColor: totalColor,
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
  final VoidCallback onExtendRoomCharge;
  /// Called before this cashier changes the order itself (add items, transfer).
  final VoidCallback? onSelfChange;
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
    required this.onExtendRoomCharge,
    this.onSelfChange,
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

  /// Tapping the card opens the full order breakdown.
  void _openDetails() {
    OrderDetailsSheet.show(
      context,
      order: widget.order,
      roomChargeRate: _roomChargeRate,
      floorLabel: widget.isGroundFloor ? 'GF' : '2F',
      isHistory: widget.isHistory,
      onSettle: widget.isHistory ? null : widget.onSettle,
    );
  }

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
      roomOrNumber = widget.order.isTakeOut
          ? widget.order.takeOutLabel
          : (widget.order.orderType ?? 'Dine-In');
    }

    final items = widget.order.items;
    final previewItems = items.take(3).toList();
    final remainingCount = items.length - previewItems.length;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: EdgeInsets.only(
            top: widget.isHistory ? 0 : CardCancelButton.overhang,
            right: widget.isHistory ? 0 : CardCancelButton.overhang,
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openDetails,
            child: MouseRegion(
      cursor: SystemMouseCursors.click,
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
                      if (!widget.isHistory)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: RoomCountdownBadge(
                            order: widget.order,
                            fallbackRate: _roomChargeRate,
                            onDark: true,
                            dense: true,
                          ),
                        ),
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
                    if (RoomChargeHistory.hasContent(widget.order, fallbackRate: _roomChargeRate))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: RoomChargeHistory(
                          order: widget.order,
                          fallbackRate: _roomChargeRate,
                          dense: true,
                        ),
                      ),
                    InkWell(
                        onTap: _openDetails,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2, bottom: 2),
                          child: Row(
                            children: [
                              Text(
                                remainingCount > 0
                                    ? '+ $remainingCount more items · View breakdown'
                                    : 'View breakdown',
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
                                widget.onSelfChange?.call();
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
                                  order: widget.order,
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
                        // Add Items
                        Expanded(
                          flex: 1,
                          child: SizedBox(
                            height: 36,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                widget.onSelfChange?.call();
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
                                      startInSwitchMenu: true, // new menu by default
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
                    // Rooms only: add another session without leaving the cashier.
                    if (_roomChargeRate > 0) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        height: 38,
                        child: OutlinedButton.icon(
                          onPressed: widget.onExtendRoomCharge,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF059669),
                            side: const BorderSide(color: Color(0xFF059669), width: 1.2),
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.more_time_rounded, size: 17),
                          label: Text(
                            'Extend Room Charge',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.urbanist(fontWeight: FontWeight.w800, fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
        ),
          ),
        ),
        // Cancel X on the card's top-right corner (active orders only). Big hit
        // area, inside the Stack so it's actually tappable.
        if (!widget.isHistory)
          Positioned(
            top: 0,
            right: 0,
            child: CardCancelButton(onTap: widget.onCancel),
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

  // Room hours billed in total (every room the order used), for the
  // "Room Charge (2 hrs)" line; null for a regular table.
  double? get _roomHours {
    final segments = roomChargeSegmentsOf(widget.order);
    if (segments.isEmpty) return null;
    return segments.fold<double>(0, (sum, s) => sum + s.hours);
  }

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
                                widget.order.isTakeOut ? widget.order.takeOutLabel : (widget.order.tableNumber != null ? 'Table ${widget.order.tableNumber}' : 'Dine-In'),
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
                        if (RoomChargeHistory.hasContent(widget.order)) ...[
                          const SizedBox(height: 4),
                          RoomChargeHistory(order: widget.order),
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
                                _roomHours != null
                                    ? 'Room Charge (${formatRoomHours(_roomHours!)})'
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
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(
                      isCash ? 'CASH TENDERED (₱)' : '$_selectedPaymentMethod AMOUNT PAID (₱)',
                      style: GoogleFonts.urbanist(fontSize: 12.5, fontWeight: FontWeight.w900, color: Colors.grey.shade600, letterSpacing: 1.2),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // One-tap "customer paid the exact amount". Big, full width and
                  // solid green so it can't be missed (it was a tiny chip).
                  Builder(
                    builder: (context) {
                      final isExact = _cashTendered > 0 &&
                          (_cashTendered - finalAmountDue).abs() < 0.005;
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _tenderedController.text = formatPrice(finalAmountDue);
                              _cashTendered = finalAmountDue;
                            });
                          },
                          child: Ink(
                            height: 56,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: const LinearGradient(
                                colors: [Color(0xFF10B981), Color(0xFF047857)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: emerald.withValues(alpha: 0.35),
                                  blurRadius: 12,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isExact ? Icons.check_circle_rounded : Icons.flash_on_rounded,
                                  size: 24,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  isExact ? 'EXACT AMOUNT ✓' : 'EXACT AMOUNT',
                                  style: GoogleFonts.urbanist(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '₱${formatPrice(finalAmountDue)}',
                                  style: GoogleFonts.urbanist(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
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

/// Unsettled / History / Activity as the shared sliding segmented control, driven by the
/// page's DefaultTabController (so swiping the list moves the pill too).
class _CashierTabs extends StatelessWidget {
  final int unsettledCount;
  final int historyCount;

  const _CashierTabs({
    required this.unsettledCount,
    required this.historyCount,
  });

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => SlidingSegments(
        selectedIndex: controller.index,
        position: controller.animation,
        onChanged: controller.animateTo,
        segments: [
          SegmentLabel(
            label: 'unsettled'.tr,
            icon: Icons.pending_actions_rounded,
            count: unsettledCount,
            alert: true,
          ),
          SegmentLabel(
            label: 'history'.tr,
            icon: Icons.history_rounded,
            count: historyCount,
          ),
          SegmentLabel(
            label: 'activity'.tr,
            icon: Icons.manage_history_rounded,
          ),
        ],
      ),
    );
  }
}
