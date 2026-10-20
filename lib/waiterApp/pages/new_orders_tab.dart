import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/widgets/centered_section_header.dart';
import '../../shared/widgets/offline_order_badge.dart';
import '../waiter_models.dart';
import '../widgets/waiter_ui.dart';

const _navy = Color(0xFF0C0E2B);
const _navy2 = Color(0xFF1B1E4A);
const _gold = Color(0xFFE8C468);

class NewOrdersTab extends StatelessWidget {
  final List<WaiterOrder> orders;
  final VoidCallback onRefresh;
  final void Function(WaiterOrder order) onEdit;
  final void Function(WaiterOrder order) onConfirm;
  final void Function(WaiterOrder order)? onViewDetails;

  const NewOrdersTab({
    super.key,
    required this.orders,
    required this.onRefresh,
    required this.onEdit,
    required this.onConfirm,
    this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    return _OrdersScrollView(
      title: 'New Orders',
      subtitle: '${orders.length} pending',
      orders: orders,
      showConfirm: true,
      emptyMessage: 'No pending orders',
      onEdit: onEdit,
      onConfirm: onConfirm,
      onTap: onViewDetails,
    );
  }
}

// Order List can realistically hold hundreds of confirmed/settled orders
// (this is a per-day worklist, not filtered down further), so it's paged
// client-side at 15 per page instead of rendering everything at once.
class OrdersTab extends StatefulWidget {
  final List<WaiterOrder> orders;
  final void Function(WaiterOrder order) onViewDetails;

  const OrdersTab({
    super.key,
    required this.orders,
    required this.onViewDetails,
  });

  @override
  State<OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<OrdersTab> {
  static const int _pageSize = 15;
  int _page = 0;

  int _maxPage(int total) => total == 0 ? 0 : (total - 1) ~/ _pageSize;

  @override
  void didUpdateWidget(covariant OrdersTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The order list refreshes underneath (sockets, pull-to-refresh) — if
    // that shrinks the list below the current page, snap back into range
    // instead of showing an empty page.
    final maxPage = _maxPage(widget.orders.length);
    if (_page > maxPage) {
      setState(() => _page = maxPage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.orders.length;
    final maxPage = _maxPage(total);
    final start = _page * _pageSize;
    final end = (start + _pageSize).clamp(0, total);
    final pageOrders = total == 0 ? const <WaiterOrder>[] : widget.orders.sublist(start, end);

    return Column(
      children: [
        Expanded(
          child: _OrdersScrollView(
            title: 'Order List',
            subtitle: '$total order(s)',
            orders: pageOrders,
            showConfirm: false,
            emptyMessage: 'No confirmed orders',
            onEdit: (_) {},
            onConfirm: (_) {},
            onTap: widget.onViewDetails,
          ),
        ),
        if (total > _pageSize)
          _PaginationBar(
            page: _page,
            maxPage: maxPage,
            onPrevious: _page > 0 ? () => setState(() => _page--) : null,
            onNext: _page < maxPage ? () => setState(() => _page++) : null,
          ),
      ],
    );
  }
}

class _PaginationBar extends StatelessWidget {
  final int page;
  final int maxPage;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _PaginationBar({
    required this.page,
    required this.maxPage,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _gold.withValues(alpha: 0.25))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _PageButton(icon: Icons.chevron_left, onTap: onPrevious),
          const SizedBox(width: 16),
          Text(
            'Page ${page + 1} of ${maxPage + 1}',
            style: GoogleFonts.urbanist(
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
              color: _navy,
            ),
          ),
          const SizedBox(width: 16),
          _PageButton(icon: Icons.chevron_right, onTap: onNext),
        ],
      ),
    );
  }
}

class _PageButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _PageButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? _navy : Colors.grey.shade200,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 20, color: enabled ? _gold : Colors.grey.shade400),
        ),
      ),
    );
  }
}

/// Shared scaffold for both tabs — a single scrollable (CustomScrollView +
/// SliverList) instead of a SingleChildScrollView wrapping a shrink-wrapped,
/// non-scrolling ListView. That older combo forces Flutter to build and lay
/// out EVERY order card up front regardless of what's on screen; with a
/// branch's order history running into the thousands, that was the actual
/// cause of the slow load, on top of the (now separately fixed) N+1 query on
/// the backend. A real sliver list only builds the cards near the viewport.
class _OrdersScrollView extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<WaiterOrder> orders;
  final bool showConfirm;
  final String emptyMessage;
  final void Function(WaiterOrder order) onEdit;
  final void Function(WaiterOrder order) onConfirm;
  final void Function(WaiterOrder order)? onTap;

  const _OrdersScrollView({
    required this.title,
    required this.subtitle,
    required this.orders,
    required this.showConfirm,
    required this.emptyMessage,
    required this.onEdit,
    required this.onConfirm,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Cards used to be full-width, single-column — fine with a couple
        // orders, but stretched a plain "order#/table/total" line across
        // the whole content pane once there were more than a few. A
        // responsive grid keeps each card a sane, readable width instead.
        final width = constraints.maxWidth;
        // Lowered threshold so portrait tablet content pane (~440-500px
        // after the sidebar) gets 2 order-card columns instead of 1.
        final crossAxisCount = width > 1100
            ? 3
            : width > 460
                ? 2
                : 1;
        // New Orders cards are taller (Edit/Confirm buttons row); Order
        // List cards don't have that row.
        final mainAxisExtent = showConfirm ? 214.0 : 140.0;

        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: CenteredSectionHeader(title: title, subtitle: subtitle),
                ),
              ),
            ),
            if (orders.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverToBoxAdapter(child: EmptyState(message: emptyMessage)),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    mainAxisExtent: mainAxisExtent,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _OrderCard(
                      order: orders[index],
                      showConfirm: showConfirm,
                      onEdit: onEdit,
                      onConfirm: onConfirm,
                      onTap: onTap,
                    ),
                    childCount: orders.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  final WaiterOrder order;
  final bool showConfirm;
  final void Function(WaiterOrder order) onEdit;
  final void Function(WaiterOrder order) onConfirm;
  final void Function(WaiterOrder order)? onTap;

  const _OrderCard({
    required this.order,
    required this.showConfirm,
    required this.onEdit,
    required this.onConfirm,
    this.onTap,
  });

  // Status colors tuned for the navy card (the shared StatusChip is for white).
  static (String, Color) _status(int status) {
    switch (status) {
      case 3:
        return ('Pending', const Color(0xFFFF6B6B));
      case 2:
        return ('Confirmed', const Color(0xFFF59E0B));
      case 1:
        return ('Settled', const Color(0xFF4ADE80));
      case -1:
        return ('Cancelled', const Color(0xFFFF6B6B));
      default:
        return ('Unknown', Colors.grey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusColor) = _status(order.status);
    final rawTable = (order.tableNumber ?? '').trim();
    final tableName = rawTable.isEmpty
        ? '-'
        : (rawTable.toLowerCase().startsWith('table') ? rawTable.substring(5).trim() : rawTable);

    final card = Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_navy, _navy2],
        ),
        border: Border.all(color: _gold.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order.orderNo ?? 'Order #${order.id}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.urbanist(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: Colors.white.withValues(alpha: 0.65),
                  ),
                ),
              ),
              OfflineOrderBadge(orderId: order.id),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withValues(alpha: 0.6)),
                ),
                child: Text(
                  statusLabel,
                  style: GoogleFonts.urbanist(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.table_restaurant_rounded, size: 20, color: _gold),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    (order.isTakeOut ? order.takeOutLabel : 'TABLE $tableName').toUpperCase(),
                    maxLines: 1,
                    style: GoogleFonts.urbanist(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${order.items.length} item(s)',
                style: GoogleFonts.urbanist(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '₱${order.grandTotal.toStringAsFixed(2)}',
                style: GoogleFonts.urbanist(
                  fontWeight: FontWeight.w900,
                  color: _gold,
                  fontSize: 22,
                ),
              ),
            ],
          ),
          if (showConfirm) ...[
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onEdit(order),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _gold,
                      side: BorderSide(color: _gold.withValues(alpha: 0.6)),
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      'Edit Order',
                      style: GoogleFonts.urbanist(fontWeight: FontWeight.w800, fontSize: 14.5),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => onConfirm(order),
                    icon: const Icon(Icons.check_circle_rounded, size: 19),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: _navy,
                      elevation: 0,
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    label: Text(
                      'Confirm',
                      style: GoogleFonts.urbanist(fontWeight: FontWeight.w900, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return card;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onTap!(order),
        child: card,
      ),
    );
  }
}
