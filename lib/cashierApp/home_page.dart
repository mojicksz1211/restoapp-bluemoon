import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../waiterApp/models.dart';
import '../waiterApp/waiter_models.dart';
import '../waiterApp/services/api_service.dart';
import '../waiterApp/services/socket_service.dart';
import '../shared/globals.dart';
import 'pages/get_order_page.dart';
import '../shared/settings_sheet.dart';
import '../shared/app_translations.dart';

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
  switch (method.toUpperCase()) {
    case 'GCASH':
      icon = Icons.account_balance_wallet_rounded;
      color = const Color(0xFF007DFE);
      break;
    case 'CARD':
      icon = Icons.credit_card_rounded;
      color = const Color(0xFF2E8B57);
      break;
    default:
      icon = Icons.payments_rounded;
      color = const Color(0xFF0C0E2B);
  }

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.1),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          method.toLowerCase().tr,
          style: GoogleFonts.urbanist(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 10,
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

class _CashierHomePageState extends State<CashierHomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isLoading = true;
  String? _errorMessage;
  List<WaiterOrder> _orders = [];
  final Set<int> _joinedOrderIds = {};
  String _searchQuery = '';
  final Set<int> _pinnedOrderIds = {};
  
  VoidCallback? _disposeOrderUpdated;
  VoidCallback? _disposeOrderItemsAdded;
  VoidCallback? _disposeOrderCreated;

  @override
  void initState() {
    super.initState();
    _loadData();
    _initializeSocket();
    languageNotifier.addListener(_onLanguageChanged);
  }

  void _onLanguageChanged() {
    if (mounted) {
      _loadData();
    }
  }

  @override
  void dispose() {
    languageNotifier.removeListener(_onLanguageChanged);
    _cleanupSocket();
    super.dispose();
  }

  Future<void> _loadData({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final ordersResult = await ApiService.getWaiterOrders();
      debugPrint('📊 Refreshed orders - success: ${ordersResult['success']}');
      
      if (ordersResult['unauthorized'] == true) {
        await _redirectToLogin();
        return;
      }

      if (ordersResult['success'] == true) {
        final ordersData = List<Map<String, dynamic>>.from(ordersResult['data']);
        debugPrint('📊 Loaded ${ordersData.length} orders from API');
        setState(() {
          _orders = ordersData.map(WaiterOrder.fromApi).toList();
          _isLoading = false;
        });
        _syncSocketOrderRooms();
      } else {
        setState(() {
          _errorMessage = ordersResult['error'] ?? 'Failed to load orders';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading data: ${e.toString()}';
        _isLoading = false;
      });
      debugPrint('❌ Error in _loadData: $e');
    }
  }

  Future<void> _redirectToLogin() async {
    await ApiService.logout();
    if (!mounted) return;
    refreshAppAuth();
  }

  Future<void> _initializeSocket() async {
    try {
      await SocketService.initialize();

      _disposeOrderUpdated?.call();
      _disposeOrderUpdated = SocketService.addOrderUpdateListener((data) {
        if (!mounted) return;
        _handleSocketOrderEvent(data, isFullUpdate: true);
      });

      _disposeOrderItemsAdded?.call();
      _disposeOrderItemsAdded = SocketService.addOrderItemsAddedListener((data) {
        if (!mounted) return;
        _handleSocketOrderEvent(data, isFullUpdate: false);
      });

      _disposeOrderCreated?.call();
      _disposeOrderCreated = SocketService.addOrderCreatedListener((data) {
        if (!mounted) return;
        _handleSocketOrderEvent(data, isFullUpdate: true);
      });

      _syncSocketOrderRooms();
    } catch (e) {
      debugPrint('Error initializing socket in cashier_home_page: $e');
    }
  }

  void _handleSocketOrderEvent(Map<String, dynamic> data, {bool isFullUpdate = false}) {
    if (!mounted) return;

    debugPrint('🔔 Socket event received (isFullUpdate: $isFullUpdate): ${data.keys.toList()}');

    final rawOrderData = data['order'];
    final orderData = rawOrderData is Map
        ? Map<String, dynamic>.from(rawOrderData)
        : Map<String, dynamic>.from(data);

    if (orderData['order_id'] == null && orderData['orderId'] != null) {
      orderData['order_id'] = orderData['orderId'];
    }

    final orderIdRaw = orderData['order_id'];
    final orderId = orderIdRaw is int ? orderIdRaw : int.tryParse(orderIdRaw?.toString() ?? '');
    debugPrint('🔔 Socket Event - Order ID: $orderId, Items in event: ${(orderData['items'] as List?)?.length ?? 0}');
    
    if (orderId == null) {
      debugPrint('❌ Socket event - Could not parse order ID');
      return;
    }

    final existingIndex = _orders.indexWhere((o) => o.id == orderId);
    
    try {
      final normalized = _normalizeSocketOrder(orderData);
      final updatedOrder = WaiterOrder.fromApi(normalized);

      setState(() {
        if (existingIndex == -1) {
          debugPrint('✓ Socket: Adding new order ${orderId}');
          _orders = [..._orders, updatedOrder];
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
        }
      });
      _syncSocketOrderRooms();
    } catch (e) {
      debugPrint('❌ Error updating order from socket: $e');
    }
  }

  Map<String, dynamic> _normalizeSocketOrder(Map<String, dynamic> data) {
    final normalized = Map<String, dynamic>.from(data);
    if (normalized['order_id'] == null && normalized['orderId'] != null) normalized['order_id'] = normalized['orderId'];
    if (normalized['order_no'] == null && normalized['orderNo'] != null) normalized['order_no'] = normalized['orderNo'];
    if (normalized['table_id'] == null && normalized['tableId'] != null) normalized['table_id'] = normalized['tableId'];
    if (normalized['table_number'] == null && normalized['tableNumber'] != null) normalized['table_number'] = normalized['tableNumber'];
    if (normalized['grand_total'] == null && normalized['grandTotal'] != null) normalized['grand_total'] = normalized['grandTotal'];
    if (normalized['payment_method'] == null && normalized['paymentMethod'] != null) normalized['payment_method'] = normalized['paymentMethod'];
    if (normalized['items'] is List) {
      normalized['items'] = (normalized['items'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    }
    return normalized;
  }

  void _cleanupSocket() {
    for (final id in _joinedOrderIds) {
      SocketService.leaveOrder(id);
    }
    _joinedOrderIds.clear();
    _disposeOrderUpdated?.call();
    _disposeOrderItemsAdded?.call();
    _disposeOrderCreated?.call();
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

  Future<void> _settleOrder(WaiterOrder order) async {
    final paymentMethod = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (context) => _SettleOrderSheet(order: order),
    );

    if (paymentMethod == null) return;

    setState(() => _isLoading = true);

    try {
      final result = await ApiService.updateWaiterOrderStatus(
        orderId: order.id,
        status: 1,
        paymentMethod: paymentMethod,
      );

      if (result['success'] == true) {
        await _loadData(showSpinner: false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Order settled successfully'), backgroundColor: Colors.green),
          );
        }
      } else {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['error'] ?? 'Failed to settle order'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
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

    final unsettledOrders = _orders.where((o) => o.status == 2).toList();
    final settledOrders = _orders.where((o) => o.status == 1).toList();
    final totalCollected = settledOrders.fold(0.0, (sum, o) => sum + o.grandTotal);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: const Color(0xFFF5F6F0),
        appBar: AppBar(
          title: Text(
            'cashier_dashboard'.tr,
            style: GoogleFonts.urbanist(
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              fontSize: 18,
              color: const Color(0xFF1A1C18),
            ),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 2,
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0C0E2B).withOpacity(0.1),
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
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(240),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                  child: Row(
                    children: [
                      _buildQuickStat(
                        label: 'ready_to_settle'.tr,
                        value: unsettledOrders.length.toString(),
                        icon: Icons.assignment_turned_in_rounded,
                        color: const Color(0xFF0C0E2B),
                      ),
                      const SizedBox(width: 16),
                      _buildQuickStat(
                        label: 'collected'.tr,
                        value: '₱${formatPrice(totalCollected)}',
                        icon: Icons.account_balance_wallet_rounded,
                        color: const Color(0xFF2E8B57),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0C0E2B).withOpacity(0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextField(
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
                          fontSize: 15,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: const Color(0xFF0C0E2B).withOpacity(0.6),
                          size: 22,
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? GestureDetector(
                                onTap: () => setState(() => _searchQuery = ''),
                                child: Icon(
                                  Icons.clear_rounded,
                                  color: Colors.grey.shade400,
                                  size: 20,
                                ),
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide(color: Colors.grey.withOpacity(0.1), width: 1.5),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide(color: Colors.grey.withOpacity(0.1), width: 1.5),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: const BorderSide(color: Color(0xFF0C0E2B), width: 2),
                        ),
                      ),
                      style: GoogleFonts.urbanist(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1A1C18),
                      ),
                    ),
                  ),
                ),
                TabBar(
                  labelColor: const Color(0xFF0C0E2B),
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: const Color(0xFF0C0E2B),
                  indicatorWeight: 4,
                  indicatorSize: TabBarIndicatorSize.label,
                  labelStyle: GoogleFonts.urbanist(fontWeight: FontWeight.w900, letterSpacing: 1, fontSize: 13),
                  tabs: [
                    Tab(text: 'unsettled'.tr),
                    Tab(text: 'history'.tr),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: Container(
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
              _buildOrderList(_filterOrders(settledOrders), isHistory: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickStat({required String label, required String value, required IconData icon, required Color color}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.withOpacity(0.08), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color.withOpacity(0.15), color.withOpacity(0.08)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.urbanist(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      style: GoogleFonts.urbanist(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
        itemCount: orders.length,
        itemBuilder: (context, index) {
          return _HistoryOrderListItem(
            order: orders[index],
          );
        },
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = screenWidth > 900 ? 3 : (screenWidth > 600 ? 2 : 1);
    double spacing = 20;
    double padding = 24;
    double cardWidth = (screenWidth - (padding * 2) - (spacing * (crossAxisCount - 1))) / crossAxisCount;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
      child: Wrap(
        spacing: spacing,
        runSpacing: 24,
        children: orders.map((order) {
          return SizedBox(
            width: cardWidth,
            child: _AnimatedOrderCard(
              key: ValueKey('order_${order.id}'),
              order: order,
              isHistory: isHistory,
              onSettle: () => _settleOrder(order),
              isPinned: _pinnedOrderIds.contains(order.id),
              onPin: () => _togglePinOrder(order.id),
              onRefresh: () => _loadData(showSpinner: false),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _HistoryOrderListItem extends StatelessWidget {
  final WaiterOrder order;

  const _HistoryOrderListItem({required this.order});

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0C0E2B);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: primaryColor.withOpacity(0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          leading: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.receipt_long_rounded, color: primaryColor, size: 24),
          ),
          title: Text(
            order.orderNo ?? '#${order.id}',
            style: GoogleFonts.urbanist(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: const Color(0xFF1A1C18),
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(Icons.chair_alt_rounded, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Text(
                  order.tableNumber != null ? '${'table'.tr} ${order.tableNumber}' : 'dine_in'.tr,
                  style: GoogleFonts.urbanist(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(width: 12),
                Text('•', style: TextStyle(color: Colors.grey.shade400)),
                const SizedBox(width: 12),
                Text(
                  '${order.items.length} ${'items'.tr}',
                  style: GoogleFonts.urbanist(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          trailing: SizedBox(
            width: 100,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '₱${formatPrice(order.grandTotal)}',
                    style: GoogleFonts.urbanist(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: primaryColor,
                      height: 1.1,
                    ),
                  ),
                ),
                if (order.paymentMethod != null) ...[
                  const SizedBox(height: 1),
                  _buildPaymentMethodBadge(order.paymentMethod!),
                ],
              ],
            ),
          ),
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 32),
                  Text(
                    'ORDER ITEMS',
                    style: GoogleFonts.urbanist(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade500,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: order.items.length,
                    separatorBuilder: (context, i) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final item = order.items[i];
                      return Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: primaryColor.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                '${item.quantity.toInt()}',
                                style: GoogleFonts.urbanist(
                                  fontWeight: FontWeight.w900,
                                  color: primaryColor,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              item.name,
                              style: GoogleFonts.urbanist(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: const Color(0xFF1A1C18),
                              ),
                            ),
                          ),
                          Text(
                            '₱${formatPrice(item.lineTotal)}',
                            style: GoogleFonts.urbanist(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: const Color(0xFF1A1C18),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedOrderCard extends StatefulWidget {
  final WaiterOrder order;
  final bool isHistory;
  final VoidCallback onSettle;
  final bool isPinned;
  final VoidCallback onPin;
  final Future<void> Function() onRefresh;

  const _AnimatedOrderCard({
    super.key,
    required this.order,
    required this.isHistory,
    required this.onSettle,
    required this.isPinned,
    required this.onPin,
    required this.onRefresh,
  });

  @override
  State<_AnimatedOrderCard> createState() => _AnimatedOrderCardState();
}

class _AnimatedOrderCardState extends State<_AnimatedOrderCard> {
  bool _isHovered = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_AnimatedOrderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.order.items.length > oldWidget.order.items.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0C0E2B);
    const secondaryColor = Color(0xFF1B1E4A);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        transform: _isHovered ? (Matrix4.identity()..translate(0, -10, 0)) : Matrix4.identity(),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: _isHovered ? primaryColor.withOpacity(0.6) : primaryColor.withOpacity(0.35),
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(
              color: _isHovered ? Colors.black.withOpacity(0.12) : Colors.black.withOpacity(0.05),
              blurRadius: _isHovered ? 30 : 15,
              offset: Offset(0, _isHovered ? 15 : 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 140,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [primaryColor, secondaryColor.withOpacity(0.9)],
                    ),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -30,
                        top: -30,
                        child: Icon(Icons.payments_outlined, size: 140, color: Colors.white.withOpacity(0.08)),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      widget.order.orderNo ?? '#${widget.order.id}',
                                      style: GoogleFonts.urbanist(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.5),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!widget.isHistory)
                                      GestureDetector(
                                        onTap: widget.onPin,
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                                          child: Icon(widget.isPinned ? Icons.star : Icons.star_outline, color: Colors.white, size: 16),
                                        ),
                                      ),
                                    if (!widget.isHistory) const SizedBox(width: 8),
                                    if (widget.isHistory && widget.order.paymentMethod != null) ...[
                                      _buildPaymentMethodBadge(widget.order.paymentMethod!),
                                      const SizedBox(width: 8),
                                    ],
                                    _buildStatusChip(widget.order.status),
                                  ],
                                ),
                              ],
                            ),
                            const Spacer(),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
                                  child: const Icon(Icons.chair_alt_rounded, color: Colors.white, size: 18),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  widget.order.tableNumber != null ? '${'table'.tr} ${widget.order.tableNumber}' : 'dine_in'.tr,
                                  style: GoogleFonts.urbanist(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: 1),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('order_items'.tr, style: GoogleFonts.urbanist(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey.shade500, letterSpacing: 1.5)),
                          const SizedBox(width: 8),
                          Expanded(child: Divider(color: Colors.grey.withOpacity(0.2))),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Column(
                        children: widget.order.items.map((item) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(color: primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                                  child: Center(child: Text('${item.quantity.toInt()}', style: GoogleFonts.urbanist(fontWeight: FontWeight.w900, color: primaryColor, fontSize: 11))),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Text(item.name, style: GoogleFonts.urbanist(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF1A1C18)), maxLines: 2, overflow: TextOverflow.visible)),
                                const SizedBox(width: 8),
                                Text('₱${formatPrice(item.lineTotal)}', style: GoogleFonts.urbanist(fontWeight: FontWeight.w800, fontSize: 13, color: const Color(0xFF1A1C18))),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(color: const Color(0xFFF5F6F0), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.withOpacity(0.1))),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('total_due'.tr, style: GoogleFonts.urbanist(fontWeight: FontWeight.w800, fontSize: 11, color: Colors.grey.shade600, letterSpacing: 1)),
                            Text('₱${formatPrice(widget.order.grandTotal)}', style: GoogleFonts.urbanist(fontWeight: FontWeight.w900, fontSize: 22, color: primaryColor)),
                          ],
                        ),
                      ),
                      if (!widget.isHistory) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          height: 38,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              await Navigator.of(context).push(MaterialPageRoute(builder: (context) => GetOrderPage(existingOrder: widget.order)));
                              if (mounted) await widget.onRefresh();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF5F6F0),
                              foregroundColor: primaryColor,
                              shadowColor: Colors.transparent,
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: primaryColor.withOpacity(0.3))),
                            ),
                            icon: const Icon(Icons.add_circle_outline, size: 14),
                            label: Text('add_items'.tr, style: GoogleFonts.urbanist(fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.5)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          height: 48,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: const LinearGradient(colors: [primaryColor, secondaryColor]),
                            boxShadow: _isHovered ? [BoxShadow(color: primaryColor.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))] : [],
                          ),
                          child: ElevatedButton(
                            onPressed: widget.onSettle,
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, foregroundColor: Colors.white, shadowColor: Colors.transparent, padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.receipt_long_rounded, size: 16),
                                const SizedBox(width: 8),
                                Text('settle_payment'.tr, style: GoogleFonts.urbanist(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0C0E2B);
    const secondaryColor = Color(0xFF1B1E4A);
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      decoration: const BoxDecoration(color: Color(0xFFF5F6F0), borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [primaryColor, secondaryColor], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
            child: Column(
              children: [
                Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: Colors.white.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('order_settlement'.tr, style: GoogleFonts.urbanist(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1)),
                          const SizedBox(height: 4),
                          Text('${'complete_payment_for'.tr} ${widget.order.orderNo ?? '#${widget.order.id}'}', style: GoogleFonts.urbanist(fontSize: 14, color: Colors.white70, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.2))),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.chair_alt_rounded, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Text(widget.order.tableNumber != null ? '${'table'.tr} ${widget.order.tableNumber}' : 'dine_in'.tr, style: GoogleFonts.urbanist(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('BILL DETAILS', style: GoogleFonts.urbanist(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.grey.shade600, letterSpacing: 1.5)),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.withOpacity(0.1))),
                    child: Column(
                      children: [
                        ...widget.order.items.map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${item.quantity.toInt()}x', style: GoogleFonts.urbanist(fontWeight: FontWeight.w900, color: primaryColor, fontSize: 14)),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.name, style: GoogleFonts.urbanist(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1A1C18))),
                                    Text('₱${formatPrice(item.unitPrice)}', style: GoogleFonts.urbanist(fontSize: 12, color: Colors.grey.shade500)),
                                  ],
                                ),
                              ),
                              Text('₱${formatPrice(item.lineTotal)}', style: GoogleFonts.urbanist(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF1A1C18))),
                            ],
                          ),
                        )),
                        const Divider(height: 32),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('subtotal'.tr, style: GoogleFonts.urbanist(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.grey.shade600)),
                            Text('₱${formatPrice(widget.order.grandTotal)}', style: GoogleFonts.urbanist(fontSize: 16, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('payment_method'.tr, style: GoogleFonts.urbanist(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.grey.shade600, letterSpacing: 1.5)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildPaymentOption(method: 'CASH', icon: Icons.payments_rounded, label: 'cash'.tr, primaryColor: primaryColor),
                      const SizedBox(width: 12),
                      _buildPaymentOption(method: 'GCASH', icon: Icons.account_balance_wallet_rounded, label: 'gcash'.tr, primaryColor: primaryColor),
                      const SizedBox(width: 12),
                      _buildPaymentOption(method: 'CARD', icon: Icons.credit_card_rounded, label: 'card'.tr, primaryColor: primaryColor),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 24, offset: const Offset(0, -12))]),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('amount_to_pay'.tr, style: GoogleFonts.urbanist(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.grey.shade500, letterSpacing: 1)),
                          Text('₱${formatPrice(widget.order.grandTotal)}', style: GoogleFonts.urbanist(fontSize: 32, fontWeight: FontWeight.w900, color: primaryColor)),
                        ],
                      ),
                      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: primaryColor.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.check_circle_rounded, color: primaryColor, size: 32)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(null),
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18), foregroundColor: Colors.grey.shade600),
                          child: Text('cancel'.tr.toUpperCase(), style: GoogleFonts.urbanist(fontWeight: FontWeight.w900, letterSpacing: 1)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: const LinearGradient(colors: [primaryColor, secondaryColor]),
                            boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))],
                          ),
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(_selectedPaymentMethod),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, foregroundColor: Colors.white, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                            child: Text('complete_settlement'.tr.toUpperCase(), style: GoogleFonts.urbanist(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1)),
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

  Widget _buildPaymentOption({required String method, required IconData icon, required String label, required Color primaryColor}) {
    final isSelected = _selectedPaymentMethod == method;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedPaymentMethod = method),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: isSelected ? primaryColor.withOpacity(0.1) : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: isSelected ? primaryColor : Colors.grey.withOpacity(0.1), width: 2)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: isSelected ? primaryColor : Colors.grey.shade400, size: 20),
              const SizedBox(height: 4),
              Text(label, style: GoogleFonts.urbanist(fontSize: 10, fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700, color: isSelected ? primaryColor : Colors.grey.shade500)),
            ],
          ),
        ),
      ),
    );
  }
}
