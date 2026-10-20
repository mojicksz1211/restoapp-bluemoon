import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models.dart' show formatPrice;
import '../services/room_time_alerts.dart';
import '../waiter_models.dart';

const _gold = Color(0xFFD97706);

/// "₱1,500/hr × 1 hr · since 8:47 PM · 25m used" — what one room of an order's
/// room-charge history was billed for, and when the order was in it.
/// [carriedTo] names the next room when this room's time was carried over to
/// it (moved before 30 minutes — see [roomTimeCarriedOver]).
String roomChargeDetail(RoomChargeSegment s, {String? carriedTo}) {
  final parts = <String>[
    if (carriedTo != null)
      'Under $kRoomCarryOverMinutes mins · time continued in $carriedTo'
    else if (s.hours <= 0)
      '₱${formatPrice(s.rate)}/hr · waived'
    else
      '₱${formatPrice(s.rate)}/hr × ${formatRoomHours(s.hours)}',
  ];
  final range = s.timeRangeLabel;
  if (range != null) parts.add(range);
  final used = s.liveMinutesUsed;
  if (s.startedAt != null && (s.isActive || s.endedAt != null)) {
    parts.add(s.isActive ? '${formatMinutesUsed(used)} used' : '${formatMinutesUsed(used)} there');
  }
  return parts.join('  ·  ');
}

/// One line per room an order's room charge was made in (oldest first), with
/// its hours, rate, time there and amount — plus any extra service charge.
/// Used by the waiter's order details and the cashier's card / settle sheet.
class RoomChargeHistory extends StatelessWidget {
  final WaiterOrder order;

  /// The order's table's hourly room charge, for orders with no recorded
  /// history (see [roomChargeSegmentsOf]).
  final double fallbackRate;

  /// Smaller text for order cards.
  final bool dense;

  const RoomChargeHistory({
    super.key,
    required this.order,
    this.fallbackRate = 0,
    this.dense = false,
  });

  /// Whether there is anything to show for [order].
  static bool hasContent(WaiterOrder order, {double fallbackRate = 0}) =>
      order.serviceCharge > 0.005 ||
      roomChargeSegmentsOf(order, fallbackRate: fallbackRate).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final segments = roomChargeSegmentsOf(order, fallbackRate: fallbackRate);
    final rows = <Widget>[];
    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      rows.add(_line(
        title: s.roomLabel,
        badge: s.isActive && segments.length > 1 ? 'NOW' : null,
        detail: roomChargeDetail(
          s,
          carriedTo: roomTimeCarriedOver(segments, i) ? segments[i + 1].roomLabel : null,
        ),
        amount: s.amount,
      ));
    }
    final other = segments.isEmpty ? order.serviceCharge : order.otherServiceCharge;
    if (other > 0.005) {
      rows.add(_line(title: 'Service charge', detail: null, amount: other, tag: 'FEE'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }

  Widget _line({
    required String title,
    String? badge,
    required String? detail,
    required double amount,
    String tag = 'ROOM',
  }) {
    final titleSize = dense ? 13.0 : 14.5;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 3 : 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 1),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              tag,
              style: GoogleFonts.urbanist(
                fontSize: dense ? 10 : 11,
                fontWeight: FontWeight.w900,
                color: _gold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.urbanist(
                          fontSize: titleSize,
                          fontWeight: FontWeight.w800,
                          color: _gold,
                        ),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: _gold,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badge,
                          style: GoogleFonts.urbanist(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (detail != null)
                  Text(
                    detail,
                    style: GoogleFonts.urbanist(
                      fontSize: dense ? 11 : 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '₱${formatPrice(amount)}',
            style: GoogleFonts.urbanist(
              fontSize: titleSize,
              fontWeight: FontWeight.w800,
              color: _gold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Live countdown of the room an open order is in ("1h 12m left"): amber in
/// the last 15 minutes, red once the booked time is over. Nothing for
/// regular tables or waived rooms. Refreshes itself every 15 seconds.
class RoomCountdownBadge extends StatefulWidget {
  final WaiterOrder order;
  final double fallbackRate;

  /// Light text/colors for dark (navy) backgrounds.
  final bool onDark;

  /// Smaller, for cards.
  final bool dense;

  const RoomCountdownBadge({
    super.key,
    required this.order,
    this.fallbackRate = 0,
    this.onDark = false,
    this.dense = false,
  });

  @override
  State<RoomCountdownBadge> createState() => _RoomCountdownBadgeState();
}

class _RoomCountdownBadgeState extends State<RoomCountdownBadge> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final countdown = RoomCountdown.of(widget.order, fallbackRate: widget.fallbackRate);
    if (countdown == null) return const SizedBox.shrink();
    final Color color;
    if (countdown.isOver) {
      color = widget.onDark ? const Color(0xFFFF8A8A) : const Color(0xFFDC2626);
    } else if (countdown.isEndingSoon) {
      color = widget.onDark ? const Color(0xFFFBBF24) : _gold;
    } else {
      color = widget.onDark ? const Color(0xFF7DD3A8) : const Color(0xFF059669);
    }
    final size = widget.dense ? 11.5 : 12.5;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: widget.dense ? 7 : 9, vertical: widget.dense ? 2.5 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: widget.onDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            countdown.isOver ? Icons.timer_off_rounded : Icons.timer_outlined,
            size: size + 2,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            countdown.label,
            style: GoogleFonts.urbanist(
              fontSize: size,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          if (!widget.dense) ...[
            Text(
              '  ·  ends ${formatClock(countdown.endsAt)}',
              style: GoogleFonts.urbanist(
                fontSize: size - 0.5,
                fontWeight: FontWeight.w700,
                color: color.withValues(alpha: 0.8),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
