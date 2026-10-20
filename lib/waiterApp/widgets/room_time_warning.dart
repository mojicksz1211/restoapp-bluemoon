import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/sound_service.dart';
import '../../shared/widgets/blurred_dialog.dart';
import '../services/room_time_alerts.dart';
import '../waiter_models.dart';

/// Watches the open orders of the waiter / cashier home page and, when a
/// room has 15 minutes or less of its booked time left, pops up "Room Time
/// Ending Soon" (with a chime + spoken announcement) so staff can ask the
/// guest whether to extend. One warning per booking — extending moves the end
/// time and re-arms it. Checks every 30 seconds while the app is on screen.
class RoomTimeWarningController {
  RoomTimeWarningController({
    required this.orders,
    required this.context,
    required this.fallbackRateFor,
    required this.onExtend,
  });

  /// The orders this device should be warned about (already floor-scoped).
  final Iterable<WaiterOrder> Function() orders;

  /// The page's context; null once it's gone.
  final BuildContext? Function() context;

  /// Hourly room charge of an order's table, for orders with no recorded
  /// room-charge history.
  final double Function(WaiterOrder order) fallbackRateFor;

  /// Opens the Room Charge dialog for [order].
  final Future<void> Function(WaiterOrder order) onExtend;

  Timer? _timer;
  bool _showing = false;
  final List<String> _queue = [];

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => check());
    // First pass once the page has loaded its orders.
    Future.delayed(const Duration(seconds: 3), check);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  RoomCountdown? _countdownFor(int orderId) {
    for (final o in orders()) {
      if (o.id == orderId) return RoomCountdown.of(o, fallbackRate: fallbackRateFor(o));
    }
    return null;
  }

  Future<void> check() async {
    if (_timer == null) return;
    // Only warn while the app is actually on screen; the background service
    // covers the rest (and this check runs again on the next tick).
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    for (final order in orders().toList()) {
      final c = RoomCountdown.of(order, fallbackRate: fallbackRateFor(order));
      if (c == null || !c.shouldWarn) continue;
      if (_queue.contains(c.alertKey)) continue;
      if (await RoomTimeAlertLog.claim(c.alertKey)) _queue.add(c.alertKey);
    }
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_showing) return;
    _showing = true;
    try {
      while (_queue.isNotEmpty) {
        final key = _queue.removeAt(0);
        final orderId = int.tryParse(key.split('|').first);
        // Still current? It may have been extended, moved or settled since.
        final c = orderId == null ? null : _countdownFor(orderId);
        if (c == null || c.alertKey != key || !c.shouldWarn) continue;
        final ctx = context();
        if (ctx == null || !ctx.mounted) break;
        SoundService.announceOnce(
          c.isOver
              ? '${c.roomName}, room time is up. Please ask the guest if they want to extend.'
              : '${c.roomName}, ${(c.remaining.inSeconds / 60).ceil()} minutes left. Please ask the guest if they want to extend.',
        );
        final extend = await showRoomTimeWarning(ctx, c);
        if (extend) {
          final latest = _countdownFor(c.order.id)?.order ?? c.order;
          await onExtend(latest);
        }
      }
    } finally {
      _showing = false;
    }
  }
}

const _navy = Color(0xFF0C0E2B);
const _navy2 = Color(0xFF1B1E4A);
const _amber = Color(0xFFD97706);
const _red = Color(0xFFDC2626);

/// "Room Time Ending Soon" / "Room Time Is Up" popup (waiter and cashier
/// apps): a white card that springs in, with a pulsing, ringing timer and a
/// live countdown. Returns true when Extend was tapped (the caller then opens
/// the Room Charge dialog).
Future<bool> showRoomTimeWarning(
  BuildContext context,
  RoomCountdown countdown,
) async {
  final extend = await showBlurredDialog<bool>(
    context,
    barrierDismissible: false,
    builder: (ctx) => _RoomTimeWarningDialog(countdown: countdown),
  );
  return extend == true;
}

class _RoomTimeWarningDialog extends StatefulWidget {
  final RoomCountdown countdown;

  const _RoomTimeWarningDialog({required this.countdown});

  @override
  State<_RoomTimeWarningDialog> createState() => _RoomTimeWarningDialogState();
}

class _RoomTimeWarningDialogState extends State<_RoomTimeWarningDialog>
    with TickerProviderStateMixin {
  // Expanding rings behind the timer icon.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  // Alarm-clock ring: a short shake, then a pause, on repeat.
  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  // Keeps the countdown live while the popup is open.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pulse.dispose();
    _ring.dispose();
    super.dispose();
  }

  /// Shake during the first 35% of each cycle, still for the rest.
  double _shakeAngle(double t) {
    if (t > 0.35) return 0;
    final p = t / 0.35;
    return math.sin(p * math.pi * 6) * 0.22 * (1 - p);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.countdown;
    final isOver = c.isOver;
    final accent = isOver ? _red : _amber;
    final orderLabel = c.order.orderNo ?? '#${c.order.id}';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 40,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildIcon(accent, isOver),
                  const SizedBox(height: 16),
                  Text(
                    isOver ? 'Room Time Is Up' : 'Room Time Ending Soon',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.urbanist(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${c.roomName}  •  $orderLabel',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.urbanist(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.9, end: 1).animate(anim),
                        child: child,
                      ),
                    ),
                    child: Text(
                      c.label,
                      key: ValueKey(c.label),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.urbanist(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: accent,
                        height: 1.1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Booked time ends at ${formatClock(c.endsAt)}',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.urbanist(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: accent.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.record_voice_over_rounded,
                          size: 20,
                          color: accent,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Please inform the guest and ask if they want to extend.',
                            style: GoogleFonts.urbanist(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: _navy,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _navy,
                            side: const BorderSide(color: _navy, width: 1.5),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            'Later',
                            style: GoogleFonts.urbanist(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: const LinearGradient(
                              colors: [_navy, _navy2],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _navy.withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.of(context).pop(true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.more_time_rounded, size: 18),
                            label: Text(
                              'Extend',
                              style: GoogleFonts.urbanist(
                                fontWeight: FontWeight.w900,
                                fontSize: 14.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(Color accent, bool isOver) {
    return SizedBox(
      width: 96,
      height: 96,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulse, _ring]),
        builder: (context, _) {
          Widget ring(double phase) {
            final t = (_pulse.value + phase) % 1.0;
            return Opacity(
              opacity: (1 - t) * 0.45,
              child: Container(
                width: 64 + 32 * t,
                height: 64 + 32 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accent, width: 2),
                ),
              ),
            );
          }

          return Stack(
            alignment: Alignment.center,
            children: [
              ring(0),
              ring(0.5),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.12),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: Transform.rotate(
                  angle: _shakeAngle(_ring.value),
                  child: Icon(
                    isOver ? Icons.timer_off_rounded : Icons.alarm_rounded,
                    size: 32,
                    color: accent,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
