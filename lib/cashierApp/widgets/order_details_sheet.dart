import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../waiterApp/models.dart' show formatPrice;
import '../../waiterApp/waiter_models.dart';
import '../../shared/widgets/blurred_dialog.dart';
import '../../waiterApp/widgets/room_charge_history.dart' show roomChargeDetail, RoomCountdownBadge;

/// Full breakdown of one order, opened by tapping an order card in the
/// cashier app: every item (qty × unit price), the room/service charge
/// split, tax, discount and the total due — plus payment details for
/// settled orders.
class OrderDetailsSheet extends StatelessWidget {
  final WaiterOrder order;

  /// Base per-session room charge of the order's table (0 for regular
  /// tables) — splits SERVICE_CHARGE into "₱1,500 × 2".
  final double roomChargeRate;

  /// 'GF' / '2F' badge shown next to the table name.
  final String floorLabel;
  final bool isHistory;
  final VoidCallback? onSettle;

  const OrderDetailsSheet({
    super.key,
    required this.order,
    required this.roomChargeRate,
    required this.floorLabel,
    this.isHistory = false,
    this.onSettle,
  });

  static Future<void> show(
    BuildContext context, {
    required WaiterOrder order,
    required double roomChargeRate,
    required String floorLabel,
    bool isHistory = false,
    VoidCallback? onSettle,
  }) {
    return showBlurredDialog<void>(
      context,
      useRootNavigator: false,
      builder: (_) => OrderDetailsSheet(
        order: order,
        roomChargeRate: roomChargeRate,
        floorLabel: floorLabel,
        isHistory: isHistory,
        onSettle: onSettle,
      ),
    );
  }

  static const _navy = Color(0xFF0C0E2B);
  static const _navy2 = Color(0xFF1B1E4A);
  static const _gold = Color(0xFFD97706);
  static const _amber = Color(0xFFFBBF24);
  static const _ink = Color(0xFF1E293B);
  static const _muted = Color(0xFF64748B);
  static const _line = Color(0xFFE2E8F0);
  static const _added = Color(0xFF2563EB);
  static const _discount = Color(0xFF16A34A);

  /// Room-charge units in SERVICE_CHARGE when it divides evenly into the
  /// base rate (0.5 steps, matching the card); null otherwise.
  double? get _roomChargeUnits {
    final rate = roomChargeRate;
    final total = order.serviceCharge;
    if (rate <= 0 || total <= 0) return null;
    final q = total / rate;
    final rounded = (q * 2).round() / 2;
    if (rounded >= 0.5 && (q - rounded).abs() < 0.01) return rounded;
    return null;
  }

  /// How much less than one full session a room is billed, as a percent:
  /// 100 when the room charge was waived (set to 0), 50 for half a session.
  /// Null when it isn't discounted (or the table isn't a room).
  double? get _roomDiscountPercent {
    final rate = roomChargeRate;
    if (rate <= 0) return null;
    final billed = order.serviceCharge;
    if (billed >= rate - 0.005) return null;
    return ((1 - billed / rate) * 100).clamp(0, 100).toDouble();
  }

  /// Rooms always list their room charge — also when it was waived (₱0) —
  /// so a discount is visible instead of the charge silently disappearing.
  bool get _showCharges =>
      order.serviceCharge > 0 || roomChargeRate > 0 || order.roomCharges.isNotEmpty;

  /// Room hours booked in total ("2.5 hrs"), shown next to the room charge;
  /// null when unknown.
  String? get _roomHoursLabel {
    final hours = order.totalRoomHours ?? _roomChargeUnits;
    if (hours == null) return null;
    return formatRoomHours(hours);
  }

  String _percentLabel(double pct) =>
      '${pct % 1 == 0 ? pct.toInt() : pct.toStringAsFixed(1)}% LESS';

  String _units(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);

  String _qty(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(2);

  double get _itemsTotal =>
      order.items.fold<double>(0, (sum, item) => sum + item.lineTotal);

  double get _itemCount =>
      order.items.fold<double>(0, (sum, item) => sum + item.quantity);

  String get _tableTitle {
    var name = (order.tableNumber ?? '').trim();
    if (name.toLowerCase().startsWith('table')) name = name.substring(5).trim();
    if (name.isNotEmpty) return name;
    return order.isTakeOut
        ? order.takeOutLabel
        : (order.orderType ?? 'Dine-In');
  }

  String get _tableKicker {
    final hasTable = (order.tableNumber ?? '').trim().isNotEmpty;
    return hasTable ? 'Table' : 'Type';
  }

  String _orderTypeLabel() {
    final raw = (order.orderType ?? '').trim();
    if (raw.isEmpty) return 'Dine In';
    return raw
        .toLowerCase()
        .split(RegExp(r'[\s_]+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  String _openedAtLabel() {
    final dt = order.gmt8DateTime;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final h12 = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final min = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '${months[dt.month - 1]} ${dt.day}, $h12:$min $period';
  }

  /// "1h 25m" since the order was opened (Manila time on both sides, so a
  /// tablet set to another timezone still gets it right).
  String? _openForLabel() {
    final opened = order.gmt8DateTime;
    final nowPh = DateTime.now().toUtc().add(const Duration(hours: 8));
    final openedNaive = DateTime(
      opened.year,
      opened.month,
      opened.day,
      opened.hour,
      opened.minute,
      opened.second,
    );
    final nowNaive = DateTime(
      nowPh.year,
      nowPh.month,
      nowPh.day,
      nowPh.hour,
      nowPh.minute,
      nowPh.second,
    );
    final diff = nowNaive.difference(openedNaive);
    if (diff.isNegative) return null;
    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;
    if (hours == 0) return '${diff.inMinutes}m';
    return '${hours}h ${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final narrow = media.size.width < 520;
    // First order + each later addition, when items were added after it.
    final batches = order.itemBatches;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: narrow ? 12 : 24,
        vertical: 24,
      ),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: media.size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  narrow ? 16 : 22,
                  18,
                  narrow ? 16 : 22,
                  8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel(
                      'ORDER BREAKDOWN',
                      trailing:
                          '${_qty(_itemCount)} item${_itemCount == 1 ? '' : 's'}',
                    ),
                    const SizedBox(height: 8),
                    _breakdownCard(batches),
                    const SizedBox(height: 16),
                    _summaryBox(),
                    if (isHistory || order.status == 1) ...[
                      const SizedBox(height: 14),
                      _paymentBox(),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            _buildFooter(context, narrow: narrow),
          ],
        ),
      ),
    );
  }

  // ==================== Header ====================

  Widget _buildHeader(BuildContext context) {
    final openFor = isHistory ? null : _openForLabel();
    final creator = (order.encodedByName ?? '').trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_navy, _navy2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.table_restaurant_rounded,
                  color: _amber,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _tableKicker,
                          style: GoogleFonts.urbanist(
                            color: _amber,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            letterSpacing: 0.8,
                          ),
                        ),
                        Text(
                          '  •  ',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                            fontSize: 11,
                          ),
                        ),
                        Flexible(
                          child: Text(
                            order.orderNo ?? '#${order.id}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.urbanist(
                              color: Colors.white60,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _tableTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.urbanist(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _darkChip(floorLabel),
                        const SizedBox(width: 6),
                        _statusChip(order.status),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white70,
                  size: 22,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _metaChip(Icons.schedule_rounded, _openedAtLabel()),
              if (openFor != null)
                _metaChip(Icons.timelapse_rounded, 'Open $openFor'),
              _metaChip(Icons.restaurant_menu_rounded, _orderTypeLabel()),
              if (creator.isNotEmpty)
                _metaChip(Icons.person_outline_rounded, creator),
              if (!isHistory)
                RoomCountdownBadge(
                  order: order,
                  fallbackRate: roomChargeRate,
                  onDark: true,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _darkChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.urbanist(
          color: Colors.white70,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _statusChip(int status) {
    final (label, color) = switch (status) {
      1 => ('SETTLED', const Color(0xFF2E8B57)),
      2 => ('CONFIRMED', const Color(0xFFDAA520)),
      3 => ('PENDING', _navy),
      -1 => ('CANCELLED', Colors.red.shade700),
      _ => ('UNKNOWN', Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.urbanist(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 10,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white60),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.urbanist(
              color: Colors.white.withValues(alpha: 0.85),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== Body ====================

  Widget _sectionLabel(String label, {String? trailing}) {
    return Row(
      children: [
        Text(
          label,
          style: GoogleFonts.urbanist(
            color: _muted,
            fontSize: 11.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const Spacer(),
        if (trailing != null)
          Text(
            trailing,
            style: GoogleFonts.urbanist(
              color: _muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }

  // ==================== Breakdown ====================

  static const _tabular = [FontFeature.tabularFigures()];

  /// The whole breakdown in one card, read like an invoice: a slim band per
  /// section (the first order, each addition, charges) and plain rows under
  /// it — qty · item · amount — so prices sit in one column to scan.
  Widget _breakdownCard(List<OrderItemBatch> batches) {
    final children = <Widget>[];
    var firstBand = true;

    void band({
      required String label,
      String? time,
      String? trailing,
      bool added = false,
      bool charge = false,
    }) {
      children.add(
        _sectionBand(
          label: label,
          time: time,
          trailing: trailing,
          added: added,
          charge: charge,
          first: firstBand,
        ),
      );
      firstBand = false;
    }

    void rows(List<Widget> lines) {
      for (var i = 0; i < lines.length; i++) {
        if (i > 0) {
          children.add(
            const Divider(
              height: 1,
              thickness: 1,
              indent: 16,
              endIndent: 16,
              color: Color(0xFFF1F5F9),
            ),
          );
        }
        children.add(lines[i]);
      }
    }

    if (order.items.isEmpty) {
      band(label: 'ITEMS');
      rows([
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Text(
            'No items in this order yet.',
            style: GoogleFonts.urbanist(
              fontSize: 13.5,
              color: Colors.grey.shade500,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ]);
    } else if (batches.length <= 1) {
      band(label: 'ITEMS', trailing: _countAndAmount(_itemCount, _itemsTotal));
      rows(order.items.map(_itemLine).toList());
    } else {
      for (var i = 0; i < batches.length; i++) {
        final batch = batches[i];
        band(
          label: batch.isInitial
              ? 'FIRST ORDER'
              : (batches.length > 2 ? 'ADDED #$i' : 'ADDED'),
          time: batch.timeLabel,
          trailing: _countAndAmount(batch.quantity, batch.subtotal),
          added: !batch.isInitial,
        );
        rows(batch.items.map(_itemLine).toList());
      }
    }

    if (_showCharges) {
      final hours = _roomHoursLabel;
      band(
        label: order.roomCharges.length > 1 ? 'ROOM CHARGES' : 'CHARGES',
        charge: true,
        trailing: hours == null ? null : '$hours total',
      );
      rows(order.roomCharges.isEmpty ? [_chargeLine()] : _roomHistoryLines());
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  String _countAndAmount(double qty, double amount) =>
      '${_qty(qty)} item${qty == 1 ? '' : 's'}  ·  ₱${formatPrice(amount)}';

  Widget _sectionBand({
    required String label,
    String? time,
    String? trailing,
    bool added = false,
    bool charge = false,
    bool first = false,
  }) {
    final fg = added ? _added : (charge ? _gold : _muted);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
      decoration: BoxDecoration(
        color: added
            ? const Color(0xFFEFF6FF)
            : (charge ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC)),
        border: Border(
          top: first ? BorderSide.none : const BorderSide(color: _line),
          bottom: const BorderSide(color: _line),
        ),
      ),
      child: Row(
        children: [
          if (added) ...[
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: _added,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: GoogleFonts.urbanist(
              color: fg,
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
            ),
          ),
          if (time != null)
            Text(
              '   $time',
              style: GoogleFonts.urbanist(
                color: fg.withValues(alpha: 0.85),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          const Spacer(),
          if (trailing != null)
            Text(
              trailing,
              style: GoogleFonts.urbanist(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFeatures: _tabular,
              ),
            ),
        ],
      ),
    );
  }

  /// qty · name (+ unit price when more than one, + note) · amount.
  Widget _breakdownLine({
    required String qty,
    required String name,
    String? detail,
    String? note,
    required String amount,
    Color? accent,
    String? originalAmount,
    String? tag,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Text(
              qty,
              style: GoogleFonts.urbanist(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: accent ?? _muted,
                fontFeatures: _tabular,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.urbanist(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: accent ?? _ink,
                      ),
                    ),
                    if (tag != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _discount.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          tag,
                          style: GoogleFonts.urbanist(
                            color: _discount,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                  ],
                ),
                if (detail != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      detail,
                      style: GoogleFonts.urbanist(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _muted,
                        fontFeatures: _tabular,
                      ),
                    ),
                  ),
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.sticky_note_2_outlined,
                            size: 13,
                            color: _gold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            note,
                            style: GoogleFonts.urbanist(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              fontStyle: FontStyle.italic,
                              color: _gold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (originalAmount != null)
                Text(
                  originalAmount,
                  style: GoogleFonts.urbanist(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _muted,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: _muted,
                    fontFeatures: _tabular,
                  ),
                ),
              Text(
                amount,
                style: GoogleFonts.urbanist(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: accent ?? _ink,
                  fontFeatures: _tabular,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _itemLine(WaiterOrderItem item) {
    final remarks = (item.remarks ?? '').trim();
    final unitPrice = item.unitPrice > 0
        ? item.unitPrice
        : (item.quantity > 0 ? item.lineTotal / item.quantity : 0);
    return _breakdownLine(
      qty: '${_qty(item.quantity)}×',
      name: item.name,
      detail: item.quantity == 1 ? null : '₱${formatPrice(unitPrice)} each',
      note: remarks.isEmpty ? null : remarks,
      amount: '₱${formatPrice(item.lineTotal)}',
    );
  }

  /// One line per room the room charge was made in (the room's rate, hours,
  /// when the order was there) — plus any extra service charge.
  List<Widget> _roomHistoryLines() {
    final lines = <Widget>[];
    final segments = order.roomCharges;
    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      final carried = roomTimeCarriedOver(segments, i);
      lines.add(_breakdownLine(
        qty: s.hours <= 0 ? '0h' : '${_units(s.hours)}h',
        name: segments.length > 1 && s.isActive
            ? '${s.roomLabel}  (now)'
            : s.roomLabel,
        tag: s.hours <= 0 && !carried ? '100% LESS' : null,
        detail: roomChargeDetail(
          s,
          carriedTo: carried ? segments[i + 1].roomLabel : null,
        ),
        amount: '₱${formatPrice(s.amount)}',
        accent: _gold,
      ));
    }
    final other = order.otherServiceCharge;
    if (other > 0) {
      lines.add(_breakdownLine(
        qty: '',
        name: 'Service charge',
        detail: 'Added to this order',
        amount: '₱${formatPrice(other)}',
        accent: _gold,
      ));
    }
    return lines;
  }

  Widget _chargeLine() {
    final isRoom = roomChargeRate > 0;
    final units = _roomChargeUnits;
    final discount = _roomDiscountPercent;
    if (discount != null) {
      // Billed under one session: show the full session struck through.
      final waived = order.serviceCharge <= 0.005;
      final billedUnits =
          (order.serviceCharge / roomChargeRate * 2).round() / 2;
      return _breakdownLine(
        qty: '${_units(billedUnits)}h',
        name: 'Room charge',
        tag: _percentLabel(discount),
        detail: waived
            ? '₱${formatPrice(roomChargeRate)}/hr  ·  waived'
            : '₱${formatPrice(roomChargeRate)}/hr × ${formatRoomHours(billedUnits)}  ·  discounted',
        amount: '₱${formatPrice(order.serviceCharge)}',
        originalAmount: '₱${formatPrice(roomChargeRate)}',
        accent: _gold,
      );
    }
    final String detail;
    if (isRoom && units != null) {
      detail = '₱${formatPrice(roomChargeRate)}/hr × ${formatRoomHours(units)}';
    } else if (isRoom) {
      detail = 'Base rate ₱${formatPrice(roomChargeRate)}';
    } else {
      detail = 'Added to this order';
    }
    return _breakdownLine(
      qty: units != null ? '${_units(units)}h' : '',
      name: isRoom ? 'Room charge' : 'Service charge',
      detail: detail,
      amount: '₱${formatPrice(order.serviceCharge)}',
      accent: _gold,
    );
  }

  Widget _summaryRow(
    String label,
    String value, {
    Color? valueColor,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.urbanist(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _muted,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(width: 6),
            Text(
              hint,
              style: GoogleFonts.urbanist(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade400,
              ),
            ),
          ],
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.urbanist(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: valueColor ?? _ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryBox() {
    final subtotal = order.subtotal > 0 ? order.subtotal : _itemsTotal;
    final isRoom = roomChargeRate > 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Column(
        children: [
          _summaryRow(
            'Items subtotal',
            '₱${formatPrice(subtotal)}',
            hint: '(${_qty(_itemCount)})',
          ),
          if (_showCharges)
            _summaryRow(
              isRoom || order.roomCharges.isNotEmpty ? 'Room charge' : 'Service charge',
              '₱${formatPrice(order.serviceCharge)}',
              valueColor: _gold,
              hint: order.roomCharges.isEmpty && _roomDiscountPercent != null
                  ? '(${_percentLabel(_roomDiscountPercent!).toLowerCase()})'
                  : (_roomHoursLabel == null ? null : '($_roomHoursLabel)'),
            ),
          if (order.taxAmount > 0)
            _summaryRow('Tax', '₱${formatPrice(order.taxAmount)}'),
          if (order.discountAmount > 0)
            _summaryRow(
              'Discount',
              '−₱${formatPrice(order.discountAmount)}',
              valueColor: Colors.red.shade600,
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: _line),
          ),
          Row(
            children: [
              Text(
                isHistory || order.status == 1 ? 'TOTAL' : 'TOTAL DUE',
                style: GoogleFonts.urbanist(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: _muted,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              Text(
                '₱${formatPrice(order.grandTotal)}',
                style: GoogleFonts.urbanist(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: _gold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _paymentBox() {
    final method = (order.paymentMethod ?? '').trim();
    final ref = (order.paymentRef ?? '').trim();
    final change = order.amountPaid - order.grandTotal;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF2E8B57).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF2E8B57).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('PAYMENT'),
          const SizedBox(height: 6),
          if (method.isNotEmpty) _summaryRow('Method', method.toUpperCase()),
          if (order.amountPaid > 0)
            _summaryRow('Amount paid', '₱${formatPrice(order.amountPaid)}'),
          if (order.amountPaid > 0 && change > 0.009)
            _summaryRow('Change', '₱${formatPrice(change)}'),
          if (ref.isNotEmpty) _summaryRow('Reference', ref),
          if (method.isEmpty && order.amountPaid <= 0 && ref.isEmpty)
            _summaryRow('Details', 'Not available'),
        ],
      ),
    );
  }

  // ==================== Footer ====================

  Widget _buildFooter(BuildContext context, {required bool narrow}) {
    final canAct = !isHistory && order.status != 1 && order.status != -1;
    final closeButton = OutlinedButton(
      onPressed: () => Navigator.of(context).pop(),
      style: OutlinedButton.styleFrom(
        foregroundColor: _navy,
        side: BorderSide(color: Colors.grey.shade300),
        minimumSize: const Size(0, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        'Close',
        style: GoogleFonts.urbanist(fontWeight: FontWeight.w800, fontSize: 14),
      ),
    );

    return Container(
      padding: EdgeInsets.fromLTRB(narrow ? 16 : 22, 12, narrow ? 16 : 22, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: !canAct
          ? SizedBox(width: double.infinity, child: closeButton)
          : Row(
              children: [
                Expanded(child: closeButton),
                if (onSettle != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    flex: narrow ? 1 : 2,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onSettle!();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _navy,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        minimumSize: const Size(0, 46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.payments_rounded, size: 18),
                      label: Text(
                        narrow
                            ? 'Settle'
                            : 'Settle ₱${formatPrice(order.grandTotal)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.urbanist(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
