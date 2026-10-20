import '../../shared/widgets/loading_overlay.dart';
import '../../shared/widgets/floating_result.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models.dart' show formatPrice;
import '../waiter_models.dart';
import '../services/api_service.dart';
import '../../shared/widgets/blurred_dialog.dart';

Future<bool?> showTransferTableModal({
  required BuildContext context,
  required int orderId,
  required String currentTableName,
  int? currentTableId,
  required List<WaiterTable> allTables,
  // The order being moved — lets the sheet work out the room charge when a
  // room is involved (time spent in the current room, its rate).
  WaiterOrder? order,
}) async {
  return showBlurredBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (modalContext) {
      return _TransferTableSheet(
        orderId: orderId,
        currentTableName: currentTableName,
        currentTableId: currentTableId,
        allTables: allTables,
        order: order,
      );
    },
  );
}

class _TransferTableSheet extends StatefulWidget {
  final int orderId;
  final String currentTableName;
  final int? currentTableId;
  final List<WaiterTable> allTables;
  final WaiterOrder? order;

  const _TransferTableSheet({
    required this.orderId,
    required this.currentTableName,
    this.currentTableId,
    required this.allTables,
    this.order,
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
  static const _amber = Color(0xFFD97706);
  static const double _maxHours = 20;

  // Room charge on a move that involves a room: the room being left is billed
  // for the time spent there (whole half-hours — 37 min → 30 mins) and the new
  // room starts a fresh session (1 hr). Room-to-room before 30 minutes, the
  // time carries over instead: the old room is billed nothing and the new room
  // continues the same clock and booked hours at its own rate. Set when a
  // table is picked ([_resetRoomHours]); both adjustable before confirming.
  double _prevHours = 0;
  double _newHours = 1;

  WaiterTable? _tableById(int? id) {
    if (id == null) return null;
    for (final t in widget.allTables) {
      if (t.id == id) return t;
    }
    return null;
  }

  WaiterTable? get _targetTable => _tableById(_selectedTargetTableId);

  RoomChargeSegment? get _currentRoom => widget.order?.currentRoomCharge;

  double get _sourceRate {
    final active = _currentRoom;
    if (active != null) return active.rate;
    final order = widget.order;
    if (order != null && order.roomCharges.isNotEmpty) return 0; // already moved out of its last room
    return _tableById(widget.currentTableId)?.roomCharge ?? order?.roomCharge ?? 0;
  }

  double get _targetRate => _targetTable?.roomCharge ?? 0;

  bool get _isOpenOrder {
    final status = widget.order?.status;
    return status == null || status == 2 || status == 3;
  }

  bool get _showRoomCharge =>
      widget.order != null &&
      _isOpenOrder &&
      _selectedTargetTableId != null &&
      (_sourceRate > 0 || _targetRate > 0);

  /// Minutes the order has been in its current room.
  int get _minutesInRoom {
    final active = _currentRoom;
    if (active != null && active.startedAt != null) return active.liveMinutesUsed;
    final order = widget.order;
    if (order == null) return 0;
    final m = manilaNow().difference(order.gmt8DateTime).inMinutes;
    return m < 0 ? 0 : m;
  }

  /// Hours the current room is billed for now.
  double get _bookedHours {
    final active = _currentRoom;
    if (active != null) return active.hours;
    final order = widget.order;
    final rate = _sourceRate;
    if (order == null || rate <= 0) return 0;
    return (order.serviceCharge / rate * 2).round() / 2;
  }

  /// Room-to-room before 30 minutes: the time carries over to the new room.
  bool get _carryOver =>
      _sourceRate > 0 && _targetRate > 0 && _minutesInRoom < kRoomCarryOverMinutes;

  /// When the order's clock in its current room started (Manila time).
  DateTime? get _roomStartedAt => _currentRoom?.startedAt ?? widget.order?.gmt8DateTime;

  void _resetRoomHours() {
    if (_carryOver) {
      _prevHours = 0;
      _newHours = _bookedHours > 0 ? _bookedHours : 1;
    } else {
      _prevHours = _defaultPrevHours;
      _newHours = 1;
    }
  }

  double get _defaultPrevHours {
    if (_sourceRate <= 0) return 0;
    // A waived room (0 hrs) stays waived unless staff change it.
    if (_bookedHours <= 0) return 0;
    return billableRoomHours(_minutesInRoom);
  }

  /// Room charge after the move, for the preview.
  double get _roomChargeAfter {
    final order = widget.order;
    if (order == null) return 0;
    final earlier = order.roomCharges
        .where((s) => !s.isActive)
        .fold<double>(0, (sum, s) => sum + s.amount);
    final double other;
    if (order.roomCharges.isNotEmpty) {
      other = order.otherServiceCharge;
    } else if (_sourceRate > 0) {
      other = (order.serviceCharge - _bookedHours * _sourceRate).clamp(0.0, double.infinity).toDouble();
    } else {
      other = order.serviceCharge;
    }
    return earlier +
        _prevHours * _sourceRate +
        (_targetRate > 0 ? _newHours * _targetRate : 0) +
        other;
  }

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
      final result = await runWithLoader<Map<String, dynamic>>(
        context,
        message: 'Transferring table…',
        task: () => ApiService.transferTableOrder(
          orderId: widget.orderId,
          targetTableId: _selectedTargetTableId!,
          prevRoomHours: _showRoomCharge && _sourceRate > 0 ? _prevHours : null,
          newRoomHours: _showRoomCharge && _targetRate > 0 ? _newHours : null,
          carryOverTime: _showRoomCharge && _sourceRate > 0 && _targetRate > 0 ? _carryOver : null,
        ),
      );

      if (!mounted) return;
      setState(() => _isTransferring = false);

      if (result['unauthorized'] == true) {
        showFloatingError(
          context,
          title: 'Session expired',
          message: 'Please login again.',
        );
        return;
      }

      if (result['success'] == true) {
        // Insert into the root overlay first (it outlives this sheet), then
        // close the sheet.
        showFloatingResult(
          context,
          title: 'Table Transferred',
          subtitle: (result['message'] ?? 'Order moved to the new table.').toString(),
        );
        Navigator.pop(context, true);
      } else {
        showFloatingError(
          context,
          title: 'Transfer failed',
          message: (result['error'] ?? 'Failed to transfer table').toString(),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isTransferring = false);
      showFloatingError(context, title: 'Transfer failed', message: e.toString());
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
                                if (_selectedTargetTableId != table.id) {
                                  _selectedTargetTableId = table.id;
                                  _resetRoomHours();
                                }
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
                                        if (table.hasRoomCharge) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            '₱${formatPrice(table.roomCharge)}/hr',
                                            style: GoogleFonts.urbanist(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w800,
                                              color: isSelected ? _gold : _amber,
                                            ),
                                          ),
                                        ] else if (table.capacity > 0) ...[
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
            if (_showRoomCharge) _buildRoomChargePanel(isMobile),
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

  Widget _buildRoomChargePanel(bool isMobile) {
    final targetName = (_targetTable?.number ?? '').trim();
    final sourceName = widget.currentTableName.trim();
    final before = widget.order?.serviceCharge ?? 0;
    final after = _roomChargeAfter;
    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(isMobile ? 14 : 20, 0, isMobile ? 14 : 20, 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _amber.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.more_time_rounded, size: 16, color: _amber),
              const SizedBox(width: 6),
              Text(
                'ROOM CHARGE',
                style: GoogleFonts.urbanist(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  color: _amber,
                  letterSpacing: 1.1,
                ),
              ),
              const Spacer(),
              Text(
                (after - before).abs() < 0.005
                    ? '₱${formatPrice(after)}'
                    : '₱${formatPrice(before)} → ₱${formatPrice(after)}',
                style: GoogleFonts.urbanist(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: _navy,
                ),
              ),
            ],
          ),
          if (_sourceRate > 0) ...[
            const SizedBox(height: 8),
            _roomHoursRow(
              title: sourceName.isEmpty ? 'Current room' : sourceName,
              subtitle: _carryOver
                  ? 'In room ${formatMinutesUsed(_minutesInRoom)} · under $kRoomCarryOverMinutes mins, time continues in ${targetName.isEmpty ? 'the new room' : targetName}'
                  : 'In room ${formatMinutesUsed(_minutesInRoom)} · billed for time used · ₱${formatPrice(_sourceRate)}/hr',
              hours: _prevHours,
              rate: _sourceRate,
              onChanged: (v) => setState(() => _prevHours = v),
            ),
          ],
          if (_targetRate > 0) ...[
            const SizedBox(height: 8),
            _roomHoursRow(
              title: targetName.isEmpty ? 'New room' : targetName,
              subtitle: _carryOver && _roomStartedAt != null
                  ? 'Continues from ${formatClock(_roomStartedAt!)} · ₱${formatPrice(_targetRate)}/hr'
                  : 'New session · ₱${formatPrice(_targetRate)}/hr',
              hours: _newHours,
              rate: _targetRate,
              onChanged: (v) => setState(() => _newHours = v),
            ),
          ],
        ],
      ),
    );
  }

  Widget _roomHoursRow({
    required String title,
    required String subtitle,
    required double hours,
    required double rate,
    required ValueChanged<double> onChanged,
  }) {
    Widget stepButton(IconData icon, VoidCallback? onTap) {
      final enabled = onTap != null;
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
            border: Border.all(
              color: enabled ? _amber.withValues(alpha: 0.5) : Colors.grey.shade300,
            ),
          ),
          child: Icon(icon, size: 16, color: enabled ? _amber : Colors.grey.shade400),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.urbanist(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: _navy,
                ),
              ),
              Text(
                subtitle,
                style: GoogleFonts.urbanist(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        stepButton(
          Icons.remove_rounded,
          hours > 0 ? () => onChanged((hours - 0.5).clamp(0, _maxHours).toDouble()) : null,
        ),
        SizedBox(
          width: 62,
          child: Text(
            hours <= 0 ? 'Waived' : formatRoomHours(hours),
            textAlign: TextAlign.center,
            style: GoogleFonts.urbanist(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: _navy,
            ),
          ),
        ),
        stepButton(
          Icons.add_rounded,
          hours < _maxHours ? () => onChanged((hours + 0.5).clamp(0, _maxHours).toDouble()) : null,
        ),
        SizedBox(
          width: 78,
          child: Text(
            '₱${formatPrice(rate * hours)}',
            textAlign: TextAlign.right,
            style: GoogleFonts.urbanist(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: _amber,
            ),
          ),
        ),
      ],
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
