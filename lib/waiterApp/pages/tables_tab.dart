import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/widgets/card_cancel_button.dart';
import '../../shared/widgets/centered_section_header.dart';
import '../../shared/widgets/offline_order_badge.dart';
import '../models.dart' show formatPrice;
import '../waiter_models.dart';
import '../widgets/waiter_ui.dart';
import '../widgets/room_charge_history.dart' show RoomCountdownBadge;
import '../services/room_time_alerts.dart';
import '../services/waiter_cart_store.dart';

class TablesTab extends StatelessWidget {
  final List<WaiterTable> tables;
  final List<WaiterOrder> orders;
  final StatusInfo Function(int status) statusInfoFor;
  final void Function(WaiterTable table) onViewDetails;
  final void Function(WaiterTable table) onGetOrder;
  final void Function(WaiterTable table) onAddOrder;
  final void Function(WaiterTable table) onEditOrder;
  final void Function(WaiterTable table) onExtendRoomCharge;
  final void Function(WaiterOrder order)? onCancelOrder;
  // Starts a take-out order (no table). Null hides the button.
  final VoidCallback? onNewTakeOut;
  // Lets the sidebar's Occupied/Available submenu reuse this same grid with
  // a pre-filtered `tables` list, just relabeling the header/empty-state
  // text to match — the filtering itself happens in the caller.
  final String title;
  final String emptyMessage;
  final String? currentFilter;
  final ValueChanged<String>? onFilterChanged;
  final int totalAllCount;
  final int totalGfAvailableCount;
  final int totalGfOccupiedCount;
  final int total2fAvailableCount;
  final int total2fOccupiedCount;
  final bool showFilterChips;
  // 'gf', '2f', or null (unscoped). When set, the chip(s) for the *other*
  // floor are hidden — a floor-scoped account only ever sees its own floor.
  final String? lockedFloor;

  const TablesTab({
    super.key,
    required this.tables,
    required this.orders,
    required this.statusInfoFor,
    required this.onViewDetails,
    required this.onGetOrder,
    required this.onAddOrder,
    required this.onEditOrder,
    required this.onExtendRoomCharge,
    this.onCancelOrder,
    this.onNewTakeOut,
    this.title = 'Table Monitoring',
    this.emptyMessage = 'No tables found',
    this.currentFilter = 'all',
    this.onFilterChanged,
    this.totalAllCount = 0,
    this.totalGfAvailableCount = 0,
    this.totalGfOccupiedCount = 0,
    this.total2fAvailableCount = 0,
    this.total2fOccupiedCount = 0,
    this.showFilterChips = false,
    this.lockedFloor,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          if (showFilterChips && onFilterChanged != null) ...[
            const SizedBox(height: 14),
            _buildFilterPills(),
          ],
          if (onNewTakeOut != null) ...[
            const SizedBox(height: 8),
            // Take-outs are rare, so this stays a quiet outlined chip.
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                height: 36,
                child: OutlinedButton.icon(
                  onPressed: onNewTakeOut,
                  icon: const Icon(Icons.shopping_bag_outlined, size: 17),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _navy,
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: _line, width: 1.2),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  label: Text(
                    'Take Out',
                    style: GoogleFonts.urbanist(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _buildTablesGrid(context),
        ],
      ),
    );
  }

  static const _navy = Color(0xFF0C0E2B);
  static const _navy2 = Color(0xFF1B1E4A);
  static const _gold = Color(0xFFE8C468);
  static const _line = Color(0xFFDDDED3);
  static const _muted = Color(0xFF6B6F80);

  // Centered title between thin gold rules, table count underneath.
  Widget _buildHeader() => CenteredSectionHeader(
        title: title,
        subtitle: '${tables.length} tables',
      );

  // Filter pills, centered and equal width (same pill cards as the Switch
  // Menu categories): up to 3 per row, extra ones wrap onto a centered row.
  Widget _buildFilterPills() {
    final pills = <(String, String, int, IconData, Color?)>[
      ('all', 'All', totalAllCount, Icons.table_bar_rounded, null),
      if (lockedFloor != '2f') ...[
        (
          'gf_available',
          'GF Available',
          totalGfAvailableCount,
          Icons.check_circle_outline_rounded,
          Colors.green.shade700,
        ),
        (
          'gf_occupied',
          'GF Occupied',
          totalGfOccupiedCount,
          Icons.person_rounded,
          Colors.orange.shade700,
        ),
      ],
      if (lockedFloor != 'gf') ...[
        (
          '2f_available',
          '2F Available',
          total2fAvailableCount,
          Icons.check_circle_outline_rounded,
          Colors.green.shade700,
        ),
        (
          '2f_occupied',
          '2F Occupied',
          total2fOccupiedCount,
          Icons.person_rounded,
          Colors.orange.shade700,
        ),
      ],
    ];
    final perRow = pills.length <= 3 ? pills.length : (pills.length == 4 ? 2 : 3);
    const gap = 8.0;

    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - (perRow - 1) * gap) / perRow;
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final p in pills)
              SizedBox(
                width: w,
                height: 54,
                child: _filterPill(
                  key: p.$1,
                  label: p.$2,
                  count: p.$3,
                  icon: p.$4,
                  accentColor: p.$5,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _filterPill({
    required String key,
    required String label,
    required int count,
    required IconData icon,
    Color? accentColor,
  }) {
    final selected = currentFilter == key;
    final fg = selected ? _gold : _navy;
    return GestureDetector(
      onTap: () => onFilterChanged?.call(key),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(colors: [_navy, _navy2])
              : null,
          color: selected ? null : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected
                ? _navy
                : (accentColor?.withValues(alpha: 0.55) ?? _line),
          ),
        ),
        // Scales down instead of overflowing when pills share a phone.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 22,
                color: selected ? _gold : (accentColor ?? _navy),
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: GoogleFonts.urbanist(
                  color: fg,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                '$count',
                style: GoogleFonts.urbanist(
                  color: selected ? _gold.withValues(alpha: 0.8) : _muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // "ORDER BY TABLE_NUMBER ASC" on the backend is a plain string sort, so
  // "Room 10"/"Room 11"/.../"Room 13" sort right after "Room 1" and before
  // "Room 2". Sort by (non-numeric prefix, trailing number) instead so
  // "Room 1".."Room 13" (and M1..M13, P1..P4, etc.) read in numeric order.
  static List<WaiterTable> _naturallySortedTables(List<WaiterTable> source) {
    final sorted = List<WaiterTable>.from(source);
    sorted.sort((a, b) => _compareTableNumbers(a.number, b.number));
    return sorted;
  }

  static int _compareTableNumbers(String a, String b) {
    final aMatch = RegExp(r'^(.*?)(\d+)\s*$').firstMatch(a.trim());
    final bMatch = RegExp(r'^(.*?)(\d+)\s*$').firstMatch(b.trim());
    if (aMatch != null && bMatch != null) {
      final prefixCompare = aMatch
          .group(1)!
          .trim()
          .toUpperCase()
          .compareTo(bMatch.group(1)!.trim().toUpperCase());
      if (prefixCompare != 0) return prefixCompare;
      final aNum = int.tryParse(aMatch.group(2)!) ?? 0;
      final bNum = int.tryParse(bMatch.group(2)!) ?? 0;
      return aNum.compareTo(bNum);
    }
    return a.trim().toUpperCase().compareTo(b.trim().toUpperCase());
  }

  Widget _buildTablesGrid(BuildContext context) {
    if (tables.isEmpty) {
      return EmptyState(message: emptyMessage);
    }

    final sortedTables = _naturallySortedTables(tables);
    final tableOrderStatus = _buildTableOrderStatus();

    // Room-charge tables that currently have an active order get an extra
    // "Extend Room Charge" button, so those cards need more vertical room.
    final anyExtendable = sortedTables.any((t) =>
        t.hasRoomCharge &&
        orders.any((o) =>
            o.tableId == t.id && (o.status == 2 || o.status == 3)));

    // Rebuild the grid whenever a Get Order cart is saved/placed/emptied, so
    // the "unplaced cart" badge on a table card stays in sync without the
    // waiter having to pull-to-refresh.
    return AnimatedBuilder(
      animation: WaiterCartStore.instance,
      builder: (context, _) {
        final anyPendingCart = sortedTables.any(
            (t) => WaiterCartStore.instance.pendingItemCountForTable(t.id) > 0);

        // Size columns off the space this grid actually has, not the full
        // window width — the sidebar (~280-320px) already eats into that, and
        // picking a column count off the raw screen width squeezed cards down
        // to ~128px, which is what was blowing up the layout below.
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final textGrow = math.max(
              1.0,
              MediaQuery.textScalerOf(context).scale(10) / 10,
            );
            final crossAxisCount = width > 1150
                ? 5
                : width > 850
                    ? 4
                    : width > 560
                        ? 3
                        : width > 320
                            ? 2
                            : 1;

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: sortedTables.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                // Grows with the text scale so larger text never overflows.
                mainAxisExtent: ((anyExtendable ? 336 : 256) +
                        (anyPendingCart ? 58 : 0)) *
                    textGrow,
              ),
              itemBuilder: (context, index) {
                final table = sortedTables[index];
                final statusInfo = statusInfoFor(table.status);
                final orderStatusInfo = tableOrderStatus[table.id] ??
                    const StatusInfo('No Order', Colors.grey);
                return _TableCard(
                  table: table,
                  statusInfo: statusInfo,
                  orderStatusInfo: orderStatusInfo,
                  orders: orders,
                  cartPendingCount: WaiterCartStore.instance
                      .pendingItemCountForTable(table.id),
                  cartPendingTotal:
                      WaiterCartStore.instance.pendingTotalForTable(table.id),
                  onViewDetails: onViewDetails,
                  onGetOrder: onGetOrder,
                  onAddOrder: onAddOrder,
                  onEditOrder: onEditOrder,
                  onExtendRoomCharge: onExtendRoomCharge,
                  onCancelOrder: onCancelOrder,
                );
              },
            );
          },
        );
      },
    );
  }

  Map<int, StatusInfo> _buildTableOrderStatus() {
    final Map<int, StatusInfo> map = {};
    for (final order in orders) {
      final tableId = order.tableId;
      if (tableId == null) continue;
      if (order.status != 2 && order.status != 3) continue;
      final next = orderStatusInfo(order.status);
      if (!map.containsKey(tableId)) {
        map[tableId] = next;
        continue;
      }
      // Prefer confirmed over pending if multiple orders exist.
      if (order.status == 2) {
        map[tableId] = next;
      }
    }
    return map;
  }
}

class _TableCard extends StatelessWidget {
  final WaiterTable table;
  final StatusInfo statusInfo;
  final StatusInfo orderStatusInfo;
  final List<WaiterOrder> orders;
  // Units / peso value of a Get Order cart the waiter started for this table
  // but hasn't placed yet (0 when there is none).
  final int cartPendingCount;
  final double cartPendingTotal;
  final void Function(WaiterTable table) onViewDetails;
  final void Function(WaiterTable table) onGetOrder;
  final void Function(WaiterTable table) onAddOrder;
  final void Function(WaiterTable table) onEditOrder;
  final void Function(WaiterTable table) onExtendRoomCharge;
  final void Function(WaiterOrder order)? onCancelOrder;

  const _TableCard({
    required this.table,
    required this.statusInfo,
    required this.orderStatusInfo,
    required this.orders,
    this.cartPendingCount = 0,
    this.cartPendingTotal = 0,
    required this.onViewDetails,
    required this.onGetOrder,
    required this.onAddOrder,
    required this.onEditOrder,
    required this.onExtendRoomCharge,
    this.onCancelOrder,
  });

  static const _navy = Color(0xFF0C0E2B);
  static const _navyLight = Color(0xFF1B1E4A);
  static const _gold = Color(0xFFE8C468);
  static const _muted = Color(0xFFA9ACCB);
  static const _mint = Color(0xFF7DD3A8);

  // Lifts a status color (Colors.green/orange/red…) so it reads on navy.
  static Color _bright(Color c) => Color.lerp(c, Colors.white, 0.22)!;

  @override
  Widget build(BuildContext context) {
    final isAvailable = table.status == 1;
    final hasPendingCart = cartPendingCount > 0;
    final actionLabel = isAvailable
        ? (hasPendingCart ? 'Resume Order' : 'Get Order')
        : 'View Details';

    // "Extend Room Charge" only makes sense for a VIP/KTV room (has a room
    // charge configured) that currently has an active order to extend.
    final hasActiveOrder = orders.any((o) =>
        o.tableId == table.id && (o.status == 2 || o.status == 3));
    final showExtend = table.hasRoomCharge && hasActiveOrder;
    WaiterOrder? activeOrder;
    for (final o in orders) {
      if (o.tableId == table.id && (o.status == 2 || o.status == 3)) {
        activeOrder = o;
        break;
      }
    }

    final rawName = table.number.trim();
    final cleanTableName = rawName.toLowerCase().startsWith('table')
        ? rawName.substring(5).trim()
        : rawName;

    final accent = _bright(statusInfo.color);
    final orderAccent = _bright(orderStatusInfo.color);
    final showCountdown = activeOrder != null &&
        RoomCountdown.of(activeOrder, fallbackRate: table.roomCharge) != null;
    final subtitle = table.hasRoomCharge
        // Whole-peso rates drop the .00 so the rate fits on narrow cards.
        ? '₱${formatPrice(table.roomCharge).replaceAll(RegExp(r'\.00$'), '')} / hr'
        : (table.capacity > 0 ? '${table.capacity} seats' : 'Table');
    final itemCount = activeOrder?.items.length ?? 0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: CardCancelButton.overhang,
            right: CardCancelButton.overhang,
          ),
          child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: isAvailable ? () => onGetOrder(table) : () => onViewDetails(table),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_navyLight, _navy],
            ),
            border: Border.all(
              color: accent.withValues(alpha: activeOrder != null ? 0.5 : 0.22),
              width: activeOrder != null ? 1.4 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _navy.withValues(alpha: 0.22),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(17),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: name + status pill on one line, then the room
                      // rate / seats at full width.
                      Row(
                        children: [
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                cleanTableName,
                                maxLines: 1,
                                style: GoogleFonts.urbanist(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  height: 1.15,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  statusInfo.label,
                                  style: GoogleFonts.urbanist(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: accent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Room for the cancel X on the top-right corner.
                          if (activeOrder != null && onCancelOrder != null)
                            const SizedBox(width: 14),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.urbanist(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: table.hasRoomCharge ? _gold : _muted,
                        ),
                      ),
                      if (activeOrder != null) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OfflineOrderBadge(orderId: activeOrder.id),
                        ),
                      ],
                      const SizedBox(height: 12),
                      if (hasPendingCart) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: _gold.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _gold.withValues(alpha: 0.45)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.shopping_cart_rounded, size: 17, color: _gold),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Unplaced Order',
                                      maxLines: 1,
                                      style: GoogleFonts.urbanist(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w900,
                                        color: _gold,
                                      ),
                                    ),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        '$cartPendingCount item${cartPendingCount == 1 ? '' : 's'} · ₱${formatPrice(cartPendingTotal)}',
                                        maxLines: 1,
                                        style: GoogleFonts.urbanist(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: _gold.withValues(alpha: 0.85),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      // Order summary panel.
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(color: orderAccent, shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    orderStatusInfo.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.urbanist(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      color: activeOrder != null ? orderAccent : _muted,
                                    ),
                                  ),
                                ),
                                if (activeOrder != null)
                                  Text(
                                    '₱${formatPrice(activeOrder.grandTotal)}',
                                    maxLines: 1,
                                    style: GoogleFonts.urbanist(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              activeOrder != null
                                  ? '$itemCount item${itemCount == 1 ? '' : 's'} · ${activeOrder.orderNo ?? '#${activeOrder.id}'}'
                                  : (isAvailable ? 'Ready for guests' : 'No active order'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.urbanist(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _muted,
                              ),
                            ),
                            if (showCountdown) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.timer_outlined, size: 15, color: _muted),
                                  const SizedBox(width: 5),
                                  Text(
                                    'Time Left',
                                    maxLines: 1,
                                    style: GoogleFonts.urbanist(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: _muted,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerRight,
                                      child: RoomCountdownBadge(
                                        order: activeOrder,
                                        fallbackRate: table.roomCharge,
                                        onDark: true,
                                        dense: true,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(height: 10),
                      if (isAvailable)
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: ElevatedButton.icon(
                            onPressed: () => onGetOrder(table),
                            icon: Icon(
                              hasPendingCart
                                  ? Icons.shopping_cart_checkout_rounded
                                  : Icons.add_circle_outline_rounded,
                              size: 19,
                            ),
                            label: Text(
                              actionLabel,
                              style: GoogleFonts.urbanist(fontWeight: FontWeight.w900, fontSize: 14.5),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _gold,
                              foregroundColor: _navy,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        )
                      else ...[
                        Row(
                          children: [
                            Expanded(
                              child: _CardAction(
                                icon: Icons.receipt_long_rounded,
                                label: 'Details',
                                onTap: () => onViewDetails(table),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _CardAction(
                                icon: Icons.edit_rounded,
                                label: 'Edit',
                                onTap: () => onEditOrder(table),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _CardAction(
                                icon: Icons.add_rounded,
                                label: 'Add',
                                filled: true,
                                onTap: () => onAddOrder(table),
                              ),
                            ),
                          ],
                        ),
                        if (showExtend) ...[
                          const SizedBox(height: 6),
                          SizedBox(
                            width: double.infinity,
                            height: 40,
                            child: OutlinedButton.icon(
                              onPressed: () => onExtendRoomCharge(table),
                              icon: const Icon(Icons.more_time_rounded, size: 17),
                              label: Text(
                                'Extend Room Charge',
                                style: GoogleFonts.urbanist(fontWeight: FontWeight.w800, fontSize: 13),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _mint,
                                backgroundColor: _mint.withValues(alpha: 0.08),
                                side: BorderSide(color: _mint.withValues(alpha: 0.55)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
        ),
        ),
        // Cancel X on the card's top-right corner, only when there's an active
        // order on this table. Big hit area, inside the Stack so it's tappable.
        if (activeOrder != null && onCancelOrder != null)
          Positioned(
            top: 0,
            right: 0,
            child: CardCancelButton(onTap: () => onCancelOrder!(activeOrder!)),
          ),
      ],
    );
  }
}

/// Icon-over-label action button for an occupied table card. [filled] is the
/// gold primary action; the others are subtle tonal buttons.
class _CardAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  const _CardAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  static const _navy = Color(0xFF0C0E2B);
  static const _gold = Color(0xFFE8C468);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? _gold : Colors.white.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 54,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: filled ? _navy : _gold),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: GoogleFonts.urbanist(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: filled ? _navy : Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
