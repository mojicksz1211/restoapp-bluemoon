import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Left-hand nav rail for the waiter app (tablet/desktop) — replaces the
/// old top AppBar + TabBar. Selecting an item just calls [onSelect], which
/// the caller wires to the same TabController the TabBarView already uses
/// (via controller.animateTo), so swiping and the "jump to New Orders" tap
/// on the incoming-order alert keep working unchanged.
class WaiterSidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  // Opens the shared settings sheet (same one menuApp uses) — logout lives
  // inside that sheet now instead of being its own row here.
  final VoidCallback onOpenSettings;
  // Manual data refresh — sits next to Settings at the bottom of the rail.
  final VoidCallback onRefresh;
  final double width;
  // Notification badge counts, keyed by the same index as _items
  // (0: Tables, 1: New Orders, 2: Order List). A null/zero count hides the
  // badge for that row.
  final int newOrdersCount;
  final int orderListCount;
  // Which Tables sub-filter is active ('all' | 'occupied' | 'available'),
  // only meaningful while selectedIndex == 0. Drives the "Occupied" /
  // "Available" submenu rows nested under "Tables".
  final String tableFilter;
  final ValueChanged<String> onSelectTableFilter;
  // Compact the header/logo/nav padding when the device is in landscape
  // orientation — vertical space is scarce on a tablet held sideways.
  final bool isLandscape;
  // 'gf', '2f', or null (unscoped). When set, the sub-nav rows for the
  // *other* floor are hidden — the account can only ever browse its own
  // floor's tables, since `_tables` itself is already restricted server-side
  // by the caller.
  final String? lockedFloor;

  const WaiterSidebar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.onOpenSettings,
    required this.onRefresh,
    this.width = 280,
    this.newOrdersCount = 0,
    this.orderListCount = 0,
    this.tableFilter = 'all',
    required this.onSelectTableFilter,
    this.isLandscape = false,
    this.lockedFloor,
  });

  static const navy = Color(0xFF0C0E2B);
  static const navyLight = Color(0xFF1B1E4A);
  static const gold = Color(0xFFE8C468);

  static const _items = <_NavItemData>[
    _NavItemData(Icons.table_bar_outlined, 'Tables'),
    _NavItemData(Icons.receipt_long_outlined, 'New Orders'),
    _NavItemData(Icons.list_alt_outlined, 'Order List'),
  ];

  @override
  Widget build(BuildContext context) {
    final isCompact = width <= 210;
    final isTight = isCompact || isLandscape;

    return Container(
      width: width,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [navy, navyLight],
        ),
        border: Border(right: BorderSide(color: Color(0x40E8C468), width: 1)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            Padding(
              padding: isTight
                  ? const EdgeInsets.fromLTRB(12, 12, 12, 8)
                  : const EdgeInsets.fromLTRB(16, 18, 16, 16),
              child: Column(
                children: [
                  if (!isLandscape)
                    Text(
                      'WAITER DASHBOARD',
                      style: GoogleFonts.urbanist(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        fontSize: isCompact ? 13 : 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  if (!isLandscape) SizedBox(height: isCompact ? 8 : 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: isTight ? 64 : 110,
                      height: isTight ? 64 : 110,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => SizedBox(
                        width: isTight ? 64 : 96,
                        height: isTight ? 64 : 96,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: gold.withValues(alpha: 0.15), height: 1, thickness: 1),
            SizedBox(height: isCompact ? 8 : 12),
            for (var i = 0; i < _items.length; i++) ...[
              _NavRow(
                icon: _items[i].icon,
                label: _items[i].label,
                // "Tables" only reads as selected when its own sub-filter
                // is 'all' — otherwise the Occupied/Available sub-row below
                // is the one that should show as active.
                isSelected: i == selectedIndex && (i != 0 || tableFilter == 'all'),
                onTap: () => onSelect(i),
                badgeCount: i == 1
                    ? newOrdersCount
                    : i == 2
                        ? orderListCount
                        : 0,
              ),
              if (i == 0) ...[
                if (lockedFloor != '2f') ...[
                  _SubNavRow(
                    label: 'GF Available',
                    isSelected: selectedIndex == 0 && tableFilter == 'gf_available',
                    onTap: () => onSelectTableFilter('gf_available'),
                  ),
                  _SubNavRow(
                    label: 'GF Occupied',
                    isSelected: selectedIndex == 0 && tableFilter == 'gf_occupied',
                    onTap: () => onSelectTableFilter('gf_occupied'),
                  ),
                ],
                if (lockedFloor != 'gf') ...[
                  _SubNavRow(
                    label: '2F Available',
                    isSelected: selectedIndex == 0 && tableFilter == '2f_available',
                    onTap: () => onSelectTableFilter('2f_available'),
                  ),
                  _SubNavRow(
                    label: '2F Occupied',
                    isSelected: selectedIndex == 0 && tableFilter == '2f_occupied',
                    onTap: () => onSelectTableFilter('2f_occupied'),
                  ),
                ],
              ],
            ],
            const Spacer(),
            _NavRow(
              icon: Icons.refresh,
              label: 'Refresh',
              isSelected: false,
              onTap: onRefresh,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              child: _NavRow(
                icon: Icons.settings_outlined,
                label: 'Settings',
                isSelected: false,
                onTap: onOpenSettings,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItemData {
  final IconData icon;
  final String label;
  const _NavItemData(this.icon, this.label);
}

// Indented submenu row nested under "Tables" (Occupied / Available). Same
// tap/selected-state pattern as _NavRow, just smaller and without its own
// icon — the indent alone reads as "child of Tables".
class _SubNavRow extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SubNavRow({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const gold = WaiterSidebar.gold;
    final color = isSelected ? gold : Colors.white.withValues(alpha: 0.65);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.fromLTRB(48, 9, 14, 9),
            decoration: BoxDecoration(
              color: isSelected ? gold.withValues(alpha: 0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.circle, size: 6, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.urbanist(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: color,
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
}

class _NavRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final int badgeCount;

  const _NavRow({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    const gold = WaiterSidebar.gold;
    final color = isSelected ? gold : Colors.white.withValues(alpha: 0.75);
    // In landscape mode the sidebar is passed `isLandscape` from the
    // parent; _NavRow doesn't have that context directly, but it reads from
    // the MediaQuery so we can tighten vertical padding automatically.
    final isCompact = MediaQuery.of(context).orientation == Orientation.landscape;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: isCompact ? 2 : 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: isCompact ? 9 : 14),
            decoration: BoxDecoration(
              color: isSelected ? gold.withValues(alpha: 0.14) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border(
                left: BorderSide(color: isSelected ? gold : Colors.transparent, width: 3),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 21, color: color),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.urbanist(
                      fontSize: 14.5,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: color,
                    ),
                  ),
                ),
                if (badgeCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    constraints: const BoxConstraints(minWidth: 20),
                    decoration: BoxDecoration(
                      color: gold,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badgeCount > 99 ? '99+' : '$badgeCount',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.urbanist(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: WaiterSidebar.navy,
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
}
