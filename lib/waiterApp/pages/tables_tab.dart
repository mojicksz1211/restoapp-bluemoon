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
                mainAxisExtent: (anyExtendable ? 300 : 255) +
                    (anyPendingCart ? 58 : 0),
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
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isAvailable ? () => onGetOrder(table) : () => onViewDetails(table),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_navy, _navyLight],
            ),
            border: Border.all(color: _gold.withValues(alpha: 0.25), width: 1),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'TABLE',
                          style: GoogleFonts.urbanist(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: _gold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            cleanTableName,
                            maxLines: 1,
                            style: GoogleFonts.urbanist(
                              fontSize: 18.5,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: statusInfo.color.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusInfo.color.withValues(alpha: 0.6)),
                    ),
                    child: Text(
                      statusInfo.label,
                      style: GoogleFonts.urbanist(
                        fontSize: 12.0,
                        fontWeight: FontWeight.w800,
                        color: statusInfo.color,
                      ),
                    ),
                  ),
                ],
              ),
              if (activeOrder != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OfflineOrderBadge(orderId: activeOrder.id),
                ),
              ],
              const SizedBox(height: 10),
              if (hasPendingCart) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: _gold.withValues(alpha: 0.55)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.shopping_cart_rounded, size: 15, color: _gold),
                          const SizedBox(width: 6),
                          Text(
                            'Unplaced Order',
                            style: GoogleFonts.urbanist(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w900,
                              color: _gold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.center,
                        child: Text(
                          '$cartPendingCount item${cartPendingCount == 1 ? '' : 's'} · ₱${formatPrice(cartPendingTotal)}',
                          maxLines: 1,
                          style: GoogleFonts.urbanist(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: _gold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              _InfoRow(
                label: 'Order Status',
                value: orderStatusInfo.label,
                valueColor: orderStatusInfo.color,
              ),
              const SizedBox(height: 6),
              if (activeOrder != null &&
                  RoomCountdown.of(activeOrder, fallbackRate: table.roomCharge) != null)
                Row(
                  children: [
                    Text(
                      'Time Left',
                      maxLines: 1,
                      style: GoogleFonts.urbanist(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.7),
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
                )
              else
                _InfoRow(
                  label: 'Capacity',
                  value: table.capacity.toString(),
                  valueColor: Colors.white,
                ),
              const Spacer(),
              const SizedBox(height: 8),
              if (isAvailable)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => onGetOrder(table),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: _navy,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 10.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(
                      actionLabel,
                      style: GoogleFonts.urbanist(fontWeight: FontWeight.w800, fontSize: 14.5),
                    ),
                  ),
                )
              else
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => onViewDetails(table),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          actionLabel,
                          style: GoogleFonts.urbanist(fontWeight: FontWeight.w800, fontSize: 13.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => onEditOrder(table),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _gold,
                              side: BorderSide(color: _gold.withValues(alpha: 0.6)),
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: Text(
                              'Edit Order',
                              style: GoogleFonts.urbanist(fontWeight: FontWeight.w800, fontSize: 13),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => onAddOrder(table),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _gold,
                              foregroundColor: _navy,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: Text(
                              'Add Order',
                              style: GoogleFonts.urbanist(fontWeight: FontWeight.w800, fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (showExtend) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => onExtendRoomCharge(table),
                          icon: const Icon(Icons.more_time_rounded, size: 16),
                          label: Text(
                            'Extend Room Charge',
                            style: GoogleFonts.urbanist(fontWeight: FontWeight.w800, fontSize: 13),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF7DD3A8),
                            side: const BorderSide(color: Color(0xFF7DD3A8)),
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
            ],
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

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Only the label is flexible (Expanded). Giving both label and
        // value a flex factor (previously Expanded + Flexible, both
        // defaulting to flex:1) splits the row 50/50 regardless of how
        // short the value actually is, leaving the value stranded mid-row
        // instead of pinned to the right edge like a label/value pair
        // should be. With just the label flexible, it eats exactly the
        // leftover space and the value sits flush right.
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.urbanist(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
          style: GoogleFonts.urbanist(
            fontSize: 15.0,
            fontWeight: FontWeight.w800,
            color: valueColor ?? Colors.white,
          ),
        ),
      ],
    );
  }
}

