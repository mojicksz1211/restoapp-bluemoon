part of 'menu_home_page.dart';

extension _MenuHomeOrders on _MenuHomePageState {
  void _handleSettlementDismissed(Order order) {
    if (!mounted) return;
    setState(() {
      final updatedOrders = List<Order>.from(orders);
      final idx = updatedOrders.indexWhere((o) =>
          (order.orderId != null && o.orderId == order.orderId) || o.id == order.id);
      if (idx != -1) {
        updatedOrders.removeAt(idx);
      }
      orders = updatedOrders;
      _isCartPanelOpen = false;
      // Clear cart and reset floating cart button
      cart.clear();
      // _activeOrder is a getter, it will automatically update when orders list changes
    });
    _syncSocketOrderRooms();
    _saveOrders();
  }

  // Load orders from local storage and sync with server
  Future<void> _loadOrders() async {
    try {
      // First, load from local storage for quick display
      final savedOrders = await ApiService.loadOrders();
      if (savedOrders.isNotEmpty) {
        setState(() {
          // Filter out cancelled orders (status -1) from local storage
          orders = savedOrders
              .map((orderJson) => Order.fromJson(orderJson))
              .where((order) => order.backendStatus != -1) // Remove cancelled orders
              .toList();
        });
        _syncSocketOrderRooms();
      }

      // Then sync with server to get latest orders and remove deleted/cancelled ones
      await _syncOrdersFromServer();
    } catch (e) {
      // Error loading orders
    }
  }

  // Sync orders from server - removes deleted orders automatically
  Future<void> _syncOrdersFromServer() async {
    try {
      // Get orders from server
      final serverOrdersResult = await ApiService.getUserOrders();

      // Check if unauthorized - redirect to login
      if (serverOrdersResult['unauthorized'] == true) {
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginPage()),
            (route) => false,
          );
        }
        return;
      }

      if (serverOrdersResult['success'] == true) {
        final serverOrdersData = List<Map<String, dynamic>>.from(serverOrdersResult['data']);

        // Get all menu items to match with order items
        final menuResult = await ApiService.getMenuItems();
        List<MenuItem> allMenuItems = [];
        if (menuResult['success'] == true) {
          final menuData = List<Map<String, dynamic>>.from(menuResult['data']);
          allMenuItems = menuData.map((item) => MenuItem.fromApi(item)).toList();
        }

        // Convert server orders to Order objects
        final serverOrders = <Order>[];
        for (final orderData in serverOrdersData) {
          final dbStatus = orderData['status'] is int
              ? orderData['status']
              : (orderData['status'] is String
                  ? int.tryParse(orderData['status']) ?? 3
                  : 3);
          final normalizedStatus = normalizeBackendStatus(dbStatus);

          // Skip cancelled orders (status -1)
          if (dbStatus == -1) {
            continue;
          }

          final items = orderData['items'] as List<dynamic>? ?? [];

          // Convert order items to CartItems
          final cartItems = <CartItem>[];
          if (orderData['items'] != null) {
            for (final itemData in orderData['items']) {
              // Try to find menu item from loaded menu items
              MenuItem? menuItem;
              final menuId = itemData['menu_id'] is int
                  ? itemData['menu_id']
                  : (itemData['menu_id'] as num?)?.toInt();

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
                // Create minimal MenuItem from order item data
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
          }

          // Parse table_id
          final tableId = orderData['table_id'] is int
              ? orderData['table_id']
              : (orderData['table_id'] is String ? int.tryParse(orderData['table_id']) : null);

          // Parse order_type
          final orderType = orderData['order_type'] as String?;

          // Create Order object
          final order = Order(
            id: orderData['order_no'] ?? '',
            orderId: orderData['order_id'],
            items: cartItems,
            totalPrice: (orderData['grand_total'] ?? 0).toDouble(),
            orderTime: orderData['encoded_dt'] != null
                ? DateTime.parse(orderData['encoded_dt'])
                : DateTime.now(),
            backendStatus: normalizedStatus,
            orderType: orderType,
            tableId: tableId,
          );

          serverOrders.add(order);
        }

        // Replace local orders with server orders (automatically removes deleted ones)
        setState(() {
          orders = serverOrders;
        });
        _syncSocketOrderRooms();

        // Save synced orders to local storage
        await _saveOrders();
      }
    } catch (e) {
      // Error syncing orders from server - keep local orders
    }
  }

  // Save orders to local storage
  Future<void> _saveOrders() async {
    try {
      final ordersJson = orders.map((order) => order.toJson()).toList();
      await ApiService.saveOrders(ordersJson);
    } catch (e) {
      // Error saving orders
    }
  }

  Future<void> placeOrder(List<CartItem> cartItems, double total, String? orderType) async {
    // Check if there's an active order (not settled/cancelled)
    // If yes, automatically add items to existing order
    Order? activeOrder;
    try {
      activeOrder = orders.firstWhere(
        (order) => order.orderId != null &&
            (order.backendStatus == null ||
                (order.backendStatus != 1 && order.backendStatus != -1)),
      );
    } catch (e) {
      // No active order found - will create new order
      activeOrder = null;
    }

    // If there's an active order, add items to it automatically
    if (activeOrder != null && activeOrder.orderId != null) {
      await _addItemsToExistingOrder(cartItems, total, orderType, activeOrder);
      return;
    }

    if (_isSubmittingOrder) return;
    _setSubmittingOrder(true);

    try {
      // Generate order number: ORD-YYYYMMDD-HHMMSS
      final now = DateTime.now();
      final orderNo =
          'ORD-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

      // Get user data (table_id if available)
      final userData = await ApiService.getUserData();
      final tableId = userData['table_id'] != null ? int.tryParse(userData['table_id']!) : null;

      // Prepare order items
      final items = cartItems.map((cartItem) {
        if (cartItem.item.id == null) {
          throw Exception('Menu item ID is missing for ${cartItem.item.name}');
        }
        return {
          'menu_id': cartItem.item.id,
          'qty': cartItem.quantity,
          'unit_price': cartItem.item.price,
          'status': 3, // Default status for order items
        };
      }).toList();

      // Calculate totals (simplified - you can add tax/service charge calculation here)
      final subtotal = total;
      final taxAmount = 0.0; // Add tax calculation if needed
      final serviceCharge = 0.0; // Add service charge calculation if needed
      final discountAmount = 0.0; // Add discount calculation if needed
      final grandTotal = subtotal + taxAmount + serviceCharge - discountAmount;

      // Call API to create order
      final result = await ApiService.createOrder(
        orderNo: orderNo,
        tableId: tableId,
        orderType: orderType, // 'DINE_IN' or 'TAKE_OUT'
        subtotal: subtotal,
        taxAmount: taxAmount,
        serviceCharge: serviceCharge,
        discountAmount: discountAmount,
        grandTotal: grandTotal,
        items: items,
      );

      // Check if unauthorized - redirect to login
      if (result['unauthorized'] == true) {
        if (mounted) {
          _setSubmittingOrder(false);
        }
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginPage()),
            (route) => false,
          );
        }
        return;
      }

      // Server says this table already has an open order (e.g. a waiter started
      // one on another device, so our local `orders` list didn't know about it).
      // Append to that order instead of failing the guest's order.
      if (result['success'] != true &&
          result['code'] == 'ACTIVE_ORDER_EXISTS' &&
          result['existing_order_id'] != null) {
        _setSubmittingOrder(false);
        final existingOrderId = result['existing_order_id'] is int
            ? result['existing_order_id'] as int
            : int.tryParse(result['existing_order_id'].toString());
        if (existingOrderId != null) {
          await _addItemsToExistingOrder(
            cartItems,
            total,
            orderType,
            Order(
              id: 'server-active-$existingOrderId',
              items: const [],
              totalPrice: 0,
              orderTime: DateTime.now(),
              orderId: existingOrderId,
            ),
          );
        }
        return;
      }

      if (result['success'] == true) {
        final orderData = result['data'];
        final newOrderId = orderData['order_id'];

        // Initialize socket if needed (joinOrder will be handled by _syncSocketOrderRooms)
        if (newOrderId != null) {
          await SocketService.initialize();
        }

        // Fetch latest order from server to get complete data with all items
        // Retry a few times in case server hasn't processed the order yet
        Map<String, dynamic>? createdOrderData;
        for (int retry = 0; retry < 3; retry++) {
          final latestOrdersResult = await ApiService.getUserOrders();

          if (latestOrdersResult['success'] == true && latestOrdersResult['data'] != null) {
            final serverOrdersData = List<Map<String, dynamic>>.from(latestOrdersResult['data']);
            try {
              createdOrderData = serverOrdersData.firstWhere(
                (order) => order['order_id'] == newOrderId,
              );
              // If we found the order and it has items, break
              if (createdOrderData != null) {
                final items = createdOrderData['items'] as List<dynamic>? ?? [];
                if (items.isNotEmpty || retry == 2) {
                  break; // Found order with items, or last retry
                }
              }
            } catch (e) {
              createdOrderData = null;
            }
          }

          // Wait a bit before retrying (except on last attempt)
          if (retry < 2) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }

        if (createdOrderData != null) {
          // Get all menu items to match with order items
          final menuResult = await ApiService.getMenuItems();
          List<MenuItem> allMenuItems = [];
          if (menuResult['success'] == true) {
            final menuData = List<Map<String, dynamic>>.from(menuResult['data']);
            allMenuItems = menuData.map((item) => MenuItem.fromApi(item)).toList();
          }

          final items = createdOrderData['items'] as List<dynamic>? ?? [];
          final dbStatus = createdOrderData['status'] is int
              ? createdOrderData['status']
              : (createdOrderData['status'] is String
                  ? int.tryParse(createdOrderData['status']) ?? 3
                  : 3);
          final normalizedStatus = normalizeBackendStatus(dbStatus);

          // Convert order items to CartItems
          // Use original cartItems to preserve proper names and avoid "Unknown Item" flicker
          final cartItemsFromServer = <CartItem>[];
          for (int index = 0; index < items.length; index++) {
            final itemData = items[index];
            MenuItem? menuItem;
            final menuId =
                itemData['menu_id'] is int ? itemData['menu_id'] : (itemData['menu_id'] as num?)?.toInt();

            // Try to use original cart item first to preserve proper names
            CartItem? originalCartItem;
            if (index < cartItems.length && cartItems[index].item.id == menuId) {
              originalCartItem = cartItems[index];
            } else {
              // Try to find by menuId
              try {
                originalCartItem = cartItems.firstWhere(
                  (ci) => ci.item.id == menuId,
                );
              } catch (e) {
                // If not found, use first item if available, otherwise null
                originalCartItem = cartItems.isNotEmpty ? cartItems[0] : null;
              }
            }

            if (menuId != null) {
              // If we have original cart item, use its menu item data
              if (originalCartItem != null) {
                menuItem = originalCartItem.item;
              } else {
                // Try to find in allMenuItems
                menuItem = allMenuItems.firstWhere(
                  (item) => item.id == menuId,
                  orElse: () {
                    // Use menu_name from server if available, otherwise empty string
                    final serverMenuName = itemData['menu_name'];
                    return MenuItem(
                      id: menuId,
                      name: serverMenuName ?? '',
                      description: '',
                      price: (itemData['unit_price'] ?? 0).toDouble(),
                      category: '',
                      icon: Icons.restaurant_menu,
                    );
                  },
                );
              }
            } else {
              // Fallback: use original cart item or create minimal item
              if (originalCartItem != null) {
                menuItem = originalCartItem.item;
              } else {
                final serverMenuName = itemData['menu_name'];
                menuItem = MenuItem(
                  id: itemData['menu_id'],
                  name: serverMenuName ?? '',
                  description: '',
                  price: (itemData['unit_price'] ?? 0).toDouble(),
                  category: '',
                  icon: Icons.restaurant_menu,
                );
              }
            }

            cartItemsFromServer.add(CartItem(
              item: menuItem,
              quantity: (itemData['qty'] ?? 0).toInt(),
            ));
          }

          final tableIdFromServer = createdOrderData['table_id'] is int
              ? createdOrderData['table_id']
              : (createdOrderData['table_id'] is String
                  ? int.tryParse(createdOrderData['table_id'])
                  : null);
          final orderTypeFromServer = createdOrderData['order_type'] as String?;
          final encodedDt = createdOrderData['encoded_dt']?.toString();
          final orderTime =
              encodedDt != null ? DateTime.tryParse(encodedDt) ?? DateTime.now() : DateTime.now();

          // Create Order object with complete data from server
          final order = Order(
            id: createdOrderData['order_no'] ?? orderData['order_no'] ?? orderNo,
            orderId: newOrderId,
            items: cartItemsFromServer,
            totalPrice: (createdOrderData['grand_total'] ?? grandTotal).toDouble(),
            orderTime: orderTime,
            backendStatus: normalizedStatus,
            orderType: orderTypeFromServer ?? orderType,
            tableId: tableIdFromServer ?? tableId,
          );

          setState(() {
            orders.add(order);
            orderIdCounter++;
            cart.clear();
          });

          debugPrint(
            '[PLACE ORDER] Order added to list. Order ID: ${order.orderId}, Order No: ${order.id}, Items: ${order.items.length}, Total orders: ${orders.length}',
          );

          // Save orders to local storage
          await _saveOrders();
          _syncSocketOrderRooms();

          debugPrint(
            '[PLACE ORDER] Active order: ${_activeOrder?.id}, Should show tracking: $shouldShowTrackingButton',
          );

          if (mounted) {
            _setSubmittingOrder(false);
          }
          if (mounted) {
            // Transition to order tracking view
            _openOrderTrackingView();
          }
        } else {
          // Fallback: create order with local data if server fetch fails
          final order = Order(
            id: orderData['order_no'] ?? orderNo,
            orderId: newOrderId,
            items: List.from(cartItems),
            totalPrice: grandTotal,
            orderTime: DateTime.now(),
            backendStatus: 3,
            orderType: orderType,
            tableId: tableId,
          );

          setState(() {
            orders.add(order);
            orderIdCounter++;
            cart.clear();
          });
          await _saveOrders();
          _syncSocketOrderRooms();
          if (mounted) {
            _setSubmittingOrder(false);
          }
          if (mounted) {
            _openOrderTrackingView();
          }
        }
      } else {
        if (mounted) {
          _setSubmittingOrder(false);
        }
        // Show error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['error'] ?? 'Failed to place order'),
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _setSubmittingOrder(false);
      }
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error placing order: ${e.toString()}'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Add items to existing order (Additional Order)
  Future<void> _addItemsToExistingOrder(
    List<CartItem> cartItems,
    double total,
    String? orderType,
    Order existingOrder,
  ) async {
    if (existingOrder.orderId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: Order ID is missing'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    final addedCount = cartItems.length;

    if (_isSubmittingOrder) return;
    _setSubmittingOrder(true);

    try {
      // Prepare order items
      final items = cartItems.map((cartItem) {
        if (cartItem.item.id == null) {
          throw Exception('Menu item ID is missing for ${cartItem.item.name}');
        }
        return {
          'menu_id': cartItem.item.id,
          'qty': cartItem.quantity,
          'unit_price': cartItem.item.price,
          'status': 3, // Default status for order items
        };
      }).toList();

      // Call API to add items to existing order
      final result = await ApiService.addItemsToOrder(
        orderId: existingOrder.orderId!,
        items: items,
      );

      // Check if unauthorized - redirect to login
      if (result['unauthorized'] == true) {
        if (mounted) {
          _setSubmittingOrder(false);
        }
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginPage()),
            (route) => false,
          );
        }
        return;
      }

      if (result['success'] == true) {
        // Fetch latest order from server to get all items with proper statuses
        final latestOrdersResult = await ApiService.getUserOrders();

        if (latestOrdersResult['success'] == true && latestOrdersResult['data'] != null) {
          final serverOrdersData = List<Map<String, dynamic>>.from(latestOrdersResult['data']);
          Map<String, dynamic>? updatedOrderData;
          try {
            updatedOrderData = serverOrdersData.firstWhere(
              (order) => order['order_id'] == existingOrder.orderId,
            );
          } catch (e) {
            updatedOrderData = null;
          }

          if (updatedOrderData != null) {
            // Get all menu items to match with order items
            final menuResult = await ApiService.getMenuItems();
            List<MenuItem> allMenuItems = [];
            if (menuResult['success'] == true) {
              final menuData = List<Map<String, dynamic>>.from(menuResult['data']);
              allMenuItems = menuData.map((item) => MenuItem.fromApi(item)).toList();
            }

            final items = updatedOrderData['items'] as List<dynamic>? ?? [];
            final dbStatus = updatedOrderData['status'] is int
                ? updatedOrderData['status']
                : (updatedOrderData['status'] is String
                    ? int.tryParse(updatedOrderData['status']) ?? 3
                    : 3);
            final normalizedStatus = normalizeBackendStatus(dbStatus);

            // Convert order items to CartItems
            var cartItemsFromServer = <CartItem>[];
            for (final itemData in items) {
              MenuItem? menuItem;
              final rawMenuId = itemData['menu_id'] ?? itemData['MENU_ID'];
              final menuId = rawMenuId is int ? rawMenuId : (rawMenuId as num?)?.toInt();
              final rawQty = itemData['qty'] ?? itemData['QTY'] ?? 0;
              final qty = rawQty is int
                  ? rawQty
                  : rawQty is double
                      ? rawQty.toInt()
                      : int.tryParse(rawQty.toString()) ?? 0;
              final rawUnitPrice = itemData['unit_price'] ?? itemData['UNIT_PRICE'] ?? 0;
              final unitPrice = rawUnitPrice is double
                  ? rawUnitPrice
                  : rawUnitPrice is int
                      ? rawUnitPrice.toDouble()
                      : double.tryParse(rawUnitPrice.toString()) ?? 0.0;
              final menuName = itemData['menu_name'] ?? itemData['MENU_NAME'] ?? '';

              if (menuId != null) {
                menuItem = allMenuItems.firstWhere(
                  (item) => item.id == menuId,
                  orElse: () => MenuItem(
                    id: menuId,
                    name: menuName,
                    description: '',
                    price: unitPrice,
                    category: '',
                    icon: Icons.restaurant_menu,
                  ),
                );
              } else {
                menuItem = MenuItem(
                  id: rawMenuId,
                  name: menuName,
                  description: '',
                  price: unitPrice,
                  category: '',
                  icon: Icons.restaurant_menu,
                );
              }

              cartItemsFromServer.add(CartItem(
                item: menuItem,
                quantity: qty,
              ));
            }

            // Keep server line items as-is to avoid switching between
            // merged and per-item display.

            final tableId = updatedOrderData['table_id'] is int
                ? updatedOrderData['table_id']
                : (updatedOrderData['table_id'] is String
                    ? int.tryParse(updatedOrderData['table_id'])
                    : null);
            final orderTypeFromServer = updatedOrderData['order_type'] as String?;

            // Create updated order with all items from server
            final updatedOrder = Order(
              id: updatedOrderData['order_no'] ?? existingOrder.id,
              orderId: existingOrder.orderId,
              items: cartItemsFromServer,
              totalPrice: (updatedOrderData['grand_total'] ?? 0).toDouble(),
              orderTime: existingOrder.orderTime,
              backendStatus: normalizedStatus,
              orderType: orderTypeFromServer ?? existingOrder.orderType,
              tableId: tableId ?? existingOrder.tableId,
            );

            // Update order in local list
            setState(() {
              final index = orders.indexWhere((o) => o.orderId == existingOrder.orderId);
              if (index >= 0) {
                orders[index] = updatedOrder;
              }
              cart.clear();
            });

            // Save orders to local storage
            await _saveOrders();

            if (mounted) {
              _setSubmittingOrder(false);
            }
            if (mounted) {
              // Keep panel open to show updated order
              if (_isWideLayout(context)) {
                setState(() => _isCartPanelOpen = true);
              }
            }
          } else {
            // Fallback: update with local data if server fetch fails
            final updatedOrder = Order(
              id: existingOrder.id,
              orderId: existingOrder.orderId,
              items: [
                ...existingOrder.items,
                ...cartItems,
              ],
              totalPrice:
                  (result['data']['new_grand_total'] ?? existingOrder.totalPrice + total).toDouble(),
              orderTime: existingOrder.orderTime,
              backendStatus: existingOrder.backendStatus,
              orderType: existingOrder.orderType ?? orderType,
              tableId: existingOrder.tableId,
            );

            setState(() {
              final index = orders.indexWhere((o) => o.orderId == existingOrder.orderId);
              if (index >= 0) {
                orders[index] = updatedOrder;
              }
              cart.clear();
            });
            await _saveOrders();
            if (mounted) {
              _setSubmittingOrder(false);
            }
          }
        } else {
          // Fallback: update with local data if server fetch fails
          final updatedOrder = Order(
            id: existingOrder.id,
            orderId: existingOrder.orderId,
            items: [
              ...existingOrder.items,
              ...cartItems,
            ],
            totalPrice:
                (result['data']['new_grand_total'] ?? existingOrder.totalPrice + total).toDouble(),
            orderTime: existingOrder.orderTime,
            backendStatus: existingOrder.backendStatus,
            orderType: existingOrder.orderType ?? orderType,
            tableId: existingOrder.tableId,
          );

          setState(() {
            final index = orders.indexWhere((o) => o.orderId == existingOrder.orderId);
            if (index >= 0) {
              orders[index] = updatedOrder;
            }
            cart.clear();
          });
          await _saveOrders();
          if (mounted) {
            _setSubmittingOrder(false);
          }
        }
      } else {
        if (mounted) {
          _setSubmittingOrder(false);
        }
        // Show error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['error'] ?? 'Failed to add items to order'),
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _setSubmittingOrder(false);
      }
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding items: ${e.toString()}'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

