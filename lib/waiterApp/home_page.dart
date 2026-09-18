import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'models.dart';
import 'waiter_models.dart';
import 'services/api_service.dart';
import 'services/socket_service.dart';
import 'services/waiter_cart_store.dart';
import '../shared/globals.dart';
import '../shared/settings_sheet.dart';
import 'widgets/confirm_order_bottom_sheet.dart';
import 'widgets/edit_order_bottom_sheet.dart';
import 'widgets/menu_picker_sheet.dart';
import 'widgets/waiter_ui.dart';
import 'widgets/waiter_sidebar.dart';
import 'widgets/center_popup.dart';
import 'widgets/transfer_table_modal.dart';
import 'widgets/extend_room_charge_dialog.dart';
import 'services/notification_service.dart';
import 'pages/get_order_page.dart';
import 'pages/tables_tab.dart';
import 'pages/new_orders_tab.dart';
import '../shared/lan_broadcast_service.dart';
import '../shared/background_service.dart';
import '../shared/offline_sync_service.dart';
import '../shared/widgets/offline_sync_banner.dart';
import '../shared/update_dialog.dart';

class WaiterHomePage extends StatefulWidget {
  const WaiterHomePage({super.key});

  @override
  State<WaiterHomePage> createState() => _WaiterHomePageState();
}

class _WaiterHomePageState extends State<WaiterHomePage> with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isLoading = true;
  String? _errorMessage;
  List<WaiterTable> _tables = [];
  List<WaiterOrder> _orders = [];
  List<MenuItem> _menuItems = [];
  int? _branchId;
  String? _currentUserId;
  // 'gf', '2f', or null (unscoped — sees both floors). Set per-account by an
  // admin via the FLOOR column on user_info; restricts this account to only
  // its own floor's tables/orders.
  String? _floorScope;
  final Set<int> _joinedOrderIds = {};
  // REST fallback poll — socket_io_client has no real HTTP-polling fallback
  // on native, so on WebSocket-blocked networks the socket never connects and
  // the dashboard would go stale. Poll every 2s (matching cashierApp) unless
  // the socket is actually connected. [_isLoadingData] stops socket-triggered
  // refreshes, manual refreshes and poll ticks from stacking up.
  Timer? _pollTimer;
  bool _isLoadingData = false;
  bool _isManualRefreshing = false;
  VoidCallback? _disposeOrderUpdated;
  VoidCallback? _disposeOrderItemsAdded;
  VoidCallback? _disposeOrderCreated;
  VoidCallback? _disposeTableUpdated;
  VoidCallback? _disposeLanOrderCreated;
  VoidCallback? _disposeLanOrderItemsAdded;
  // Cached from DefaultTabController.of(...) in build() — the "View Order"
  // action on the New Order Received popup needs to switch tabs from a
  // socket callback, outside build()'s scope where the controller normally
  // lives as a local variable.
  TabController? _tabController;
  // Sidebar's Occupied/Available submenu under "Tables" — 'all' | 'occupied'
  // | 'available'. Only meaningful while the Tables tab (index 0) is active.
  String _tableFilter = 'all';

  @override
  void initState() {
    super.initState();
    WaiterCartStore.instance.restore();
    OfflineSyncService.instance.addDataSyncedListener(_onDataSynced);
    // Floor scope must be known before the first table fetch resolves, so a
    // floor-scoped account never briefly renders the other floor's tables.
    _loadBranchId().then((_) => _loadData());
    _initializeSocket();
    BackgroundServiceManager.ensureStarted();
    checkAndPromptAppUpdate(context);
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && !SocketService.isConnected) _pollData();
    });
  }

  void _onDataSynced() {
    if (mounted) {
      debugPrint('[WAITER] Sync completed event received, refreshing data...');
      _loadData(showSpinner: false);
    }
  }

  Future<void> _loadBranchId() async {
    final userData = await ApiService.getUserData();
    final branchIdRaw = userData['branch_id'];
    final branchId =
        branchIdRaw == null ? null : int.tryParse(branchIdRaw.toString());
    if (!mounted) return;
    setState(() {
      _branchId = branchId;
      _currentUserId = userData['user_id'];
      _floorScope = userData['floor'];
    });
  }

  // Same table-naming heuristic used across waiterApp/cashierApp: tables
  // named "Room 1" through "Room 13" are 2nd Floor; every other table is
  // Ground Floor. There's no floor column on restaurant_tables — this name
  // convention is the single source of truth for "which floor is this on."
  bool _isGroundFloorNumber(String numStr) {
    final normalized = numStr.toUpperCase().trim();
    final roomMatch = RegExp(r'\bROOM\s*[-_]?\s*([0-9]+)\b').firstMatch(normalized);
    if (roomMatch != null) {
      final roomNum = int.tryParse(roomMatch.group(1) ?? '');
      if (roomNum != null && roomNum >= 1 && roomNum <= 13) {
        return false;
      }
    }
    return true;
  }

  bool _isGroundFloorTable(WaiterTable table) => _isGroundFloorNumber(table.number);

  // Single choke point for floor-scoping: every `_tables` assignment routes
  // through this so table counts, the Tables tab grid, the transfer modal
  // and the new-order table picker are all automatically restricted for a
  // floor-scoped account, with no per-consumer filtering needed.
  List<WaiterTable> _applyFloorScope(List<WaiterTable> tables) {
    if (_floorScope != 'gf' && _floorScope != '2f') return tables;
    final wantGf = _floorScope == 'gf';
    return tables.where((t) => _isGroundFloorTable(t) == wantGf).toList();
  }

  // Orders don't carry a floor field (same as tables — inferred from the
  // table-name convention above). Orders with no table (e.g. takeout) aren't
  // tied to a floor, so they always stay visible regardless of scope —
  // otherwise a floor-scoped waiter's own takeout order would vanish from
  // their own New Orders tab.
  bool _isOrderVisibleForFloorScope(WaiterOrder order) {
    if (_floorScope != 'gf' && _floorScope != '2f') return true;
    final tableNumber = order.tableNumber;
    if (tableNumber == null || tableNumber.trim().isEmpty) return true;
    final wantGf = _floorScope == 'gf';
    return _isGroundFloorNumber(tableNumber) == wantGf;
  }

  // Mirrors _applyFloorScope but for orders — used at the New Orders/Order
  // List derivation point and before firing the new-order alert, so a
  // floor-scoped waiter never sees or gets alerted about the other floor's
  // orders even though the underlying socket room is branch-wide, not
  // floor-scoped.
  List<WaiterOrder> _applyOrderFloorScope(List<WaiterOrder> orders) {
    return orders.where(_isOrderVisibleForFloorScope).toList();
  }

  @override
  void dispose() {
    OfflineSyncService.instance.removeDataSyncedListener(_onDataSynced);
    _pollTimer?.cancel();
    _cleanupSocket();
    super.dispose();
  }

  /// Lightweight fallback poll (2s) for when the socket isn't connected:
  /// tables + orders only, no menu refetch, no spinner.
  Future<void> _pollData() async {
    if (_isLoadingData) return;
    _isLoadingData = true;
    try {
      final tablesResult = await ApiService.getTables();
      if (tablesResult['unauthorized'] == true) {
        await _redirectToLogin();
        return;
      }
      final ordersResult = await ApiService.getWaiterOrders();
      if (ordersResult['unauthorized'] == true) {
        await _redirectToLogin();
        return;
      }
      if (!mounted) return;
      if (tablesResult['success'] == true && ordersResult['success'] == true) {
        setState(() {
          _tables = _applyFloorScope(List<Map<String, dynamic>>.from(tablesResult['data'])
              .map(WaiterTable.fromApi)
              .toList());
          _orders = List<Map<String, dynamic>>.from(ordersResult['data'])
              .map(WaiterOrder.fromApi)
              .toList();
        });
        _syncSocketOrderRooms();
      }
    } catch (e) {
      debugPrint('❌ Error in _pollData: $e');
    } finally {
      _isLoadingData = false;
    }
  }

  /// Manual refresh — wired to the refresh button next to Logout. Does a full
  /// reload (tables + orders + menu) and surfaces a brief snackbar.
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

  Future<void> _loadData({bool showSpinner = true}) async {
    // Never let socket-triggered background refreshes / poll ticks stack up.
    if (_isLoadingData) return;
    _isLoadingData = true;

    if (showSpinner) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final tablesResult = await ApiService.getTables();
      if (tablesResult['unauthorized'] == true) {
        await _redirectToLogin();
        return;
      }

      final ordersResult = await ApiService.getWaiterOrders();
      if (ordersResult['unauthorized'] == true) {
        await _redirectToLogin();
        return;
      }

      final menuResult = await ApiService.getMenuItems();
      if (menuResult['unauthorized'] == true) {
        await _redirectToLogin();
        return;
      }

      if (tablesResult['success'] == true &&
          ordersResult['success'] == true &&
          menuResult['success'] == true) {
        final tablesData = List<Map<String, dynamic>>.from(
          tablesResult['data'],
        );
        final ordersData = List<Map<String, dynamic>>.from(
          ordersResult['data'],
        );
        final menuData = List<Map<String, dynamic>>.from(
          menuResult['data'],
        );

        setState(() {
          _tables = _applyFloorScope(tablesData.map(WaiterTable.fromApi).toList());
          _orders = ordersData.map(WaiterOrder.fromApi).toList();
          _menuItems = menuData.map(MenuItem.fromApi).toList();
          _isLoading = false;
        });
        _syncSocketOrderRooms();
        unawaited(ApiService.getTopRevenueItems(limit: 15));
      } else {
        setState(() {
          if (_tables.isEmpty && _menuItems.isEmpty) {
            _errorMessage =
                tablesResult['error'] ?? ordersResult['error'] ?? menuResult['error'];
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        if (_tables.isEmpty && _menuItems.isEmpty) {
          _errorMessage = 'Error loading data: ${e.toString()}';
        }
        _isLoading = false;
      });
    } finally {
      _isLoadingData = false;
    }
  }

  // Opening the ordering screen previously used a bare MaterialPageRoute,
  // which on Flutter Web can resolve to an underwhelming/near-instant
  // transition depending on the detected platform. This gives it an
  // explicit, consistent slide-in-from-right + fade regardless of platform.
  Route<T> _getOrderPageRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 550),
      reverseTransitionDuration: const Duration(milliseconds: 450),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeInOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.25, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _redirectToLogin() async {
    await ApiService.logout();
    if (!mounted) return;
    refreshAppAuth();
  }

  Future<void> _confirmOrder(WaiterOrder order) async {
    final shouldConfirm = await _showConfirmOrderSheet(order);

    if (shouldConfirm != true) {
      return;
    }

    final result = await ApiService.updateWaiterOrderStatus(
      orderId: order.id,
      status: 2,
    );

    if (result['unauthorized'] == true) {
      await _redirectToLogin();
      return;
    }

    if (result['success'] == true) {
      setState(() {
        _orders = _orders.map((o) {
          if (o.id == order.id) {
            return o.copyWith(status: 2);
          }
          return o;
        }).toList();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${order.orderNo ?? 'Order #${order.id}'} confirmed successfully.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'] ?? 'Failed to confirm order'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _initializeSocket() async {
    try {
      await SocketService.initialize();
      // Join the waiter role room — table_updated events (e.g. a table freed
      // when the cashier settles its bill) are broadcast ONLY to the role
      // rooms, never to the per-order rooms this screen subscribes to. Without
      // this the dashboard never sees a table go back to Available in realtime.
      SocketService.joinWaiter();

      _disposeOrderUpdated?.call();
      _disposeOrderUpdated = SocketService.addOrderUpdateListener((data) {
        if (!mounted) return;
        _handleSocketOrderEvent(data);
      });

      _disposeOrderItemsAdded?.call();
      _disposeOrderItemsAdded = SocketService.addOrderItemsAddedListener((data) {
        if (!mounted) return;
        _handleSocketOrderEvent(data);
      });

      _disposeOrderCreated?.call();
      _disposeOrderCreated = SocketService.addOrderCreatedListener((data) {
        if (!mounted) return;
        _handleSocketOrderEvent(data);
      });

      _disposeTableUpdated?.call();
      _disposeTableUpdated = SocketService.addTableUpdateListener((data) {
        if (!mounted) return;
        _handleSocketTableEvent(data);
      });

      // LAN fallback: same handler, just fed from a WiFi-local broadcast
      // instead of the cloud socket — see lan_broadcast_service.dart. Alerts
      // stay cashierApp-only even for this offline path, so allowAlert:false.
      _disposeLanOrderCreated?.call();
      _disposeLanOrderCreated = LanBroadcastService.instance.addOrderCreatedListener((data) {
        if (!mounted) return;
        _handleSocketOrderEvent(data, allowAlert: false);
      });

      _disposeLanOrderItemsAdded?.call();
      _disposeLanOrderItemsAdded = LanBroadcastService.instance.addOrderItemsAddedListener((data) {
        if (!mounted) return;
        _handleSocketOrderEvent(data, allowAlert: false);
      });

      _syncSocketOrderRooms();
    } catch (e) {
      debugPrint('Error initializing socket in waiter_home_page: $e');
    }
  }

  void _handleSocketOrderEvent(Map<String, dynamic> data, {bool allowAlert = true}) {
    // Ignore other branches' realtime traffic (defensive — the backend already
    // emits to per-branch rooms).
    final rawOrderData = data['order'];
    if (_branchId != null) {
      final rawBranch = data['branch_id'] ??
          data['branchId'] ??
          (rawOrderData is Map
              ? (rawOrderData['branch_id'] ?? rawOrderData['BRANCH_ID'] ?? rawOrderData['branchId'])
              : null);
      final eventBranch =
          rawBranch is int ? rawBranch : int.tryParse(rawBranch?.toString() ?? '');
      if (eventBranch != null && eventBranch != _branchId) return;
    }
    final orderData = rawOrderData is Map
        ? Map<String, dynamic>.from(rawOrderData)
        : Map<String, dynamic>.from(data);

    if (orderData['order_id'] == null && orderData['orderId'] != null) {
      orderData['order_id'] = orderData['orderId'];
    }
    if (orderData['order_id'] == null && data['order_id'] != null) {
      orderData['order_id'] = data['order_id'];
    }
    if (orderData['order_no'] == null && data['order_no'] != null) {
      orderData['order_no'] = data['order_no'];
    }

    final orderIdRaw = orderData['order_id'];
    final orderId = orderIdRaw is int ? orderIdRaw : int.tryParse(orderIdRaw?.toString() ?? '');
    if (orderId == null) return;

    final existingIndex = _orders.indexWhere((o) => o.id == orderId);
    if (existingIndex == -1 && orderData['items'] == null) {
      // Ignore partial payloads to keep updates seamless without refresh.
      return;
    }

    try {
      final normalized = _normalizeSocketOrder(orderData);
      final updatedOrder = WaiterOrder.fromApi(normalized);

      // Check if this is a new pending order (status == 3)
      final isNewPendingOrder = existingIndex == -1 && updatedOrder.status == 3;

      // Don't alert the waiter about an order they just placed themselves —
      // the "New Order Received" banner is meant to notify OTHER staff.
      final creatorId = orderData['encoded_by']?.toString();
      final isOwnOrder = creatorId != null &&
          _currentUserId != null &&
          creatorId == _currentUserId;

      setState(() {
        if (existingIndex == -1) {
          _orders = [..._orders, updatedOrder];
        } else {
          final nextOrders = List<WaiterOrder>.from(_orders);
          nextOrders[existingIndex] = updatedOrder;
          _orders = nextOrders;
        }
      });
      _syncSocketOrderRooms();

      // While offline, this device's own poll fallback re-reads its local
      // cache and replaces `_orders` wholesale — an order that only ever
      // lived in memory (arrived via LAN broadcast, never created here)
      // would get wiped on the very next poll tick and flicker in and out.
      // Persist it locally so that fallback sees it too.
      if (OfflineSyncService.instance.isOffline) {
        unawaited(OfflineSyncService.instance.upsertCachedOrder(normalized));
      }

      // Show alert for new pending orders placed by someone else. Only for
      // the real (online) socket path — allowAlert:false for the LAN
      // fallback keeps offline-mode notifications cashierApp-only.
      if (allowAlert &&
          isNewPendingOrder &&
          !isOwnOrder &&
          mounted &&
          _isOrderVisibleForFloorScope(updatedOrder)) {
        _showNewOrderAlert(updatedOrder);
      }
    } catch (e) {
      debugPrint('Error updating order from socket in waiter_home_page: $e');
    }
  }

  Map<String, dynamic> _normalizeSocketOrder(Map<String, dynamic> data) {
    final normalized = Map<String, dynamic>.from(data);
    if (normalized['order_id'] == null && normalized['orderId'] != null) {
      normalized['order_id'] = normalized['orderId'];
    }
    if (normalized['order_no'] == null && normalized['orderNo'] != null) {
      normalized['order_no'] = normalized['orderNo'];
    }
    if (normalized['table_id'] == null && normalized['tableId'] != null) {
      normalized['table_id'] = normalized['tableId'];
    }
    if (normalized['table_number'] == null && normalized['tableNumber'] != null) {
      normalized['table_number'] = normalized['tableNumber'];
    }
    if (normalized['grand_total'] == null && normalized['grandTotal'] != null) {
      normalized['grand_total'] = normalized['grandTotal'];
    }
    if (normalized['items'] is List) {
      normalized['items'] = (normalized['items'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    }
    return normalized;
  }

  void _cleanupSocket() {
    try {
      for (final orderId in _joinedOrderIds) {
        SocketService.leaveOrder(orderId);
      }
      _joinedOrderIds.clear();
      _disposeOrderUpdated?.call();
      _disposeOrderItemsAdded?.call();
      _disposeOrderCreated?.call();
      _disposeTableUpdated?.call();
      _disposeLanOrderCreated?.call();
      _disposeLanOrderItemsAdded?.call();
      _disposeOrderUpdated = null;
      _disposeOrderItemsAdded = null;
      _disposeOrderCreated = null;
      _disposeTableUpdated = null;
      _disposeLanOrderCreated = null;
      _disposeLanOrderItemsAdded = null;
    } catch (e) {
      debugPrint('Error cleaning up socket in waiter_home_page: $e');
    }
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

  void _showNewOrderAlert(WaiterOrder order) {
    final orderNo = order.orderNo ?? 'Order #${order.id}';
    final tableNumber = order.tableNumber;

    // Show local notification (works even in background/sleep)
    NotificationService.showNewOrderNotification(
      orderNo: orderNo,
      tableNumber: tableNumber,
    );

    // Play system notification sound (only if app is in foreground)
    SystemSound.play(SystemSoundType.alert);

    // Haptic feedback for better user experience (only if app is in foreground)
    HapticFeedback.mediumImpact();

    // Centered popup (only if app is in foreground) — more visible than the
    // old top-slide banner. Stays open until the waiter dismisses it.
    showCenterPopup(
      context,
      icon: Icons.notifications_active,
      accentColor: const Color(0xFFE8C468),
      title: 'New Order Received!',
      subtitle: tableNumber != null ? '$orderNo • Table $tableNumber' : orderNo,
      actionLabel: 'View Order',
      onAction: () => _tabController?.animateTo(1),
      shakeIcon: true,
    );
  }

  void _handleSocketTableEvent(Map<String, dynamic> data) {
    final rawTableData = data['table'];
    final tableData = rawTableData is Map
        ? Map<String, dynamic>.from(rawTableData)
        : Map<String, dynamic>.from(data);
    final action = (data['action'] ?? tableData['action'])?.toString() ?? 'updated';

    if (tableData['id'] == null && tableData['table_id'] != null) {
      tableData['id'] = tableData['table_id'];
    }
    if (tableData['table_number'] == null && tableData['tableNumber'] != null) {
      tableData['table_number'] = tableData['tableNumber'];
    }
    if (tableData['capacity'] == null && tableData['CAPACITY'] != null) {
      tableData['capacity'] = tableData['CAPACITY'];
    }
    if (tableData['status'] == null && tableData['STATUS'] != null) {
      tableData['status'] = tableData['STATUS'];
    }

    final tableIdRaw = tableData['id'];
    final tableId =
        tableIdRaw is int ? tableIdRaw : int.tryParse(tableIdRaw?.toString() ?? '');
    if (tableId == null) return;
    final branchIdRaw = tableData['branch_id'] ?? tableData['BRANCH_ID'];
    final tableBranchId = branchIdRaw is int
        ? branchIdRaw
        : int.tryParse(branchIdRaw?.toString() ?? '');
    if (_branchId != null && tableBranchId != null && tableBranchId != _branchId) {
      return;
    }

    try {
      if (action == 'deleted') {
        setState(() {
          _tables = _applyFloorScope(_tables.where((t) => t.id != tableId).toList());
        });
        return;
      }

      final updatedTable = WaiterTable.fromApi(tableData);
      setState(() {
        final existingIndex = _tables.indexWhere((t) => t.id == tableId);
        if (existingIndex == -1) {
          _tables = _applyFloorScope([..._tables, updatedTable]);
          return;
        }
        final nextTables = List<WaiterTable>.from(_tables);
        nextTables[existingIndex] = updatedTable;
        _tables = _applyFloorScope(nextTables);
      });
    } catch (e) {
      debugPrint('Error updating table from socket in waiter_home_page: $e');
    }
  }

  Future<void> _editOrder(WaiterOrder order) async {
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
      final newTotal = updatedItems.fold<double>(
        0,
        (sum, item) => sum + item.lineTotal,
      );
      final updatedOrderItems = updatedItems
          .map(
            (item) => WaiterOrderItem(
              id: null,
              menuId: item.menuId,
              name: item.name,
              quantity: item.quantity,
              unitPrice: item.unitPrice,
              lineTotal: item.lineTotal,
              status: item.status,
            ),
          )
          .toList();

      setState(() {
        _orders = _orders.map((o) {
          if (o.id == order.id) {
            return o.copyWith(
              items: updatedOrderItems,
              grandTotal: newTotal,
            );
          }
          return o;
        }).toList();
      });

      if (mounted) {
        showCenterPopup(
          context,
          icon: Icons.check_circle,
          accentColor: Colors.green,
          title: 'Order Updated Successfully!',
          subtitle: order.orderNo ?? 'Order #${order.id}',
        );
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'] ?? 'Failed to update order'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Cancelling reuses the same status-update endpoint used to settle/confirm
  // orders (status: -1 instead of 1/2) — the backend already fully handles
  // it (frees the table, reverses inventory deductions), same as the
  // existing cancel button in the admin web panel and cashierApp.
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

  // "Add Items" from the Order List details sheet — same "Additional Order"
  // flow _showTableOrderDetails already offers from the Tables tab, just
  // entered from an order directly instead of a table. GetOrderPage needs a
  // WaiterTable (not just the order's tableId/tableNumber), so look it up.
  Future<void> _addItemsToOrder(WaiterOrder order) async {
    WaiterTable? table;
    try {
      table = _tables.firstWhere((t) => t.id == order.tableId);
    } catch (_) {
      table = null;
    }

    if (table == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not find this order\'s table.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    await Navigator.of(context).push(
      _getOrderPageRoute(
        GetOrderPage(
          table: table,
          menuItems: _menuItems,
          existingOrder: order,
        ),
      ),
    );
    if (!mounted) return;
    await _loadData(showSpinner: false);
    if (!mounted) return;

    // Land back on this same order's details (refreshed with whatever was
    // just added) instead of dropping the waiter back on the bare Order
    // List grid.
    final updatedOrder = _orders.firstWhere(
      (o) => o.id == order.id,
      orElse: () => order,
    );
    _showOrderDetailsSheet(updatedOrder);
  }

  // Shared lookup used by both table-card actions below (and mirrored by
  // _showTableOrderDetails) — prefers an active order (confirmed/settled/
  // pending) over whatever else might be attached to the table.
  WaiterOrder? _findOrderForTable(WaiterTable table) {
    try {
      return _orders.firstWhere(
        (order) => order.tableId == table.id && (order.status == 2 || order.status == 1 || order.status == 3),
        orElse: () => _orders.firstWhere(
          (order) => order.tableId == table.id,
        ),
      );
    } catch (e) {
      return null;
    }
  }

  // "Add Order" button on an Occupied table card (Tables tab) — jumps
  // straight into the additional-items flow instead of requiring a
  // View Details tap first.
  Future<void> _addOrderForTable(WaiterTable table) async {
    final tableOrder = _findOrderForTable(table);

    if (tableOrder == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No order found for Table ${table.number}'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    await Navigator.of(context).push(
      _getOrderPageRoute(
        GetOrderPage(
          table: table,
          menuItems: _menuItems,
          existingOrder: tableOrder,
        ),
      ),
    );
    if (!mounted) return;
    await _loadData(showSpinner: false);
  }

  // "Edit Order" button on an Occupied table card — same edit-items flow
  // as the New Orders/Order List cards, just entered from the table.
  Future<void> _editOrderForTable(WaiterTable table) async {
    final tableOrder = _findOrderForTable(table);

    if (tableOrder == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No order found for Table ${table.number}'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    await _editOrder(tableOrder);
  }

  // "Extend Room Charge" button on a VIP/KTV room card — adds one more unit
  // of the table's room charge onto the active order's service charge.
  Future<void> _extendRoomChargeForTable(WaiterTable table) async {
    WaiterOrder? tableOrder;
    try {
      tableOrder = _orders.firstWhere(
        (order) => order.tableId == table.id && (order.status == 2 || order.status == 3),
      );
    } catch (_) {
      tableOrder = null;
    }

    if (tableOrder == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No active order to extend for ${table.number}'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final order = tableOrder;
    final qty = await showExtendRoomChargeConfirm(
      context,
      tableName: table.number,
      orderLabel: order.orderNo ?? '#${order.id}',
      roomCharge: table.roomCharge,
      currentRoomCharge: order.serviceCharge,
    );

    if (qty == null || qty <= 0 || !mounted) return;

    final result = await ApiService.extendRoomCharge(orderId: order.id, qty: qty);
    if (!mounted) return;

    if (result['success'] == true) {
      final data = result['data'] as Map<String, dynamic>?;
      final added = (data?['room_charge_added'] as num?)?.toDouble() ?? table.roomCharge;
      final newServiceCharge = (data?['service_charge'] as num?)?.toDouble() ??
          (order.serviceCharge + added);
      final newTotal = (data?['grand_total'] as num?)?.toDouble() ??
          (order.grandTotal + added);
      final units = table.roomCharge > 0
          ? (newServiceCharge / table.roomCharge * 2).round() / 2
          : null;

      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.mediumImpact();
      await showRoomChargeExtendedResult(
        context,
        tableName: table.number,
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
        result['error']?.toString() ?? 'Failed to extend room charge',
      );
    }
  }

  void _showTableOrderDetails(WaiterTable table) {
    // Find the order for this table
    WaiterOrder? tableOrder;
    try {
      tableOrder = _orders.firstWhere(
        (order) => order.tableId == table.id && (order.status == 2 || order.status == 1 || order.status == 3),
        orElse: () => _orders.firstWhere(
          (order) => order.tableId == table.id,
        ),
      );
    } catch (e) {
      // No order found for this table
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No order found for Table ${table.number}'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final order = tableOrder!;

    // Convert order items to ConfirmOrderLine format
    final orderLines = order.items.map((item) {
      return ConfirmOrderLine(
        name: item.name,
        quantity: item.quantity,
        unitPrice: item.unitPrice,
        lineTotal: item.lineTotal,
        remarks: item.remarks,
      );
    }).toList();
    // Show order details in a view-only bottom sheet
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final mq = MediaQuery.of(context);
        final screenWidth = mq.size.width;
        final screenHeight = mq.size.height;
        final isMobile = screenWidth < 600;

        final rawTableName = table.number.trim();
        final displayTableName = rawTableName.toLowerCase().startsWith('table')
            ? rawTableName
            : 'Table $rawTableName';

        final totalQuantity = orderLines.fold<double>(0, (sum, line) => sum + line.quantity);
        final totalQtyStr = totalQuantity % 1 == 0 ? totalQuantity.toInt().toString() : totalQuantity.toStringAsFixed(1);

        return Container(
          constraints: BoxConstraints(
            maxHeight: screenHeight * 0.85,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFFF5F6F0),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 16 : 20,
                  vertical: isMobile ? 14 : 16,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)],
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long_rounded, color: Color(0xFFE8C468), size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Order Details',
                            style: GoogleFonts.urbanist(
                              fontSize: isMobile ? 18 : 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            order.orderNo ?? 'Order #${order.id}',
                            style: GoogleFonts.urbanist(
                              fontSize: isMobile ? 13 : 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 26),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),

              // Items List
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(14),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10, left: 4),
                      child: Text(
                        displayTableName,
                        style: GoogleFonts.urbanist(
                          fontSize: isMobile ? 16 : 17.5,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0C0E2B),
                        ),
                      ),
                    ),
                    for (final line in orderLines)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    line.name,
                                    style: GoogleFonts.urbanist(
                                      fontSize: isMobile ? 15 : 16,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF0C0E2B),
                                      height: 1.2,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (line.remarks != null && line.remarks!.trim().isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE8C468).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFFE8C468).withValues(alpha: 0.6)),
                                      ),
                                      child: Text(
                                        '📝 ${line.remarks}',
                                        style: GoogleFonts.urbanist(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFFB45309),
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 3),
                                  Text(
                                    '${line.quantity.toStringAsFixed(line.quantity % 1 == 0 ? 0 : 2)} × ₱${formatPrice(line.unitPrice)}',
                                    style: GoogleFonts.urbanist(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '₱${formatPrice(line.total)}',
                              style: GoogleFonts.urbanist(
                                fontSize: isMobile ? 16.5 : 18,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFFD97706),
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              // Total Breakdown Section
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 18 : 22,
                  vertical: isMobile ? 14 : 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade200, width: 1),
                    bottom: BorderSide(color: Colors.grey.shade200, width: 1),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Total Amount',
                          style: GoogleFonts.urbanist(
                            fontSize: isMobile ? 17 : 19,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0C0E2B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Items ($totalQtyStr)',
                          style: GoogleFonts.urbanist(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '₱${formatPrice(order.grandTotal)}',
                      style: GoogleFonts.urbanist(
                        fontSize: isMobile ? 22 : 25,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFFD97706),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom Buttons (Transfer Table & Additional Order)
              Container(
                padding: EdgeInsets.fromLTRB(16, 12, 16, isMobile ? 16 : 20),
                decoration: const BoxDecoration(color: Color(0xFFF5F6F0)),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      // Transfer Table Button
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            Navigator.pop(context);
                            final transferred = await showTransferTableModal(
                              context: context,
                              orderId: order.id,
                              currentTableName: displayTableName,
                              currentTableId: table.id,
                              allTables: _tables,
                            );
                            if (transferred == true && mounted) {
                              _loadData(showSpinner: false);
                            }
                          },
                          icon: const Icon(Icons.swap_horiz_rounded, size: 20, color: Color(0xFF0C0E2B)),
                          label: Text(
                            'Transfer',
                            style: GoogleFonts.urbanist(
                              fontWeight: FontWeight.bold,
                              fontSize: isMobile ? 14 : 15.5,
                              color: const Color(0xFF0C0E2B),
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: isMobile ? 14 : 16),
                            side: const BorderSide(color: Color(0xFF0C0E2B), width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Additional Order Button
                      Expanded(
                        flex: 1,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF0C0E2B).withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                _getOrderPageRoute(
                                  GetOrderPage(
                                    table: table,
                                    menuItems: _menuItems,
                                    existingOrder: order,
                                  ),
                                ),
                              ).then((_) {
                                if (mounted) {
                                  _loadData(showSpinner: false);
                                }
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: isMobile ? 14 : 16),
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              'Add Order',
                              style: GoogleFonts.urbanist(
                                fontWeight: FontWeight.bold,
                                fontSize: isMobile ? 15 : 16.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Order List cards are tappable — this shows the same kind of summary as
  // _showTableOrderDetails above, but built straight from a WaiterOrder
  // (Order List already has the order in hand; no table lookup needed).
  void _showOrderDetailsSheet(WaiterOrder order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final mq = MediaQuery.of(context);
        final screenWidth = mq.size.width;
        final screenHeight = mq.size.height;
        final isMobile = screenWidth < 600;

        final rawTableName = (order.tableNumber ?? '').trim();
        final displayTableName = rawTableName.isEmpty
            ? 'Order #${order.id}'
            : (rawTableName.toLowerCase().startsWith('table') ? rawTableName : 'Table $rawTableName');

        final totalQuantity = order.items.fold<double>(0, (sum, item) => sum + item.quantity);
        final totalQtyStr = totalQuantity % 1 == 0 ? totalQuantity.toInt().toString() : totalQuantity.toStringAsFixed(1);

        return Container(
          constraints: BoxConstraints(
            maxHeight: screenHeight * 0.85,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFFF5F6F0),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 16 : 20,
                  vertical: isMobile ? 14 : 16,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)],
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long_rounded, color: Color(0xFFE8C468), size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Order Details',
                            style: GoogleFonts.urbanist(
                              fontSize: isMobile ? 18 : 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                order.orderNo ?? 'Order #${order.id}',
                                style: GoogleFonts.urbanist(
                                  fontSize: isMobile ? 13 : 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(width: 8),
                              StatusChip(status: order.status),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 26),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),

              // Items List
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(14),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10, left: 4),
                      child: Text(
                        displayTableName,
                        style: GoogleFonts.urbanist(
                          fontSize: isMobile ? 16 : 17.5,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0C0E2B),
                        ),
                      ),
                    ),
                    for (final item in order.items)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    item.name,
                                    style: GoogleFonts.urbanist(
                                      fontSize: isMobile ? 15 : 16,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF0C0E2B),
                                      height: 1.2,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (item.remarks != null && item.remarks!.trim().isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE8C468).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFFE8C468).withValues(alpha: 0.6)),
                                      ),
                                      child: Text(
                                        '📝 ${item.remarks}',
                                        style: GoogleFonts.urbanist(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFFB45309),
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 3),
                                  Text(
                                    '${item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 2)} × ₱${formatPrice(item.unitPrice)}',
                                    style: GoogleFonts.urbanist(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '₱${formatPrice(item.lineTotal)}',
                              style: GoogleFonts.urbanist(
                                fontSize: isMobile ? 16.5 : 18,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFFD97706),
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              // Total Breakdown Section
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 18 : 22,
                  vertical: isMobile ? 14 : 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade200, width: 1),
                    bottom: BorderSide(color: Colors.grey.shade200, width: 1),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (order.serviceCharge > 0 || order.taxAmount > 0 || order.discountAmount > 0) ...[
                      _TotalsRow(
                        label: 'Subtotal',
                        value: order.subtotal,
                        isMobile: isMobile,
                      ),
                      if (order.serviceCharge > 0)
                        _TotalsRow(
                          label: 'Service / Room Charge',
                          value: order.serviceCharge,
                          isMobile: isMobile,
                        ),
                      if (order.taxAmount > 0)
                        _TotalsRow(
                          label: 'Tax',
                          value: order.taxAmount,
                          isMobile: isMobile,
                        ),
                      if (order.discountAmount > 0)
                        _TotalsRow(
                          label: 'Discount',
                          value: -order.discountAmount,
                          isMobile: isMobile,
                        ),
                      const SizedBox(height: 6),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Total Amount',
                              style: GoogleFonts.urbanist(
                                fontSize: isMobile ? 17 : 19,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0C0E2B),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Items ($totalQtyStr)',
                              style: GoogleFonts.urbanist(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '₱${formatPrice(order.grandTotal)}',
                          style: GoogleFonts.urbanist(
                            fontSize: isMobile ? 22 : 25,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFFD97706),
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Action Buttons
              if (order.status == 2)
                Container(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, isMobile ? 16 : 20),
                  decoration: const BoxDecoration(color: Color(0xFFF5F6F0)),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (order.tableId != null) ...[
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                Navigator.pop(context);
                                final transferred = await showTransferTableModal(
                                  context: context,
                                  orderId: order.id,
                                  currentTableName: displayTableName,
                                  currentTableId: order.tableId,
                                  allTables: _tables,
                                );
                                if (transferred == true && mounted) {
                                  _loadData(showSpinner: false);
                                }
                              },
                              icon: const Icon(Icons.swap_horiz_rounded, size: 20, color: Color(0xFF0C0E2B)),
                              label: Text(
                                'Transfer Table',
                                style: GoogleFonts.urbanist(
                                  fontWeight: FontWeight.bold,
                                  fontSize: isMobile ? 14.5 : 16,
                                  color: const Color(0xFF0C0E2B),
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.symmetric(
                                  vertical: isMobile ? 12 : 14,
                                ),
                                side: const BorderSide(color: Color(0xFF0C0E2B), width: 1.5),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _editOrder(order);
                                },
                                style: OutlinedButton.styleFrom(
                                  padding: EdgeInsets.symmetric(
                                    vertical: isMobile ? 14 : 16,
                                  ),
                                  foregroundColor: const Color(0xFF0C0E2B),
                                  side: const BorderSide(color: Color(0xFF0C0E2B), width: 1.5),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: Text(
                                  'Edit Order',
                                  style: GoogleFonts.urbanist(
                                    fontWeight: FontWeight.bold,
                                    fontSize: isMobile ? 14.5 : 16,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF0C0E2B).withValues(alpha: 0.3),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ElevatedButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _addItemsToOrder(order);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    padding: EdgeInsets.symmetric(
                                      vertical: isMobile ? 14 : 16,
                                    ),
                                    backgroundColor: Colors.transparent,
                                    foregroundColor: Colors.white,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: Text(
                                    'Add Items',
                                    style: GoogleFonts.urbanist(
                                      fontWeight: FontWeight.bold,
                                      fontSize: isMobile ? 14.5 : 16,
                                    ),
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
              // Independent of the status==2 block above (Transfer/Edit/Add
              // Items) so adding Cancel here can't disturb any of that —
              // covers both pending (3) and confirmed (2) orders, matching
              // cashierApp's cancel availability.
              if (order.status == 2 || order.status == 3)
                Container(
                  padding: EdgeInsets.fromLTRB(16, order.status == 2 ? 0 : 12, 16, isMobile ? 16 : 20),
                  decoration: const BoxDecoration(color: Color(0xFFF5F6F0)),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _cancelOrder(order);
                        },
                        icon: Icon(Icons.close_rounded, size: 20, color: Colors.red.shade700),
                        label: Text(
                          'Cancel Order',
                          style: GoogleFonts.urbanist(
                            fontWeight: FontWeight.bold,
                            fontSize: isMobile ? 14.5 : 16,
                            color: Colors.red.shade700,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: isMobile ? 12 : 14),
                          side: BorderSide(color: Colors.red.shade300, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
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

  Future<bool?> _showConfirmOrderSheet(WaiterOrder order) async {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (context) {
        return ConfirmOrderBottomSheet(
          title: 'Confirm order',
          subtitle: order.orderNo ?? 'Order #${order.id}',
          items: order.items
              .map(
                (item) => ConfirmOrderLine(
                  name: item.name,
                  quantity: item.quantity,
                  unitPrice: item.unitPrice,
                  lineTotal: item.lineTotal,
                ),
              )
              .toList(),
          total: order.grandTotal,
          onCancel: () {},
          onConfirm: () {},
        );
      },
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F6F0),
        appBar: AppBar(
          title: Text(
            'WAITER DASHBOARD',
            style: GoogleFonts.urbanist(
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              fontSize: 18,
              color: const Color(0xFF1A1C18),
            ),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0C0E2B)),
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F6F0),
        appBar: AppBar(
          title: Text(
            'WAITER DASHBOARD',
            style: GoogleFonts.urbanist(
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              fontSize: 18,
              color: const Color(0xFF1A1C18),
            ),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red[700]),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => _loadData(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0C0E2B),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final scopedOrders = _applyOrderFloorScope(_orders);
    final newOrders = scopedOrders.where((order) => order.status == 3).toList();
    final confirmedOrders = scopedOrders.where((order) => order.status == 2 || order.status == 1 || order.status == -1).toList();
    // Badge counts: New Orders = pending orders awaiting review; Order List =
    // confirmed-but-not-yet-settled orders, i.e. the ones still active on the
    // floor. Settled (status 1) orders are just history, not "unread" items.
    final newOrdersCount = newOrders.length;
    final activeOrderCount = scopedOrders.where((order) => order.status == 2).length;

    return DefaultTabController(
      length: 3,
      child: Builder(
        builder: (innerContext) {
          // Sidebar (tablet/desktop) replaces the old top AppBar + TabBar;
          // phones keep that original layout since a persistent left rail
          // doesn't fit a narrow screen.
          final mediaQuery = MediaQuery.of(innerContext);
          final screenWidth = mediaQuery.size.width;
          final isLandscape = mediaQuery.orientation == Orientation.landscape;
          // Desktop sidebar is ONLY for very wide desktop PC screens (>= 1500px).
          // Tablets (like Galaxy Tab A9 at 1340x800), mobile phones, and mobile landscape use full Mobile View UI.
          final useSidebar = isLandscape && screenWidth >= 1500;
          final isMobile = !useSidebar;
          final controller = DefaultTabController.of(innerContext);
          _tabController = controller;

          Future<void> logout() async {
            await ApiService.logout();
            if (mounted) {
              refreshAppAuth();
            }
          }

          final allTablesCount = _tables.length;
          final gfAvailableCount = _tables.where((t) => _isGroundFloorTable(t) && t.status == 1).length;
          final gfOccupiedCount = _tables.where((t) => _isGroundFloorTable(t) && t.status != 1).length;
          final secondFloorAvailableCount = _tables.where((t) => !_isGroundFloorTable(t) && t.status == 1).length;
          final secondFloorOccupiedCount = _tables.where((t) => !_isGroundFloorTable(t) && t.status != 1).length;

          // Filter tables based on selected tab / sidebar option
          final filteredTables = _tableFilter == 'gf_available'
              ? _tables.where((t) => _isGroundFloorTable(t) && t.status == 1).toList()
              : _tableFilter == 'gf_occupied'
                  ? _tables.where((t) => _isGroundFloorTable(t) && t.status != 1).toList()
                  : _tableFilter == '2f_available'
                      ? _tables.where((t) => !_isGroundFloorTable(t) && t.status == 1).toList()
                      : _tableFilter == '2f_occupied'
                          ? _tables.where((t) => !_isGroundFloorTable(t) && t.status != 1).toList()
                          : _tableFilter == 'ground_floor'
                              ? _tables.where(_isGroundFloorTable).toList()
                              : _tableFilter == '2nd_floor'
                                  ? _tables.where((t) => !_isGroundFloorTable(t)).toList()
                                  : _tableFilter == 'occupied'
                                      ? _tables.where((t) => t.status != 1).toList()
                                      : _tableFilter == 'available'
                                          ? _tables.where((t) => t.status == 1).toList()
                                          : _tables;

          final tablesTitle = _tableFilter == 'gf_available'
              ? 'Ground Floor - Available Tables'
              : _tableFilter == 'gf_occupied'
                  ? 'Ground Floor - Occupied Tables'
                  : _tableFilter == '2f_available'
                      ? '2nd Floor - Available Tables'
                      : _tableFilter == '2f_occupied'
                          ? '2nd Floor - Occupied Tables'
                          : _tableFilter == 'ground_floor'
                              ? 'Ground Floor Tables'
                              : _tableFilter == '2nd_floor'
                                  ? '2nd Floor Tables'
                                  : _tableFilter == 'occupied'
                                      ? 'Occupied Tables'
                                      : _tableFilter == 'available'
                                          ? 'Available Tables'
                                          : 'Table Monitoring';

          final tablesEmptyMessage = _tableFilter == 'gf_available'
              ? 'No available tables on Ground Floor'
              : _tableFilter == 'gf_occupied'
                  ? 'No occupied tables on Ground Floor'
                  : _tableFilter == '2f_available'
                      ? 'No available tables on 2nd Floor'
                      : _tableFilter == '2f_occupied'
                          ? 'No occupied tables on 2nd Floor'
                          : _tableFilter == 'ground_floor'
                              ? 'No tables on Ground Floor'
                              : _tableFilter == '2nd_floor'
                                  ? 'No tables on 2nd Floor'
                                  : _tableFilter == 'occupied'
                                      ? 'No occupied tables'
                                      : _tableFilter == 'available'
                                          ? 'No available tables'
                                          : 'No tables found';

          final mainContent = RefreshIndicator(
            onRefresh: () => _loadData(showSpinner: false),
            child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/menubackground.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                  TabBarView(
                    physics: isMobile ? null : const NeverScrollableScrollPhysics(),
                    children: [
                      TablesTab(
                        tables: filteredTables,
                        orders: _orders,
                        statusInfoFor: _tableStatusInfo,
                        title: tablesTitle,
                        emptyMessage: tablesEmptyMessage,
                        currentFilter: _tableFilter,
                        onFilterChanged: (filter) => setState(() => _tableFilter = filter),
                        totalAllCount: allTablesCount,
                        totalGfAvailableCount: gfAvailableCount,
                        totalGfOccupiedCount: gfOccupiedCount,
                        total2fAvailableCount: secondFloorAvailableCount,
                        total2fOccupiedCount: secondFloorOccupiedCount,
                        showFilterChips: isMobile,
                        lockedFloor: _floorScope,
                        onViewDetails: (table) {
                          _showTableOrderDetails(table);
                        },
                        onGetOrder: (table) async {
                          await Navigator.of(context).push(
                            _getOrderPageRoute(
                              GetOrderPage(
                                table: table,
                                menuItems: _menuItems,
                              ),
                            ),
                          );
                          if (!mounted) return;
                          await _loadData(showSpinner: false);
                        },
                        onAddOrder: _addOrderForTable,
                        onEditOrder: _editOrderForTable,
                        onExtendRoomCharge: _extendRoomChargeForTable,
                        onCancelOrder: _cancelOrder,
                      ),
                      NewOrdersTab(
                        orders: newOrders,
                        onRefresh: () => _loadData(showSpinner: false),
                        onEdit: _editOrder,
                        onConfirm: _confirmOrder,
                        onViewDetails: _showOrderDetailsSheet,
                      ),
                      OrdersTab(
                        orders: confirmedOrders,
                        onViewDetails: _showOrderDetailsSheet,
                      ),
                    ],
                  ),
                ],
              ),
          );

          return Scaffold(
            key: _scaffoldKey,
            backgroundColor: const Color(0xFFF5F6F0),
            appBar: isMobile
                ? AppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    scrolledUnderElevation: 0,
                    title: Text(
            'WAITER DASHBOARD',
            style: GoogleFonts.urbanist(
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              fontSize: 18,
              color: const Color(0xFF1A1C18),
            ),
          ),
                    actions: [
                      IconButton(
                        tooltip: 'Refresh',
                        onPressed: _isManualRefreshing ? null : _manualRefresh,
                        icon: _isManualRefreshing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                      ),
                      IconButton(
                        tooltip: 'Settings',
                        onPressed: () => showAppSettingsSheet(
                          context: context,
                          onLogout: logout,
                        ),
                        icon: const Icon(Icons.settings_outlined),
                      ),
                      IconButton(
                        tooltip: 'Logout',
                        onPressed: logout,
                        icon: const Icon(Icons.logout),
                      ),
                    ],
                    bottom: PreferredSize(
                      preferredSize: const Size.fromHeight(48),
                      child: TabBar(
                        labelColor: const Color(0xFF0C0E2B),
                        unselectedLabelColor: Colors.black54,
                        indicatorColor: const Color(0xFF0C0E2B),
                        indicatorWeight: 3,
                        indicatorSize: TabBarIndicatorSize.label,
                        tabs: [
                          const Tab(
                            child: _TabBadgeItem(
                              label: 'Tables',
                              count: 0,
                            ),
                          ),
                          Tab(
                            child: _TabBadgeItem(
                              label: 'New Orders',
                              count: newOrdersCount,
                              badgeColor: const Color(0xFFD32F2F),
                            ),
                          ),
                          Tab(
                            child: _TabBadgeItem(
                              label: 'Order List',
                              count: activeOrderCount,
                              badgeColor: const Color(0xFF0C0E2B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : null,
            body: Column(
              children: [
                const OfflineSyncBanner(),
                Expanded(
                  child: isMobile
                      ? mainContent
                      : Row(
                          children: [
                            AnimatedBuilder(
                              animation: controller,
                              builder: (context, _) => WaiterSidebar(
                                selectedIndex: controller.index,
                                onSelect: (index) {
                                  // Tapping "Tables" itself (not its Occupied/
                                  // Available sub-rows) means "show everything".
                                  if (index == 0) {
                                    setState(() => _tableFilter = 'all');
                                  }
                                  controller.animateTo(index);
                                },
                                tableFilter: _tableFilter,
                                onSelectTableFilter: (filter) {
                                  setState(() => _tableFilter = filter);
                                  controller.animateTo(0);
                                },
                                lockedFloor: _floorScope,
                                width: isMobile
                                    ? 200
                                    : (mediaQuery.size.width < 750
                                        ? 190
                                        : (mediaQuery.size.width < 1000
                                            ? 220
                                            : (isLandscape ? 240 : 270))),
                                isLandscape: isLandscape,
                                newOrdersCount: newOrdersCount,
                                orderListCount: activeOrderCount,
                                onRefresh: _manualRefresh,
                                onOpenSettings: () {
                                  showAppSettingsSheet(
                                    context: context,
                                    onLogout: logout,
                                  );
                                },
                              ),
                            ),
                            Expanded(child: mainContent),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
  StatusInfo _tableStatusInfo(int status) {
    switch (status) {
      case 1:
        return const StatusInfo('Available', Colors.green);
      case 2:
        return const StatusInfo('Occupied', Colors.orange);
      default:
        return const StatusInfo('Unknown', Colors.grey);
    }
  }

}

/// One line of the order-details totals breakdown (Subtotal / Service
/// Charge / Tax / Discount) shown above the bold Total row.
class _TotalsRow extends StatelessWidget {
  final String label;
  final double value;
  final bool isMobile;

  const _TotalsRow({
    required this.label,
    required this.value,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    final isNegative = value < 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.urbanist(
              fontSize: isMobile ? 12.5 : 14,
              color: Colors.grey[700],
            ),
          ),
          const Spacer(),
          Text(
            '${isNegative ? '-' : ''}₱${formatPrice(value.abs())}',
            style: GoogleFonts.urbanist(
              fontSize: isMobile ? 12.5 : 14,
              fontWeight: FontWeight.w600,
              color: isNegative ? Colors.red[700] : Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }
}

class _TabBadgeItem extends StatelessWidget {
  final String label;
  final int count;
  final Color? badgeColor;
  final Color? textColor;

  const _TabBadgeItem({
    required this.label,
    required this.count,
    this.badgeColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final bg = badgeColor ?? const Color(0xFFD32F2F);
    final fg = textColor ?? Colors.white;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: GoogleFonts.urbanist(
            fontWeight: FontWeight.w700,
            fontSize: 14.5,
          ),
        ),
        if (count > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            constraints: const BoxConstraints(minWidth: 18),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: bg.withValues(alpha: 0.35),
                  blurRadius: 4,
                  offset: const Offset(0, 1.5),
                ),
              ],
            ),
            child: Text(
              count > 99 ? '99+' : '$count',
              textAlign: TextAlign.center,
              style: GoogleFonts.urbanist(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
