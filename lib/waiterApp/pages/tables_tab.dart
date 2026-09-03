import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../waiter_models.dart';
import '../widgets/waiter_ui.dart';

class TablesTab extends StatelessWidget {
  final List<WaiterTable> tables;
  final List<WaiterOrder> orders;
  final StatusInfo Function(int status) statusInfoFor;
  final void Function(WaiterTable table) onViewDetails;
  final void Function(WaiterTable table) onGetOrder;
  final void Function(WaiterTable table) onAddOrder;
  final void Function(WaiterTable table) onEditOrder;
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

  const TablesTab({
    super.key,
    required this.tables,
    required this.orders,
    required this.statusInfoFor,
    required this.onViewDetails,
    required this.onGetOrder,
    required this.onAddOrder,
    required this.onEditOrder,
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
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: title,
            subtitle: '${tables.length} tables',
          ),
          if (showFilterChips && onFilterChanged != null) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  _buildFilterChip(
                    key: 'all',
                    label: 'All',
                    count: totalAllCount,
                    icon: Icons.table_bar_rounded,
                  ),
                  _buildFilterChip(
                    key: 'gf_available',
                    label: 'GF Available',
                    count: totalGfAvailableCount,
                    icon: Icons.check_circle_outline_rounded,
                    accentColor: Colors.green.shade700,
                  ),
                  _buildFilterChip(
                    key: 'gf_occupied',
                    label: 'GF Occupied',
                    count: totalGfOccupiedCount,
                    icon: Icons.person_rounded,
                    accentColor: Colors.orange.shade700,
                  ),
                  _buildFilterChip(
                    key: '2f_available',
                    label: '2F Available',
                    count: total2fAvailableCount,
                    icon: Icons.check_circle_outline_rounded,
                    accentColor: Colors.green.shade700,
                  ),
                  _buildFilterChip(
                    key: '2f_occupied',
                    label: '2F Occupied',
                    count: total2fOccupiedCount,
                    icon: Icons.person_rounded,
                    accentColor: Colors.orange.shade700,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          _buildTablesGrid(context),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String key,
    required String label,
    required int count,
    required IconData icon,
    Color? accentColor,
  }) {
    final isSelected = currentFilter == key;
    return Container(
      margin: const EdgeInsets.only(right: 10, top: 3, bottom: 3),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          onTap: () => onFilterChanged?.call(key),
          borderRadius: BorderRadius.circular(28),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: isSelected
                  ? const LinearGradient(
                      colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)],
                    )
                  : null,
              color: isSelected ? null : Colors.white,
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF0C0E2B)
                    : (accentColor != null ? accentColor.withValues(alpha: 0.5) : Colors.grey.shade300),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: isSelected
                      ? const Color(0xFF0C0E2B).withValues(alpha: 0.25)
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
                      ? const Color(0xFFE8C468)
                      : (accentColor ?? const Color(0xFF0C0E2B)),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: GoogleFonts.urbanist(
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    color: isSelected ? Colors.white : const Color(0xFF0C0E2B),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.2)
                        : (accentColor != null ? accentColor.withValues(alpha: 0.12) : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: GoogleFonts.urbanist(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? Colors.white
                          : (accentColor ?? Colors.grey.shade700),
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

  Widget _buildTablesGrid(BuildContext context) {
    if (tables.isEmpty) {
      return EmptyState(message: emptyMessage);
    }

    final tableOrderStatus = _buildTableOrderStatus();

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
          itemCount: tables.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 255,
          ),
          itemBuilder: (context, index) {
            final table = tables[index];
            final statusInfo = statusInfoFor(table.status);
            final orderStatusInfo = tableOrderStatus[table.id] ??
                const StatusInfo('No Order', Colors.grey);
            return _TableCard(
              table: table,
              statusInfo: statusInfo,
              orderStatusInfo: orderStatusInfo,
              orders: orders,
              onViewDetails: onViewDetails,
              onGetOrder: onGetOrder,
              onAddOrder: onAddOrder,
              onEditOrder: onEditOrder,
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
  final void Function(WaiterTable table) onViewDetails;
  final void Function(WaiterTable table) onGetOrder;
  final void Function(WaiterTable table) onAddOrder;
  final void Function(WaiterTable table) onEditOrder;

  const _TableCard({
    required this.table,
    required this.statusInfo,
    required this.orderStatusInfo,
    required this.orders,
    required this.onViewDetails,
    required this.onGetOrder,
    required this.onAddOrder,
    required this.onEditOrder,
  });

  static const _navy = Color(0xFF0C0E2B);
  static const _navyLight = Color(0xFF1B1E4A);
  static const _gold = Color(0xFFE8C468);

  @override
  Widget build(BuildContext context) {
    final isAvailable = table.status == 1;
    final actionLabel = isAvailable ? 'Get Order' : 'View Details';

    final rawName = table.number.trim();
    final cleanTableName = rawName.toLowerCase().startsWith('table')
        ? rawName.substring(5).trim()
        : rawName;

    return Material(
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
              const SizedBox(height: 10),
              _InfoRow(
                label: 'Order Status',
                value: orderStatusInfo.label,
                valueColor: orderStatusInfo.color,
              ),
              const SizedBox(height: 6),
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
                  ],
                ),
            ],
          ),
        ),
      ),
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

