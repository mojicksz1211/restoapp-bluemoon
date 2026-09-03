import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'models.dart';
import 'pages/menu_home_page.dart';
import 'services/socket_service.dart';
import 'services/api_service.dart';
import 'services/settlement_dialog_service.dart';

class OrderTrackingPage extends StatefulWidget {
  final Order order;
  final Function(Order)? onOrderUpdated; // Callback to update order after adding items

  const OrderTrackingPage({super.key, required this.order, this.onOrderUpdated});

  @override
  State<OrderTrackingPage> createState() => _OrderTrackingPageState();

  // Helper function to map backend status to OrderStatus enum
  // Backend: Order Item Status - 3=PENDING, 2=PREPARING, 1=READY
  // Backend: Order Status - 3=PENDING, 2=CONFIRMED, 1=SETTLED, -1=CANCELLED
  // Priority: Use order items status to determine preparingOrder and ordersReady
  static OrderStatus mapStatusFromBackend(int orderStatus, List<dynamic> items) {
    // If order is cancelled or settled
    if (orderStatus == -1 || orderStatus == 1) {
      return OrderStatus.ordersReady; // Consider it done
    }

    // Check item statuses - this is the primary way to determine preparingOrder and ordersReady
    if (items.isEmpty) {
      // If order is CONFIRMED (2) but no items yet
      if (orderStatus == 2) {
        return OrderStatus.orderConfirmed;
      }
      return OrderStatus.waitingForAssistance;
    }

    // Get all item statuses from order items table
    // Handle both uppercase (STATUS) and lowercase (status) field names
    // Also handle both int and string values from database
    final itemStatuses = items.map((item) {
      if (item is Map) {
        final statusValue = item['STATUS'] ?? item['status'] ?? 3;
        // Convert to int if it's a string
        if (statusValue is String) {
          return int.tryParse(statusValue) ?? 3;
        }
        return statusValue is int ? statusValue : 3;
      }
      return 3;
    }).toList();

    // Debug: Print item statuses for troubleshooting
    debugPrint('[ORDER STATUS] Item statuses: $itemStatuses, Order status: $orderStatus');

    // Priority 1: If all items are READY (1) -> Orders Ready
    if (itemStatuses.every((status) => status == 1)) {
      debugPrint('[ORDER STATUS] All items READY -> Orders Ready');
      return OrderStatus.ordersReady;
    }

    // Priority 2: If any item is PREPARING (2) -> Preparing Order
    if (itemStatuses.any((status) => status == 2)) {
      debugPrint('[ORDER STATUS] Some items PREPARING -> Preparing Order');
      return OrderStatus.preparingOrder;
    }

    // Priority 3: If order is CONFIRMED (2) and items are all PENDING (3) -> Order Confirmed
    if (orderStatus == 2 && itemStatuses.every((status) => status == 3)) {
      debugPrint('[ORDER STATUS] Order CONFIRMED, all items PENDING -> Order Confirmed');
      return OrderStatus.orderConfirmed;
    }

    // Default: waiting for assistance (items are PENDING but order not confirmed yet)
    debugPrint('[ORDER STATUS] Default -> Waiting for Assistance');
    return OrderStatus.waitingForAssistance;
  }
}

class _OrderTrackingPageState extends State<OrderTrackingPage> with TickerProviderStateMixin {
  late Order _currentOrder;
  bool _isLoading = false;
  Map<int, MenuItem>? _menuItemsCache; // Cache for menu items with images
  final Map<String, int> _itemStatusMap = {}; // Map to store item status: key = "menuId_quantity_index"
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _lineController;
  late Animation<double> _lineAnimation;
  VoidCallback? _disposeOrderUpdated;
  VoidCallback? _disposeOrderItemsAdded;
  VoidCallback? _disposeOrderCreated;

  // Update order from socket data
  void _updateOrderFromSocket(Map<String, dynamic> socketData) {
    try {
      final orderData = socketData['order'] as Map<String, dynamic>?;
      if (orderData == null) {
        debugPrint('[SOCKET UPDATE] No order data in socket message');
        return;
      }

      final orderId = orderData['order_id'] ?? orderData['orderId'];
      final items = orderData['items'] as List<dynamic>? ?? [];
      
      // Parse status - handle both int and string
      final statusValue = orderData['status'];
      final status = statusValue is int 
          ? statusValue 
          : (statusValue is String ? int.tryParse(statusValue) ?? 3 : 3);
      
      // Parse grand_total - handle both number and string
      final grandTotalValue = orderData['grand_total'] ?? orderData['grandTotal'] ?? 0;
      final grandTotal = grandTotalValue is double
          ? grandTotalValue
          : grandTotalValue is int
              ? grandTotalValue.toDouble()
              : grandTotalValue is String
                  ? double.tryParse(grandTotalValue) ?? 0.0
                  : 0.0;

      // Debug: Print received socket data
      debugPrint('[SOCKET UPDATE] Received order update - Order ID: $orderId, Status: $status, Items count: ${items.length}');
      if (items.isNotEmpty) {
        debugPrint('[SOCKET UPDATE] First item status: ${items[0] is Map ? (items[0]['STATUS'] ?? items[0]['status']) : 'N/A'}');
      }

      // Map backend status to OrderStatus enum
      final mappedStatus = OrderTrackingPage.mapStatusFromBackend(status, items);
      debugPrint('[SOCKET UPDATE] Mapped status: $mappedStatus');

      // Check if order just became SETTLED (was not SETTLED before, now is SETTLED)
      final wasSettled = _currentOrder.backendStatus == 1;
      final isNowSettled = status == 1;
      final isTableOrder = _currentOrder.tableId != null || _currentOrder.orderType == 'DINE_IN';
      final justBecameSettled = !wasSettled && isNowSettled && isTableOrder;

      // Convert backend items to CartItems
      _itemStatusMap.clear(); // Clear previous status map
      final cartItems = items.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        final menuId = item['MENU_ID'] ?? item['menu_id'];
        
        // Parse QTY - handle both number and string
        final qtyValue = item['QTY'] ?? item['qty'] ?? 1;
        final qty = qtyValue is double
            ? qtyValue
            : qtyValue is int
                ? qtyValue.toDouble()
                : qtyValue is String
                    ? double.tryParse(qtyValue) ?? 1.0
                    : 1.0;
        
        // Parse UNIT_PRICE - handle both number and string
        final unitPriceValue = item['UNIT_PRICE'] ?? item['unit_price'] ?? 0;
        final unitPrice = unitPriceValue is double
            ? unitPriceValue
            : unitPriceValue is int
                ? unitPriceValue.toDouble()
                : unitPriceValue is String
                    ? double.tryParse(unitPriceValue) ?? 0.0
                    : 0.0;
        
        // Parse STATUS - handle both number and string
        final statusValue = item['STATUS'] ?? item['status'] ?? 3;
        final status = statusValue is int
            ? statusValue
            : statusValue is String
                ? int.tryParse(statusValue) ?? 3
                : 3;
        
        final menuName = item['MENU_NAME'] ?? item['menu_name'] ?? 'Unknown Item';
        final menuIdInt = menuId is int ? menuId : int.tryParse(menuId.toString()) ?? 0;

        // Get menu item with image from cache
        final menuItem = _getMenuItemWithImage(menuIdInt, menuName, unitPrice);

        // Store status with unique key (menuId_quantity_index)
        final statusKey = '${menuIdInt}_${qty.toInt()}_$index';
        _itemStatusMap[statusKey] = status;

        return CartItem(
          item: menuItem,
          quantity: qty.toInt(),
        );
      }).toList();

      setState(() {
        _currentOrder = Order(
          id: _currentOrder.id,
          orderId: orderId is int ? orderId : int.tryParse(orderId.toString()),
          items: cartItems,
          totalPrice: grandTotal,
          orderTime: _currentOrder.orderTime,
          status: mappedStatus,
          backendStatus: status, // Preserve backend status
          orderType: _currentOrder.orderType, // Preserve order type
          tableId: _currentOrder.tableId, // Preserve table ID
        );
        _isLoading = false;
      });

      // Line animation is already running infinitely, no need to restart

      // Emit global settlement dialog event if order just became SETTLED
      if (justBecameSettled) {
        SettlementDialogService.instance.emit(_currentOrder);
      }

      // Notify parent if callback exists
      if (widget.onOrderUpdated != null) {
        widget.onOrderUpdated!(_currentOrder);
      }
    } catch (e) {
      debugPrint('Error updating order from socket: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _currentOrder = widget.order;

    // Initialize pulse animation controller
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    // Initialize line animation controller (infinite pulse)
    _lineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _lineAnimation = Tween<double>(
      begin: 0.7,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _lineController,
      curve: Curves.easeInOut,
    ));

    // Load menu items cache first, then fetch order status
    _loadMenuItemsCache().then((_) {
      _fetchLatestOrderStatus();
    });
  }

  // Load menu items to get images
  Future<void> _loadMenuItemsCache() async {
    try {
      final result = await ApiService.getMenuItems();
      if (result['success'] == true && result['data'] != null) {
        final menus = result['data'] as List<dynamic>;
        _menuItemsCache = {
          for (var menu in menus)
            menu['id'] as int: MenuItem.fromApi(menu)
        };
        debugPrint('[ORDER TRACKING] Loaded ${_menuItemsCache!.length} menu items for image cache');
      }
    } catch (e) {
      debugPrint('[ORDER TRACKING] Error loading menu items cache: $e');
    }
  }

  // Get menu item with image from cache
  MenuItem _getMenuItemWithImage(int menuId, String menuName, double price) {
    if (_menuItemsCache != null && _menuItemsCache!.containsKey(menuId)) {
      final cachedItem = _menuItemsCache![menuId]!;
      return MenuItem(
        id: menuId,
        name: menuName,
        description: cachedItem.description,
        price: price,
        category: cachedItem.category,
        categoryName: cachedItem.categoryName,
        categoryId: cachedItem.categoryId,
        icon: cachedItem.icon,
        imageUrl: cachedItem.imageUrl, // Use cached image URL
        isAvailable: cachedItem.isAvailable,
      );
    }
    
    // Fallback if not in cache
    return MenuItem(
      id: menuId,
      name: menuName,
      description: '',
      price: price,
      category: '',
      icon: Icons.restaurant_menu,
    );
  }

  // Fetch latest order status from API
  Future<void> _fetchLatestOrderStatus() async {
    if (_currentOrder.orderId == null) {
      debugPrint('[ORDER TRACKING] No order ID, skipping API fetch');
      _initializeSocket();
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      // Fetch all user orders from API
      final result = await ApiService.getUserOrders();
      
      if (result['success'] == true && result['data'] != null) {
        final orders = result['data'] as List<dynamic>;
        
        // Find the order matching our order ID
        final orderData = orders.firstWhere(
          (order) => (order['order_id'] == _currentOrder.orderId),
          orElse: () => null,
        );

        if (orderData != null) {
          // Update order with latest data from API
          final items = orderData['items'] as List<dynamic>? ?? [];
          final status = orderData['status'] as int? ?? 3;
          final grandTotal = (orderData['grand_total'] ?? 0).toDouble();
          
          // Map backend status to OrderStatus enum
          final mappedStatus = OrderTrackingPage.mapStatusFromBackend(status, items);
          
           // Convert backend items to CartItems
           _itemStatusMap.clear(); // Clear previous status map
           final cartItems = items.asMap().entries.map((entry) {
             final index = entry.key;
             final item = entry.value;
             final menuId = item['menu_id'];
             
             // Parse QTY
             final qtyValue = item['qty'] ?? 1;
             final qty = qtyValue is double
                 ? qtyValue
                 : qtyValue is int
                     ? qtyValue.toDouble()
                     : qtyValue is String
                         ? double.tryParse(qtyValue) ?? 1.0
                         : 1.0;
             
             // Parse UNIT_PRICE
             final unitPriceValue = item['unit_price'] ?? 0;
             final unitPrice = unitPriceValue is double
                 ? unitPriceValue
                 : unitPriceValue is int
                     ? unitPriceValue.toDouble()
                     : unitPriceValue is String
                         ? double.tryParse(unitPriceValue) ?? 0.0
                         : 0.0;
             
             // Parse STATUS
             final statusValue = item['status'] ?? 3;
             final status = statusValue is int
                 ? statusValue
                 : statusValue is String
                     ? int.tryParse(statusValue) ?? 3
                     : 3;
             
             final menuName = item['menu_name'] ?? 'Unknown Item';
             final menuIdInt = menuId is int ? menuId : int.tryParse(menuId.toString()) ?? 0;
             
             // Get menu item with image from cache
             final menuItem = _getMenuItemWithImage(menuIdInt, menuName, unitPrice);
             
             // Store status with unique key (menuId_quantity_index)
             final statusKey = '${menuIdInt}_${qty.toInt()}_$index';
             _itemStatusMap[statusKey] = status;
             
             return CartItem(
               item: menuItem,
               quantity: qty.toInt(),
             );
           }).toList();
          
           setState(() {
             _currentOrder = Order(
               id: _currentOrder.id,
               orderId: _currentOrder.orderId,
               items: cartItems,
               totalPrice: grandTotal,
               orderTime: _currentOrder.orderTime,
               status: mappedStatus,
               backendStatus: status, // Preserve backend status
               orderType: _currentOrder.orderType, // Preserve order type
               tableId: _currentOrder.tableId, // Preserve table ID
             );
             _isLoading = false;
           });
           
           debugPrint('[ORDER TRACKING] Fetched latest order status: $mappedStatus');
           
           // Line animation is already running infinitely, no need to restart
        } else {
          debugPrint('[ORDER TRACKING] Order not found in API response');
          setState(() {
            _isLoading = false;
          });
        }
      } else {
        debugPrint('[ORDER TRACKING] Failed to fetch orders: ${result['error']}');
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[ORDER TRACKING] Error fetching latest order status: $e');
      setState(() {
        _isLoading = false;
      });
    }

    // Initialize socket after fetching latest status
    _initializeSocket();
  }

  Future<void> _initializeSocket() async {
    if (_currentOrder.orderId == null) {
      debugPrint('[ORDER TRACKING] No order ID, skipping socket connection');
      return;
    }

    try {
      // Initialize socket connection
      await SocketService.initialize();

      // Join order room
      SocketService.joinOrder(_currentOrder.orderId!);

      // Listen for order updates
      _disposeOrderUpdated?.call();
      _disposeOrderUpdated = SocketService.addOrderUpdateListener((data) {
        if (mounted) {
          setState(() {
            _isLoading = true;
          });
          _updateOrderFromSocket(data);
        }
      });

      // Listen for order items added
      _disposeOrderItemsAdded?.call();
      _disposeOrderItemsAdded = SocketService.addOrderItemsAddedListener((data) {
        if (mounted) {
          setState(() {
            _isLoading = true;
          });
          _updateOrderFromSocket(data);
        }
      });

      // Listen for order created (in case order was just created)
      _disposeOrderCreated?.call();
      _disposeOrderCreated = SocketService.addOrderCreatedListener((data) {
        if (mounted) {
          setState(() {
            _isLoading = true;
          });
          _updateOrderFromSocket(data);
        }
      });
    } catch (e) {
      debugPrint('[ORDER TRACKING] Error initializing socket: $e');
    }
  }

  @override
  void dispose() {
    // Stop animation controllers
    _pulseController.dispose();
    _lineController.dispose();
    
    // Let menu control socket rooms; avoid leaving here to keep updates alive.
    _disposeOrderUpdated?.call();
    _disposeOrderItemsAdded?.call();
    _disposeOrderCreated?.call();
    _disposeOrderUpdated = null;
    _disposeOrderItemsAdded = null;
    _disposeOrderCreated = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    final statuses = [
      OrderStatus.waitingForAssistance,
      OrderStatus.orderConfirmed,
      OrderStatus.preparingOrder,
      OrderStatus.ordersReady,
    ];

    final currentStatusIndex = statuses.indexOf(_currentOrder.status);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Order Tracking',
          style: GoogleFonts.urbanist(
            fontWeight: FontWeight.bold,
            fontSize: isMobile ? 18 : 20,
            color: Colors.white,
          ),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [const Color(0xFF0C0E2B), const Color(0xFF1B1E4A)], // Maroon gradient
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white, size: 32),
      ),
      body: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF5F6F0), // Cream background - solid color
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(isMobile ? 16 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Order ID Card
              Container(
                padding: EdgeInsets.all(isMobile ? 16 : 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F6F0), // Cream background
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order ID',
                      style: GoogleFonts.urbanist(
                        fontSize: isMobile ? 12 : 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          _currentOrder.id,
                          style: GoogleFonts.urbanist(
                            fontSize: isMobile ? 20 : 24,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0C0E2B), // Maroon
                          ),
                        ),
                        if (_isLoading) ...[
                          const SizedBox(width: 8),
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0C0E2B)),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total Amount',
                              style: GoogleFonts.urbanist(
                                fontSize: isMobile ? 12 : 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '₱${formatPrice(_currentOrder.totalPrice)}',
                              style: GoogleFonts.urbanist(
                                fontSize: isMobile ? 18 : 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Items',
                              style: GoogleFonts.urbanist(
                                fontSize: isMobile ? 12 : 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_currentOrder.items.length}',
                              style: GoogleFonts.urbanist(
                                fontSize: isMobile ? 18 : 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              SizedBox(height: isMobile ? 16 : 24),

              // Ready Notification Card (shows when order is ready)
              if (_currentOrder.status == OrderStatus.ordersReady)
                Container(
                  margin: EdgeInsets.only(bottom: isMobile ? 16 : 24),
                  padding: EdgeInsets.all(isMobile ? 16 : 20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)], // Green gradient
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 5),
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_circle,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Your Food is Ready!',
                              style: GoogleFonts.urbanist(
                                fontSize: isMobile ? 18 : 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Please proceed to the counter to pick up your order',
                              style: GoogleFonts.urbanist(
                                fontSize: isMobile ? 12 : 14,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // Status Timeline
              Container(
                padding: EdgeInsets.all(isMobile ? 16 : 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F6F0), // Cream background
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order Status',
                      style: GoogleFonts.urbanist(
                        fontSize: isMobile ? 18 : 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: isMobile ? 16 : 24),
                    ...List.generate(statuses.length, (index) {
                      final status = statuses[index];
                      final isCompleted = index <= currentStatusIndex;
                      final isCurrent = index == currentStatusIndex;

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            children: [
                              // Main status dot with animation
                              SizedBox(
                                width: isMobile ? 50 : 60,
                                height: isMobile ? 50 : 60,
                                child: Stack(
                                  alignment: Alignment.center,
                                  clipBehavior: Clip.none,
                                  children: [
                                    // Outer pulsing ring for current status (only if not the last status)
                                    if (isCurrent && index < statuses.length - 1)
                                      Positioned(
                                        child: AnimatedBuilder(
                                          animation: _pulseAnimation,
                                          builder: (context, child) {
                                            return Opacity(
                                              opacity: 1.0 - (_pulseAnimation.value - 1.0) * 0.5,
                                              child: Container(
                                                width: (isMobile ? 40 : 50) * _pulseAnimation.value,
                                                height: (isMobile ? 40 : 50) * _pulseAnimation.value,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: const Color(0xFF0C0E2B).withValues(alpha: 0.2),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    // Inner pulsing ring for current status
                                    if (isCurrent && index < statuses.length - 1)
                                      Positioned(
                                        child: AnimatedBuilder(
                                          animation: _pulseAnimation,
                                          builder: (context, child) {
                                            return Opacity(
                                              opacity: 1.0 - (_pulseAnimation.value - 1.0) * 0.3,
                                              child: Container(
                                                width: (isMobile ? 32 : 40) * _pulseAnimation.value,
                                                height: (isMobile ? 32 : 40) * _pulseAnimation.value,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: const Color(0xFF0C0E2B).withValues(alpha: 0.3),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    // Main dot (fixed position, no animation)
                                    Container(
                                      width: isMobile ? 32 : 40,
                                      height: isMobile ? 32 : 40,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isCompleted
                                            ? const Color(0xFF0C0E2B) // Maroon
                                            : Colors.grey[300],
                                        border: Border.all(
                                          color: isCurrent
                                              ? const Color(0xFF1B1E4A) // Medium maroon
                                              : Colors.transparent,
                                          width: 3,
                                        ),
                                      ),
                                      child: isCompleted
                                          ? Icon(
                                              Icons.check,
                                              color: Colors.white,
                                              size: isMobile ? 18 : 24,
                                            )
                                          : isCurrent
                                              ? Container(
                                                  margin: EdgeInsets.all(isMobile ? 8 : 10),
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: const Color(0xFF0C0E2B),
                                                  ),
                                                )
                                              : null,
                                    ),
                                  ],
                                ),
                              ),
                              if (index < statuses.length - 1)
                                // Fixed height container to prevent layout shift
                                SizedBox(
                                  width: 2,
                                  height: (isMobile ? 50 : 60).toDouble(),
                                  child: Stack(
                                    alignment: Alignment.topCenter,
                                    clipBehavior: Clip.none,
                                    children: [
                                      // Background line for future statuses (grey)
                                      if (!isCompleted)
                                        Container(
                                          width: 2,
                                          height: (isMobile ? 50 : 60).toDouble(),
                                          color: Colors.grey[300],
                                        ),
                                      // Static completed lines (before current status)
                                      if (isCompleted && index < currentStatusIndex)
                                        Container(
                                          width: 2,
                                          height: (isMobile ? 50 : 60).toDouble(),
                                          color: const Color(0xFF0C0E2B), // Maroon
                                        ),
                                      // Animated line (only for current status line - infinite pulse)
                                      if (isCompleted && index == currentStatusIndex)
                                        AnimatedBuilder(
                                          animation: _lineAnimation,
                                          builder: (context, child) {
                                            final lineHeight = (isMobile ? 50 : 60).toDouble();
                                            return Container(
                                              width: 2,
                                              height: lineHeight * _lineAnimation.value,
                                              color: const Color(0xFF0C0E2B), // Maroon
                                            );
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          SizedBox(width: isMobile ? 12 : 16),
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                top: index == 0 ? (isMobile ? 6 : 8) : 0,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    status == OrderStatus.waitingForAssistance
                                        ? 'Waiting for Assistance'
                                        : status == OrderStatus.orderConfirmed
                                        ? 'Order Confirmed'
                                        : status == OrderStatus.preparingOrder
                                        ? 'Preparing Order'
                                        : 'Orders Ready',
                                    style: GoogleFonts.urbanist(
                                      fontSize: isMobile ? 14 : 16,
                                      fontWeight: isCurrent
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                      color: isCompleted
                                          ? Colors.black87
                                          : Colors.grey[600],
                                    ),
                                  ),
                                  if (isCurrent) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Current status',
                                      style: GoogleFonts.urbanist(
                                        fontSize: isMobile ? 10 : 12,
                                        color: const Color(0xFF0C0E2B), // Maroon
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),

              SizedBox(height: isMobile ? 16 : 24),

              // Order Items
              Container(
                padding: EdgeInsets.all(isMobile ? 16 : 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F6F0), // Cream background
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order Items',
                      style: GoogleFonts.urbanist(
                        fontSize: isMobile ? 18 : 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: isMobile ? 12 : 16),
                    ..._currentOrder.items.asMap().entries.map((entry) {
                      final index = entry.key;
                      final cartItem = entry.value;
                      final menuId = cartItem.item.id ?? 0;
                      final statusKey = '${menuId}_${cartItem.quantity}_$index';
                      final itemStatus = _itemStatusMap[statusKey] ?? 3;
                      
                      return Padding(
                        padding: EdgeInsets.only(bottom: isMobile ? 12 : 16),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: cartItem.item.imageUrl != null && cartItem.item.imageUrl!.startsWith('http')
                              ? CachedNetworkImage(
                                      imageUrl: cartItem.item.imageUrl!,
                                      width: isMobile ? 50 : 60,
                                      height: isMobile ? 50 : 60,
                                      fit: BoxFit.cover,
                                      memCacheWidth: isMobile ? 100 : 120,
                                      memCacheHeight: isMobile ? 100 : 120,
                                      fadeInDuration: const Duration(milliseconds: 200),
                                      placeholder: (context, url) => Container(
                                        width: isMobile ? 50 : 60,
                                        height: isMobile ? 50 : 60,
                                        decoration: BoxDecoration(
                                          color: Colors.grey[200],
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Center(
                                          child: SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          ),
                                        ),
                                      ),
                                      errorWidget: (context, url, error) => Container(
                                        width: isMobile ? 50 : 60,
                                        height: isMobile ? 50 : 60,
                                        decoration: BoxDecoration(
                                          color: Colors.grey[200],
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          cartItem.item.icon,
                                          color: Colors.grey[600],
                                          size: isMobile ? 25 : 30,
                                        ),
                                      ),
                                    )
                                  : cartItem.item.imageUrl != null
                                      ? Image.asset(
                                          cartItem.item.imageUrl!,
                                          width: isMobile ? 50 : 60,
                                          height: isMobile ? 50 : 60,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                                return Container(
                                                  width: isMobile ? 50 : 60,
                                                  height: isMobile ? 50 : 60,
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey[200],
                                                    borderRadius:
                                                        BorderRadius.circular(8),
                                                  ),
                                                  child: Icon(
                                                    cartItem.item.icon,
                                                    color: Colors.grey[600],
                                                    size: isMobile ? 25 : 30,
                                                  ),
                                                );
                                              },
                                        )
                                      : Container(
                                          width: isMobile ? 50 : 60,
                                          height: isMobile ? 50 : 60,
                                          decoration: BoxDecoration(
                                            color: Colors.grey[200],
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Icon(
                                            cartItem.item.icon,
                                            color: Colors.grey[600],
                                            size: isMobile ? 25 : 30,
                                          ),
                                        ),
                            ),
                            SizedBox(width: isMobile ? 10 : 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    cartItem.item.name,
                                    style: GoogleFonts.urbanist(
                                      fontSize: isMobile ? 14 : 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Text(
                                        'Quantity: ${cartItem.quantity}',
                                        style: GoogleFonts.urbanist(
                                          fontSize: isMobile ? 12 : 14,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // Status Badge
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: isMobile ? 6 : 8,
                                          vertical: isMobile ? 2 : 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: itemStatus == 1
                                              ? Colors.green[100] // READY - Light green
                                              : itemStatus == 2
                                                  ? Colors.orange[100] // PREPARING - Light orange
                                                  : Colors.grey[200], // PENDING - Light grey
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: itemStatus == 1
                                                ? Colors.green[700]!
                                                : itemStatus == 2
                                                    ? Colors.orange[700]!
                                                    : Colors.grey[600]!,
                                            width: 1,
                                          ),
                                        ),
                                        child: Text(
                                          itemStatus == 1
                                              ? 'Ready'
                                              : itemStatus == 2
                                                  ? 'Preparing'
                                                  : 'Pending',
                                          style: GoogleFonts.urbanist(
                                            fontSize: isMobile ? 10 : 11,
                                            fontWeight: FontWeight.bold,
                                            color: itemStatus == 1
                                                ? Colors.green[900]
                                                : itemStatus == 2
                                                    ? Colors.orange[900]
                                                    : Colors.grey[800],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '₱${formatPrice(cartItem.item.price * cartItem.quantity)}',
                              style: GoogleFonts.urbanist(
                                fontSize: isMobile ? 14 : 16,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF0C0E2B), // Maroon
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),

              SizedBox(height: isMobile ? 16 : 24),

              // Add More Items Button
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)], // Maroon gradient
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0C0E2B).withValues(alpha: 0.3), // Maroon shadow
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Navigate to menu page - will automatically detect active order
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const MenuHomePage(),
                      ),
                    ).then((_) {
                      // Reload orders when coming back
                      // The order will be automatically updated if items were added
                    });
                  },
                  icon: const Icon(
                    Icons.add_shopping_cart,
                    color: Colors.white,
                  ),
                  label: Text(
                    'Add More Order',
                    style: GoogleFonts.urbanist(
                      fontSize: isMobile ? 16 : 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shadowColor: Colors.transparent,
                    padding: EdgeInsets.symmetric(
                      vertical: isMobile ? 16 : 18,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ).copyWith(
                    overlayColor: WidgetStateProperty.all(Colors.transparent), // Remove blue splash
                  ),
                ),
              ),

              SizedBox(height: isMobile ? 16 : 24),
            ],
          ),
        ),
      ),
    );
  }

  // Show settlement confirmation dialog
  void _showSettlementConfirmation(Order order) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Success Icon
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: Colors.white,
                    size: 64,
                  ),
                ),
                const SizedBox(height: 20),
                // Title
                Text(
                  'Bill Settled!',
                  style: GoogleFonts.urbanist(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                // Message
                Text(
                  'Your bill has been settled successfully.\nThank you for dining with us!\n\nPlease come again!',
                  style: GoogleFonts.urbanist(
                    fontSize: 16,
                    color: Colors.white.withValues(alpha: 0.95),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                // Order Details
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Order No:',
                            style: GoogleFonts.urbanist(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                          Text(
                            order.id,
                            style: GoogleFonts.urbanist(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total Amount:',
                            style: GoogleFonts.urbanist(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                          Text(
                            '₱${formatPrice(order.totalPrice)}',
                            style: GoogleFonts.urbanist(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // OK Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      // Close dialog and navigate back to menu page
                      Navigator.of(context).pop(); // Close dialog
                      Navigator.of(context).pop(); // Exit tracking page
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF4CAF50),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'OK',
                      style: GoogleFonts.urbanist(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
