import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models.dart';
import '../../waiterApp/models.dart';
import '../../waiterApp/waiter_models.dart';
import '../../waiterApp/services/api_service.dart';
import '../../waiterApp/widgets/confirm_order_bottom_sheet.dart';

class GetOrderPage extends StatefulWidget {
  final WaiterOrder? existingOrder;
  final List<MenuItem>? menuItems;
  final int? tableId;
  final String? tableNumber;

  const GetOrderPage({
    super.key,
    this.existingOrder,
    this.menuItems,
    this.tableId,
    this.tableNumber,
  });

  @override
  State<GetOrderPage> createState() => _GetOrderPageState();
}

class _GetOrderPageState extends State<GetOrderPage> with TickerProviderStateMixin {
  late List<String> _categories;
  String _selectedCategory = 'All';
  final List<CartItem> _cart = [];
  String? _selectedOrderType;
  int _displayLimit = 18;
  List<MenuItem> _menuItems = [];
  bool _isLoadingMenu = true;
  String? _errorMessage;

  // Flying cart animation
  final GlobalKey _cartFabKey = GlobalKey();
  late AnimationController _flyController;
  late Animation<Offset> _flyAnimation;
  late Animation<double> _flyOpacity;
  late Animation<double> _flyScale;
  Future<void>? _flyInFlight;

  @override
  void initState() {
    super.initState();
    debugPrint('GetOrderPage initState called');
    debugPrint('Table ID: ${widget.tableId}, Table Number: ${widget.tableNumber}');
    debugPrint('Existing Order: ${widget.existingOrder?.id}');
    
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

    Future.delayed(const Duration(milliseconds: 100), () {
      debugPrint('Calling _loadMenuItems');
      _loadMenuItems();
    });
  }

  @override
  void dispose() {
    _flyController.dispose();
    super.dispose();
  }

  Future<void> _loadMenuItems() async {
    try {
      debugPrint('=== LOAD MENU ITEMS START ===');
      debugPrint('Using passed menuItems: ${widget.menuItems != null}');
      
      if (widget.menuItems != null && widget.menuItems!.isNotEmpty) {
        debugPrint('Using provided menu items: ${widget.menuItems!.length}');
        setState(() {
          _menuItems = widget.menuItems!;
          _categories = _buildCategories(_menuItems);
          _isLoadingMenu = false;
          _errorMessage = null;
        });
        debugPrint('✓ Menu loaded from widget');
      } else {
        debugPrint('No menu items provided, fetching from API...');
        final result = await ApiService.getMenuItems();
        
        debugPrint('API Response received');
        debugPrint('Success: ${result['success']}');
        
        if (result['success'] == true) {
          final menuData = result['data'] is List
              ? List<Map<String, dynamic>>.from(result['data'])
              : [];
          
          debugPrint('✓ Menu data is list, length: ${menuData.length}');
          
          if (menuData.isNotEmpty) {
            debugPrint('Parsing ${menuData.length} items...');
            final items = menuData.map((item) {
              try {
                return MenuItem.fromApi(item);
              } catch (e) {
                debugPrint('Error parsing item: $e');
                rethrow;
              }
            }).toList();
            
            debugPrint('✓ Successfully parsed ${items.length} items');
            
            if (mounted) {
              setState(() {
                _menuItems = items;
                _categories = _buildCategories(_menuItems);
                _isLoadingMenu = false;
                _errorMessage = null;
              });
              debugPrint('✓ State updated');
            }
          } else {
            debugPrint('✗ Menu data is empty');
            if (mounted) {
              setState(() {
                _errorMessage = 'No menu items available';
                _isLoadingMenu = false;
              });
            }
          }
        } else {
          debugPrint('✗ API returned success=false: ${result['error']}');
          if (mounted) {
            setState(() {
              _errorMessage = result['error'] ?? 'Failed to load menu items';
              _isLoadingMenu = false;
            });
          }
        }
      }
      debugPrint('=== LOAD MENU ITEMS END ===');
    } catch (e) {
      debugPrint('✗ EXCEPTION in _loadMenuItems: $e');
      debugPrintStack(label: 'Stack trace');
      if (mounted) {
        setState(() {
          _errorMessage = 'Error loading menu: ${e.toString()}';
          _isLoadingMenu = false;
        });
      }
    }
  }

  List<String> _buildCategories(List<MenuItem> items) {
    final set = <String>{};
    for (final item in items) {
      final category = item.categoryName ?? item.category;
      if (category.trim().isEmpty) continue;
      set.add(category);
    }
    final list = set.toList()..sort();
    return ['All', ...list];
  }

  List<MenuItem> get _allFilteredItems {
    if (_selectedCategory == 'All') return _menuItems;
    return _menuItems.where((item) {
      final category = item.categoryName ?? item.category;
      return category == _selectedCategory;
    }).toList();
  }

  List<MenuItem> get _filteredItems {
    final allItems = _allFilteredItems;

    if (_selectedCategory == 'All') {
      return allItems.take(_displayLimit).toList();
    }

    return allItems;
  }

  bool get _hasMoreItems {
    if (_selectedCategory != 'All') return false;
    return _allFilteredItems.length > _displayLimit;
  }

  void _loadMoreItems() {
    setState(() {
      _displayLimit += 18;
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
  }

  void _removeItemAt(int index) {
    setState(() {
      _cart.removeAt(index);
    });
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

      final cartContext = _cartFabKey.currentContext;
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
    debugPrint('Adding item: ${item.name}, Current cart: ${_cart.length}');
    _increaseItemQuantity(item);
    debugPrint('After adding: ${_cart.length} items');
    _showFlyAnimation(context, item);
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
          onPressed: () => _onAddPressed(buttonContext, item),
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
    debugPrint('Opening cart sheet with ${_cart.length} items');
    _cart.forEach((item) {
      debugPrint('  - ${item.item.name}: ${item.quantity}');
    });
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

          final rawTableName = (widget.tableNumber ?? '').trim();
          final displayTableName = rawTableName.isEmpty
              ? 'New'
              : (rawTableName.toLowerCase().startsWith('table') ? rawTableName : 'Table $rawTableName');
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
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // Item Price on right
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
                                    // Stepper Button
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
                // Breakdown Section
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
          'status': 3,
        };
      }).toList();

      final subtotal = _totalPrice;
      final taxAmount = 0.0;
      final serviceCharge = 0.0;
      final discountAmount = 0.0;
      final grandTotal = subtotal + taxAmount + serviceCharge - discountAmount;

      final result = await ApiService.createOrder(
        orderNo: orderNo,
        tableId: widget.tableId ?? 0,
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
            status: 2,
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
        debugPrint('✓ New order placed successfully: $orderNo');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order placed successfully! Order #${result['data']?['order_no'] ?? orderNo}'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
        Future.delayed(const Duration(milliseconds: 500), () {
          debugPrint('Popping GetOrderPage to refresh orders list');
          Navigator.pop(context);
        });
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
          'status': 3,
        };
      }).toList();

      final result = await ApiService.addItemsToOrder(
        orderId: widget.existingOrder!.id,
        items: items,
      );

      debugPrint('📤 API Response: success=${result['success']}');
      debugPrint('📤 Response data: ${result['data']}');

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
        debugPrint('✓ $itemCount item(s) successfully added to order');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$itemCount item(s) added to order #${widget.existingOrder!.orderNo ?? widget.existingOrder!.id}'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
        Future.delayed(const Duration(milliseconds: 500), () {
          debugPrint('Popping GetOrderPage to refresh orders list');
          Navigator.pop(context);
        });
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
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final isMobile = shortestSide < 600;

    if (_isLoadingMenu) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Loading Order'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0C0E2B)),
              ),
              const SizedBox(height: 24),
              const Text('Loading menu items...'),
              const SizedBox(height: 16),
              Text(
                'Table: ${widget.tableNumber ?? 'N/A'}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              Text(
                'Order ID: ${widget.existingOrder?.id ?? 'New'}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Get Order'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Error: $_errorMessage'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadMenuItems,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F0),
      appBar: AppBar(
        title: Text(
          widget.existingOrder != null 
              ? 'Additional Order • #${widget.existingOrder!.orderNo}'
              : widget.tableNumber != null
              ? 'New Order • Table ${widget.tableNumber}'
              : 'New Order',
          style: GoogleFonts.urbanist(
            fontSize: isMobile ? 22 : 24,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0C0E2B),
            letterSpacing: 0.2,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          iconSize: isMobile ? 36 : 44,
          onPressed: () => Navigator.pop(context),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ),
      body: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: _buildCategoryPane(context),
          ),
          Expanded(
            child: _buildMenuPane(context),
          ),
        ],
      ),
      floatingActionButton: Container(
        key: _cartFabKey,
        decoration: _cart.isNotEmpty
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0C0E2B).withOpacity(0.4),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              )
            : null,
        child: _cart.isNotEmpty
            ? FloatingActionButton.extended(
                onPressed: _showCartSheet,
                backgroundColor: Colors.transparent,
                elevation: 0,
                icon: Badge(
                  label: Text('$_totalItems'),
                  child: const Icon(Icons.shopping_cart_outlined, color: Colors.white),
                ),
                label: Text(
                  '₱${formatPrice(_totalPrice)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              )
            : const IgnorePointer(
                child: Opacity(
                  opacity: 0,
                  child: SizedBox(width: 56, height: 56),
                ),
              ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildCategoryPane(BuildContext context) {
    return Container(
      width: 220,
      color: Colors.white,
      child: _categories.isEmpty
          ? const Center(child: Text('No categories available'))
          : ListView.separated(
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
    debugPrint('Menu Pane - Total items: ${_menuItems.length}, Filtered items: ${items.length}');
    
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.restaurant_menu, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text('No menu items available (Total loaded: ${_menuItems.length})'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadMenuItems,
              child: const Text('Reload Menu'),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = MediaQuery.of(context).size.shortestSide < 600;
        final crossAxisCount = constraints.maxWidth >= 1000
            ? 4
            : (constraints.maxWidth >= 650
                ? 3
                : (constraints.maxWidth >= 360 ? 2 : 1));
        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  mainAxisExtent: 120,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = items[index];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: const [
                          BoxShadow(
                            color: Color.fromRGBO(0, 0, 0, 0.08),
                            blurRadius: 12,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              Text(
                                '₱${formatPrice(item.price)}',
                                style: const TextStyle(
                                  color: Color(0xFF0C0E2B),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                              const Spacer(),
                              _buildAddButton(
                                item: item,
                                isMobile: isMobile,
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                  childCount: items.length,
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                ),
              ),
            ),
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
                        overlayColor: WidgetStateProperty.all(Colors.transparent),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
