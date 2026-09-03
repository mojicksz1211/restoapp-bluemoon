import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models.dart';
import '../menu_item_detail_page.dart';
import '../home_page.dart';
import '../widgets/category_menu_page.dart';
import '../widgets/category_filter_bar.dart';
import '../widgets/category_sidebar.dart';
import '../widgets/menu_cart_fab.dart';
import '../../shared/login_page.dart';
import '../../shared/globals.dart';
import '../../shared/settings_sheet.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/settlement_dialog_service.dart';
import '../widgets/cart_bottom_sheet.dart';
import '../widgets/cart_side_panel.dart';
import '../widgets/menu_background.dart';
part 'menu_home_orders.dart';
part 'menu_home_socket.dart';
part 'menu_home_ui_helpers.dart';

class MenuHomePage extends StatefulWidget {
  final String? initialCategory;
  final int? initialCategoryId;
  
  const MenuHomePage({super.key, this.initialCategory, this.initialCategoryId});

  @override
  State<MenuHomePage> createState() => _MenuHomePageState();
}

class _MenuHomePageState extends State<MenuHomePage> with TickerProviderStateMixin {
  late String selectedCategory;
  late PageController _pageController;
  final TextEditingController searchController = TextEditingController();
  List<CartItem> cart = [];
  List<Order> orders = [];
  int orderIdCounter = 1;
  
  List<MenuItem> menuItems = []; // Store ALL menu items (not filtered)
  List<String> categories = ['All'];
  Map<String, int> categoryNameToId = {}; // Cache category name to ID mapping
  Map<String, List<MenuItem>> _categoryItemsCache = {}; // Pre-filtered items per category
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
  StreamSubscription<Order>? _settlementDismissSubscription;
  late final AnimationController _cartShakeController;
  late final Animation<double> _cartShake;
  
  int _displayLimit = 9; // Initial limit for "All" filter

  // For flying cart animation
  final GlobalKey _cartFabKey = GlobalKey();
  final GlobalKey _cartIconKey = GlobalKey(); // Key for cart icon in side panel header
  late AnimationController _flyController;
  late Animation<Offset> _flyAnimation;
  late Animation<double> _flyOpacity;
  late Animation<double> _flyScale;
  late Animation<double> _flyRotation;
  Future<void>? _flyInFlight;
  bool _isCartPanelOpen = false;
  bool _isCartSheetOpen = false;
  bool _isSubmittingOrder = false;
  StateSetter? _cartSheetSetState;

  void _setSubmittingOrder(bool value) {
    if (!mounted) return;
    setState(() => _isSubmittingOrder = value);
    _cartSheetSetState?.call(() {});
  }

  void _openOrderTrackingView() {
    if (!mounted) return;
    if (_isWideLayout(context)) {
      setState(() => _isCartPanelOpen = true);
      return;
    }
    if (_isCartSheetOpen) {
      Navigator.of(context).pop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openCartBottomSheet();
      });
      return;
    }
    _openCartBottomSheet();
  }

  Future<void> _openCartBottomSheet() async {
    if (!mounted || _isCartSheetOpen) return;
    setState(() => _isCartSheetOpen = true);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      builder: (modalContext) => StatefulBuilder(
        builder: (context, setModalState) {
          _cartSheetSetState = setModalState;
          return CartBottomSheet(
            cart: cart,
            totalPrice: totalPrice,
            isSubmitting: _isSubmittingOrder,
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
            activeOrder: _activeOrder,
            onOrderUpdated: (updatedOrder) {
              setState(() {
                final index = orders.indexWhere((o) => o.orderId == updatedOrder.orderId);
                if (index >= 0) {
                  orders[index] = updatedOrder;
                }
                _saveOrders();
              });
            },
          );
        },
      ),
    ).whenComplete(() {
      if (mounted) {
        setState(() => _isCartSheetOpen = false);
      }
      _cartSheetSetState = null;
    });
  }

  bool _isWideLayout(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1100;

  void _openCartPanelIfWide() {
    if (!mounted) return;
    if (!_isWideLayout(context)) return;
    if (cart.isEmpty) return;
    if (_isCartPanelOpen) return;
    setState(() => _isCartPanelOpen = true);
  }

  void _closeCartPanel() {
    if (!mounted) return;
    if (!_isCartPanelOpen) return;
    setState(() => _isCartPanelOpen = false);
  }

  void _syncCartPanelState() {
    if (!mounted) return;
    // Don't close panel if cart is empty but there's an active order to track
    if (cart.isEmpty && _isCartPanelOpen && !shouldShowTrackingButton) {
      _isCartPanelOpen = false;
    }
  }

  void _closeLoadingDialog() {
    if (!mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }
  
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
    languageNotifier.addListener(_onLanguageChanged);
    _initializeSocket(); // Initialize socket for real-time updates
    _settlementDismissSubscription =
        SettlementDialogService.instance.dismissed.listen(_handleSettlementDismissed);

    _cartShakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _cartShake = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -6.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -6.0, end: 6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6.0, end: -6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6.0, end: 6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6.0, end: 0.0), weight: 1),
    ]).animate(
      CurvedAnimation(parent: _cartShakeController, curve: Curves.easeInOut),
    );

    _flyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _flyAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _flyController, curve: Curves.easeInOut));
    _flyOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 10),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 90),
    ]).animate(CurvedAnimation(parent: _flyController, curve: Curves.easeOut));
    _flyScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 4.2), weight: 10),
      TweenSequenceItem(tween: ConstantTween(4.2), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 4.2, end: 0.5), weight: 40),
    ]).animate(CurvedAnimation(parent: _flyController, curve: Curves.easeInOutCubic));
    _flyRotation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -0.08), weight: 40),
      TweenSequenceItem(tween: Tween(begin: -0.08, end: 0.12), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 0.12, end: 0.0), weight: 20),
    ]).animate(CurvedAnimation(parent: _flyController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    languageNotifier.removeListener(_onLanguageChanged);
    _categoryScrollController.dispose();
    _pageController.dispose();
    searchController.dispose();
    _cartShakeController.dispose();
    _flyController.dispose();
    _cleanupSocket(); // Clean up socket listeners
    _settlementDismissSubscription?.cancel();
    super.dispose();
  }

  void _onLanguageChanged() {
    if (!mounted) return;
    _loadData();
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
        final newCategories = ['All', ...cats.map((cat) => cat['name'] as String).toList()];
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
        } else if (mounted && _pageController.hasClients && !_pageControllerInitialized) {
          // If controller already has clients, jump to correct page
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _pageController.hasClients) {
              final finalIndex = categories.indexOf(selectedCategory).clamp(0, categories.length - 1);
              if (finalIndex >= 0 && finalIndex < categories.length) {
                _pageController.jumpToPage(finalIndex);
                _pageControllerInitialized = true;
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
        
        
        setState(() {
          menuItems = items;
          _categoryItemsCache = _buildCategoryItemsCache(items);
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

  Map<String, List<MenuItem>> _buildCategoryItemsCache(List<MenuItem> items) {
    final cache = <String, List<MenuItem>>{};
    for (final category in categories) {
      final categoryId = category != 'All' ? categoryNameToId[category] : null;
      cache[category] = _filterItemsForCategory(items, category, categoryId);
    }
    return cache;
  }

  List<MenuItem> _filterItemsForCategory(
    List<MenuItem> items,
    String category,
    int? categoryId,
  ) {
    if (category == 'All') {
      return items;
    }

    if (categoryId != null) {
      final filtered = items.where((item) {
        if (item.categoryId == null) return false;
        final itemCatId =
            item.categoryId is int ? item.categoryId : (item.categoryId as num?)?.toInt();
        final targetCatId = categoryId is int ? categoryId : (categoryId as num?)?.toInt();
        return itemCatId == targetCatId;
      }).toList();

      if (filtered.isNotEmpty) {
        return filtered;
      }
    }

    return items
        .where((item) =>
            item.category == category ||
            item.categoryName == category ||
            (item.category.isNotEmpty &&
                item.category.toLowerCase() == category.toLowerCase()) ||
            (item.categoryName != null &&
                item.categoryName!.toLowerCase() == category.toLowerCase()))
        .toList();
  }

  int _estimateMinutes(MenuItem item) {
    // Stable, lightweight estimate (no extra model fields needed)
    return 5 + (item.name.hashCode.abs() % 21); // 5..25
  }

  // Sidebar search → tapping a specific menu item result. Syncs the
  // selected category (so the sidebar/right pane reflect where the item
  // lives) and opens the item quick-view modal, same as tapping its card
  // in the grid would.
  Future<void> _openItemFromSearch(MenuItem item) async {
    _onCategoryChanged(item.category);
    await showMenuItemDetailModal(
      context,
      item: item,
      getItemQuantity: getItemQuantity,
      onAddWithAnimation: _onAddPressed,
      onDecreaseQuantity: (item) {
        decreaseItemQuantity(item);
        setState(() {});
      },
    );
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

  // Get filtered items with limit applied for all categories when not searching
  List<MenuItem> get filteredItems {
    final allItems = _allFilteredItems;

    if (searchController.text.isEmpty) {
      return allItems.take(_displayLimit).toList();
    }

    return allItems;
  }

  // Check if there are more items to load
  bool get hasMoreItems {
    if (searchController.text.isNotEmpty) {
      return false; // No limit during search
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
    
    // Show button if there's at least one order that is NOT cancelled, NOT a SETTLED table order
    final hasActiveOrder = orders.any((order) => 
      order.backendStatus != -1 && // Not cancelled
      !_isSettledTableOrder(order)
    );
    
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
      (order) => order.backendStatus != -1 && // Not cancelled
                 !_isSettledTableOrder(order),
      orElse: () => orders.firstWhere(
        (order) => order.backendStatus != -1, // At least not cancelled
        orElse: () => orders.isNotEmpty ? orders.last : throw StateError('No orders'),
      ),
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
    _syncCartPanelState();
    _openCartPanelIfWide();
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
    _syncCartPanelState();
  }

  void increaseQuantity(int index) {
    setState(() {
      cart[index].quantity++;
    });
    _syncCartPanelState();
    _openCartPanelIfWide();
  }

  void decreaseQuantity(int index) {
    setState(() {
      if (cart[index].quantity > 1) {
        cart[index].quantity--;
      } else {
        cart.removeAt(index);
      }
    });
    _syncCartPanelState();
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
    _syncCartPanelState();
    _openCartPanelIfWide();
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
    _syncCartPanelState();
  }

  void loadMoreItems() {
    setState(() {
      _displayLimit += 9; // Load 9 more items
    });
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
    final activeOrder = _activeOrder;
    final combinedFabCount =
        cart.length + (activeOrder?.items.length ?? 0);

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
        // Regular tablets sa landscape: 3 columns, tamang taas para makita ang name at price
        crossAxisCount = 3;
        childAspectRatio = 1.05;
        spacing = 16;
      } else if (isLargeTablet) {
        // iPad Pro at mas malalaking tablets sa landscape
        crossAxisCount = 3;
        childAspectRatio = 0.90;
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

    final isWide = _isWideLayout(context);
    final cartPanelWidth = (screenWidth * 0.34).clamp(340.0, 420.0);
    // Tablet/desktop get a persistent left category rail instead of the
    // page-navigation flow (tap category → new page); phones keep the
    // horizontal chip bar since a side rail would eat too much width.
    final showCategorySidebar = !isMobile;
    final categoryCounts = <String, int>{
      for (final category in categories) category: (_categoryItemsCache[category]?.length ?? 0),
    };

    // Builds the item grid for one category. Shared by the PageView (mobile
    // swipe) and the AnimatedSwitcher (sidebar tap) below so both paths stay
    // in sync instead of drifting into two copies of the same logic.
    Widget buildCategoryContent(String category) {
      final categoryIdForPage = category != 'All' ? categoryNameToId[category] : null;
      final itemsForCategory = _categoryItemsCache[category] ??
          _filterItemsForCategory(menuItems, category, categoryIdForPage);

      return CategoryMenuPage(
        key: PageStorageKey('category-$category-${categoryIdForPage ?? 'all'}'),
        itemsForCategory: itemsForCategory,
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
          await showMenuItemDetailModal(
            context,
            item: item,
            getItemQuantity: getItemQuantity,
            onAddWithAnimation: _onAddPressed,
            onDecreaseQuantity: (item) {
              decreaseItemQuantity(item);
              setState(() {});
            },
          );
        },
        getItemQuantity: getItemQuantity,
        buildQuantityControl: _buildQuantityControl,
        estimateMinutes: _estimateMinutes,
      );
    }

    final menuContent = MenuBackground(
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
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (context) => const HomePage()),
                      );
                    },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.settings, size: 40),
                      color: const Color(0xFF0C0E2B),
                      onPressed: () {
                        showAppSettingsSheet(
                          context: context,
                          onLogout: () async {
                            await ApiService.logout();
                            if (context.mounted) {
                              refreshAppAuth();
                            }
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),

              // Category Filter — only on phones; tablet/desktop use the
              // left sidebar instead (see CategorySidebar in the outer Row).
              if (!showCategorySidebar) ...[
                CategoryFilterBar(
                  categories: categories,
                  selectedCategory: selectedCategory,
                  isMobile: isMobile,
                  scrollController: _categoryScrollController,
                  onCategoryTap: _onCategoryChanged,
                ),
                SizedBox(height: isMobile ? 6 : 8),
              ],

              // STEP 4 — CATEGORY CONTENT
              // One shared PageView for both layouts — this (not a from-
              // scratch AnimatedSwitcher) is what actually keeps a category's
              // loaded images intact when you leave and come back to it:
              // CategoryMenuPage's AutomaticKeepAliveClientMixin only works
              // under a Scrollable ancestor that understands KeepAlive
              // notifications, which PageView provides and AnimatedSwitcher
              // does not. AnimatedSwitcher was disposing the outgoing page
              // (and cancelling any images still mid-fetch) on every switch,
              // which is why revisiting a category showed broken/blank
              // images. Sidebar mode disables swipe (tap-only) but keeps the
              // same animateToPage slide from _onCategoryChanged; mobile
              // keeps the swipe gesture.
              Expanded(
                child: !_categoriesLoaded
                    ? const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0C0E2B)),
                        ),
                      )
                    : RepaintBoundary(
                        child: PageView.builder(
                          controller: _pageController,
                          physics: showCategorySidebar
                              ? const NeverScrollableScrollPhysics()
                              : const PageScrollPhysics(),
                          onPageChanged: _onPageChanged,
                          itemCount: categories.length,
                          itemBuilder: (context, index) => buildCategoryContent(categories[index]),
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
      );

    return Scaffold(
      body: Row(
        children: [
          if (showCategorySidebar)
            CategorySidebar(
              categories: categories,
              selectedCategory: selectedCategory,
              itemCounts: categoryCounts,
              onCategoryTap: _onCategoryChanged,
              allMenuItems: menuItems,
              onItemTap: _openItemFromSearch,
              width: isLargeTablet ? 320 : 280,
            ),
          Expanded(child: menuContent),
          if (isWide)
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              width: (_isCartPanelOpen && (cart.isNotEmpty || shouldShowTrackingButton)) ? cartPanelWidth : 0,
              child: (_isCartPanelOpen && (cart.isNotEmpty || shouldShowTrackingButton))
                  ? Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F6F0),
                        border: Border(
                          left: BorderSide(color: Colors.grey.shade300),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 18,
                            offset: const Offset(-6, 0),
                          ),
                        ],
                      ),
                      child: CartSidePanel(
                        cart: cart,
                        totalPrice: totalPrice,
                        cartIconKey: _cartIconKey,
                        cartShakeAnimation: _cartShake,
                        isSubmitting: _isSubmittingOrder,
                        onIncreaseQuantity: increaseQuantity,
                        onDecreaseQuantity: decreaseQuantity,
                        onPlaceOrder: (orderType) {
                          // Don't close panel - it will change to order tracking content
                          placeOrder(cart, totalPrice, orderType);
                        },
                        onClose: _closeCartPanel,
                        activeOrder: _activeOrder,
                        onOrderUpdated: (updatedOrder) {
                          setState(() {
                            final index = orders.indexWhere((o) => o.orderId == updatedOrder.orderId);
                            if (index >= 0) {
                              orders[index] = updatedOrder;
                            }
                            _saveOrders();
                          });
                        },
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
        ],
      ),
      floatingActionButton: MenuCartFab(
        isWide: isWide,
        isCartPanelOpen: _isCartPanelOpen,
        isCartSheetOpen: _isCartSheetOpen,
        shouldShowTrackingButton: shouldShowTrackingButton,
        hasCartItems: cart.isNotEmpty,
        combinedFabCount: combinedFabCount,
        totalPrice: totalPrice,
        cartFabKey: _cartFabKey,
        onTogglePanel: () => setState(() => _isCartPanelOpen = !_isCartPanelOpen),
        onOpenSheet: _openCartBottomSheet,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

