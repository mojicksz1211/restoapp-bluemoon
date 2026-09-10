import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models.dart';
import '../waiter_models.dart';
import '../services/api_service.dart';
import '../services/waiter_cart_store.dart';
import '../../shared/globals.dart';
import '../../shared/settings_sheet.dart';
import '../../menuApp/widgets/menu_background.dart';
import '../widgets/confirm_order_bottom_sheet.dart';
import '../widgets/get_order_menu_card.dart';
import '../widgets/get_order_sidebar.dart';
import '../widgets/get_order_cart_panel.dart';
import '../widgets/center_popup.dart';
import '../widgets/item_note_modal.dart';
import '../widgets/quick_add_drinks_carousel.dart';
import '../widgets/fire_glow_background.dart';

class GetOrderPage extends StatefulWidget {
  final WaiterTable table;
  final List<MenuItem> menuItems;
  final WaiterOrder? existingOrder;

  const GetOrderPage({
    super.key,
    required this.table,
    required this.menuItems,
    this.existingOrder,
  });

  @override
  State<GetOrderPage> createState() => _GetOrderPageState();
}

class _GetOrderPageState extends State<GetOrderPage> with TickerProviderStateMixin {
  static const String topRevenueCategory = '🔥 Top Revenue';
  static const String sizzlingCategory = '🍳 Sizzling & Pulutan';
  static const String chickenCategory = '🍗 Chicken & Wings';
  static const String beerDrinkCategory = '🍺 Beers & Drinks';
  static const String pizzaRiceCategory = '🍕 Pizza & Rice Meals';
  static const String dessertsCategory = '🍹 Shakes & Desserts';

  late List<String> _categories;
  String _selectedCategory = 'All';
  String _selectedSubCategory = 'All';
  final List<CartItem> _cart = [];
  // Key into WaiterCartStore for this table / additional-order session, so the
  // cart survives leaving and re-entering the Get Order screen.
  late final String _cartKey;
  String? _selectedOrderType;
  int _displayLimit = 18; // Initial limit for "All" filter
  bool _isCartPanelOpen = false;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Horizontal scroll position of the mobile category strip, so tapping the
  // pinned "All" chip snaps the strip back to the start (Sizzling & Pulutan).
  final ScrollController _categoryStripController = ScrollController();

  List<MenuItem> _topRevenueItems = [];
  bool _isLoadingTopRevenue = false;

  // Flying cart animation
  final GlobalKey _cartFabKey = GlobalKey();
  final GlobalKey _cartIconKey = GlobalKey();
  late AnimationController _flyController;
  late Animation<Offset> _flyAnimation;
  late Animation<double> _flyOpacity;
  late Animation<double> _flyScale;
  Future<void>? _flyInFlight;

  @override
  void initState() {
    super.initState();
    _cartKey = WaiterCartStore.keyFor(
      tableId: widget.table.id,
      existingOrderId: widget.existingOrder?.id,
    );
    // Restore any cart the waiter built earlier for this table but hasn't
    // placed yet (e.g. they tapped Home to check another table and came back,
    // or the app was closed and reopened).
    _cart.addAll(WaiterCartStore.instance.load(_cartKey));
    // Cold start straight into a table (before Home's restore() finished) —
    // pull the on-disk carts in and fill this one if it was still empty.
    if (_cart.isEmpty) {
      WaiterCartStore.instance.restore().then((_) {
        if (!mounted || _cart.isNotEmpty) return;
        final restored = WaiterCartStore.instance.load(_cartKey);
        if (restored.isNotEmpty) {
          setState(() => _cart.addAll(restored));
        }
      });
    }
    final cachedRaw = ApiService.cachedTopRevenueRaw;
    if (cachedRaw != null && cachedRaw.isNotEmpty) {
      _topRevenueItems = _resolveTopRevenueItems(cachedRaw);
    }
    _categories = _buildCategories();
    _selectedOrderType = 'DINE_IN';

    _flyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _flyAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _flyController, curve: Curves.easeInOut));
    _flyOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _flyController, curve: Curves.easeIn),
    );
    _flyScale = Tween<double>(begin: 1.0, end: 0.2).animate(
      CurvedAnimation(parent: _flyController, curve: Curves.easeIn),
    );

    _loadTopRevenueItems();
  }

  List<MenuItem> _resolveTopRevenueItems(List<dynamic> rawList) {
    final items = <MenuItem>[];
    for (final itemJson in rawList) {
      if (itemJson is! Map) continue;
      final id = itemJson['id'];
      final name = itemJson['name']?.toString() ?? '';
      final match = widget.menuItems.cast<MenuItem?>().firstWhere(
        (m) => (id != null && m?.id == id) || (m?.name.toLowerCase() == name.toLowerCase()),
        orElse: () => null,
      );
      if (match != null) {
        items.add(match);
      } else {
        try {
          items.add(MenuItem.fromApi(Map<String, dynamic>.from(itemJson)));
        } catch (_) {}
      }
    }
    return items;
  }

  Future<void> _loadTopRevenueItems() async {
    try {
      if (_topRevenueItems.isEmpty) {
        setState(() => _isLoadingTopRevenue = true);
      }
      final res = await ApiService.getTopRevenueItems(limit: 120);
      if (res['success'] == true && res['data'] is List) {
        final rawList = res['data'] as List;
        final items = _resolveTopRevenueItems(rawList);
        if (mounted && items.isNotEmpty) {
          setState(() {
            _topRevenueItems = items;
            _categories = _buildCategories();
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading top revenue items: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingTopRevenue = false);
      }
    }
  }

  void _selectCategory(String category) {
    setState(() {
      _selectedCategory = category;
      _selectedSubCategory = 'All';
      _displayLimit = 18;
      // If user taps a category while searching, clear search query so they see the category items
      if (_searchQuery.isNotEmpty) {
        _searchQuery = '';
        _searchController.clear();
      }
    });
  }

  @override
  void dispose() {
    // Safety net — the mutation helpers already persist on every change, but
    // this covers anything that slipped through before the page went away.
    _persistCart();
    _flyController.dispose();
    _searchController.dispose();
    _categoryStripController.dispose();
    super.dispose();
  }

  /// Mirrors the current cart into WaiterCartStore so it survives navigation
  /// away from this screen (and shows up on the Tables dashboard card).
  void _persistCart() {
    WaiterCartStore.instance.save(_cartKey, _cart);
  }

  static const Map<int, int> _dbSalesQty = {
    212: 152, 213: 232, 214: 186, 215: 39, 216: 44, 217: 38, 218: 154, 219: 96,
    220: 238, 221: 77, 222: 422, 223: 31, 224: 109, 225: 75, 226: 68, 227: 1,
    228: 14, 229: 2, 230: 1, 231: 2, 232: 1, 233: 4, 241: 4, 242: 1, 246: 1,
    249: 7, 251: 2, 255: 19, 256: 2, 257: 3, 258: 7, 260: 1, 261: 18, 262: 3,
    263: 2, 265: 7, 266: 8, 267: 21, 271: 1, 272: 2, 278: 4, 279: 42, 280: 3,
    281: 5, 282: 20, 283: 252, 284: 38, 285: 54, 286: 131, 287: 20, 288: 86,
    289: 6, 290: 29, 291: 43, 292: 11, 296: 11, 298: 14, 299: 44, 300: 48,
    301: 29, 302: 6, 303: 123, 304: 55, 305: 68, 306: 68, 307: 16, 308: 1127,
    309: 36, 310: 93, 311: 25, 313: 18, 314: 11, 315: 87, 316: 212, 317: 242,
    318: 73, 319: 23, 320: 89, 321: 74, 322: 24, 323: 32, 324: 16, 325: 1967,
    326: 668, 327: 388, 328: 156, 329: 1375, 331: 33, 332: 67, 333: 6, 334: 495,
    335: 70, 336: 87, 337: 111, 338: 44, 339: 19, 340: 24, 341: 113, 342: 57,
    343: 20, 344: 40, 345: 75, 346: 49, 347: 112, 348: 59, 349: 3639, 350: 909,
    351: 3019, 352: 4430, 353: 1788, 354: 147, 355: 86, 356: 36, 357: 2, 358: 9606,
    359: 562, 360: 226, 361: 493, 363: 25, 364: 85, 365: 21, 366: 4, 367: 1453,
    368: 319, 369: 475, 370: 217, 371: 246, 372: 389, 373: 221, 374: 203, 375: 828,
    376: 69, 377: 76, 378: 140, 379: 519, 380: 63, 381: 352, 382: 42, 383: 47,
    384: 153, 385: 72, 386: 111, 387: 29, 388: 112, 389: 52, 390: 74, 391: 291,
    392: 385, 393: 418, 394: 64, 395: 57, 396: 4, 397: 99, 398: 122, 399: 13,
    401: 63, 402: 127, 403: 18, 404: 101, 405: 163, 406: 60, 407: 342, 408: 141,
    409: 42, 410: 122, 411: 17, 412: 286, 413: 161, 414: 98, 415: 96, 416: 97,
    417: 379, 418: 164, 419: 533, 420: 181, 421: 134, 422: 159, 423: 29, 424: 69,
    425: 661, 426: 825, 427: 630, 428: 213, 429: 458, 430: 419, 431: 48, 432: 16,
    433: 28, 434: 49, 435: 32, 436: 29, 437: 150, 438: 176, 439: 23, 440: 62,
    441: 46, 442: 21, 443: 131, 444: 1011, 445: 32, 446: 34, 447: 38, 448: 18,
    449: 11, 450: 19, 451: 1, 453: 127, 454: 382, 455: 18, 456: 2, 457: 17,
    458: 13, 459: 45, 460: 35, 461: 27, 462: 24, 463: 30, 464: 30, 465: 28,
    466: 37, 467: 43, 468: 30, 469: 28, 470: 5, 471: 16, 472: 9, 473: 311,
    475: 1, 476: 1, 477: 1, 478: 1, 479: 1, 480: 2, 481: 1, 482: 1, 484: 1,
    485: 1, 486: 1, 488: 2, 491: 186, 492: 233, 493: 116, 494: 173, 505: 23,
    538: 26, 874: 682, 1252: 24, 1253: 43, 1254: 28, 1255: 27, 1486: 7, 1487: 10,
  };

  int _getItemSalesQty(MenuItem item) {
    if (item.salesQty > 0) return item.salesQty;
    if (item.id != null && _dbSalesQty.containsKey(item.id!)) {
      return _dbSalesQty[item.id!]!;
    }
    return 0;
  }

  int _compareBySales(MenuItem a, MenuItem b) {
    final qtyA = _getItemSalesQty(a);
    final qtyB = _getItemSalesQty(b);
    final cmp = qtyB.compareTo(qtyA);
    if (cmp != 0) return cmp;
    final revCmp = b.totalRevenue.compareTo(a.totalRevenue);
    if (revCmp != 0) return revCmp;
    return (a.id ?? 0).compareTo(b.id ?? 0);
  }

  List<MenuItem> _getSizzlingPulutanItems() {
    final list = widget.menuItems.where((item) {
      final name = item.name.toLowerCase();
      final cat = (item.categoryName ?? item.category).toLowerCase();
      return name.contains('sisig') ||
          name.contains('sweet sour pork') ||
          name.contains('sweet and sour') ||
          name.contains('crispy pata') ||
          name.contains('calamari') ||
          name.contains('squid') ||
          name.contains('nacho') ||
          name.contains('fries') ||
          name.contains('chips') ||
          name.contains('dynamite') ||
          name.contains('takoyaki') ||
          name.contains('sinigang') ||
          name.contains('pancit') ||
          name.contains('eggroll') ||
          name.contains('gizzard') ||
          name.contains('corn cheese') ||
          name.contains('spam') ||
          cat == 'filipino food' ||
          cat == 'fries' ||
          cat == 'platter';
    }).toList();

    list.sort((a, b) {
      final nA = a.name.toLowerCase();
      final nB = b.name.toLowerCase();
      // Keep Sizzling Sisig and Sweet Sour Pork at the top pair as requested
      if (nA.contains('sisig') && !nB.contains('sisig')) return -1;
      if (nB.contains('sisig') && !nA.contains('sisig')) return 1;
      if ((nA.contains('sweet sour pork') || nA.contains('sweet and sour')) &&
          !(nB.contains('sweet sour pork') || nB.contains('sweet and sour'))) return -1;
      if ((nB.contains('sweet sour pork') || nB.contains('sweet and sour')) &&
          !(nA.contains('sweet sour pork') || nA.contains('sweet and sour'))) return 1;
      return _compareBySales(a, b);
    });
    return list;
  }

  List<MenuItem> _getChickenItems() {
    final list = widget.menuItems.where((item) {
      final name = item.name.toLowerCase();
      final cat = (item.categoryName ?? item.category).toLowerCase();
      return cat == 'chicken' ||
          name.contains('chicken') ||
          name.contains('wing') ||
          name.contains('gangjung') ||
          name.contains('korean spicy barbecue');
    }).toList();

    list.sort(_compareBySales);
    return list;
  }

  List<MenuItem> _getBeerDrinkItems() {
    final list = widget.menuItems.where((item) {
      final name = item.name.toLowerCase();
      final cat = (item.categoryName ?? item.category).toLowerCase();
      return cat == 'local beer' ||
          cat == 'imported beer' ||
          cat == 'soju' ||
          cat == 'cocktail soju' ||
          cat == 'soda in can' ||
          name.contains('beer') ||
          name.contains('soju') ||
          name.contains('san mig') ||
          name.contains('red horse') ||
          name.contains('chamisul') ||
          name.contains('chumchurum') ||
          name.contains('coke') ||
          name.contains('sprite') ||
          name.contains('royal') ||
          name.contains('water');
    }).toList();

    list.sort(_compareBySales);
    return list;
  }

  List<MenuItem> _getPizzaRiceItems() {
    final list = widget.menuItems.where((item) {
      final name = item.name.toLowerCase();
      final cat = (item.categoryName ?? item.category).toLowerCase();
      return cat == 'rice' ||
          cat == 'pizza' ||
          cat == 'pasta' ||
          cat == 'noodle and soup' ||
          name.contains('rice') ||
          name.contains('pizza') ||
          name.contains('ramyun') ||
          name.contains('pasta') ||
          name.contains('soup') ||
          name.contains('stew');
    }).toList();

    list.sort(_compareBySales);
    return list;
  }

  List<MenuItem> _getDessertItems() {
    final list = widget.menuItems.where((item) {
      final name = item.name.toLowerCase();
      final cat = (item.categoryName ?? item.category).toLowerCase();
      return cat == 'fruit shakes' ||
          cat == 'dessert' ||
          cat == 'frappe' ||
          cat == 'ade' ||
          name.contains('shake') ||
          name.contains('bingsu') ||
          name.contains('sherbet') ||
          name.contains('fruit') ||
          name.contains('punch');
    }).toList();

    list.sort(_compareBySales);
    return list;
  }

  List<MenuItem> _getTopSuggestedDrinks() {
    final drinks = widget.menuItems.where((item) {
      final name = item.name.toLowerCase();
      final cat = (item.categoryName ?? item.category).toLowerCase();
      return cat == 'local beer' ||
          cat == 'soju' ||
          cat == 'soda in can' ||
          cat == 'fruit shakes' ||
          cat == 'imported beer' ||
          cat == 'ade' ||
          cat == 'cocktail soju' ||
          name.contains('beer') ||
          name.contains('soju') ||
          name.contains('chamisul') ||
          name.contains('coke') ||
          name.contains('water') ||
          name.contains('shake') ||
          name.contains('sprite') ||
          name.contains('san mig') ||
          name.contains('red horse') ||
          name.contains('royal');
    }).toList();
    drinks.sort(_compareBySales);
    return drinks.take(15).toList();
  }

  /// Ranked top-revenue list. The API/cache order is authoritative for the
  /// items it returned; anything short of [max] is padded from the full menu
  /// sorted by sales, so the section and its "View All" view always fill up
  /// even when the endpoint returns a short list or is offline.
  List<MenuItem> _rankedTopRevenue({required int max}) {
    final seen = <String>{};
    final result = <MenuItem>[];
    void add(MenuItem m) {
      if (result.length >= max) return;
      final key = m.id?.toString() ?? m.name.toLowerCase();
      if (seen.add(key)) result.add(m);
    }

    for (final m in _topRevenueItems) {
      add(m);
    }
    if (result.length < max) {
      final rest = List<MenuItem>.from(widget.menuItems)..sort(_compareBySales);
      for (final m in rest) {
        add(m);
      }
    }
    return result;
  }

  List<MenuItem> _getItemsForCategory(String category) {
    if (category == 'All') {
      final all = List<MenuItem>.from(widget.menuItems);
      all.sort(_compareBySales);
      return all;
    }
    if (category == topRevenueCategory) return _rankedTopRevenue(max: 100);
    if (category == sizzlingCategory) return _getSizzlingPulutanItems();
    if (category == chickenCategory) return _getChickenItems();
    if (category == beerDrinkCategory) return _getBeerDrinkItems();
    if (category == pizzaRiceCategory) return _getPizzaRiceItems();
    if (category == dessertsCategory) return _getDessertItems();
    final list = widget.menuItems.where((item) {
      final c = item.categoryName ?? item.category;
      return c == category;
    }).toList();
    list.sort(_compareBySales);
    return list;
  }

  List<String> _buildCategories() {
    // The Get Order filter bar mirrors the curated groups shown in the
    // "All Menu Items" section (Sizzling & Pulutan, Chicken & Wings, …)
    // instead of every raw DB category, so the two rows stay consistent.
    // Only groups that actually have matching items are shown.
    return [
      'All',
      if (_getSizzlingPulutanItems().isNotEmpty) sizzlingCategory,
      if (_getChickenItems().isNotEmpty) chickenCategory,
      if (_getBeerDrinkItems().isNotEmpty) beerDrinkCategory,
      if (_getPizzaRiceItems().isNotEmpty) pizzaRiceCategory,
      if (_getDessertItems().isNotEmpty) dessertsCategory,
    ];
  }

  // Get all filtered items without limit
  List<MenuItem> get _allFilteredItems {
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      return widget.menuItems.where((item) {
        final nameMatch = item.name.toLowerCase().contains(q);
        final descMatch = item.description.toLowerCase().contains(q);
        final catMatch = (item.categoryName ?? item.category).toLowerCase().contains(q);
        return nameMatch || descMatch || catMatch;
      }).toList();
    }
    if (_selectedCategory == 'All') {
      if (_selectedSubCategory != 'All') {
        return _getItemsForCategory(_selectedSubCategory);
      }
      return widget.menuItems;
    }
    return _getItemsForCategory(_selectedCategory);
  }

  // Get filtered items with limit applied for "All" filter
  List<MenuItem> get _filteredItems {
    if (_searchQuery.trim().isNotEmpty) {
      return _allFilteredItems;
    }
    final allItems = _allFilteredItems;
    
    // Apply limit only for "All" filter when no subcategory is selected
    if (_selectedCategory == 'All' && _selectedSubCategory == 'All') {
      return allItems.take(_displayLimit).toList();
    }
    
    return allItems;
  }

  // Check if there are more items to load
  bool get _hasMoreItems {
    if (_searchQuery.trim().isNotEmpty) return false;
    if (_selectedCategory != 'All') return false;
    if (_selectedSubCategory != 'All') return false;
    return _allFilteredItems.length > _displayLimit;
  }

  void _loadMoreItems() {
    setState(() {
      _displayLimit += 18; // Load 18 more items
    });
  }

  double get _totalPrice {
    return _cart.fold(0.0, (sum, cartItem) => sum + (cartItem.item.price * cartItem.quantity));
  }

  int get _totalItems {
    return _cart.fold(0, (sum, cartItem) => sum + cartItem.quantity);
  }

  int _getItemQuantity(MenuItem item) {
    final existingIndex = _cart.indexWhere((cartItem) => cartItem.item.name == item.name);
    if (existingIndex >= 0) {
      return _cart[existingIndex].quantity;
    }
    return 0;
  }

  void _increaseItemQuantity(MenuItem item) {
    setState(() {
      final existingIndex = _cart.indexWhere((cartItem) => cartItem.item.name == item.name);
      if (existingIndex >= 0) {
        _cart[existingIndex].quantity++;
      } else {
        _cart.add(CartItem(item: item, quantity: 1));
      }
    });
    _persistCart();
  }

  void _decreaseItemQuantity(MenuItem item) {
    setState(() {
      final existingIndex = _cart.indexWhere((cartItem) => cartItem.item.name == item.name);
      if (existingIndex >= 0) {
        if (_cart[existingIndex].quantity > 1) {
          _cart[existingIndex].quantity--;
        } else {
          _cart.removeAt(existingIndex);
        }
      }
    });
    _persistCart();
  }

  void _removeItemAt(int index) {
    setState(() {
      _cart.removeAt(index);
    });
    _persistCart();
  }

  Future<void> _showFlyAnimation(BuildContext context, MenuItem item) {
    if (_flyInFlight != null) {
      return _flyInFlight!;
    }

    final completer = Completer<void>();
    _flyInFlight = completer.future;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _flyInFlight = null;
        completer.complete();
        return;
      }

      // FAB is hidden while the side panel is open (see build()'s
      // showCartPanel check) — fly to the panel's own cart icon instead,
      // same as menuApp's isWide/_isCartPanelOpen target switch.
      final isMobile = MediaQuery.of(context).size.shortestSide < 600;
      final targetKey = (!isMobile && _isCartPanelOpen) ? _cartIconKey : _cartFabKey;
      final cartContext = targetKey.currentContext ?? _cartFabKey.currentContext;
      if (cartContext == null) {
        _flyInFlight = null;
        completer.complete();
        return;
      }

      final startBox = context.findRenderObject() as RenderBox?;
      if (startBox == null) {
        _flyInFlight = null;
        completer.complete();
        return;
      }
      final startPosition = startBox.localToGlobal(Offset.zero);

      final endBox = cartContext.findRenderObject() as RenderBox?;
      if (endBox == null) {
        _flyInFlight = null;
        completer.complete();
        return;
      }
      final endPosition = endBox.localToGlobal(Offset.zero);

      _flyAnimation = Tween<Offset>(
        begin: startPosition,
        end: endPosition,
      ).animate(CurvedAnimation(parent: _flyController, curve: Curves.easeInOut));

      final overlay = Overlay.of(context);
      final overlayEntry = OverlayEntry(
        builder: (context) => AnimatedBuilder(
          animation: _flyController,
          builder: (context, child) {
            final t = Curves.easeInOutCubic.transform(_flyController.value);
            final dx = startPosition.dx + (endPosition.dx - startPosition.dx) * t;
            final dy = startPosition.dy + (endPosition.dy - startPosition.dy) * t;
            final arcHeight = 90.0;
            final arcOffset = math.sin(t * math.pi) * arcHeight;
            final position = Offset(dx, dy - arcOffset);

            return Positioned(
              left: position.dx,
              top: position.dy,
              child: Opacity(
                opacity: _flyOpacity.value,
                child: Transform.scale(
                  scale: _flyScale.value,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                          ? Image.network(
                              item.imageUrl!,
                              fit: BoxFit.cover,
                              width: 80,
                              height: 80,
                              errorBuilder: (context, error, stackTrace) => Container(
                                color: Colors.red,
                                child: const Icon(
                                  Icons.restaurant_menu,
                                  color: Colors.white,
                                  size: 30,
                                ),
                              ),
                            )
                          : Container(
                              color: Colors.red,
                              child: const Icon(
                                Icons.restaurant_menu,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );

      overlay.insert(overlayEntry);
      _flyController
          .forward(from: 0)
          .then((_) {
            overlayEntry.remove();
            _flyController.reset();
          })
          .whenComplete(() {
            _flyInFlight = null;
            if (!completer.isCompleted) {
              completer.complete();
            }
          });
    });

    return completer.future;
  }

  void _onAddPressed(BuildContext context, MenuItem item) {
    _increaseItemQuantity(item);
    _showFlyAnimation(context, item);
    _openCartPanelIfWide(context);
  }

  void _openCartPanelIfWide(BuildContext context) {
    if (_isCartPanelOpen) return;
    if (MediaQuery.of(context).size.width < 1100) return;
    setState(() => _isCartPanelOpen = true);
  }

  Widget _buildAddButton({
    required MenuItem item,
    required bool isMobile,
    Key? key,
  }) {
    return Builder(
      builder: (buttonContext) => Container(
        key: key ?? ValueKey('${item.name}_add'),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0C0E2B).withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: IconButton(
          icon: Icon(Icons.add, size: isMobile ? 24 : 28, color: Colors.white),
          onPressed: () => _onAddPressed(buttonContext, item),
          padding: EdgeInsets.all(isMobile ? 8 : 10),
          constraints: BoxConstraints(
            minWidth: isMobile ? 42 : 48,
            minHeight: isMobile ? 42 : 48,
          ),
          style: IconButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            alignment: Alignment.center,
          ),
        ),
      ),
    );
  }

  /// Compact "-  qty  +" pill for the grid card's quantityControl slot —
  /// same shape as menuApp's grid quantity control (a single horizontal
  /// row that swaps to just "+" at zero), unlike the vertical/stacked
  /// _buildQuantityControl above which was built for a different layout.
  Widget _buildGridQuantityControl({
    required MenuItem item,
    required bool isMobile,
  }) {
    final quantity = _getItemQuantity(item);
    if (quantity == 0) {
      return _buildAddButton(item: item, isMobile: isMobile);
    }
    return Builder(
      builder: (buttonContext) => Container(
        key: ValueKey('${item.name}_$quantity'),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0C0E2B).withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.remove, size: isMobile ? 20 : 24, color: Colors.white),
              onPressed: () => _decreaseItemQuantity(item),
              padding: EdgeInsets.all(isMobile ? 6 : 8),
              constraints: BoxConstraints(minWidth: isMobile ? 32 : 36, minHeight: isMobile ? 38 : 44),
              style: IconButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                alignment: Alignment.center,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '$quantity',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: isMobile ? 15 : 17,
                  color: Colors.white,
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.add, size: isMobile ? 20 : 24, color: Colors.white),
              onPressed: () => _onAddPressed(buttonContext, item),
              padding: EdgeInsets.all(isMobile ? 6 : 8),
              constraints: BoxConstraints(minWidth: isMobile ? 32 : 36, minHeight: isMobile ? 38 : 44),
              style: IconButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                alignment: Alignment.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Top Revenue section preview — "pill" cards (no image): big item name +
  // price on the left, add / qty control on the right. Up to 16 items laid
  // out as two rows of eight that scroll sideways together.
  Widget _buildTopRevenueScroller(List<MenuItem> items) {
    const pillWidth = 220.0;
    const perRow = 8;
    final firstRow = items.take(perRow).toList();
    final secondRow = items.skip(perRow).take(perRow).toList();

    Widget row(List<MenuItem> r) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < r.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                SizedBox(width: pillWidth, child: _buildTopRevenuePill(r[i])),
              ],
            ],
          ),
        );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row(firstRow),
          if (secondRow.isNotEmpty) ...[
            const SizedBox(height: 10),
            row(secondRow),
          ],
        ],
      ),
    );
  }

  Widget _buildTopRevenuePill(MenuItem item) {
    final quantity = _getItemQuantity(item);
    final active = quantity > 0;
    return Builder(
      builder: (btnCtx) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active
                ? const Color(0xFF0C0E2B)
                : const Color(0xFFE8C468).withValues(alpha: 0.55),
            width: active ? 1.8 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.urbanist(
                      fontSize: 15,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0C0E2B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '₱${formatPrice(item.price)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.urbanist(
                      fontSize: 13.5,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFFB88A1E),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (active)
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)],
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _pillIconButton(Icons.remove, () => _decreaseItemQuantity(item), size: 20, padding: 7),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Text(
                        '$quantity',
                        style: GoogleFonts.urbanist(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    _pillIconButton(Icons.add, () => _onAddPressed(btnCtx, item), size: 20, padding: 7),
                  ],
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)],
                  ),
                ),
                child: _pillIconButton(
                  Icons.add,
                  () => _onAddPressed(btnCtx, item),
                  size: 24,
                  padding: 9,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pillIconButton(IconData icon, VoidCallback onTap, {double size = 20, double padding = 6}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Icon(icon, size: size, color: Colors.white),
      ),
    );
  }

  Widget _buildQuantityControl({
    required MenuItem item,
    required int quantity,
    required bool isMobile,
    required bool isPortrait,
    Key? key,
  }) {
    return Builder(
      builder: (context) => quantity == 0
          ? Container(
              key: key ?? ValueKey('${item.name}_0'),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0C0E2B).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: IconButton(
                icon: Icon(Icons.add, size: isMobile ? 20 : 22, color: Colors.white),
                onPressed: () => _onAddPressed(context, item),
                padding: EdgeInsets.all(isMobile ? 4 : 6),
                constraints: BoxConstraints(
                  minWidth: isMobile ? 32 : 36,
                  minHeight: isMobile ? 32 : 36,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  alignment: Alignment.center,
                ),
              ),
            )
          : Container(
              key: key ?? ValueKey('${item.name}_$quantity'),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0C0E2B).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: isPortrait
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.add,
                            size: isMobile ? 20 : 22,
                            color: Colors.white,
                          ),
                          onPressed: () => _onAddPressed(context, item),
                          padding: EdgeInsets.all(isMobile ? 4 : 6),
                          constraints: BoxConstraints(
                            minWidth: isMobile ? 32 : 36,
                            minHeight: isMobile ? 32 : 36,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            alignment: Alignment.center,
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: isMobile ? 4 : 6),
                          child: Text(
                            '$quantity',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: isMobile ? 14 : 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.remove,
                            size: isMobile ? 20 : 22,
                            color: Colors.white,
                          ),
                          onPressed: () => _decreaseItemQuantity(item),
                          padding: EdgeInsets.all(isMobile ? 4 : 6),
                          constraints: BoxConstraints(
                            minWidth: isMobile ? 32 : 36,
                            minHeight: isMobile ? 32 : 36,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            alignment: Alignment.center,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.remove,
                            size: isMobile ? 20 : 22,
                            color: Colors.white,
                          ),
                          onPressed: () => _decreaseItemQuantity(item),
                          padding: EdgeInsets.all(isMobile ? 4 : 6),
                          constraints: BoxConstraints(
                            minWidth: isMobile ? 32 : 36,
                            minHeight: isMobile ? 32 : 36,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            alignment: Alignment.center,
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: isMobile ? 6 : 8),
                          child: Text(
                            '$quantity',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: isMobile ? 14 : 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.add,
                            size: isMobile ? 20 : 22,
                            color: Colors.white,
                          ),
                          onPressed: () => _onAddPressed(context, item),
                          padding: EdgeInsets.all(isMobile ? 4 : 6),
                          constraints: BoxConstraints(
                            minWidth: isMobile ? 32 : 36,
                            minHeight: isMobile ? 32 : 36,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            alignment: Alignment.center,
                          ),
                        ),
                      ],
                    ),
            ),
    );
  }

  void _showCartSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final mq = MediaQuery.of(context);
          final screenWidth = mq.size.width;
          final screenHeight = mq.size.height;
          final isMobile = screenWidth < 600;

          final rawTableName = widget.table.number.trim();
          final displayTableName = rawTableName.toLowerCase().startsWith('table')
              ? rawTableName
              : 'Table $rawTableName';
          final cartHeaderTitle = '$displayTableName - Order';

          return Container(
            constraints: BoxConstraints(
              maxHeight: screenHeight * 0.82,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFFF5F6F0),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with styled Close X button
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
                      const Icon(Icons.shopping_cart_outlined, color: Color(0xFFE8C468), size: 22),
                      const SizedBox(width: 8),
                      Text(
                        cartHeaderTitle,
                        style: GoogleFonts.urbanist(
                          fontSize: isMobile ? 18 : 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8C468).withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_cart.length} items',
                          style: GoogleFonts.urbanist(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFFE8C468),
                          ),
                        ),
                      ),
                      const Spacer(),
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
                // Cart Items List
                Flexible(
                  child: Container(
                    color: const Color(0xFFF5F6F0),
                    child: _cart.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Center(
                              child: Text(
                                'Cart is empty',
                                style: GoogleFonts.urbanist(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            padding: EdgeInsets.all(isMobile ? 12 : 16),
                            physics: const BouncingScrollPhysics(),
                            itemCount: _cart.length,
                            itemBuilder: (context, index) {
                              final cartItem = _cart[index];
                              final item = cartItem.item;
                              return Container(
                                margin: EdgeInsets.only(bottom: isMobile ? 8 : 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
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
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.urbanist(
                                              fontSize: isMobile ? 16 : 17.5,
                                              fontWeight: FontWeight.bold,
                                              color: const Color(0xFF0C0E2B),
                                              height: 1.2,
                                            ),
                                          ),
                                          if (cartItem.quantity > 1) ...[
                                            const SizedBox(height: 3),
                                            Text(
                                              '₱${formatPrice(item.price)} each',
                                              style: GoogleFonts.urbanist(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 4),
                                          if (cartItem.remarks != null && cartItem.remarks!.trim().isNotEmpty)
                                            InkWell(
                                              onTap: () => showItemNoteModal(
                                                context: context,
                                                cartItem: cartItem,
                                                onSaved: () {
                                                  setState(() {});
                                                  setModalState(() {});
                                                  _persistCart();
                                                },
                                              ),
                                              borderRadius: BorderRadius.circular(6),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFE8C468).withValues(alpha: 0.18),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: const Color(0xFFE8C468).withValues(alpha: 0.6)),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.edit_note_rounded, size: 14, color: Color(0xFFB45309)),
                                                    const SizedBox(width: 4),
                                                    Flexible(
                                                      child: Text(
                                                        cartItem.remarks!,
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: GoogleFonts.urbanist(
                                                          fontSize: 11.5,
                                                          fontWeight: FontWeight.w700,
                                                          color: const Color(0xFFB45309),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            )
                                          else
                                            InkWell(
                                              onTap: () => showItemNoteModal(
                                                context: context,
                                                cartItem: cartItem,
                                                onSaved: () {
                                                  setState(() {});
                                                  setModalState(() {});
                                                  _persistCart();
                                                },
                                              ),
                                              borderRadius: BorderRadius.circular(4),
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(vertical: 2),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.add_comment_outlined, size: 13, color: Colors.grey.shade600),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      '+ Add note',
                                                      style: GoogleFonts.urbanist(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w600,
                                                        color: Colors.grey.shade600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // Item Price on the right side before stepper
                                    Text(
                                      '₱${formatPrice(item.price * cartItem.quantity)}',
                                      style: GoogleFonts.urbanist(
                                        fontSize: isMobile ? 17 : 19,
                                        fontWeight: FontWeight.w900,
                                        color: const Color(0xFFD97706),
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // Stepper Button (- qty +)
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        gradient: const LinearGradient(
                                          colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF0C0E2B).withValues(alpha: 0.25),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: Icon(
                                              Icons.remove,
                                              size: isMobile ? 18 : 20,
                                              color: Colors.white,
                                            ),
                                            onPressed: () {
                                              _decreaseItemQuantity(item);
                                              setModalState(() {});
                                            },
                                            padding: const EdgeInsets.all(5),
                                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                            style: IconButton.styleFrom(
                                              backgroundColor: Colors.transparent,
                                              foregroundColor: Colors.white,
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 4),
                                            child: Text(
                                              '${cartItem.quantity}',
                                              style: GoogleFonts.urbanist(
                                                fontWeight: FontWeight.bold,
                                                fontSize: isMobile ? 14 : 16,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: Icon(
                                              Icons.add,
                                              size: isMobile ? 18 : 20,
                                              color: Colors.white,
                                            ),
                                            onPressed: () {
                                              _increaseItemQuantity(item);
                                              setModalState(() {});
                                            },
                                            padding: const EdgeInsets.all(5),
                                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                            style: IconButton.styleFrom(
                                              backgroundColor: Colors.transparent,
                                              foregroundColor: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ),
                // Quick Add Drinks Carousel
                QuickAddDrinksCarousel(
                  suggestedDrinks: _getTopSuggestedDrinks(),
                  getItemQuantity: _getItemQuantity,
                  onAdd: (item) {
                    _increaseItemQuantity(item);
                    setModalState(() {});
                  },
                  onRemove: (item) {
                    _decreaseItemQuantity(item);
                    setModalState(() {});
                  },
                  isMobile: isMobile,
                ),
                // Bottom Breakdown / Summary Section
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
                            'Items (${_cart.fold<int>(0, (sum, ci) => sum + ci.quantity)})',
                            style: GoogleFonts.urbanist(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '₱${formatPrice(_totalPrice)}',
                        style: GoogleFonts.urbanist(
                          fontSize: isMobile ? 23 : 26,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFFD97706),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                // Order Type Selector
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 16 : 20,
                    vertical: isMobile ? 10 : 12,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF5F6F0),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order Type',
                        style: GoogleFonts.urbanist(
                          fontSize: isMobile ? 14 : 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _buildOrderTypeOption(
                              context: context,
                              value: 'DINE_IN',
                              label: 'Dine In',
                              icon: Icons.restaurant,
                              isMobile: isMobile,
                              onSelected: () {
                                setModalState(() {
                                  _selectedOrderType = 'DINE_IN';
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildOrderTypeOption(
                              context: context,
                              value: 'TAKE_OUT',
                              label: 'Take Out',
                              icon: Icons.shopping_bag,
                              isMobile: isMobile,
                              onSelected: () {
                                setModalState(() {
                                  _selectedOrderType = 'TAKE_OUT';
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Place Order Action Button
                Container(
                  padding: EdgeInsets.fromLTRB(
                    isMobile ? 16 : 20,
                    4,
                    isMobile ? 16 : 20,
                    isMobile ? 16 : 20,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF5F6F0),
                  ),
                  child: SafeArea(
                    child: SizedBox(
                      width: double.infinity,
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
                          onPressed: _cart.isEmpty ? null : _placeOrderFromCart,
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              vertical: isMobile ? 16 : 18,
                            ),
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ).copyWith(
                            overlayColor: WidgetStateProperty.all(Colors.transparent),
                          ),
                          child: Text(
                            'Place Order',
                            style: GoogleFonts.urbanist(
                              fontSize: isMobile ? 16.5 : 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _placeOrderFromCart() {
    Navigator.pop(context);
    _confirmPlaceOrder();
  }

  void _closeLoadingDialog() {
    if (!mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  Future<void> _confirmPlaceOrder() async {
    _createOrderFromCart();
  }

  Future<void> _createOrderFromCart() async {
    if (_cart.isEmpty) return;

    // If there's an existing order, add items to it (Additional Order)
    if (widget.existingOrder != null) {
      await _addItemsToExistingOrder();
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0C0E2B)),
                ),
                SizedBox(height: 16),
                Text('Placing order...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final now = DateTime.now();
      final orderNo =
          'ORD-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

      final items = _cart.map((cartItem) {
        if (cartItem.item.id == null) {
          throw Exception('Menu item ID is missing for ${cartItem.item.name}');
        }
        return {
          'menu_id': cartItem.item.id,
          'qty': cartItem.quantity,
          'unit_price': cartItem.item.price,
          'status': 3, // PENDING
          if (cartItem.remarks != null && cartItem.remarks!.trim().isNotEmpty)
            'remarks': cartItem.remarks!.trim(),
        };
      }).toList();

      final subtotal = _totalPrice;
      final taxAmount = 0.0;
      final serviceCharge = 0.0;
      final discountAmount = 0.0;
      final grandTotal = subtotal + taxAmount + serviceCharge - discountAmount;

      final result = await ApiService.createOrder(
        orderNo: orderNo,
        tableId: widget.table.id,
        orderType: _selectedOrderType,
        subtotal: subtotal,
        taxAmount: taxAmount,
        serviceCharge: serviceCharge,
        discountAmount: discountAmount,
        grandTotal: grandTotal,
        items: items,
      );

      _closeLoadingDialog();

      if (!mounted) return;

      if (result['unauthorized'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session expired. Please login again.'),
            duration: Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (result['success'] == true) {
        final orderIdRaw = result['data']?['order_id'] ?? result['data']?['orderId'];
        final orderId = orderIdRaw is int ? orderIdRaw : int.tryParse(orderIdRaw?.toString() ?? '');
        if (orderId != null) {
          final statusResult = await ApiService.updateWaiterOrderStatus(
            orderId: orderId,
            status: 2, // CONFIRMED
          );
          if (statusResult['unauthorized'] == true && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Session expired. Please login again.'),
                duration: Duration(seconds: 3),
                backgroundColor: Colors.red,
              ),
            );
            return;
          }
        }
        setState(() {
          _cart.clear();
        });
        WaiterCartStore.instance.clear(_cartKey);
        showCenterPopup(
          context,
          icon: Icons.check_circle,
          accentColor: Colors.green,
          title: 'Order Placed Successfully!',
          subtitle: 'Order #${result['data']?['order_no'] ?? orderNo}',
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error'] ?? 'Failed to place order'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      _closeLoadingDialog();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error placing order: ${e.toString()}'),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _addItemsToExistingOrder() async {
    if (widget.existingOrder == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0C0E2B)),
                ),
                SizedBox(height: 16),
                Text('Adding items to order...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final items = _cart.map((cartItem) {
        if (cartItem.item.id == null) {
          throw Exception('Menu item ID is missing for ${cartItem.item.name}');
        }
        return {
          'menu_id': cartItem.item.id,
          'qty': cartItem.quantity,
          'unit_price': cartItem.item.price,
          'status': 3, // PENDING
          if (cartItem.remarks != null && cartItem.remarks!.trim().isNotEmpty)
            'remarks': cartItem.remarks!.trim(),
        };
      }).toList();

      final result = await ApiService.addItemsToOrder(
        orderId: widget.existingOrder!.id,
        items: items,
      );

      _closeLoadingDialog();

      if (!mounted) return;

      if (result['unauthorized'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session expired. Please login again.'),
            duration: Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (result['success'] == true) {
        final itemCount = _cart.length;
        setState(() {
          _cart.clear();
        });
        WaiterCartStore.instance.clear(_cartKey);
        showCenterPopup(
          context,
          icon: Icons.check_circle,
          accentColor: Colors.green,
          title: 'Items Added Successfully!',
          subtitle: '$itemCount item(s) added to order #${widget.existingOrder!.orderNo ?? widget.existingOrder!.id}',
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error'] ?? 'Failed to add items to order'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      _closeLoadingDialog();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error adding items: ${e.toString()}'),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildOrderTypeOption({
    required BuildContext context,
    required String value,
    required String label,
    required IconData icon,
    required bool isMobile,
    required VoidCallback onSelected,
  }) {
    final isSelected = _selectedOrderType == value;

    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 16,
          vertical: isMobile ? 10 : 12,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF0C0E2B) : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          color: isSelected ? const Color(0xFF0C0E2B).withOpacity(0.1) : Colors.white,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: isMobile ? 18 : 20,
              color: isSelected ? const Color(0xFF0C0E2B) : Colors.grey.shade600,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.urbanist(
                fontSize: isMobile ? 13 : 15,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? const Color(0xFF0C0E2B) : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    final isLargeDesktop = screenWidth >= 1600;
    // Desktop sidebar is ONLY for very wide desktop PC screens (>= 1500px).
    // Tablets (like Galaxy Tab A9 at 1340x800), mobile phones, and mobile landscape use full Mobile View UI.
    final useSidebar = isLandscape && screenWidth >= 1500;
    final isMobile = !useSidebar;
    final canShowSideCart = useSidebar && screenWidth >= 1500;
    final showCartPanel = canShowSideCart && _isCartPanelOpen && _cart.isNotEmpty;

    final sidebarWidth = isLargeDesktop ? 280.0 : 240.0;

    final categoryCounts = <String, int>{
      for (final category in _categories)
        category: _getItemsForCategory(category).length,
    };

    final tableLabel = widget.existingOrder != null
        ? 'Additional Order • Table ${widget.table.number}'
        : 'Get Order • Table ${widget.table.number}';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F0),
      appBar: isMobile
          ? AppBar(
              title: Text(
                tableLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.urbanist(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0C0E2B),
                  letterSpacing: 0.2,
                ),
              ),
              centerTitle: true,
              leadingWidth: 60,
              leading: IconButton(
                icon: const HomeGlyph(size: 32, color: Color(0xFF0C0E2B)),
                tooltip: 'Home',
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.settings, size: 28),
                  color: const Color(0xFF0C0E2B),
                  onPressed: () {
                    showAppSettingsSheet(
                      context: context,
                      onLogout: () async {
                        await ApiService.logout();
                        if (context.mounted) refreshAppAuth();
                      },
                    );
                  },
                ),
              ],
            )
          : null,
      body: MenuBackground(
        child: isMobile
            ? Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: _searchQuery.isNotEmpty
                              ? const Color(0xFF0C0E2B)
                              : Colors.grey.shade300,
                          width: _searchQuery.isNotEmpty ? 1.5 : 1.1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                          });
                        },
                        style: GoogleFonts.urbanist(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF0C0E2B),
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search menu items (e.g. beer, pizza, chicken)...',
                          hintStyle: GoogleFonts.urbanist(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w500,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: Color(0xFF0C0E2B),
                            size: 22,
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 20, color: Colors.grey),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _searchQuery = '';
                                    });
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  if (_searchQuery.isEmpty)
                    Container(
                      height: 58,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          // "All" stays pinned on the left so the waiter can
                          // jump back to the full menu (incl. Top Revenue)
                          // without scrolling the category strip back.
                          Padding(
                            padding: const EdgeInsets.only(left: 14),
                            child: _buildCategoryChip(
                              category: 'All',
                              count: categoryCounts['All'] ?? widget.menuItems.length,
                              isSelected: _selectedCategory == 'All',
                              onTap: () {
                                _selectCategory('All');
                                // Snap the strip back to the start so the
                                // first category (Sizzling & Pulutan) is in view.
                                if (_categoryStripController.hasClients) {
                                  _categoryStripController.animateTo(
                                    0,
                                    duration: const Duration(milliseconds: 320),
                                    curve: Curves.easeOutCubic,
                                  );
                                }
                              },
                            ),
                          ),
                          Container(
                            width: 1.4,
                            height: 26,
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            color: Colors.grey.shade300,
                          ),
                          Expanded(
                            child: ListView.builder(
                              controller: _categoryStripController,
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.only(right: 14),
                              itemCount: _categories.length - 1,
                              itemBuilder: (context, index) {
                                final category = _categories[index + 1];
                                final isSelected = category == _selectedCategory;
                                final count = categoryCounts[category] ?? 0;
                                return _buildCategoryChip(
                                  category: category,
                                  count: count,
                                  isSelected: isSelected,
                                  onTap: () => _selectCategory(category),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(child: _buildMenuPane(context)),
                ],
              )
            : Row(
                children: [
                  GetOrderSidebar(
                    categories: _categories,
                    selectedCategory: _selectedCategory,
                    itemCounts: categoryCounts,
                    onCategoryTap: _selectCategory,
                    allMenuItems: widget.menuItems,
                    onItemTap: (item) => _selectCategory(item.categoryName ?? item.category),
                    width: sidebarWidth,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const HomeGlyph(size: 34, color: Color(0xFF0C0E2B)),
                                tooltip: 'Home',
                                onPressed: () => Navigator.pop(context),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                tableLabel,
                                style: GoogleFonts.urbanist(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF0C0E2B),
                                ),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                child: Container(
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                      color: _searchQuery.isNotEmpty
                                          ? const Color(0xFF0C0E2B)
                                          : Colors.grey.shade300,
                                      width: _searchQuery.isNotEmpty ? 1.5 : 1.1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.04),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: TextField(
                                    controller: _searchController,
                                    onChanged: (value) {
                                      setState(() {
                                        _searchQuery = value;
                                      });
                                    },
                                    style: GoogleFonts.urbanist(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF0C0E2B),
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'Search menu items...',
                                      hintStyle: GoogleFonts.urbanist(
                                        fontSize: 13,
                                        color: Colors.grey.shade500,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      prefixIcon: const Icon(
                                        Icons.search_rounded,
                                        color: Color(0xFF0C0E2B),
                                        size: 20,
                                      ),
                                      suffixIcon: _searchQuery.isNotEmpty
                                          ? IconButton(
                                              icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.grey),
                                              onPressed: () {
                                                _searchController.clear();
                                                setState(() {
                                                  _searchQuery = '';
                                                });
                                              },
                                            )
                                          : null,
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              IconButton(
                                icon: const Icon(Icons.settings, size: 30),
                                color: const Color(0xFF0C0E2B),
                                onPressed: () {
                                  showAppSettingsSheet(
                                    context: context,
                                    onLogout: () async {
                                      await ApiService.logout();
                                      if (context.mounted) refreshAppAuth();
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        Expanded(child: _buildMenuPane(context)),
                      ],
                    ),
                  ),
                  if (canShowSideCart)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      width: showCartPanel ? (isLargeDesktop ? 380 : 340) : 0,
                      child: showCartPanel
                          ? Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5F6F0),
                                border: Border(left: BorderSide(color: Colors.grey.shade300)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    blurRadius: 18,
                                    offset: const Offset(-6, 0),
                                  ),
                                ],
                              ),
                              child: GetOrderCartPanel(
                                cart: _cart,
                                totalPrice: _totalPrice,
                                cartIconKey: _cartIconKey,
                                selectedOrderType: _selectedOrderType,
                                onOrderTypeChanged: (type) => setState(() => _selectedOrderType = type),
                                onIncrease: _increaseItemQuantity,
                                onDecrease: _decreaseItemQuantity,
                                onRemarksChanged: () => setState(() {}),
                                onClose: () => setState(() => _isCartPanelOpen = false),
                                onPlaceOrder: _cart.isEmpty ? null : () => _confirmPlaceOrder(),
                                isAdditionalOrder: widget.existingOrder != null,
                                title: '${widget.table.number.trim().toLowerCase().startsWith('table') ? widget.table.number.trim() : 'Table ${widget.table.number.trim()}'} - Order',
                                suggestedDrinks: _getTopSuggestedDrinks(),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
      ),
      // One prominent gold cart button, floating bottom-centre where the
      // waiter's thumb naturally rests — same fixed spot every time, high
      // contrast against the pale page and navy cards, and a big tap target.
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: (_cart.isNotEmpty && !showCartPanel)
          ? _buildCartButton(canShowSideCart: canShowSideCart)
          : null,
    );
  }

  Widget _buildCartButton({required bool canShowSideCart}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: FireGlowBackground(
        child: Material(
        key: _cartFabKey,
        color: const Color(0xFFE8C468),
        borderRadius: BorderRadius.circular(32),
        elevation: 8,
        shadowColor: const Color(0xFF0C0E2B).withValues(alpha: 0.55),
        child: InkWell(
          borderRadius: BorderRadius.circular(32),
          onTap: canShowSideCart
              ? () => setState(() => _isCartPanelOpen = !_isCartPanelOpen)
              : _showCartSheet,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 20, 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Cart icon + count, wrapped in a dark disc so it reads
                // clearly on the gold.
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: Color(0xFF0C0E2B),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.shopping_cart_outlined,
                          color: Color(0xFFE8C468), size: 22),
                    ),
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFE8C468), width: 2),
                        ),
                        child: Text(
                          '$_totalItems',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.urbanist(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0C0E2B),
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Text(
                  'View Order',
                  style: GoogleFonts.urbanist(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF0C0E2B),
                  ),
                ),
                const SizedBox(width: 10),
                Container(width: 1.4, height: 20, color: const Color(0xFF0C0E2B).withValues(alpha: 0.25)),
                const SizedBox(width: 10),
                Text(
                  '₱${formatPrice(_totalPrice)}',
                  style: GoogleFonts.urbanist(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF0C0E2B),
                  ),
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    final name = category.toLowerCase();
    if (category == 'All') return Icons.apps_rounded;
    if (category == topRevenueCategory || category.contains('Top') || category.contains('🔥') || category.contains('Best')) {
      return Icons.local_fire_department_rounded;
    }
    if (category == sizzlingCategory || name.contains('sizzling') || name.contains('pulutan')) {
      return Icons.outdoor_grill_rounded;
    }
    if (category == chickenCategory || name.contains('chicken') || name.contains('wing')) {
      return Icons.kebab_dining_rounded;
    }
    if (category == beerDrinkCategory || name.contains('beer')) {
      return Icons.sports_bar_rounded;
    }
    if (category == pizzaRiceCategory || name.contains('pizza') || name.contains('rice')) {
      return Icons.local_pizza_rounded;
    }
    if (category == dessertsCategory || name.contains('shake') || name.contains('dessert')) {
      return Icons.icecream_rounded;
    }
    if (name.contains('cocktail') || name.contains('liquor') || name.contains('shot')) return Icons.local_bar_rounded;
    if (name.contains('wine')) return Icons.wine_bar_rounded;
    if (name.contains('coffee')) return Icons.coffee_rounded;
    if (name.contains('shake') || name.contains('ade') || name.contains('drink') || name.contains('juice')) {
      return Icons.local_drink_rounded;
    }
    if (name.contains('pasta') || name.contains('noodle')) return Icons.ramen_dining_rounded;
    return Icons.restaurant_rounded;
  }

  // Strips the leading emoji from a category constant so the filter chip
  // shows a clean label ("Sizzling & Pulutan") matching the "All Menu Items"
  // sub-category chips, while the raw value still drives the filtering.
  String _categoryLabel(String category) =>
      category.replaceFirst(RegExp(r'^[^\w(]+\s*'), '').trim();

  Widget _buildCategoryChip({
    required String category,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isTopRevenue = category.contains('Top') || category.contains('🔥');
    final icon = _getCategoryIcon(category);

    return Container(
      margin: const EdgeInsets.only(right: 10, top: 3, bottom: 3),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: isSelected
                  ? (isTopRevenue
                      ? const LinearGradient(
                          colors: [Color(0xFFE8C468), Color(0xFFD4A843)],
                        )
                      : const LinearGradient(
                          colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)],
                        ))
                  : null,
              color: isSelected ? null : Colors.white,
              border: Border.all(
                color: isSelected
                    ? (isTopRevenue ? const Color(0xFFE8C468) : const Color(0xFF0C0E2B))
                    : (isTopRevenue ? const Color(0xFFE8C468).withValues(alpha: 0.8) : Colors.grey.shade300),
                width: isTopRevenue ? 1.8 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: isSelected
                      ? (isTopRevenue
                          ? const Color(0xFFE8C468).withValues(alpha: 0.35)
                          : const Color(0xFF0C0E2B).withValues(alpha: 0.25))
                      : Colors.black.withValues(alpha: 0.05),
                  blurRadius: isSelected ? 10 : 4,
                  offset: isSelected ? const Offset(0, 4) : const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected
                      ? (isTopRevenue ? const Color(0xFF0C0E2B) : const Color(0xFFE8C468))
                      : (isTopRevenue ? const Color(0xFFE8C468) : const Color(0xFF0C0E2B)),
                ),
                const SizedBox(width: 8),
                Text(
                  _categoryLabel(category),
                  style: GoogleFonts.urbanist(
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    color: isSelected
                        ? (isTopRevenue ? const Color(0xFF0C0E2B) : Colors.white)
                        : const Color(0xFF0C0E2B),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isTopRevenue
                            ? const Color(0xFF0C0E2B).withValues(alpha: 0.15)
                            : Colors.white.withValues(alpha: 0.2))
                        : (isTopRevenue ? const Color(0xFFE8C468).withValues(alpha: 0.2) : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: GoogleFonts.urbanist(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? (isTopRevenue ? const Color(0xFF0C0E2B) : Colors.white)
                          : (isTopRevenue ? const Color(0xFFD4A843) : Colors.grey.shade700),
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

  Widget _buildCategoryPane(BuildContext context) {
    return Container(
      width: 220,
      color: Colors.white,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemBuilder: (context, index) {
          final category = _categories[index];
          final isSelected = category == _selectedCategory;
          return ListTile(
            title: Text(
              category,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? const Color(0xFF0C0E2B) : Colors.black87,
              ),
            ),
            selected: isSelected,
            selectedTileColor: const Color(0xFFF4E9E9),
            onTap: () {
              setState(() {
                _selectedCategory = category;
                _displayLimit = 18;
              });
            },
          );
        },
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemCount: _categories.length,
      ),
    );
  }

  Widget _buildMenuPane(BuildContext context) {
    final items = _filteredItems;
    if (items.isEmpty) {
      if (_searchQuery.trim().isNotEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off_rounded, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 14),
                Text(
                  'No items found for "$_searchQuery"',
                  style: GoogleFonts.urbanist(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0C0E2B),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'Try searching by item name or category',
                  style: GoogleFonts.urbanist(fontSize: 13, color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  icon: const Icon(Icons.clear_rounded, size: 16),
                  label: const Text('Clear Search'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0C0E2B),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return const Center(
        child: Text('No menu items available.'),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        int crossAxisCount;
        double childAspectRatio;
        double spacing;

        if (availableWidth >= 1150) {
          crossAxisCount = 5;
          childAspectRatio = 0.85;
          spacing = 16;
        } else if (availableWidth >= 850) {
          crossAxisCount = 4;
          childAspectRatio = 0.85;
          spacing = 16;
        } else if (availableWidth >= 580) {
          crossAxisCount = 3;
          childAspectRatio = 0.85;
          spacing = 14;
        } else if (availableWidth >= 340) {
          crossAxisCount = 2;
          childAspectRatio = 0.80;
          spacing = 12;
        } else {
          crossAxisCount = 1;
          childAspectRatio = 1.30;
          spacing = 10;
        }

        return CustomScrollView(
          key: ValueKey('grid_${_selectedCategory}_${_displayLimit}_${_topRevenueItems.length}_$_searchQuery'),
          physics: const BouncingScrollPhysics(),
          slivers: [
            if (_searchQuery.trim().isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded, size: 20, color: Color(0xFF0C0E2B)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Results for "$_searchQuery"',
                          style: GoogleFonts.urbanist(
                            fontSize: availableWidth < 500 ? 19.5 : 21.5,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0C0E2B),
                            letterSpacing: -0.3,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0C0E2B).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${items.length} items',
                          style: GoogleFonts.urbanist(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0C0E2B),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                        child: Text(
                          'Clear',
                          style: GoogleFonts.urbanist(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (_selectedCategory == 'All') ...[
              // Show whenever we can rank anything — the /api/menu/top-revenue
              // endpoint may be missing on the backend, in which case
              // _rankedTopRevenue falls back to the menu sorted by sales.
              if (_rankedTopRevenue(max: 1).isNotEmpty) ...[
                SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8C468).withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.local_fire_department,
                          color: const Color(0xFFD97706),
                          size: availableWidth < 500 ? 22 : 24,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Top Revenue Items',
                        style: GoogleFonts.urbanist(
                          fontSize: availableWidth < 500 ? 21.0 : 23.0,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF0C0E2B),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => _selectCategory(topRevenueCategory),
                        child: Text(
                          'View All (${_rankedTopRevenue(max: 100).length})',
                          style: GoogleFonts.urbanist(
                            fontSize: availableWidth < 500 ? 14 : 15,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0C0E2B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _buildTopRevenueScroller(_rankedTopRevenue(max: 16)),
              ),
            ],

              // Section title only — the category chips live in the sticky
              // filter bar at the top of the page, so a second row here was
              // redundant.
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        'All Menu Items',
                        style: GoogleFonts.urbanist(
                          fontSize: availableWidth < 500 ? 21.0 : 23.0,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF0C0E2B),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${widget.menuItems.length}',
                        style: GoogleFonts.urbanist(
                          fontSize: availableWidth < 500 ? 14 : 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ] else if (_selectedCategory != 'All') ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0C0E2B).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _getCategoryIcon(_selectedCategory),
                        color: const Color(0xFF0C0E2B),
                        size: availableWidth < 500 ? 22 : 24,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _selectedCategory,
                      style: GoogleFonts.urbanist(
                        fontSize: availableWidth < 500 ? 21.0 : 23.0,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0C0E2B),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0C0E2B).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${items.length} items',
                        style: GoogleFonts.urbanist(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF0C0E2B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: _selectedCategory == topRevenueCategory
                  ? SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: availableWidth >= 900
                            ? 4
                            : availableWidth >= 600
                                ? 3
                                : 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        mainAxisExtent: 90,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _buildTopRevenuePill(items[index]),
                        childCount: items.length,
                        addAutomaticKeepAlives: false,
                        addRepaintBoundaries: true,
                      ),
                    )
                  : SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: spacing,
                        mainAxisSpacing: spacing,
                        childAspectRatio: childAspectRatio,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final item = items[index];
                          return GetOrderMenuCard(
                            key: ValueKey(
                                'card_${item.id ?? item.name}_${item.imageUrl}'),
                            item: item,
                            onTap: () {},
                            quantityControl: _buildGridQuantityControl(
                              item: item,
                              isMobile: availableWidth < 500,
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
            if (_hasMoreItems)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: 16,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0C0E2B).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: _loadMoreItems,
                      icon: Icon(
                        Icons.add_circle_outline,
                        color: Colors.white,
                        size: availableWidth < 500 ? 20 : 24,
                      ),
                      label: Text(
                        'Load More Menu',
                        style: GoogleFonts.urbanist(
                          fontSize: availableWidth < 500 ? 14 : 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shadowColor: Colors.transparent,
                        padding: EdgeInsets.symmetric(
                          horizontal: availableWidth < 500 ? 24 : 32,
                          vertical: availableWidth < 500 ? 12 : 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ).copyWith(
                        overlayColor: WidgetStateProperty.all(Colors.transparent),
                      ),
                    ),
                  ),
                ),
              ),
            // Clears the floating cart button so the last row stays tappable.
            SliverToBoxAdapter(
              child: SizedBox(height: _cart.isNotEmpty ? 96 : 12),
            ),
          ],
        );
      },
    );
  }
}

/// A hand-drawn house/home glyph. Painted with a [CustomPainter] instead of an
/// icon-font glyph so it renders no matter what happens with MaterialIcons
/// tree-shaking or font loading on web.
class HomeGlyph extends StatelessWidget {
  final double size;
  final Color color;
  const HomeGlyph({super.key, this.size = 26, this.color = const Color(0xFF0C0E2B)});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _HomeGlyphPainter(color)),
    );
  }
}

class _HomeGlyphPainter extends CustomPainter {
  final Color color;
  _HomeGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.085
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    // House outline: left eave → roof apex → right eave → down the right
    // wall → along the base → back up the left wall.
    final house = Path()
      ..moveTo(w * 0.13, h * 0.45)
      ..lineTo(w * 0.50, h * 0.11)
      ..lineTo(w * 0.87, h * 0.45)
      ..lineTo(w * 0.87, h * 0.87)
      ..lineTo(w * 0.13, h * 0.87)
      ..close();
    canvas.drawPath(house, stroke);

    // Door.
    final door = Path()
      ..moveTo(w * 0.40, h * 0.87)
      ..lineTo(w * 0.40, h * 0.58)
      ..lineTo(w * 0.60, h * 0.58)
      ..lineTo(w * 0.60, h * 0.87);
    canvas.drawPath(door, stroke);
  }

  @override
  bool shouldRepaint(_HomeGlyphPainter oldDelegate) => oldDelegate.color != color;
}


