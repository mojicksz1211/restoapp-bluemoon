part of 'menu_home_page.dart';

extension _MenuHomeSocket on _MenuHomePageState {
  // Initialize socket for real-time order updates
  Future<void> _initializeSocket() async {
    try {
      await SocketService.initialize();

      // Listen for order updates
      _disposeOrderUpdated?.call();
      _disposeOrderUpdated = SocketService.addOrderUpdateListener((data) {
        if (!mounted) return;
        _handleSocketOrderEvent(data);
      });

      // Listen for order items added
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

      // Join all active order rooms
      _syncSocketOrderRooms();
    } catch (e) {
      // Error initializing socket
    }
  }

  // Update order from socket data
  void _handleSocketOrderEvent(Map<String, dynamic> data) {
    final rawOrderData = data['order'];
    final orderData = rawOrderData is Map
        ? Map<String, dynamic>.from(rawOrderData)
        : Map<String, dynamic>.from(data);
    // Merge top-level fields if missing in order payload.
    if (orderData['order_id'] == null && data['order_id'] != null) {
      orderData['order_id'] = data['order_id'];
    }
    if (orderData['order_no'] == null && data['order_no'] != null) {
      orderData['order_no'] = data['order_no'];
    }

    final orderIdRaw =
        orderData['order_id'] ?? orderData['orderId'] ?? data['order_id'] ?? data['orderId'];
    final orderId = orderIdRaw is int ? orderIdRaw : int.tryParse(orderIdRaw.toString());
    final orderNo = (orderData['order_no'] ?? data['order_no'])?.toString();
    final statusRaw = orderData['status'] ?? data['status'];

    int orderIndex = -1;
    if (orderId != null) {
      orderIndex = orders.indexWhere((o) => o.orderId == orderId);
    }
    if (orderIndex == -1 && orderNo != null) {
      orderIndex = orders.indexWhere((o) => o.id == orderNo);
    }
    if (orderIndex == -1) {
      _addOrderFromSocket(orderData);
      return;
    }

    _updateOrderFromSocket(orderData, orderIndex);
  }

  Future<void> _addOrderFromSocket(Map<String, dynamic> orderData) async {
    try {
      final orderIdRaw = orderData['order_id'] ?? orderData['orderId'];
      final orderId = orderIdRaw is int ? orderIdRaw : int.tryParse(orderIdRaw.toString());
      final orderNo = (orderData['order_no'] ?? orderData['orderNo'])?.toString();
      if (orderId == null && orderNo == null) return;

      final items = orderData['items'] as List<dynamic>? ?? [];
      final statusValue = orderData['status'];
      final dbStatus = statusValue is int
          ? statusValue
          : (statusValue is String ? int.tryParse(statusValue) ?? 3 : 3);
      final normalizedStatus = normalizeBackendStatus(dbStatus);

      // Skip cancelled orders (status -1)
      if (dbStatus == -1) {
        return;
      }

      final grandTotalValue = orderData['grand_total'] ?? 0;
      final grandTotal = grandTotalValue is double
          ? grandTotalValue
          : grandTotalValue is int
              ? grandTotalValue.toDouble()
              : grandTotalValue is String
                  ? double.tryParse(grandTotalValue) ?? 0.0
                  : 0.0;

      final menuResult = await ApiService.getMenuItems();
      List<MenuItem> allMenuItems = [];
      if (menuResult['success'] == true) {
        final menuData = List<Map<String, dynamic>>.from(menuResult['data']);
        allMenuItems = menuData.map((item) => MenuItem.fromApi(item)).toList();
      }

      final cartItems = <CartItem>[];
      for (final itemData in items) {
        MenuItem? menuItem;
        final menuId =
            itemData['menu_id'] is int ? itemData['menu_id'] : (itemData['menu_id'] as num?)?.toInt();

        if (menuId != null) {
          menuItem = allMenuItems.firstWhere(
            (item) => item.id == menuId,
            orElse: () => MenuItem(
              id: menuId,
              name: itemData['menu_name'] ?? '',
              description: '',
              price: (itemData['unit_price'] ?? 0).toDouble(),
              category: '',
              icon: Icons.restaurant_menu,
            ),
          );
        } else {
          menuItem = MenuItem(
            id: itemData['menu_id'],
            name: itemData['menu_name'] ?? '',
            description: '',
            price: (itemData['unit_price'] ?? 0).toDouble(),
            category: '',
            icon: Icons.restaurant_menu,
          );
        }

        cartItems.add(CartItem(
          item: menuItem,
          quantity: (itemData['qty'] ?? 0).toInt(),
        ));
      }

      final tableId = orderData['table_id'] is int
          ? orderData['table_id']
          : (orderData['table_id'] is String ? int.tryParse(orderData['table_id']) : null);
      final orderType = orderData['order_type'] as String?;
      final encodedDt = orderData['encoded_dt']?.toString();
      final orderTime =
          encodedDt != null ? DateTime.tryParse(encodedDt) ?? DateTime.now() : DateTime.now();

      final newOrder = Order(
        id: orderNo ?? (orderId?.toString() ?? ''),
        orderId: orderId,
        items: cartItems,
        totalPrice: grandTotal,
        orderTime: orderTime,
        backendStatus: normalizedStatus,
        orderType: orderType,
        tableId: tableId,
      );

      if (mounted) {
        setState(() {
          orders = [...orders, newOrder];
        });
        _syncSocketOrderRooms();
        await _saveOrders();
      }
    } catch (e) {
      // Error adding order from socket
    }
  }

  void _updateOrderFromSocket(Map<String, dynamic> orderData, int orderIndex) async {
    try {
      final orderIdRaw = orderData['order_id'] ?? orderData['orderId'];
      final orderId = orderIdRaw is int ? orderIdRaw : int.tryParse(orderIdRaw.toString());
      final items = orderData['items'] as List<dynamic>? ?? [];

      // Parse status
      final statusValue = orderData['status'];
      final dbStatus = statusValue is int
          ? statusValue
          : (statusValue is String ? int.tryParse(statusValue) ?? 3 : 3);
      final normalizedStatus = normalizeBackendStatus(dbStatus);

      // Parse grand_total
      final grandTotalValue = orderData['grand_total'] ?? 0;
      final grandTotal = grandTotalValue is double
          ? grandTotalValue
          : grandTotalValue is int
              ? grandTotalValue.toDouble()
              : grandTotalValue is String
                  ? double.tryParse(grandTotalValue) ?? 0.0
                  : 0.0;

      // Get all menu items to match with order items
      final menuResult = await ApiService.getMenuItems();
      List<MenuItem> allMenuItems = [];
      if (menuResult['success'] == true) {
        final menuData = List<Map<String, dynamic>>.from(menuResult['data']);
        allMenuItems = menuData.map((item) => MenuItem.fromApi(item)).toList();
      }

      // Convert order items to CartItems
      final cartItems = <CartItem>[];
      for (final itemData in items) {
        MenuItem? menuItem;
        final menuId =
            itemData['menu_id'] is int ? itemData['menu_id'] : (itemData['menu_id'] as num?)?.toInt();

        if (menuId != null) {
          menuItem = allMenuItems.firstWhere(
            (item) => item.id == menuId,
            orElse: () => MenuItem(
              id: menuId,
              name: itemData['menu_name'] ?? '',
              description: '',
              price: (itemData['unit_price'] ?? 0).toDouble(),
              category: '',
              icon: Icons.restaurant_menu,
            ),
          );
        } else {
          menuItem = MenuItem(
            id: itemData['menu_id'],
            name: itemData['menu_name'] ?? '',
            description: '',
            price: (itemData['unit_price'] ?? 0).toDouble(),
            category: '',
            icon: Icons.restaurant_menu,
          );
        }

        cartItems.add(CartItem(
          item: menuItem,
          quantity: (itemData['qty'] ?? 0).toInt(),
        ));
      }

      // Parse table_id and order_type (use existing order as fallback)
      final existingOrder = orders[orderIndex];
      final tableId = orderData['table_id'] is int
          ? orderData['table_id']
          : (orderData['table_id'] is String ? int.tryParse(orderData['table_id']) : null) ??
              existingOrder.tableId;
      final orderType = orderData['order_type'] as String? ?? existingOrder.orderType;

      // If order is cancelled (status -1), remove it from the list
      if (dbStatus == -1) {
        if (mounted) {
          setState(() {
            orders.removeAt(orderIndex);
          });
          _syncSocketOrderRooms();
          await _saveOrders();
        }
        return;
      }

      // Check if order just became SETTLED (was not SETTLED before, now is SETTLED)
      final wasSettled = existingOrder.backendStatus == 1;
      final isNowSettled = dbStatus == 1;
      final wasCancelled = existingOrder.backendStatus == -1;
      final isNowCancelled = dbStatus == -1;
      // Show settlement dialog for both table orders and take-out orders
      final justBecameSettled = !wasSettled && isNowSettled;
      final justBecameCancelled = !wasCancelled && isNowCancelled;

      // Update the order
      final updatedOrder = Order(
        id: existingOrder.id,
        orderId: orderId ?? existingOrder.orderId,
        items: cartItems,
        totalPrice: grandTotal,
        orderTime: existingOrder.orderTime,
        backendStatus: normalizedStatus,
        orderType: orderType,
        tableId: tableId,
      );

      if (mounted) {
        if (justBecameSettled || justBecameCancelled) {
          SettlementDialogService.instance.emit(updatedOrder);
          return;
        }
        if (dbStatus == 1) {
          setState(() {
            final updatedOrders = List<Order>.from(orders);
            updatedOrders.removeAt(orderIndex);
            orders = updatedOrders;
            _isCartPanelOpen = false;
          });
          _syncSocketOrderRooms();
          await _saveOrders();
          return;
        }
        setState(() {
          // Create a new list to ensure Flutter detects the change
          final updatedOrders = List<Order>.from(orders);
          updatedOrders[orderIndex] = updatedOrder;
          orders = updatedOrders;
          // Shake cart FAB when order status changes
          if (existingOrder.backendStatus != normalizedStatus) {
            _cartShakeController.forward(from: 0);
          }
        });
        _syncSocketOrderRooms();

        await _saveOrders();
      }
    } catch (e) {
      // Error updating order from socket
    }
  }

  // Clean up socket listeners
  void _cleanupSocket() {
    try {
      // Leave all order rooms
      for (final orderId in _joinedOrderIds) {
        SocketService.leaveOrder(orderId);
      }
      _joinedOrderIds.clear();
      _disposeOrderUpdated?.call();
      _disposeOrderItemsAdded?.call();
      _disposeOrderCreated?.call();
      _disposeOrderUpdated = null;
      _disposeOrderItemsAdded = null;
      _disposeOrderCreated = null;
    } catch (e) {
      // Error cleaning up socket
    }
  }

  void _syncSocketOrderRooms() {
    final activeIds = orders
        .where((order) =>
            order.orderId != null &&
            order.backendStatus != -1 && // Exclude cancelled orders
            !_isSettledTableOrder(order))
        .map((order) => order.orderId!)
        .toSet();

    for (final id in activeIds.difference(_joinedOrderIds)) {
      SocketService.joinOrder(id);
      _joinedOrderIds.add(id);
    }

    for (final id in _joinedOrderIds.difference(activeIds).toList()) {
      SocketService.leaveOrder(id);
      _joinedOrderIds.remove(id);
    }
  }
}

