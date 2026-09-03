import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models.dart';
import '../../menuApp/models.dart' as menu_models;
import '../order_tracking_page.dart';
import '../menu_item_detail_page.dart';
import '../../menuApp/widgets/menu_item_card.dart';
import '../../shared/login_page.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/settlement_dialog_service.dart';
import '../../menuApp/widgets/cart_bottom_sheet.dart';
import '../../menuApp/widgets/menu_background.dart';

class MenuHomePage extends StatefulWidget {
  final String? initialCategory;
  final int? initialCategoryId;
  
  const MenuHomePage({super.key, this.initialCategory, this.initialCategoryId});

  @override
  State<MenuHomePage> createState() => _MenuHomePageState();
}

class _MenuHomePageState extends State<MenuHomePage> with SingleTickerProviderStateMixin {
  late String selectedCategory;
  late PageController _pageController;
  final TextEditingController searchController = TextEditingController();
  List<CartItem> cart = [];
  List<Order> orders = [];
  int orderIdCounter = 1;
  
  List<MenuItem> menuItems = []; // Store ALL menu items (not filtered)
  List<String> categories = ['All'];
  Map<String, int> categoryNameToId = {}; // Cache category name to ID mapping
  bool isLoading = true;
  String? errorMessage;
  int? selectedCategoryId;
  final ScrollController _categoryScrollController = ScrollController(); // For auto-scrolling category filter
  bool _isManualCategoryChange = false; // Flag to prevent flicker during manual button clicks
  bool _categoriesLoaded = false; // Flag to track if categories are loaded (for PageView initialization)
  bool _pageControllerInitialized = false; // Flag to track if PageController is initialized with correct page
  final Set<int> _joinedOrderIds = {}; // Track socket rooms joined
  VoidCallback? _disposeOrderUpdated;
  VoidCallback? _disposeOrderItemsAdded;
  VoidCallback? _disposeOrderCreated;
  late final AnimationController _trackingShakeController;
  late final Animation<double> _trackingShake;
  
  int _displayLimit = 9; // Initial limit for "All" filter
  
  // ============================================
  // BOTTOM BAR HEIGHT SETTINGS - ADJUST HERE
  // ============================================
  // Adjust these values to change bottom bar height
  // Current: 30px (mobile), 40px (tablet), 50px (large tablet)
  // You can make it smaller (e.g., 20, 30, 40) or larger as needed
  double get _bottomBarHeightMobile => 30.0;    // Mobile bottom bar height
  double get _bottomBarHeightTablet => 22.0;    // Tablet bottom bar height
  double get _bottomBarHeightLargeTablet => 30.0; // Large tablet bottom bar height
  // ============================================

  @override
  void initState() {
    super.initState();
    selectedCategory = widget.initialCategory ?? 'All';
    selectedCategoryId = widget.initialCategoryId;
    // Initialize page controller - will be updated after categories load
    _pageController = PageController(
      initialPage: 0,
    );
    _loadOrders(); // Load saved orders first
    _loadData();
    _initializeSocket(); // Initialize socket for real-time updates

    _trackingShakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _trackingShake = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -8.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: -8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: 0.0), weight: 1),
    ]).animate(
      CurvedAnimation(parent: _trackingShakeController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _categoryScrollController.dispose();
    _pageController.dispose();
    searchController.dispose();
    _trackingShakeController.dispose();
    _cleanupSocket(); // Clean up socket listeners
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      // Load categories
      final categoriesResult = await ApiService.getCategories();
      
      // Check if unauthorized - redirect to login
      if (categoriesResult['unauthorized'] == true) {
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginPage()),
            (route) => false,
          );
        }
        return;
      }
      
      if (categoriesResult['success'] == true) {
        final cats = List<Map<String, dynamic>>.from(categoriesResult['data']);
        // Build category name to ID mapping
        final categoryMap = <String, int>{};
        for (var cat in cats) {
          // Ensure id is properly converted to int
          final catId = cat['id'] is int ? cat['id'] as int : (cat['id'] as num?)?.toInt();
          if (catId != null) {
            categoryMap[cat['name'] as String] = catId;
          }
        }
        // Calculate the correct initial page index BEFORE setting state
        final targetCategory = widget.initialCategory ?? selectedCategory;
        // Keep API order for categories (ascending order)
        final newCategories = ['All', ...cats.map((cat) => cat['name'] as String)];
        final initialIndex = newCategories.indexOf(targetCategory);
        final correctInitialPage = initialIndex >= 0 ? initialIndex : 0;
        
        setState(() {
          categories = newCategories;
          categoryNameToId = categoryMap;
          _categoriesLoaded = true; // Mark categories as loaded
          
          // Prioritize initialCategoryId if provided (from category_page navigation)
          if (widget.initialCategoryId != null) {
            selectedCategoryId = widget.initialCategoryId;
            // Also ensure selectedCategory matches if we have initialCategory
            if (widget.initialCategory != null && widget.initialCategory != selectedCategory) {
              selectedCategory = widget.initialCategory!;
            }
          } else if (selectedCategory != 'All' && selectedCategoryId == null) {
            // If we have a selectedCategory but no selectedCategoryId, try to get it from the map
            selectedCategoryId = categoryMap[selectedCategory];
          }
        });
        
        // Recreate PageController with correct initial page if needed
        if (mounted && correctInitialPage != 0 && !_pageControllerInitialized) {
          // Dispose old controller
          _pageController.dispose();
          // Create new controller with correct initial page
          _pageController = PageController(initialPage: correctInitialPage);
          _pageControllerInitialized = true;
          debugPrint('🔄 Recreated PageController with initialPage=$correctInitialPage for category="$targetCategory"');
        } else if (mounted && _pageController.hasClients && !_pageControllerInitialized) {
          // If controller already has clients, jump to correct page
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _pageController.hasClients) {
              final finalIndex = categories.indexOf(selectedCategory).clamp(0, categories.length - 1);
              if (finalIndex >= 0 && finalIndex < categories.length) {
                _pageController.jumpToPage(finalIndex);
                _pageControllerInitialized = true;
                debugPrint('📍 Jumped to page $finalIndex for category="$selectedCategory"');
              }
            }
          });
        }
      }

      // Load ALL menu items (no category filter) for client-side filtering
      final menuResult = await ApiService.getMenuItems(
        categoryId: null, // Load all items
      );
      
      // Check if unauthorized - redirect to login
      if (menuResult['unauthorized'] == true) {
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginPage()),
            (route) => false,
          );
        }
        return;
      }
      
      if (menuResult['success'] == true) {
        final menuData = List<Map<String, dynamic>>.from(menuResult['data']);
        // Keep API order for menu items (ascending order)
        final items = menuData.map((item) => MenuItem.fromApi(item)).toList();
        
        // Debug: Print category distribution
        final categoryCounts = <int, int>{};
        for (var item in items) {
          if (item.categoryId != null) {
            categoryCounts[item.categoryId!] = (categoryCounts[item.categoryId] ?? 0) + 1;
          }
        }
        debugPrint('📊 Loaded ${items.length} menu items. Category distribution: $categoryCounts');
        debugPrint('📋 CategoryNameToId mapping: $categoryNameToId');
        if (widget.initialCategoryId != null) {
          debugPrint('🎯 Initial categoryId from navigation: ${widget.initialCategoryId}');
          final itemsForCategory = items.where((item) => item.categoryId == widget.initialCategoryId).toList();
          debugPrint('✅ Found ${itemsForCategory.length} items for initialCategoryId=${widget.initialCategoryId}');
        }
        
        setState(() {
          menuItems = items;
          isLoading = false;
        });
        
        // Preload images in background for better UX
        final imageUrls = items
            .where((item) => item.imageUrl != null && item.imageUrl!.startsWith('http'))
            .map((item) => item.imageUrl!)
            .toList();
        if (imageUrls.isNotEmpty) {
          // Preload in background without blocking UI
          ApiService.preloadImages(imageUrls).catchError((e) {
            // Silently fail - preloading is optional
          });
        }
      } else {
        setState(() {
          errorMessage = menuResult['error'] ?? 'Failed to load menu items';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Error loading data: ${e.toString()}';
        isLoading = false;
      });
    }
  }

  int _estimateMinutes(MenuItem item) {
    // Stable, lightweight estimate (no extra model fields needed)
    return 5 + (item.name.hashCode.abs() % 21); // 5..25
  }

  // STEP 2 — CATEGORY CHANGE (BUTTON ↔ PAGE SYNC)
  void _onCategoryChanged(String category) {
    final index = categories.indexOf(category);
    if (index == -1) return;

    // Set flag to prevent flicker during animation
    _isManualCategoryChange = true;
    
    setState(() {
      selectedCategory = category;
      selectedCategoryId = category != 'All' ? categoryNameToId[category] : null;
      _displayLimit = 9;
    });

    if (_pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      ).then((_) {
        // Reset flag after animation completes
        if (mounted) {
          _isManualCategoryChange = false;
        }
      });
    }
    
    // Auto-scroll category filter to show selected category
    _scrollToSelectedCategory();
  }

  // STEP 3 — PAGE CHANGE (SWIPE ↔ BUTTON SYNC)
  void _onPageChanged(int index) {
    if (index < 0 || index >= categories.length) return;

    // Only update selectedCategory if it's a swipe gesture (not manual button click)
    // This prevents flicker when manually clicking buttons far away
    if (!_isManualCategoryChange) {
      setState(() {
        selectedCategory = categories[index];
        selectedCategoryId = selectedCategory != 'All' ? categoryNameToId[selectedCategory] : null;
        _displayLimit = 9;
      });
      
      // Auto-scroll category filter to show selected category
      _scrollToSelectedCategory();
    }
  }

  void _scrollToSelectedCategory() {
    if (!mounted) return;
    final index = categories.indexOf(selectedCategory);
    if (index >= 0 && _categoryScrollController.hasClients) {
      // Calculate approximate position (each button is ~100-120px wide with padding)
      final itemWidth = 100.0; // Approximate width per category button
      final screenWidth = MediaQuery.of(context).size.width;
      final scrollPosition = (index * itemWidth) - (screenWidth / 2) + (itemWidth / 2);
      _categoryScrollController.animateTo(
        scrollPosition.clamp(0.0, _categoryScrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }


  // Get all filtered items without limit
  List<MenuItem> get _allFilteredItems {
    var items = menuItems;

    if (selectedCategory != 'All') {
      // Use categoryId for filtering if available (more reliable than name matching)
      if (selectedCategoryId != null) {
        // Ensure both are int for proper comparison
        items = items.where((item) {
          if (item.categoryId == null) return false;
          final itemCatId = item.categoryId is int ? item.categoryId : (item.categoryId as num?)?.toInt();
          final targetCatId = selectedCategoryId is int ? selectedCategoryId : (selectedCategoryId as num?)?.toInt();
          return itemCatId == targetCatId;
        }).toList();
      } else {
        // Fallback to name matching if categoryId is not available
        items = items.where((item) => 
          item.category == selectedCategory || 
          item.categoryName == selectedCategory ||
          (item.category.isNotEmpty && item.category.toLowerCase() == selectedCategory.toLowerCase()) ||
          (item.categoryName != null && item.categoryName!.toLowerCase() == selectedCategory.toLowerCase())
        ).toList();
      }
    }

    if (searchController.text.isNotEmpty) {
      final query = searchController.text.toLowerCase();
      items = items.where((item) {
        return item.name.toLowerCase().contains(query) ||
            item.description.toLowerCase().contains(query);
      }).toList();
    }

    return items;
  }

  // Get filtered items with limit applied for "All" filter
  List<MenuItem> get filteredItems {
    final allItems = _allFilteredItems;
    
    // Apply limit only for "All" filter when not searching
    if (selectedCategory == 'All' && searchController.text.isEmpty) {
      return allItems.take(_displayLimit).toList();
    }
    
    return allItems;
  }

  // Check if there are more items to load
  bool get hasMoreItems {
    if (selectedCategory != 'All' || searchController.text.isNotEmpty) {
      return false; // No limit for category filters or search
    }
    return _allFilteredItems.length > _displayLimit;
  }

  double get totalPrice {
    return cart.fold(
      0.0,
      (sum, cartItem) => sum + (cartItem.item.price * cartItem.quantity),
    );
  }

  // Check if tracking button should be shown
  bool get shouldShowTrackingButton {
    if (orders.isEmpty) return false;
    
    // Show button if there's at least one order that is NOT a SETTLED table order
    final hasActiveOrder = orders.any((order) => !_isSettledTableOrder(order));
    
    debugPrint('[TRACKING BTN] shouldShowTrackingButton: $hasActiveOrder (total orders: ${orders.length})');
    return hasActiveOrder;
  }

  bool _isSettledTableOrder(Order order) {
    final isSettled = order.backendStatus != null && order.backendStatus == 1;
    final isTableOrder = order.tableId != null || order.orderType == 'DINE_IN';
    return isSettled && isTableOrder;
  }

  Order? get _activeOrder {
    if (orders.isEmpty) return null;
    return orders.firstWhere(
      (order) => !_isSettledTableOrder(order),
      orElse: () => orders.last,
    );
  }

  int get totalItems {
    return cart.fold(0, (sum, cartItem) => sum + cartItem.quantity);
  }

  void addToCart(MenuItem item) {
    setState(() {
      final existingIndex = cart.indexWhere(
        (cartItem) => cartItem.item.name == item.name,
      );
      if (existingIndex >= 0) {
        cart[existingIndex].quantity++;
      } else {
        cart.add(CartItem(item: item, quantity: 1));
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${item.name} added to cart'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void removeFromCart(int index) {
    setState(() {
      cart.removeAt(index);
    });
  }

  void increaseQuantity(int index) {
    setState(() {
      cart[index].quantity++;
    });
  }

  void decreaseQuantity(int index) {
    setState(() {
      if (cart[index].quantity > 1) {
        cart[index].quantity--;
      } else {
        cart.removeAt(index);
      }
    });
  }

  int getItemQuantity(MenuItem item) {
    final existingIndex = cart.indexWhere(
      (cartItem) => cartItem.item.name == item.name,
    );
    if (existingIndex >= 0) {
      return cart[existingIndex].quantity;
    }
    return 0;
  }

  void increaseItemQuantity(MenuItem item) {
    setState(() {
      final existingIndex = cart.indexWhere(
        (cartItem) => cartItem.item.name == item.name,
      );
      if (existingIndex >= 0) {
        cart[existingIndex].quantity++;
      } else {
        cart.add(CartItem(item: item, quantity: 1));
      }
    });
  }

  void decreaseItemQuantity(MenuItem item) {
    setState(() {
      final existingIndex = cart.indexWhere(
        (cartItem) => cartItem.item.name == item.name,
      );
      if (existingIndex >= 0) {
        if (cart[existingIndex].quantity > 1) {
          cart[existingIndex].quantity--;
        } else {
          cart.removeAt(existingIndex);
        }
      }
    });
  }

  void loadMoreItems() {
    setState(() {
      _displayLimit += 9; // Load 9 more items
    });
  }

  // Load orders from local storage and sync with server
  Future<void> _loadOrders() async {
    try {
      // First, load from local storage for quick display
      final savedOrders = await ApiService.loadOrders();
      if (savedOrders.isNotEmpty) {
        setState(() {
          orders = savedOrders
              .map((orderJson) => Order.fromJson(orderJson))
              .toList();
        });
        _syncSocketOrderRooms();
      }

      // Then sync with server to get latest orders and remove deleted ones
      await _syncOrdersFromServer();
    } catch (e) {
      debugPrint('Error loading orders: $e');
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
          // Get order status - map from database status to OrderStatus enum
          // Backend: Order Status - 3=PENDING, 2=CONFIRMED, 1=SETTLED, -1=CANCELLED
          // Use the same mapping logic as order_tracking_page.dart
          final dbStatus = orderData['status'] is int 
              ? orderData['status'] 
              : (orderData['status'] is String ? int.tryParse(orderData['status']) ?? 3 : 3);
          final items = orderData['items'] as List<dynamic>? ?? [];
          final mappedStatus = OrderTrackingPage.mapStatusFromBackend(dbStatus, items);

          // Convert order items to CartItems
          final cartItems = <CartItem>[];
          if (orderData['items'] != null) {
            for (final itemData in orderData['items']) {
              // Try to find menu item from loaded menu items
              MenuItem? menuItem;
              final menuId = itemData['menu_id'] is int ? itemData['menu_id'] : (itemData['menu_id'] as num?)?.toInt();
              
              if (menuId != null) {
                menuItem = allMenuItems.firstWhere(
                  (item) => item.id == menuId,
                  orElse: () => MenuItem(
                    id: menuId,
                    name: itemData['menu_name'] ?? 'Unknown Item',
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
                  name: itemData['menu_name'] ?? 'Unknown Item',
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
            status: mappedStatus,
            backendStatus: dbStatus,
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
      debugPrint('Error syncing orders from server: $e');
      // On error, keep local orders
    }
  }

  // Save orders to local storage
  Future<void> _saveOrders() async {
    try {
      final ordersJson = orders.map((order) => order.toJson()).toList();
      await ApiService.saveOrders(ordersJson);
    } catch (e) {
      debugPrint('Error saving orders: $e');
    }
  }

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
      debugPrint('Error initializing socket in menu_home_page: $e');
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

    final orderIdRaw = orderData['order_id'] ?? orderData['orderId'] ?? data['order_id'] ?? data['orderId'];
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
    if (orderIndex == -1) return;
    if (orderIndex == -1) return;

    _updateOrderFromSocket(orderData, orderIndex);
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
      
      // Parse grand_total
      final grandTotalValue = orderData['grand_total'] ?? 0;
      final grandTotal = grandTotalValue is double
          ? grandTotalValue
          : grandTotalValue is int
              ? grandTotalValue.toDouble()
              : grandTotalValue is String
                  ? double.tryParse(grandTotalValue) ?? 0.0
                  : 0.0;

      // Map backend status to OrderStatus enum
      final mappedStatus = OrderTrackingPage.mapStatusFromBackend(dbStatus, items);

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
        final menuId = itemData['menu_id'] is int ? itemData['menu_id'] : (itemData['menu_id'] as num?)?.toInt();
        
        if (menuId != null) {
          menuItem = allMenuItems.firstWhere(
            (item) => item.id == menuId,
            orElse: () => MenuItem(
              id: menuId,
              name: itemData['menu_name'] ?? 'Unknown Item',
              description: '',
              price: (itemData['unit_price'] ?? 0).toDouble(),
              category: '',
              icon: Icons.restaurant_menu,
            ),
          );
        } else {
          menuItem = MenuItem(
            id: itemData['menu_id'],
            name: itemData['menu_name'] ?? 'Unknown Item',
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
          : (orderData['table_id'] is String ? int.tryParse(orderData['table_id']) : null) ?? existingOrder.tableId;
      final orderType = orderData['order_type'] as String? ?? existingOrder.orderType;
      
      // Check if order just became SETTLED (was not SETTLED before, now is SETTLED)
      final wasSettled = existingOrder.backendStatus == 1;
      final isNowSettled = dbStatus == 1;
      final isTableOrder = tableId != null || orderType == 'DINE_IN';
      final justBecameSettled = !wasSettled && isNowSettled && isTableOrder;

      // Update the order
      final updatedOrder = Order(
        id: existingOrder.id,
        orderId: orderId ?? existingOrder.orderId,
        items: cartItems,
        totalPrice: grandTotal,
        orderTime: existingOrder.orderTime,
        status: mappedStatus,
        backendStatus: dbStatus,
        orderType: orderType,
        tableId: tableId,
      );

      if (mounted) {
        setState(() {
          // Create a new list to ensure Flutter detects the change
          final updatedOrders = List<Order>.from(orders);
          updatedOrders[orderIndex] = updatedOrder;
          orders = updatedOrders;
          if (existingOrder.backendStatus != dbStatus) {
            _trackingShakeController.forward(from: 0);
          }
        });
        _syncSocketOrderRooms();
        
        debugPrint('[SOCKET UPDATE] Updated order ${updatedOrder.id} - backendStatus: ${updatedOrder.backendStatus}, tableId: ${updatedOrder.tableId}, orderType: ${updatedOrder.orderType}');
        debugPrint('[SOCKET UPDATE] Total orders: ${orders.length}, SETTLED table orders: ${orders.where((o) => o.backendStatus == 1 && (o.tableId != null || o.orderType == 'DINE_IN')).length}');
        
        await _saveOrders();
        
        // Show confirmation dialog if order just became SETTLED
          if (justBecameSettled) {
          SettlementDialogService.instance.emit(updatedOrder);
        }
      }
    } catch (e) {
      debugPrint('Error updating order from socket in menu_home_page: $e');
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
      debugPrint('Error cleaning up socket in menu_home_page: $e');
    }
  }

  void _syncSocketOrderRooms() {
    final activeIds = orders
        .where((order) => order.orderId != null && !_isSettledTableOrder(order))
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

  void _resetDisplayLimit() {
    setState(() {
      _displayLimit = 9; // Reset to initial limit
    });
  }

  // Build preview of next/previous category when dragging

  Widget _buildQuantityControl({
    required MenuItem item,
    required int quantity,
    required bool isMobile,
    required bool isLargeTablet,
    Key? key,
  }) {
    if (quantity == 0) {
      return Container(
        key: key ?? ValueKey('${item.name}_0'),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)], // Maroon gradient
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0C0E2B).withValues(alpha: 0.3), // Maroon shadow
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: IconButton(
          icon: Icon(Icons.add, size: isMobile ? 20 : (isLargeTablet ? 32 : 22), color: Colors.white),
          onPressed: () => increaseItemQuantity(item),
          padding: EdgeInsets.all(isMobile ? 4 : (isLargeTablet ? 10 : 5)),
          constraints: BoxConstraints(
            minWidth: isMobile ? 32 : (isLargeTablet ? 48 : 36),
            minHeight: isMobile ? 32 : (isLargeTablet ? 48 : 36),
          ),
          style: IconButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            alignment: Alignment.center,
          ),
        ),
      );
    }
    return Container(
      key: key ?? ValueKey('${item.name}_$quantity'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)], // Maroon gradient
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0C0E2B).withValues(alpha: 0.3), // Maroon shadow
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              Icons.remove,
              size: isMobile ? 20 : (isLargeTablet ? 32 : 22),
              color: Colors.white,
            ),
            onPressed: () => decreaseItemQuantity(item),
            padding: EdgeInsets.all(isMobile ? 4 : (isLargeTablet ? 10 : 5)),
            constraints: BoxConstraints(
              minWidth: isMobile ? 32 : (isLargeTablet ? 48 : 36),
              minHeight: isMobile ? 32 : (isLargeTablet ? 48 : 36),
            ),
            style: IconButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              alignment: Alignment.center,
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 6 : (isLargeTablet ? 12 : 8)),
            child: Text(
              '$quantity',
              style: GoogleFonts.urbanist(
                fontWeight: FontWeight.bold,
                fontSize: isMobile ? 14 : (isLargeTablet ? 24 : 16),
                color: Colors.white,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.add,
              size: isMobile ? 20 : (isLargeTablet ? 32 : 22),
              color: Colors.white,
            ),
            onPressed: () => increaseItemQuantity(item),
            padding: EdgeInsets.all(isMobile ? 4 : (isLargeTablet ? 10 : 5)),
            constraints: BoxConstraints(
              minWidth: isMobile ? 32 : (isLargeTablet ? 48 : 36),
              minHeight: isMobile ? 32 : (isLargeTablet ? 48 : 36),
            ),
            style: IconButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              alignment: Alignment.center,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> placeOrder(List<CartItem> cartItems, double total, String? orderType) async {
    // Check if there's an active order (waitingForAssistance, orderConfirmed, preparingOrder)
    // If yes, automatically add items to existing order
    Order? activeOrder;
    try {
      activeOrder = orders.firstWhere(
        (order) => order.orderId != null && 
          (order.status == OrderStatus.waitingForAssistance || 
           order.status == OrderStatus.orderConfirmed || 
           order.status == OrderStatus.preparingOrder),
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

    // Show loading dialog for new order
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0C0E2B)),
                ),
                const SizedBox(height: 16),
                Text(
                  'Placing order...',
                  style: GoogleFonts.urbanist(
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      // Generate order number: ORD-YYYYMMDD-HHMMSS
      final now = DateTime.now();
      final orderNo = 'ORD-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

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
          'status': 3, // Default status: PENDING (3=PENDING, 2=PREPARING, 1=READY)
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

      // Hide loading dialog
      if (mounted) {
        Navigator.pop(context);
      }

      // Check if unauthorized - redirect to login
      if (result['unauthorized'] == true) {
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginPage()),
            (route) => false,
          );
        }
        return;
      }

      if (result['success'] == true) {
        final orderData = result['data'];
        
        // Create Order object for local tracking
        final order = Order(
          id: orderData['order_no'] ?? orderNo,
          orderId: orderData['order_id'], // Save backend order ID
          items: List.from(cartItems),
          totalPrice: grandTotal,
          orderTime: DateTime.now(),
          status: OrderStatus.waitingForAssistance,
          backendStatus: 3, // PENDING (default status for new orders)
          orderType: orderType,
          tableId: tableId,
        );

        setState(() {
          orders.add(order);
          orderIdCounter++;
          cart.clear();
        });

        // Join order room for socket updates
        if (order.orderId != null) {
          await SocketService.initialize();
          SocketService.joinOrder(order.orderId!);
        }

        // Save orders to local storage
        await _saveOrders();

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Order placed successfully! Order #${orderData['order_no']}'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.green,
            ),
          );

          // Navigate to order tracking page
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OrderTrackingPage(order: order),
            ),
          );
        }
      } else {
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
      // Hide loading dialog
      if (mounted) {
        Navigator.pop(context);
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
  Future<void> _addItemsToExistingOrder(List<CartItem> cartItems, double total, String? orderType, Order existingOrder) async {
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

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0C0E2B)),
                ),
                const SizedBox(height: 16),
                Text(
                  'Adding items to order...',
                  style: GoogleFonts.urbanist(
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

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
          'status': 3, // Default status: PENDING (3=PENDING, 2=PREPARING, 1=READY)
        };
      }).toList();

      // Call API to add items to existing order
      final result = await ApiService.addItemsToOrder(
        orderId: existingOrder.orderId!,
        items: items,
      );

      // Hide loading dialog
      if (mounted) {
        Navigator.pop(context);
      }

      // Check if unauthorized - redirect to login
      if (result['unauthorized'] == true) {
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginPage()),
            (route) => false,
          );
        }
        return;
      }

      if (result['success'] == true) {
        final orderData = result['data'];
        
        // Update existing order with new items and totals
        final updatedOrder = Order(
          id: existingOrder.id,
          orderId: existingOrder.orderId,
          items: [
            ...existingOrder.items,
            ...cartItems,
          ],
          totalPrice: (orderData['new_grand_total'] ?? existingOrder.totalPrice + total).toDouble(),
          orderTime: existingOrder.orderTime,
          status: existingOrder.status,
          backendStatus: existingOrder.backendStatus, // Preserve backend status
          orderType: existingOrder.orderType ?? orderType, // Preserve or update order type
          tableId: existingOrder.tableId, // Preserve table ID
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

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${cartItems.length} item(s) added to order #${existingOrder.id}'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.green,
            ),
          );

          // Navigate to order tracking page with updated order
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OrderTrackingPage(
                order: updatedOrder,
                onOrderUpdated: (updated) {
                  setState(() {
                    final index = orders.indexWhere((o) => o.orderId == updated.orderId);
                    if (index >= 0) {
                      orders[index] = updated;
                    }
                    _saveOrders();
                  });
                },
              ),
            ),
          );
        }
      } else {
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
      // Hide loading dialog
      if (mounted) {
        Navigator.pop(context);
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

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;
    // Gumamit ng shortestSide para hindi ma-detect na tablet ang malalaking phones sa landscape
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final isMobile = shortestSide < 600;
    final isTablet = shortestSide >= 600 && shortestSide < 1024;
    final isLargeTablet = shortestSide >= 1024; // iPad Pro and larger

    // Responsive grid columns
    int crossAxisCount;
    double childAspectRatio;
    double spacing;

    // Landscape: laging 3 items per row para malalaki ang cards,
    // tapos ina-adjust natin ang aspect ratio para makita yung details sa baba.
    if (isLandscape) {
      if (isMobile) {
        // Small phones sa landscape: mas matangkad ang card para makita details
        crossAxisCount = 3;
        childAspectRatio = 0.75;
        spacing = 10;
      } else if (isTablet) {
        // Regular tablets sa landscape: 3 columns, mas maikli ang card para hindi masyadong matangkad
        crossAxisCount = 3;
        childAspectRatio = 1.80;
        spacing = 16;
      } else if (isLargeTablet) {
        // iPad Pro at mas malalaking tablets sa landscape: 3 columns, mas maikli para walang sobrang space
        crossAxisCount = 3;
        childAspectRatio = 1.80;
        spacing = 18;
      } else {
        // Mas malalaking screen (desktop / web): 3 columns, matangkad pa rin
        crossAxisCount = 3;
        childAspectRatio = 0.95;
        spacing = 18;
      }
    } else if (isMobile) {
      crossAxisCount = 2;
      // Mas matangkad para makita details sa mobile portrait
      childAspectRatio = 0.75;
      spacing = 12;
    } else if (isTablet) {
      crossAxisCount = 3;
      // Mas matangkad para makita details sa tablet portrait (iPad Mini, etc.)
      childAspectRatio = 0.8;
      spacing = 14;
    } else if (isLargeTablet) {
      crossAxisCount = 4;
      // iPad Pro portrait: 4 columns, mas matangkad ang cards para makita details sa baba
      childAspectRatio = 0.65;
      spacing = 16;
    } else {
      crossAxisCount = 4;
      // Mas matangkad para makita details sa large screens
      childAspectRatio = 0.85;
      spacing = 16;
    }

    if (isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F6F0),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0C0E2B)),
              ),
              const SizedBox(height: 16),
              Text(
                'Loading menu...',
                style: GoogleFonts.urbanist(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (errorMessage != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F6F0),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(
                errorMessage!,
                style: GoogleFonts.urbanist(
                  fontSize: 16,
                  color: Colors.red[700],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadData,
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

    return Scaffold(
      body: MenuBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Back button only (match category_page.dart)
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 12 : 16,
                  vertical: isMobile ? 6 : 8,
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.black),
                    iconSize: isMobile ? 40 : 48,
                    onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                  ),
                  ],
                ),
              ),

              // Category Filter
              SizedBox(
                height: isMobile ? 45 : 50,
                child: ListView.builder(
                  controller: _categoryScrollController,
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final isSelected = category == selectedCategory;
                    return Padding(
                      padding: EdgeInsets.only(right: isMobile ? 8 : 12),
                      child: Transform(
                        transform: Matrix4.identity(),
                        child: isSelected
                            ? Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(25),
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)], // Maroon gradient
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF0C0E2B).withValues(alpha: 0.4),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ElevatedButton(
                                  onPressed: () {
                                    _onCategoryChanged(category);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    foregroundColor: Colors.white,
                                    shadowColor: Colors.transparent,
                                    elevation: 0,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isMobile ? 16 : 20,
                                      vertical: isMobile ? 10 : 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(25),
                                    ),
                                  ).copyWith(
                                    overlayColor: WidgetStateProperty.all(Colors.transparent), // Remove blue splash
                                  ),
                                  child: Text(
                                    category,
                                    style: GoogleFonts.urbanist(
                                      fontWeight: FontWeight.bold,
                                      fontSize: isMobile ? 12 : 14,
                                    ),
                                  ),
                                ),
                              )
                            : ElevatedButton(
                                onPressed: () {
                                  _onCategoryChanged(category);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFF5F6F0), // Cream background
                                  foregroundColor: Colors.black87,
                                  elevation: 1,
                                  shadowColor: Colors.black.withValues(alpha: 0.1),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isMobile ? 16 : 20,
                                    vertical: isMobile ? 10 : 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(25),
                                    side: BorderSide(
                                      color: Colors.grey.shade300,
                                      width: 1,
                                    ),
                                  ),
                                ).copyWith(
                                  overlayColor: WidgetStateProperty.all(Colors.transparent), // Remove blue splash
                                ),
                                child: Text(
                                  category,
                                  style: GoogleFonts.urbanist(
                                    fontWeight: FontWeight.w500,
                                    fontSize: isMobile ? 12 : 14,
                                  ),
                                ),
                              ),
                      ),
                    );
                  },
                ),
              ),

              SizedBox(height: isMobile ? 6 : 8),

              // STEP 4 — PAGEVIEW (CORE FIX 🔥)
              Expanded(
                child: _categoriesLoaded
                    ? RepaintBoundary(
                        child: PageView.builder(
                          // Don't use key based on selectedCategory - it causes rebuilds that break swipe
                          // Each page will filter correctly based on its own categoryId
                          controller: _pageController,
                          physics: const ClampingScrollPhysics(), // ANDROID FEEL
                          itemCount: categories.length,
                          onPageChanged: _onPageChanged,
                          itemBuilder: (context, index) {
                    final category = categories[index];
                    // Each page should ALWAYS use its OWN categoryId from the mapping
                    // This ensures correct filtering when clicking filter buttons or swiping
                    final categoryIdForPage = category != 'All' ? categoryNameToId[category] : null;
                    
                    // Debug: Print category info for troubleshooting
                    debugPrint('📄 Building page $index: category="$category", categoryId=$categoryIdForPage');
                    
                    return _CategoryMenuPage(
                      key: ValueKey('$category-${categoryIdForPage ?? 'all'}'),
                      category: category,
                      categoryId: categoryIdForPage, // Always use mapping, not widget.initialCategoryId
                      allItems: menuItems,
                      displayLimit: _displayLimit,
                      isMobile: isMobile,
                      isTablet: isTablet,
                      isLargeTablet: isLargeTablet,
                      crossAxisCount: crossAxisCount,
                      childAspectRatio: childAspectRatio,
                      spacing: spacing,
                      bottomBarHeight: 0, // No padding - items will scroll into bar area
                      onLoadMore: () {
                        setState(() {
                          _displayLimit += 9;
                        });
                      },
                      onItemTap: (item) async {
                        // Get all filtered items for the current category
                                  // Need to filter items based on current category
                        List<MenuItem> allFilteredItems;
                        if (category == 'All') {
                          allFilteredItems = menuItems.take(_displayLimit).toList();
                        } else {
                          if (categoryIdForPage != null) {
                            allFilteredItems = menuItems.where((menuItem) {
                              if (menuItem.categoryId == null) return false;
                              final itemCatId = menuItem.categoryId is int ? menuItem.categoryId : (menuItem.categoryId as num?)?.toInt();
                              final targetCatId = categoryIdForPage;
                              return itemCatId == targetCatId;
                            }).toList();
                          } else {
                            allFilteredItems = menuItems.where((menuItem) => 
                              menuItem.category == category || 
                              menuItem.categoryName == category ||
                              (menuItem.category.isNotEmpty && menuItem.category.toLowerCase() == category.toLowerCase()) ||
                              (menuItem.categoryName != null && menuItem.categoryName!.toLowerCase() == category.toLowerCase())
                            ).toList();
                          }
                        }
                        // Find the index of the tapped item
                        final itemIndex = allFilteredItems.indexWhere((i) => i.id == item.id);
                        final currentIndex = itemIndex >= 0 ? itemIndex : 0;
                        
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MenuItemDetailPage(
                              items: allFilteredItems,
                              initialIndex: currentIndex,
                              getItemQuantity: getItemQuantity,
                              onIncreaseQuantity: (item) {
                                increaseItemQuantity(item);
                                setState(() {});
                              },
                              onDecreaseQuantity: (item) {
                                decreaseItemQuantity(item);
                                setState(() {});
                              },
                            ),
                          ),
                        );
                        setState(() {});
                      },
                      getItemQuantity: getItemQuantity,
                      buildQuantityControl: _buildQuantityControl,
                      estimateMinutes: _estimateMinutes,
                    );
                  },
                        ),
                      )
                    : const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0C0E2B)),
                        ),
                      ),
              ),
              
              // Bottom Bar (Same structure as filter bar - walang content, para lang sa space)
              SizedBox(
                height: isMobile 
                    ? _bottomBarHeightMobile 
                    : (isLargeTablet 
                        ? _bottomBarHeightLargeTablet 
                        : _bottomBarHeightTablet),
                // Walang content - para lang sa space, items will scroll into this area
                // Adjust height using _bottomBarHeightMobile, _bottomBarHeightTablet, _bottomBarHeightLargeTablet settings above
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Order Tracking FAB
          // Only show if there are orders that are NOT SETTLED table orders
          if (shouldShowTrackingButton)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: AnimatedBuilder(
                animation: _trackingShake,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(_trackingShake.value, 0),
                    child: child,
                  );
                },
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)], // Maroon gradient
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0C0E2B).withValues(alpha: 0.4), // Maroon shadow
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: FloatingActionButton.extended(
                    onPressed: () {
                      final activeOrder = _activeOrder;
                      if (activeOrder == null) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => OrderTrackingPage(
                            order: activeOrder,
                            onOrderUpdated: (updatedOrder) {
                              // Update order in list when items are added
                              setState(() {
                                final index = orders.indexWhere((o) => o.orderId == updatedOrder.orderId);
                                if (index >= 0) {
                                  orders[index] = updatedOrder;
                                }
                                _saveOrders();
                              });
                            },
                          ),
                        ),
                      );
                    },
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    icon: const Icon(
                      Icons.track_changes_outlined,
                      color: Colors.white,
                    ),
                    label: Text(
                      'Track Order',
                      style: GoogleFonts.urbanist(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // Cart FAB
          if (cart.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)], // Maroon gradient
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0C0E2B).withValues(alpha: 0.4), // Maroon shadow
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: FloatingActionButton.extended(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    builder: (modalContext) => StatefulBuilder(
                      builder: (context, setModalState) {
                        return CartBottomSheet(
                          cart: cart.map((c) => menu_models.CartItem(
                            item: menu_models.MenuItem(
                              id: c.item.id,
                              name: c.item.name,
                              description: c.item.description,
                              price: c.item.price,
                              category: c.item.category,
                              icon: c.item.icon,
                              imageUrl: c.item.imageUrl,
                              isAvailable: c.item.isAvailable,
                              categoryName: c.item.categoryName,
                              categoryId: c.item.categoryId,
                            ),
                            quantity: c.quantity,
                          )).toList(),
                          totalPrice: totalPrice,
                          onRemove: (index) {
                            removeFromCart(index);
                            setModalState(() {});
                          },
                          onIncreaseQuantity: (index) {
                            increaseQuantity(index);
                            setModalState(() {});
                          },
                          onDecreaseQuantity: (index) {
                            decreaseQuantity(index);
                            setModalState(() {});
                          },
                          onPlaceOrder: (orderType) {
                            placeOrder(cart, totalPrice, orderType);
                          },
                        );
                      },
                    ),
                  );
                },
                backgroundColor: Colors.transparent,
                elevation: 0,
                icon: Badge(
                  label: Text('${cart.length}'),
                  child: const Icon(
                    Icons.shopping_cart_outlined,
                    color: Colors.white,
                  ),
                ),
                label: Text(
                  '₱${formatPrice(totalPrice)}',
                  style: GoogleFonts.urbanist(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

// STEP 5 — CATEGORY PAGE (ISOLATED & FAST)
class _CategoryMenuPage extends StatelessWidget {
  final String category;
  final int? categoryId; // Pass categoryId directly instead of looking it up
  final List<MenuItem> allItems;
  final int displayLimit;
  final VoidCallback onLoadMore;
  final Function(MenuItem) onItemTap;
  final Function(MenuItem) getItemQuantity;
  final Function({
    required MenuItem item,
    required int quantity,
    required bool isMobile,
    required bool isLargeTablet,
    Key? key,
  }) buildQuantityControl;
  final Function(MenuItem) estimateMinutes;

  final bool isMobile;
  final bool isTablet;
  final bool isLargeTablet;
  final int crossAxisCount;
  final double childAspectRatio;
  final double spacing;
  final double bottomBarHeight; // Height ng bottom bar para sa padding

  const _CategoryMenuPage({
    super.key,
    required this.category,
    required this.categoryId, // Pass categoryId directly
    required this.allItems,
    required this.displayLimit,
    required this.onLoadMore,
    required this.onItemTap,
    required this.getItemQuantity,
    required this.buildQuantityControl,
    required this.estimateMinutes,
    required this.isMobile,
    required this.isTablet,
    required this.isLargeTablet,
    required this.crossAxisCount,
    required this.childAspectRatio,
    required this.spacing,
    required this.bottomBarHeight,
  });

  // Helper method to filter items by category using categoryId when available
  List<MenuItem> _getFilteredItemsForCategory(List<MenuItem> items) {
    if (category == 'All') {
      return items;
    }
    
    // Use categoryId for filtering if available (more reliable than name matching)
    if (categoryId != null) {
      // Filter by categoryId - ensure both are int for proper comparison
      final filtered = items.where((item) {
        if (item.categoryId == null) return false;
        // Ensure both are int for comparison
        final itemCatId = item.categoryId is int ? item.categoryId : (item.categoryId as num?)?.toInt();
        final targetCatId = categoryId is int ? categoryId : (categoryId as num?)?.toInt();
        final matches = itemCatId == targetCatId;
        
        // Debug: Print mismatch for troubleshooting
        if (matches == false && item.category == category) {
          // This item has matching category name but different ID - potential data issue
          debugPrint('⚠️ Category mismatch: Item "${item.name}" has categoryId=$itemCatId but category="$category" expects categoryId=$targetCatId');
        }
        
        return matches;
      }).toList();
      
      // If no items found by ID but we have categoryId, try name matching as fallback
      if (filtered.isEmpty && categoryId != null) {
        debugPrint('⚠️ No items found for categoryId=$categoryId, trying name matching for category="$category"');
        return items.where((item) => 
          item.category == category || 
          item.categoryName == category ||
          (item.category.isNotEmpty && item.category.toLowerCase() == category.toLowerCase()) ||
          (item.categoryName != null && item.categoryName!.toLowerCase() == category.toLowerCase())
        ).toList();
      }
      
      return filtered;
    }
    
    // Fallback to name matching if categoryId is not available
    return items.where((item) => 
      item.category == category || 
      item.categoryName == category ||
      (item.category.isNotEmpty && item.category.toLowerCase() == category.toLowerCase()) ||
      (item.categoryName != null && item.categoryName!.toLowerCase() == category.toLowerCase())
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = category == 'All'
        ? allItems.take(displayLimit).toList()
        : _getFilteredItemsForCategory(allItems);

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: isMobile ? 48 : 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No items found',
              style: GoogleFonts.urbanist(
                fontSize: isMobile ? 16 : 18,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      physics: const ClampingScrollPhysics(),
      cacheExtent: isMobile ? 500 : 800,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.all(spacing), // No extra bottom padding - items will scroll into bar area
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: childAspectRatio,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = items[index];
                return RepaintBoundary(
                  child: MenuItemCard(
                    item: menu_models.MenuItem(
                      id: item.id,
                      name: item.name,
                      description: item.description,
                      price: item.price,
                      category: item.category,
                      icon: item.icon,
                      imageUrl: item.imageUrl,
                      isAvailable: item.isAvailable,
                      categoryName: item.categoryName,
                      categoryId: item.categoryId,
                    ),
                    estimatedMinutes: estimateMinutes(item),
                    quantityControl: RepaintBoundary(
                      child: AnimatedSwitcher(
                        duration: Duration.zero,
                        switchInCurve: Curves.linear,
                        switchOutCurve: Curves.linear,
                        child: buildQuantityControl(
                          item: item,
                          quantity: getItemQuantity(item),
                          isMobile: isMobile,
                          isLargeTablet: isLargeTablet,
                          key: ValueKey(
                            '${item.name}_${getItemQuantity(item)}',
                          ),
                        ),
                      ),
                    ),
                    onTap: () => onItemTap(item),
                  ),
                );
              },
              childCount: items.length,
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
            ),
          ),
        ),
        // Load More Button - only for "All" category
        if (category == 'All' && allItems.length > displayLimit)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(
                left: spacing,
                right: spacing,
                bottom: spacing,
                top: 0,
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)], // Maroon gradient
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0C0E2B).withValues(alpha: 0.3), // Maroon shadow
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: onLoadMore,
                  icon: Icon(
                    Icons.add_circle_outline,
                    color: Colors.white,
                    size: isMobile ? 20 : 24,
                  ),
                  label: Text(
                    'Load More Menu',
                    style: GoogleFonts.urbanist(
                      fontSize: isMobile ? 14 : 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shadowColor: Colors.transparent,
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 24 : 32,
                      vertical: isMobile ? 12 : 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ).copyWith(
                    overlayColor: WidgetStateProperty.all(Colors.transparent), // Remove blue splash
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

