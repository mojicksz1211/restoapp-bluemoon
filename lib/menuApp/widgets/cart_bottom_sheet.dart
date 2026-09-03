import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../shared/app_translations.dart';
import '../models.dart';
import '../services/socket_service.dart';
import '../services/api_service.dart';
import '../services/settlement_dialog_service.dart';
import '../models.dart';

class CartBottomSheet extends StatefulWidget {
  final List<CartItem> cart;
  final double totalPrice;
  final bool isSubmitting;
  final Function(int) onRemove;
  final Function(int) onIncreaseQuantity;
  final Function(int) onDecreaseQuantity;
  final Function(String?) onPlaceOrder;
  final Order? activeOrder; // Optional active order for tracking
  final Function(Order)? onOrderUpdated; // Callback when order is updated

  const CartBottomSheet({
    super.key,
    required this.cart,
    required this.totalPrice,
    this.isSubmitting = false,
    required this.onRemove,
    required this.onIncreaseQuantity,
    required this.onDecreaseQuantity,
    required this.onPlaceOrder,
    this.activeOrder,
    this.onOrderUpdated,
  });

  @override
  State<CartBottomSheet> createState() => _CartBottomSheetState();
}

class _CartBottomSheetState extends State<CartBottomSheet>
    with SingleTickerProviderStateMixin {
  String? selectedOrderType; // 'DINE_IN' or 'TAKE_OUT'
  Order? _currentOrder;
  bool _isLoading = false;
  Map<int, MenuItem>? _menuItemsCache;
  Map<String, int> _itemStatusMap = {};
  VoidCallback? _disposeOrderUpdated;
  VoidCallback? _disposeOrderItemsAdded;
  VoidCallback? _disposeOrderCreated;
  late final AnimationController _skeletonController;
  bool _isPlacingOrder = false;
  List<CartItem> _pendingCartSnapshot = [];
  double _pendingTotalPrice = 0;
  DateTime? _loadingLockUntil;
  static const int _minLoadingMs = 1200;
  bool _pendingWasAdditional = false;
  bool _pendingSuccessShown = false;
  bool _showSuccessBanner = false;
  String _successMessage = '';
  String? _pendingOrderFingerprint;
  bool _additionalUpdateDetected = false;

  @override
  void initState() {
    super.initState();
    _skeletonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    selectedOrderType = widget.activeOrder?.orderType ?? 'DINE_IN';
    if (widget.activeOrder != null) {
      _currentOrder = widget.activeOrder;
      _loadMenuItemsCache().then((_) {
        _fetchLatestOrderStatus();
      });
    }
  }

  @override
  void didUpdateWidget(CartBottomSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldOrderId = oldWidget.activeOrder?.orderId;
    final newOrderId = widget.activeOrder?.orderId;
    if (oldOrderId != newOrderId ||
        (widget.activeOrder != null && _currentOrder?.orderId != widget.activeOrder?.orderId)) {
      if (widget.activeOrder != null) {
        _currentOrder = widget.activeOrder;
        selectedOrderType = widget.activeOrder?.orderType ?? selectedOrderType;
        _loadMenuItemsCache().then((_) {
          _fetchLatestOrderStatus();
        });
      } else {
        _currentOrder = null;
        _cleanupSocket();
      }
    } else if (widget.activeOrder != null && _currentOrder != null &&
               widget.activeOrder!.orderId == _currentOrder!.orderId) {
      // Same order: update in-memory reference only to avoid refetch loops.
      _currentOrder = widget.activeOrder;
      selectedOrderType = widget.activeOrder?.orderType ?? selectedOrderType;
    }

    if (!_pendingSuccessShown &&
        (_isPlacingOrder || _pendingCartSnapshot.isNotEmpty)) {
      if (_pendingWasAdditional) {
        if (widget.activeOrder != null &&
            _pendingOrderFingerprint != null &&
            _fingerprintOrder(widget.activeOrder!) != _pendingOrderFingerprint) {
          _additionalUpdateDetected = true;
          _pendingSuccessShown = true;
          _maybeShowInlineSuccess();
        }
      } else if (!widget.isSubmitting) {
        _pendingSuccessShown = true;
        _maybeShowInlineSuccess();
      }
    }

    if (widget.activeOrder != null || !widget.isSubmitting) {
      _maybeClearPendingOrderState();
    }
  }

  @override
  void dispose() {
    _cleanupSocket();
    _skeletonController.dispose();
    super.dispose();
  }

  void _cleanupSocket() {
    _disposeOrderUpdated?.call();
    _disposeOrderItemsAdded?.call();
    _disposeOrderCreated?.call();
    _disposeOrderUpdated = null;
    _disposeOrderItemsAdded = null;
    _disposeOrderCreated = null;
  }

  void _clearPendingOrderState() {
    if (_isPlacingOrder || _pendingCartSnapshot.isNotEmpty) {
      setState(() {
        _isPlacingOrder = false;
        _pendingCartSnapshot = [];
        _pendingTotalPrice = 0;
        _loadingLockUntil = null;
        _pendingWasAdditional = false;
        _pendingSuccessShown = false;
        _pendingOrderFingerprint = null;
        _additionalUpdateDetected = false;
      });
    }
  }

  void _maybeClearPendingOrderState() {
    if (_pendingWasAdditional && !_additionalUpdateDetected) {
      return;
    }
    if (_loadingLockUntil != null &&
        DateTime.now().isBefore(_loadingLockUntil!)) {
      final delay = _loadingLockUntil!.difference(DateTime.now());
      Future.delayed(delay, () {
        if (mounted) {
          _clearPendingOrderState();
        }
      });
      return;
    }
    _clearPendingOrderState();
  }

  void _maybeShowInlineSuccess() {
    if (_pendingWasAdditional && !_additionalUpdateDetected) {
      return;
    }
    if (_loadingLockUntil != null &&
        DateTime.now().isBefore(_loadingLockUntil!)) {
      final delay = _loadingLockUntil!.difference(DateTime.now());
      Future.delayed(delay, () {
        if (mounted) {
          _showInlineSuccess(
            _pendingWasAdditional
                ? 'items_added_to_order'.tr
                : 'order_placed_successfully'.tr,
          );
        }
      });
      return;
    }
    _showInlineSuccess(
      _pendingWasAdditional ? 'items_added_to_order'.tr : 'order_placed_successfully'.tr,
    );
  }

  void _showInlineSuccess(String message) {
    setState(() {
      _showSuccessBanner = true;
      _successMessage = message;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _showSuccessBanner = false;
        _successMessage = '';
      });
    });
  }

  void _startPendingOrder() {
    setState(() {
      _isPlacingOrder = true;
      _pendingCartSnapshot = widget.cart
          .map((item) => CartItem(
                item: item.item,
                quantity: item.quantity,
              ))
          .toList();
      _pendingTotalPrice = widget.totalPrice;
      _loadingLockUntil =
          DateTime.now().add(const Duration(milliseconds: _minLoadingMs));
      _pendingWasAdditional = widget.activeOrder != null;
      _pendingSuccessShown = false;
      _pendingOrderFingerprint = widget.activeOrder != null
          ? _fingerprintOrder(widget.activeOrder!)
          : null;
      _additionalUpdateDetected = false;
    });
    Future.delayed(
      const Duration(milliseconds: _minLoadingMs),
      () {
        if (mounted) {
          setState(() {});
        }
      },
    );
  }

  String _fingerprintOrder(Order order) {
    return '${order.items.length}_${order.totalPrice}';
  }

  Widget _buildSuccessBanner() {
    if (!_showSuccessBanner) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _successMessage,
              style: GoogleFonts.urbanist(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF2E7D32),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadMenuItemsCache() async {
    try {
      final result = await ApiService.getMenuItems();
      if (result['success'] == true && result['data'] != null) {
        final menus = result['data'] as List<dynamic>;
        _menuItemsCache = {
          for (var menu in menus)
            menu['id'] as int: MenuItem.fromApi(menu)
        };
      }
    } catch (e) {
      debugPrint('[CART BOTTOM SHEET] Error loading menu items cache: $e');
    }
  }

  MenuItem _getMenuItemWithImage(int menuId, String menuName, double price) {
    // Don't use "Unknown Item" - use empty string or try to get from cache
    final safeMenuName = menuName == 'Unknown Item' ? '' : menuName;
    
    if (_menuItemsCache != null && _menuItemsCache!.containsKey(menuId)) {
      final cachedItem = _menuItemsCache![menuId]!;
      return MenuItem(
        id: menuId,
        name: safeMenuName.isNotEmpty ? safeMenuName : cachedItem.name,
        description: cachedItem.description,
        price: price,
        category: cachedItem.category,
        categoryName: cachedItem.categoryName,
        categoryId: cachedItem.categoryId,
        icon: cachedItem.icon,
        imageUrl: cachedItem.imageUrl,
        isAvailable: cachedItem.isAvailable,
      );
    }
    // If no cache and menuName is "Unknown Item", return empty name to prevent flicker
    return MenuItem(
      id: menuId,
      name: safeMenuName.isNotEmpty ? safeMenuName : '',
      description: '',
      price: price,
      category: '',
      icon: Icons.restaurant_menu,
    );
  }

  Future<void> _fetchLatestOrderStatus() async {
    if (_currentOrder?.orderId == null) {
      _initializeSocket();
      return;
    }

    try {
      if (!mounted) return;
      setState(() {
        _isLoading = true;
      });

      final result = await ApiService.getUserOrders();
      if (!mounted) return;
      
      if (result['success'] == true && result['data'] != null) {
        final orders = result['data'] as List<dynamic>;
        final orderData = orders.firstWhere(
          (order) => (order['order_id'] == _currentOrder!.orderId),
          orElse: () => null,
        );

        if (orderData != null) {
          final items = orderData['items'] as List<dynamic>? ?? [];
          final statusValue = orderData['status'];
          final rawStatus = statusValue is int
              ? statusValue
              : (statusValue is String ? int.tryParse(statusValue) ?? 3 : 3);
          final status = normalizeBackendStatus(rawStatus);
          final grandTotalValue = orderData['grand_total'] ?? 0;
          final grandTotal = grandTotalValue is double
              ? grandTotalValue
              : grandTotalValue is int
                  ? grandTotalValue.toDouble()
                  : double.tryParse(grandTotalValue.toString()) ?? 0.0;
          _itemStatusMap.clear();
          final cartItems = items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final menuId = item['MENU_ID'] ?? item['menu_id'];
            final qtyValue = item['QTY'] ?? item['qty'] ?? 1;
            final qty = qtyValue is double
                ? qtyValue
                : qtyValue is int
                    ? qtyValue.toDouble()
                    : qtyValue is String
                        ? double.tryParse(qtyValue) ?? 1.0
                        : 1.0;
            final unitPriceValue = item['UNIT_PRICE'] ?? item['unit_price'] ?? 0;
            final unitPrice = unitPriceValue is double
                ? unitPriceValue
                : unitPriceValue is int
                    ? unitPriceValue.toDouble()
                    : unitPriceValue is String
                        ? double.tryParse(unitPriceValue) ?? 0.0
                        : 0.0;
            final statusValue = item['STATUS'] ?? item['status'] ?? 3;
            final itemStatus = statusValue is int
                ? statusValue
                : statusValue is String
                    ? int.tryParse(statusValue) ?? 3
                    : 3;
            final menuName = item['MENU_NAME'] ?? item['menu_name'];
            // Don't use "Unknown Item" fallback - use empty string instead
            final safeMenuName = menuName ?? '';
            final menuIdInt = menuId is int ? menuId : int.tryParse(menuId.toString()) ?? 0;
            
            // Try to preserve existing item name if incoming has no name
            final existingItem = _currentOrder?.items.isNotEmpty == true && index < _currentOrder!.items.length
                ? _currentOrder!.items[index]
                : null;
            final finalMenuName = safeMenuName.isEmpty && existingItem != null && existingItem.item.id == menuIdInt
                ? existingItem.item.name
                : safeMenuName;
            
            final menuItem = _getMenuItemWithImage(menuIdInt, finalMenuName, unitPrice);
            final statusKey = '${menuIdInt}_${qty.toInt()}_$index';
            _itemStatusMap[statusKey] = itemStatus;
            
            return CartItem(item: menuItem, quantity: qty.toInt());
          }).toList();
          
          if (!mounted) return;
          setState(() {
            _currentOrder = Order(
              id: _currentOrder!.id,
              orderId: _currentOrder!.orderId,
              items: cartItems,
              totalPrice: grandTotal,
              orderTime: _currentOrder!.orderTime,
              backendStatus: status,
              orderType: _currentOrder!.orderType,
              tableId: _currentOrder!.tableId,
            );
            _isLoading = false;
          });
          
          if (widget.onOrderUpdated != null) {
            widget.onOrderUpdated!(_currentOrder!);
          }
        } else {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
          });
        }
      } else {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[CART BOTTOM SHEET] Error fetching order status: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }

    _initializeSocket();
  }

  void _updateOrderFromSocket(Map<String, dynamic> socketData) {
    try {
      final orderData = socketData['order'] as Map<String, dynamic>?;
      if (orderData == null) return;

      final orderId = orderData['order_id'] ?? orderData['orderId'];
      final items = orderData['items'] as List<dynamic>? ?? [];
      final statusValue = orderData['status'];
      final rawStatus = statusValue is int ? statusValue : (statusValue is String ? int.tryParse(statusValue) ?? 3 : 3);
      final status = normalizeBackendStatus(rawStatus);
      final grandTotalValue = orderData['grand_total'] ?? orderData['grandTotal'] ?? 0;
      final grandTotal = grandTotalValue is double ? grandTotalValue : grandTotalValue is int ? grandTotalValue.toDouble() : grandTotalValue is String ? double.tryParse(grandTotalValue) ?? 0.0 : 0.0;

      // Check if status changed
      final statusChanged = _currentOrder?.backendStatus != status;

      final wasSettled = _currentOrder?.backendStatus == 1;
      final isNowSettled = status == 1;
      final wasCancelled = _currentOrder?.backendStatus == -1;
      final isNowCancelled = status == -1;
      // Show settlement dialog for both table orders and take-out orders
      final justBecameSettled = !wasSettled && isNowSettled;
      final justBecameCancelled = !wasCancelled && isNowCancelled;

      // Update item status map first (needed for status tracking)
      final newItemStatusMap = <String, int>{};
      final cartItems = items.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        final menuId = item['MENU_ID'] ?? item['menu_id'];
        final qtyValue = item['QTY'] ?? item['qty'] ?? 1;
        final qty = qtyValue is double ? qtyValue : qtyValue is int ? qtyValue.toDouble() : qtyValue is String ? double.tryParse(qtyValue) ?? 1.0 : 1.0;
        final unitPriceValue = item['UNIT_PRICE'] ?? item['unit_price'] ?? 0;
        final unitPrice = unitPriceValue is double ? unitPriceValue : unitPriceValue is int ? unitPriceValue.toDouble() : unitPriceValue is String ? double.tryParse(unitPriceValue) ?? 0.0 : 0.0;
        final statusValue = item['STATUS'] ?? item['status'] ?? 3;
        final itemStatus = statusValue is int ? statusValue : statusValue is String ? int.tryParse(statusValue) ?? 3 : 3;
        final menuName = item['MENU_NAME'] ?? item['menu_name'];
        // Don't use "Unknown Item" fallback - use empty string instead
        final safeMenuName = menuName ?? '';
        final menuIdInt = menuId is int ? menuId : int.tryParse(menuId.toString()) ?? 0;
        
        // Try to preserve existing item name if incoming has no name
        final existingItem = _currentOrder?.items.isNotEmpty == true && index < _currentOrder!.items.length
            ? _currentOrder!.items[index]
            : null;
        final finalMenuName = safeMenuName.isEmpty && existingItem != null && existingItem.item.id == menuIdInt
            ? existingItem.item.name
            : safeMenuName;
        
        final menuItem = _getMenuItemWithImage(menuIdInt, finalMenuName, unitPrice);
        final statusKey = '${menuIdInt}_${qty.toInt()}_$index';
        newItemStatusMap[statusKey] = itemStatus;
        
        return CartItem(item: menuItem, quantity: qty.toInt());
      }).toList();

      List<CartItem> nextItems = cartItems;
      final existingItems = _currentOrder?.items ?? const <CartItem>[];
      if (existingItems.length == nextItems.length) {
        var isSame = true;
        var hasUnknownItems = false;
        for (var i = 0; i < nextItems.length; i++) {
          final existing = existingItems[i];
          final incoming = nextItems[i];
          // Check if incoming item has "Unknown Item" name
          if (incoming.item.name == 'Unknown Item' || incoming.item.name.isEmpty) {
            hasUnknownItems = true;
          }
          if (existing.item.id != incoming.item.id ||
              existing.quantity != incoming.quantity ||
              existing.item.price != incoming.item.price) {
            isSame = false;
            break;
          }
        }
        // If incoming items have "Unknown Item" but existing items have proper names, use existing
        if (hasUnknownItems && existingItems.isNotEmpty) {
          // Preserve existing item names but update other data if needed
          nextItems = existingItems.map((existing) {
            final index = existingItems.indexOf(existing);
            if (index < cartItems.length) {
              final incoming = cartItems[index];
              // Only update if incoming has valid name and it's different
              if (incoming.item.name != 'Unknown Item' && 
                  incoming.item.name.isNotEmpty &&
                  incoming.item.name != existing.item.name) {
                return incoming;
              }
            }
            return existing;
          }).toList();
        } else if (isSame) {
          nextItems = existingItems;
        }
      }

      // Check if anything actually changed before calling setState
      final itemsChanged = existingItems.length != nextItems.length || 
                          !identical(existingItems, nextItems);
      final totalPriceChanged = (_currentOrder?.totalPrice ?? 0) != grandTotal;
      
      // Check if item statuses changed
      bool itemStatusMapChanged = false;
      if (_itemStatusMap.length != newItemStatusMap.length) {
        itemStatusMapChanged = true;
      } else {
        for (final key in newItemStatusMap.keys) {
          if (_itemStatusMap[key] != newItemStatusMap[key]) {
            itemStatusMapChanged = true;
            break;
          }
        }
      }
      
      // Check if only order status changed but nothing else changed.
      // This handles status-only changes without rebuilding items.
      final onlyOrderStatusChanged = statusChanged && 
                                     !itemsChanged && 
                                     !totalPriceChanged && 
                                     !itemStatusMapChanged &&
                                     _currentOrder?.backendStatus != status;
      
      // If only order status changed (not item statuses) and nothing else changed,
      // update status silently without rebuilding items
      if (onlyOrderStatusChanged) {
        // Update item status map silently
        _itemStatusMap.clear();
        _itemStatusMap.addAll(newItemStatusMap);
        
        // Update order status without rebuilding items
        if (!mounted) return;
        setState(() {
          _currentOrder = Order(
            id: _currentOrder!.id,
            orderId: _currentOrder!.orderId,
            items: existingItems, // Keep existing items to prevent flicker
            totalPrice: _currentOrder!.totalPrice, // Keep existing total
            orderTime: _currentOrder!.orderTime,
            backendStatus: status, // Update backend status
            orderType: _currentOrder!.orderType,
            tableId: _currentOrder!.tableId,
          );
        });
        
        // Check if order became SETTLED or CANCELLED - show dialog
        if (justBecameSettled || justBecameCancelled) {
          SettlementDialogService.instance.emit(_currentOrder!);
        }
        
        if (widget.onOrderUpdated != null) {
          widget.onOrderUpdated!(_currentOrder!);
        }
        return;
      }
      
      // Only update if something actually changed
      if (!statusChanged && !itemsChanged && !totalPriceChanged && !itemStatusMapChanged) {
        // Update item status map silently without rebuild
        _itemStatusMap.clear();
        _itemStatusMap.addAll(newItemStatusMap);
        return;
      }

      // Update item status map
      _itemStatusMap.clear();
      _itemStatusMap.addAll(newItemStatusMap);

      if (!mounted) return;
      setState(() {
        _currentOrder = Order(
          id: _currentOrder!.id,
          orderId: orderId is int ? orderId : int.tryParse(orderId.toString()),
          items: nextItems,
          totalPrice: grandTotal,
          orderTime: _currentOrder!.orderTime,
          backendStatus: status,
          orderType: _currentOrder!.orderType,
          tableId: _currentOrder!.tableId,
        );
        _isLoading = false;
      });

      if (justBecameSettled || justBecameCancelled) {
        SettlementDialogService.instance.emit(_currentOrder!);
      }

      if (widget.onOrderUpdated != null) {
        widget.onOrderUpdated!(_currentOrder!);
      }
    } catch (e) {
      debugPrint('Error updating order from socket: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _initializeSocket() async {
    if (_currentOrder?.orderId == null) return;

    try {
      // Only initialize if not already connected
      if (!SocketService.isConnected) {
        await SocketService.initialize();
      }
      // Don't call joinOrder here - parent _syncSocketOrderRooms() handles this
      // SocketService.joinOrder(_currentOrder!.orderId!);

      _disposeOrderUpdated?.call();
      _disposeOrderUpdated = SocketService.addOrderUpdateListener((data) {
        if (mounted) {
          _updateOrderFromSocket(data);
        }
      });

      _disposeOrderItemsAdded?.call();
      _disposeOrderItemsAdded = SocketService.addOrderItemsAddedListener((data) {
        if (mounted) {
          _updateOrderFromSocket(data);
        }
      });

      _disposeOrderCreated?.call();
      _disposeOrderCreated = SocketService.addOrderCreatedListener((data) {
        if (mounted) {
          _updateOrderFromSocket(data);
        }
      });
    } catch (e) {
      debugPrint('[CART BOTTOM SHEET] Error initializing socket: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final combinedTotalPrice =
        (_currentOrder?.totalPrice ?? 0) + widget.totalPrice;
    final isPendingOrder = _isPlacingOrder || widget.isSubmitting;
    final isLoadingLocked = _loadingLockUntil != null &&
        DateTime.now().isBefore(_loadingLockUntil!);
    final isAdditionalWaiting =
        _pendingWasAdditional && !_additionalUpdateDetected;

    if ((isPendingOrder && isLoadingLocked) ||
        (_currentOrder == null && isPendingOrder) ||
        (isPendingOrder && isAdditionalWaiting)) {
      return DraggableScrollableSheet(
        initialChildSize: isMobile ? 0.75 : 0.7,
        minChildSize: isMobile ? 0.55 : 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              Container(
                padding: EdgeInsets.all(isMobile ? 16 : 20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'your_order'.tr,
                      style: GoogleFonts.urbanist(
                        fontSize: isMobile ? 20 : 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '₱${formatPrice(_pendingTotalPrice > 0 ? _pendingTotalPrice : widget.totalPrice)}',
                      style: GoogleFonts.urbanist(
                        fontSize: isMobile ? 20 : 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              _buildSuccessBanner(),
              Expanded(
                child: Container(
                  color: const Color(0xFFF5F6F0),
                  child: _OrderSkeleton(
                    animation: _skeletonController,
                    itemCount: (_pendingCartSnapshot.isNotEmpty
                            ? _pendingCartSnapshot.length
                            : (_currentOrder?.items.length ?? 4))
                        .clamp(1, 8),
                  ),
                ),
              ),
            ],
          );
        },
      );
    }

    return DraggableScrollableSheet(
      initialChildSize: isMobile ? 0.75 : 0.7,
      minChildSize: isMobile ? 0.55 : 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        // Show order tracking if there's an active order, otherwise show cart
        if (_currentOrder != null) {
          final orderItems = _currentOrder!.items;
          final mergedItems = [...orderItems, ...widget.cart];
          return Column(
            children: [
              // Cart header (same as when showing cart)
              Container(
                padding: EdgeInsets.all(isMobile ? 16 : 20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'your_order'.tr,
                      style: GoogleFonts.urbanist(
                        fontSize: isMobile ? 20 : 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '₱${formatPrice(combinedTotalPrice)}',
                      style: GoogleFonts.urbanist(
                        fontSize: isMobile ? 20 : 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              _buildSuccessBanner(),
              // Order info below header when there's an active order
              Container(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 20, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF7A2525), // Slightly darker red to differentiate from header
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.1),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Order ID: ${_currentOrder!.id}',
                        style: GoogleFonts.urbanist(
                          fontSize: isMobile ? 12 : 14,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                    Text(
                      '${mergedItems.length} items',
                      style: GoogleFonts.urbanist(
                        fontSize: isMobile ? 12 : 14,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  color: const Color(0xFFF5F6F0),
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: EdgeInsets.all(isMobile ? 12 : 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Order Items
                        Container(
                          padding: EdgeInsets.all(isMobile ? 12 : 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F6F0),
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
                                'current_order'.tr,
                                style: GoogleFonts.urbanist(
                                  fontSize: isMobile ? 18 : 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              SizedBox(height: isMobile ? 12 : 16),
                              ...orderItems.asMap().entries.map((entry) {
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
                                                errorBuilder: (context, error, stackTrace) => Container(
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
                                            : Container(
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
                                          color: const Color(0xFF0C0E2B),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                        if (widget.cart.isNotEmpty) ...[
                          SizedBox(height: isMobile ? 12 : 16),
                          Container(
                            padding: EdgeInsets.all(isMobile ? 12 : 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F6F0),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFF0C0E2B), width: 1),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'additional_order'.tr,
                                  style: GoogleFonts.urbanist(
                                    fontSize: isMobile ? 16 : 18,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF0C0E2B),
                                  ),
                                ),
                                SizedBox(height: isMobile ? 12 : 16),
                                ...widget.cart.asMap().entries.map((entry) {
                                  final cartItem = entry.value;
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
                                                  errorBuilder: (context, error, stackTrace) => Container(
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
                                              : Container(
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
                                                  const SizedBox.shrink(),
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
                                            color: const Color(0xFF0C0E2B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                      
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              // Order Type Selection
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 16 : 20,
                  vertical: isMobile ? 12 : 16,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFFF5F6F0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'order_type'.tr,
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
                            label: 'dine_in_label'.tr,
                            icon: Icons.restaurant,
                            isMobile: isMobile,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildOrderTypeOption(
                            context: context,
                            value: 'TAKE_OUT',
                            label: 'take_out_label'.tr,
                            icon: Icons.shopping_bag,
                            isMobile: isMobile,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.all(isMobile ? 16 : 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F6F0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, -4),
                    ),
                  ],
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
                        onPressed: widget.cart.isEmpty || widget.isSubmitting
                            ? null
                            : () {
                                if (!_isPlacingOrder) {
                                  _startPendingOrder();
                                }
                                widget.onPlaceOrder(
                                  selectedOrderType ?? _currentOrder?.orderType,
                                );
                              },
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
                          overlayColor:
                              WidgetStateProperty.all(Colors.transparent),
                        ),
                        child: widget.isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Text(
                                'update_order'.tr,
                                style: GoogleFonts.urbanist(
                                  fontSize: isMobile ? 16 : 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        // Show cart when no active order
        return Column(
          children: [
            Container(
              padding: EdgeInsets.all(isMobile ? 16 : 20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)], // Maroon gradient
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'your_order'.tr,
                    style: GoogleFonts.urbanist(
                      fontSize: isMobile ? 20 : 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    '₱${formatPrice(widget.totalPrice)}',
                    style: GoogleFonts.urbanist(
                      fontSize: isMobile ? 20 : 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            _buildSuccessBanner(),
            Expanded(
              child: Container(
                color: const Color(0xFFF5F6F0), // Cream background
                child: widget.cart.isEmpty
                    ? Center(child: Text('cart_is_empty'.tr))
                    : Transform(
                        transform: Matrix4.identity(),
                        child: ListView.builder(
                          controller: scrollController,
                          padding: EdgeInsets.all(isMobile ? 12 : 16),
                          physics: const BouncingScrollPhysics(),
                          itemCount: widget.cart.length,
                          itemBuilder: (context, index) {
                            final cartItem = widget.cart[index];
                            final item = cartItem.item;
                            return Card(
                              color: const Color(0xFFF5F6F0), // Cream background
                              margin: EdgeInsets.only(bottom: isMobile ? 6 : 8),
                              child: ListTile(
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: item.imageUrl != null && item.imageUrl!.startsWith('http')
                                      ? CachedNetworkImage(
                                          imageUrl: item.imageUrl!,
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
                                              item.icon,
                                              color: Colors.grey[600],
                                              size: isMobile ? 25 : 30,
                                            ),
                                          ),
                                        )
                                      : item.imageUrl != null
                                          ? Image.asset(
                                              item.imageUrl!,
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
                                                        item.icon,
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
                                                item.icon,
                                                color: Colors.grey[600],
                                                size: isMobile ? 25 : 30,
                                              ),
                                            ),
                                ),
                                title: Text(
                                  item.name,
                                  style: GoogleFonts.urbanist(
                                    fontSize: isMobile ? 14 : 16,
                                  ),
                                ),
                                subtitle: Text(
                                  '₱${formatPrice(item.price)} × ${cartItem.quantity}',
                                  style: GoogleFonts.urbanist(
                                    fontSize: isMobile ? 12 : 14,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFF0C0E2B), // Dark maroon
                                            Color(0xFF1B1E4A), // Medium maroon
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(
                                              0xFF0C0E2B, // Maroon
                                            ).withValues(alpha: 0.3),
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
                                              size: isMobile ? 20 : 22,
                                              color: Colors.white,
                                            ),
                                            onPressed: () =>
                                                widget.onDecreaseQuantity(index),
                                            padding: EdgeInsets.all(
                                              isMobile ? 5 : 6,
                                            ),
                                            constraints: const BoxConstraints(),
                                            style: IconButton.styleFrom(
                                              backgroundColor: Colors.transparent,
                                              foregroundColor: Colors.white,
                                            ),
                                          ),
                                          Padding(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: isMobile ? 6 : 8,
                                            ),
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
                                              size: isMobile ? 20 : 22,
                                              color: Colors.white,
                                            ),
                                            onPressed: () =>
                                                widget.onIncreaseQuantity(index),
                                            padding: const EdgeInsets.all(6),
                                            constraints: const BoxConstraints(),
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
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ),
            // Order Type Selection
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 16 : 20,
                vertical: isMobile ? 12 : 16,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F6F0), // Cream background
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'order_type'.tr,
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
                          label: 'dine_in_label'.tr,
                          icon: Icons.restaurant,
                          isMobile: isMobile,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildOrderTypeOption(
                          context: context,
                          value: 'TAKE_OUT',
                          label: 'take_out_label'.tr,
                          icon: Icons.shopping_bag,
                          isMobile: isMobile,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.all(isMobile ? 16 : 20),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F6F0), // Cream background
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  child: Container(
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
                    child: ElevatedButton(
                      onPressed: widget.cart.isEmpty || widget.isSubmitting
                          ? null
                          : () {
                              if (!_isPlacingOrder) {
                                _startPendingOrder();
                              }
                              widget.onPlaceOrder(selectedOrderType);
                            },
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
                        overlayColor: WidgetStateProperty.all(Colors.transparent), // Remove blue splash
                      ),
                      child: widget.isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              widget.activeOrder != null
                                  ? 'update_order'.tr
                                  : 'place_order'.tr,
                              style: GoogleFonts.urbanist(
                                fontSize: isMobile ? 16 : 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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

  Widget _buildOrderTypeOption({
    required BuildContext context,
    required String value,
    required String label,
    required IconData icon,
    required bool isMobile,
  }) {
    final isSelected = selectedOrderType == value;
    
    return InkWell(
      onTap: () {
        setState(() {
          selectedOrderType = value;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 16,
          vertical: isMobile ? 10 : 12,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected 
                ? const Color(0xFF0C0E2B) 
                : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          color: isSelected 
              ? const Color(0xFF0C0E2B).withValues(alpha: 0.1)
              : Colors.white,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: isMobile ? 18 : 20,
              color: isSelected 
                  ? const Color(0xFF0C0E2B)
                  : Colors.grey.shade600,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.urbanist(
                fontSize: isMobile ? 13 : 15,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected 
                    ? const Color(0xFF0C0E2B)
                    : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderSkeleton extends StatelessWidget {
  final Animation<double> animation;
  final int itemCount;

  const _OrderSkeleton({
    required this.animation,
    required this.itemCount,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = Colors.grey.shade300;
    final highlight = Colors.grey.shade100;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final dx = (animation.value * 2) - 1;
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _SkeletonTile(
                width: double.infinity,
                height: 16,
                baseColor: baseColor,
                highlight: highlight,
                dx: dx,
              ),
              const SizedBox(height: 16),
              ...List.generate(itemCount, (index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      _SkeletonTile(
                        width: 50,
                        height: 50,
                        borderRadius: 8,
                        baseColor: baseColor,
                        highlight: highlight,
                        dx: dx,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SkeletonTile(
                              width: double.infinity,
                              height: 12,
                              baseColor: baseColor,
                              highlight: highlight,
                              dx: dx,
                            ),
                            const SizedBox(height: 8),
                            _SkeletonTile(
                              width: 120,
                              height: 10,
                              baseColor: baseColor,
                              highlight: highlight,
                              dx: dx,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _SkeletonTile(
                        width: 50,
                        height: 12,
                        baseColor: baseColor,
                        highlight: highlight,
                        dx: dx,
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class _SkeletonTile extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;
  final Color baseColor;
  final Color highlight;
  final double dx;

  const _SkeletonTile({
    required this.width,
    required this.height,
    required this.baseColor,
    required this.highlight,
    required this.dx,
    this.borderRadius = 6,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment(-1.0 + dx, 0),
          end: Alignment(1.0 + dx, 0),
          colors: [
            baseColor,
            highlight,
            baseColor,
          ],
          stops: const [0.1, 0.5, 0.9],
        ),
      ),
    );
  }
}

