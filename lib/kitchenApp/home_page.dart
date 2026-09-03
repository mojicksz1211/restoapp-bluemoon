import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../menuApp/services/api_service.dart';
import '../../menuApp/services/socket_service.dart';
import '../../shared/globals.dart';
import '../shared/settings_sheet.dart';
import '../shared/app_translations.dart';
import 'models/kitchen_order.dart';

class KitchenHomePage extends StatefulWidget {
  const KitchenHomePage({super.key});

  @override
  State<KitchenHomePage> createState() => _KitchenHomePageState();
}

class _KitchenHomePageState extends State<KitchenHomePage> {
  bool _isLoading = true;
  String? _error;
  List<KitchenOrderUi> _orders = [];
  final Set<int> _joinedOrderIds = {};

  // Socket disposers
  VoidCallback? _disposeOrderUpdated;
  VoidCallback? _disposeOrderItemsAdded;
  VoidCallback? _disposeOrderCreated;

  @override
  void initState() {
    super.initState();
    _loadOrders();
    _startSocket();
    languageNotifier.addListener(_onLanguageChanged);
  }

  void _onLanguageChanged() {
    if (mounted) {
      _loadOrders();
    }
  }

  @override
  void dispose() {
    languageNotifier.removeListener(_onLanguageChanged);
    _disposeOrderUpdated?.call();
    _disposeOrderItemsAdded?.call();
    _disposeOrderCreated?.call();
    for (final id in _joinedOrderIds) {
      SocketService.leaveOrder(id);
    }
    SocketService.leaveKitchen();
    super.dispose();
  }

  Future<void> _loadOrders({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    final result = await ApiService.getKitchenOrders();
    
    if (mounted) {
      if (result['success'] == true) {
        final List<dynamic> data = result['data'];
        final orders = data.map((m) => KitchenOrderUi.fromMap(Map<String, dynamic>.from(m))).toList();
        
        setState(() {
          _orders = orders;
          _isLoading = false;
          _error = null;
        });
        
        _syncOrderRooms(orders.map((o) => o.orderId).toList());
      } else {
        setState(() {
          _isLoading = false;
          _error = result['error'] ?? 'Failed to load orders';
        });
      }
    }
  }

  void _startSocket() {
    SocketService.joinKitchen();
    
    _disposeOrderUpdated = SocketService.addOrderUpdateListener((_) => _loadOrders(showLoading: false));
    _disposeOrderItemsAdded = SocketService.addOrderItemsAddedListener((_) => _loadOrders(showLoading: false));
    _disposeOrderCreated = SocketService.addOrderCreatedListener((_) => _loadOrders(showLoading: false));
  }

  void _syncOrderRooms(List<int> orderIds) {
    final activeSet = orderIds.toSet();

    for (final id in orderIds) {
      if (_joinedOrderIds.add(id)) {
        SocketService.joinOrder(id);
      }
    }

    final toLeave = _joinedOrderIds.where((id) => !activeSet.contains(id)).toList();
    for (final id in toLeave) {
      SocketService.leaveOrder(id);
      _joinedOrderIds.remove(id);
    }
  }



  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9F3),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 2,
        toolbarHeight: 80,
        centerTitle: false,
        title: Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'kitchen_display'.tr,
                style: GoogleFonts.urbanist(
                  color: const Color(0xFF1A1C18),
                  fontWeight: FontWeight.w800,
                  fontSize: 28,
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${'connected'.tr} • ${_orders.length} ${'active_orders'.tr}',
                    style: GoogleFonts.urbanist(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: IconButton.filledTonal(
              onPressed: () async {
                await showAppSettingsSheet(
                  context: context,
                  onLogout: () async {
                    await ApiService.logout();
                    refreshAppAuth();
                  },
                );
              },
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFF2E0E0),
                foregroundColor: const Color(0xFF0C0E2B),
              ),
              icon: const Icon(Icons.settings_rounded),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0C0E2B)),
              ),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 64, color: Color(0xFF0C0E2B)),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: GoogleFonts.urbanist(fontSize: 16, color: Colors.grey.shade800),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => _loadOrders(),
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0C0E2B)),
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text('retry'.tr),
                      ),
                    ],
                  ),
                )
              : _orders.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.restaurant_rounded, size: 80, color: Colors.grey.shade300),
                          const SizedBox(height: 16),
                          Text(
                            'kitchen_is_clear'.tr,
                            style: GoogleFonts.urbanist(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          Text(
                            'no_pending_orders'.tr,
                            style: GoogleFonts.urbanist(
                              fontSize: 16,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: screenWidth > 1100 
                            ? 4 
                            : (screenWidth > 800 ? 3 : (screenWidth > 550 ? 2 : 1)),
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        mainAxisExtent: 360, // Pantay na height para sa lahat
                      ),
                      itemCount: _orders.length,
                      itemBuilder: (context, index) {
                        final order = _orders[index];
                        return _OrderCard(
                          key: ValueKey(order.orderId),
                          order: order,
                        );
                      },
                    ),
    );
  }
}

class _OrderCard extends StatefulWidget {
  final KitchenOrderUi order;

  const _OrderCard({
    super.key,
    required this.order,
  });

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  Timer? _timeUpdateTimer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timeUpdateTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  void _handleAction() {
    _showOrderDetails();
  }

  void _showOrderDetails() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _OrderDetailsSheet(
        order: widget.order,
      ),
    );
  }

  @override
  void dispose() {
    _timeUpdateTimer?.cancel();
    super.dispose();
  }

  String _getTimeAgo() {
    final diff = _now.difference(widget.order.encodedDt);
    if (diff.inMinutes < 1) return 'just_now'.tr;
    if (diff.inHours < 1) return '${diff.inMinutes}m ${'ago'.tr}';
    return '${diff.inHours}h ${diff.inMinutes % 60}m ${'ago'.tr}';
  }

  Color _getWaitColor() {
    final diff = _now.difference(widget.order.encodedDt);
    if (diff.inMinutes < 10) return const Color(0xFF2E8B57); // Green (Good)
    if (diff.inMinutes < 20) return const Color(0xFFDAA520); // Yellow/Gold (Warning)
    return const Color(0xFF0C0E2B); // Red (Critical)
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final waitColor = _getWaitColor();
    final cardBgColor = waitColor.withOpacity(0.05); // Very subtle tint for the whole card
    final headerBgColor = waitColor.withOpacity(0.12); // Slightly stronger for header
    
    Color typeColor = Colors.grey;
    String typeLabel = order.orderType;
    if (order.orderType == 'DINE_IN') {
      typeColor = const Color(0xFF2E8B57);
      typeLabel = 'dine_in_label'.tr;
    } else if (order.orderType == 'TAKE_OUT') {
      typeColor = const Color(0xFFDAA520);
      typeLabel = 'take_out_label'.tr;
    } else if (order.orderType == 'DELIVERY') {
      typeColor = const Color(0xFF4169E1);
      typeLabel = 'delivery_label'.tr;
    }

    Color statusColor = const Color(0xFFF16A1B); // Pending Orange

    const actionColor = Color(0xFF2E8B57);

    return Container(
      decoration: BoxDecoration(
        color: cardBgColor, // Dynamic background color based on wait time
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: waitColor.withOpacity(0.15), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: waitColor.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Section with Dynamic Tint
            Container(
              color: headerBgColor,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '#${order.orderNo}',
                          style: GoogleFonts.urbanist(
                            fontSize: 16, // Smaller header
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF1A1C18),
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(100),
                          boxShadow: [
                            BoxShadow(
                              color: statusColor.withOpacity(0.1),
                              blurRadius: 4,
                              spreadRadius: 1,
                            )
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: statusColor.withOpacity(0.4),
                                    blurRadius: 4,
                                    spreadRadius: 1,
                                  )
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              order.statusLabel.toLowerCase().tr.toUpperCase(),
                              style: GoogleFonts.urbanist(
                                fontSize: 11, // Larger status text
                                fontWeight: FontWeight.w900,
                                color: statusColor,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.restaurant_rounded, size: 16, color: Colors.grey.shade700),
                          const SizedBox(width: 6),
                          Text(
                            order.tableNumber != null ? '${'table'.tr} ${order.tableNumber}' : 'dine_in_label'.tr,
                            style: GoogleFonts.urbanist(
                              fontSize: 18, // Much larger table label
                              fontWeight: FontWeight.w900,
                              color: Colors.grey.shade900,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: waitColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.access_time_filled_rounded, size: 11, color: waitColor),
                            const SizedBox(width: 3),
                            Text(
                              _getTimeAgo(),
                              style: GoogleFonts.urbanist(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: waitColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Order Type Badge
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: typeColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  typeLabel.toUpperCase(),
                  style: GoogleFonts.urbanist(
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),

            // Items List (Flexible and Internal Scroll)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: order.items.map((item) => Container(
                      margin: const EdgeInsets.only(bottom: 4.0), // Smaller gap between items
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), // Smaller padding
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0C0E2B),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF0C0E2B).withOpacity(0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              )
                            ],
                          ),
                          child: Text(
                            '${item.qty.toStringAsFixed(0)}x',
                            style: GoogleFonts.urbanist(
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              fontSize: 16, // Larger font
                            ),
                          ),
                        ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.menuName,
                              style: GoogleFonts.urbanist(
                                fontWeight: FontWeight.w800, // Thicker font
                                color: const Color(0xFF1A1C18),
                                fontSize: 16, // Larger font from 13
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )).toList(),
                  ),
                ),
              ),
            ),

            // Bottom Action Bar
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.4),
                border: Border(top: BorderSide(color: Colors.black.withOpacity(0.03))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'total'.tr,
                    style: GoogleFonts.urbanist(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  Text(
                    '₱${order.grandTotal.toStringAsFixed(0)}',
                    style: GoogleFonts.urbanist(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF1A1C18),
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
}

class _OrderDetailsSheet extends StatelessWidget {
  final KitchenOrderUi order;

  const _OrderDetailsSheet({
    required this.order,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    String typeLabel = order.orderType;
    if (order.orderType == 'DINE_IN') {
      typeLabel = 'dine_in_label'.tr;
    } else if (order.orderType == 'TAKE_OUT') {
      typeLabel = 'take_out_label'.tr;
    } else if (order.orderType == 'DELIVERY') {
      typeLabel = 'delivery_label'.tr;
    }

    return DraggableScrollableSheet(
      initialChildSize: isMobile ? 0.8 : 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF5F6F0),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)],
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${'order'.tr} #${order.orderNo}',
                              style: GoogleFonts.urbanist(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              order.tableNumber != null ? '${'table'.tr} ${order.tableNumber}' : 'dine_in_label'.tr,
                              style: GoogleFonts.urbanist(
                                fontSize: 16,
                                color: Colors.white.withOpacity(0.8),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            typeLabel.toUpperCase(),
                            style: GoogleFonts.urbanist(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Items List
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  itemCount: order.items.length,
                  itemBuilder: (context, index) {
                    final item = order.items[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0C0E2B),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF0C0E2B).withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                )
                              ],
                            ),
                            child: Text(
                              '${item.qty.toStringAsFixed(0)}x',
                              style: GoogleFonts.urbanist(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                fontSize: 22, // Even larger for full details
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              item.menuName,
                              style: GoogleFonts.urbanist(
                                fontSize: 24, // Much larger font from 18
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1A1C18),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Footer with Total
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 20,
                      offset: const Offset(0, -10),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'total_amount'.tr,
                        style: GoogleFonts.urbanist(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        '₱${order.grandTotal.toStringAsFixed(0)}',
                        style: GoogleFonts.urbanist(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1A1C18),
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
}
