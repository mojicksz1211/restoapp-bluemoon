import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../waiter_models.dart';
import '../services/api_service.dart';
import 'center_popup.dart';

Future<bool?> showTransferTableModal({
  required BuildContext context,
  required int orderId,
  required String currentTableName,
  int? currentTableId,
  required List<WaiterTable> allTables,
}) async {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (modalContext) {
      return _TransferTableSheet(
        orderId: orderId,
        currentTableName: currentTableName,
        currentTableId: currentTableId,
        allTables: allTables,
      );
    },
  );
}

class _TransferTableSheet extends StatefulWidget {
  final int orderId;
  final String currentTableName;
  final int? currentTableId;
  final List<WaiterTable> allTables;

  const _TransferTableSheet({
    required this.orderId,
    required this.currentTableName,
    this.currentTableId,
    required this.allTables,
  });

  @override
  State<_TransferTableSheet> createState() => _TransferTableSheetState();
}

class _TransferTableSheetState extends State<_TransferTableSheet> {
  int? _selectedTargetTableId;
  String _selectedFloorFilter = 'all';
  bool _isTransferring = false;

  static const _navy = Color(0xFF0C0E2B);
  static const _gold = Color(0xFFE8C468);

  List<WaiterTable> get _availableTables {
    // Only available tables (status == 1) and not the current table
    return widget.allTables.where((t) {
      if (widget.currentTableId != null && t.id == widget.currentTableId) {
        return false;
      }
      return t.status == 1;
    }).toList();
  }

  List<WaiterTable> get _filteredTables {
    final available = _availableTables;
    if (_selectedFloorFilter == 'ground') {
      return available.where((t) {
        final numStr = t.number.toLowerCase();
        return !numStr.contains('2nd') && !numStr.contains('room') && !numStr.contains('vip');
      }).toList();
    }
    if (_selectedFloorFilter == 'second') {
      return available.where((t) {
        final numStr = t.number.toLowerCase();
        return numStr.contains('2nd') || numStr.startsWith('2');
      }).toList();
    }
    if (_selectedFloorFilter == 'vip') {
      return available.where((t) {
        final numStr = t.number.toLowerCase();
        return numStr.contains('room') || numStr.contains('vip') || numStr.contains('family');
      }).toList();
    }
    return available;
  }

  Future<void> _handleTransfer() async {
    if (_selectedTargetTableId == null) return;

    setState(() => _isTransferring = true);

    try {
      final result = await ApiService.transferTableOrder(
        orderId: widget.orderId,
        targetTableId: _selectedTargetTableId!,
      );

      if (!mounted) return;
      setState(() => _isTransferring = false);

      if (result['unauthorized'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session expired. Please login again.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (result['success'] == true) {
        Navigator.pop(context, true);
        showCenterPopup(
          context,
          icon: Icons.check_circle_rounded,
          accentColor: Colors.green,
          title: 'Table Transferred!',
          subtitle: result['message'] ?? 'Order successfully moved to new table.',
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error'] ?? 'Failed to transfer table'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isTransferring = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error transferring table: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final filtered = _filteredTables;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFF5F6F0),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 18 : 24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _gold.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.swap_horiz_rounded,
                      color: Color(0xFFB45309),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Transfer Table',
                          style: GoogleFonts.urbanist(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: _navy,
                          ),
                        ),
                        Text(
                          'From: ${widget.currentTableName}',
                          style: GoogleFonts.urbanist(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 22),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Filter chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 18 : 24),
              child: Row(
                children: [
                  _buildFilterChip('all', 'All Available (${_availableTables.length})'),
                  const SizedBox(width: 8),
                  _buildFilterChip('ground', 'Ground Floor'),
                  const SizedBox(width: 8),
                  _buildFilterChip('second', '2nd Floor'),
                  const SizedBox(width: 8),
                  _buildFilterChip('vip', 'VIP / Rooms'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            // Available Tables Grid
            Flexible(
              child: filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.table_bar_outlined, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              'No available tables in this section',
                              style: GoogleFonts.urbanist(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: _navy,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : GridView.builder(
                      padding: EdgeInsets.fromLTRB(
                        isMobile ? 14 : 20,
                        14,
                        isMobile ? 14 : 20,
                        14,
                      ),
                      shrinkWrap: true,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: isMobile ? 3 : 5,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 1.15,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final table = filtered[index];
                        final isSelected = _selectedTargetTableId == table.id;

                        final rawName = table.number.trim();
                        final cleanTableName = rawName.toLowerCase().startsWith('table')
                            ? rawName.substring(5).trim()
                            : rawName;

                        return Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedTargetTableId = table.id;
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                gradient: isSelected
                                    ? const LinearGradient(
                                        colors: [_navy, Color(0xFF1B1E4A)],
                                      )
                                    : null,
                                color: isSelected ? null : Colors.white,
                                border: Border.all(
                                  color: isSelected ? _gold : Colors.grey.shade300,
                                  width: isSelected ? 2 : 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: isSelected
                                        ? _navy.withValues(alpha: 0.22)
                                        : Colors.black.withValues(alpha: 0.03),
                                    blurRadius: isSelected ? 7 : 3,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Stack(
                                children: [
                                  Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          cleanTableName,
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.urbanist(
                                            fontSize: 15,
                                            height: 1.05,
                                            fontWeight: FontWeight.w900,
                                            color: isSelected ? Colors.white : _navy,
                                          ),
                                        ),
                                        if (table.capacity > 0) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            '${table.capacity} seats',
                                            style: GoogleFonts.urbanist(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w600,
                                              color: isSelected
                                                  ? Colors.white.withValues(alpha: 0.7)
                                                  : Colors.grey.shade500,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    const Positioned(
                                      top: 0,
                                      right: 0,
                                      child: Icon(
                                        Icons.check_circle_rounded,
                                        color: _gold,
                                        size: 16,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            // Bottom Action Bar
            Container(
              padding: EdgeInsets.fromLTRB(
                isMobile ? 16 : 24,
                12,
                isMobile ? 16 : 24,
                isMobile ? 16 : 24,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Colors.grey.shade400),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.urbanist(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: _selectedTargetTableId != null && !_isTransferring
                            ? const LinearGradient(colors: [_navy, Color(0xFF1B1E4A)])
                            : null,
                        color: _selectedTargetTableId == null || _isTransferring
                            ? Colors.grey.shade300
                            : null,
                        boxShadow: [
                          if (_selectedTargetTableId != null && !_isTransferring)
                            BoxShadow(
                              color: _navy.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _selectedTargetTableId != null && !_isTransferring
                            ? _handleTransfer
                            : null,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shadowColor: Colors.transparent,
                          disabledForegroundColor: Colors.grey.shade500,
                          disabledBackgroundColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isTransferring
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Text(
                                'Confirm Transfer',
                                style: GoogleFonts.urbanist(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
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

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _selectedFloorFilter == key;
    return InkWell(
      onTap: () => setState(() => _selectedFloorFilter = key),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? _navy : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? _navy : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.urbanist(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected ? Colors.white : _navy,
          ),
        ),
      ),
    );
  }
}
