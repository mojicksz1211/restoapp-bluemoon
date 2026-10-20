import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/widgets/blurred_dialog.dart';
import '../models.dart';
import '../waiter_models.dart' show formatRoomHours;

// White card over a blurred, dimmed screen — same look as the app's other
// popups (loading, results, cancel confirmation).
const _navy = Color(0xFF0C0E2B);
const _navyLight = Color(0xFF1B1E4A);
const _gold = Color(0xFFE8C468);
const _amber = Color(0xFFD97706);
const _red = Color(0xFFDC2626);
const _muted = Color(0xFF64748B);

/// Room charge adjuster for an open order: starts at the hours the room it's
/// in now is billed for (1 session = 1 hour) and goes up or down in 0.5 steps
/// — down to 0, the room charge waived (100% less) — same as the waiter's
/// new-order cart and the admin's manual-order stepper. [currentRoomCharge]
/// is that room's charge; [earlierRoomCharge] what rooms the order moved out
/// of were billed (unchanged here). Returns the room's new total hours, or
/// `null` when cancelled or unchanged.
Future<double?> showRoomChargeAdjust(
  BuildContext context, {
  required String tableName,
  required String orderLabel,
  required double roomCharge,
  required double currentRoomCharge,
  double earlierRoomCharge = 0,
}) {
  return showBlurredDialog<double>(
    context,
    useRootNavigator: false,
    builder: (ctx) => _ExtendQtyDialog(
      tableName: tableName,
      orderLabel: orderLabel,
      roomCharge: roomCharge,
      currentRoomCharge: currentRoomCharge,
      earlierRoomCharge: earlierRoomCharge,
    ),
  );
}

String _fmtQty(double v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);

class _ExtendQtyDialog extends StatefulWidget {
  final String tableName;
  final String orderLabel;
  final double roomCharge;
  final double currentRoomCharge;
  final double earlierRoomCharge;

  const _ExtendQtyDialog({
    required this.tableName,
    required this.orderLabel,
    required this.roomCharge,
    required this.currentRoomCharge,
    this.earlierRoomCharge = 0,
  });

  @override
  State<_ExtendQtyDialog> createState() => _ExtendQtyDialogState();
}

class _ExtendQtyDialogState extends State<_ExtendQtyDialog> {
  static const double _maxSessions = 20;

  /// Hours the room is billed for now (its room charge ÷ the hourly rate).
  late final double _current = widget.roomCharge > 0
      ? (widget.currentRoomCharge / widget.roomCharge * 2).round() / 2
      : 0;

  /// The new total — starts at the current one; Update stays disabled until
  /// it actually changes.
  late double _qty = _current;

  @override
  Widget build(BuildContext context) {
    final newCharge = widget.roomCharge * _qty;
    final change = newCharge - widget.roomCharge * _current;
    final String changeLabel;
    if (change.abs() < 0.005) {
      changeLabel = 'No change';
    } else if (change > 0) {
      changeLabel = '+ ₱${formatPrice(change)}';
    } else {
      changeLabel = '− ₱${formatPrice(-change)}';
    }
    return _ExtendDialogShell(
      icon: Icons.more_time_rounded,
      showLogo: true,
      title: 'Room Charge',
      accent: _gold,
      subtitle: '${widget.tableName} • ${widget.orderLabel}',
      body: Column(
        children: [
          _QtyStepper(
            qty: _qty,
            onDecrement: _qty > 0 ? () => setState(() => _qty = (_qty - 0.5).clamp(0, _maxSessions)) : null,
            onIncrement: _qty < _maxSessions
                ? () => setState(() => _qty = (_qty + 0.5).clamp(0, _maxSessions))
                : null,
          ),
          const SizedBox(height: 6),
          Text(
            '₱${formatPrice(widget.roomCharge)} per hour  •  0 = waived (100% less)',
            textAlign: TextAlign.center,
            style: GoogleFonts.urbanist(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: _muted,
            ),
          ),
          const SizedBox(height: 14),
          _BreakdownBox(
            rows: [
              if (widget.earlierRoomCharge > 0.005)
                _BreakdownRow(
                  'Earlier rooms',
                  '₱${formatPrice(widget.earlierRoomCharge)}',
                ),
              _BreakdownRow(
                'Current (${formatRoomHours(_current)})',
                '₱${formatPrice(widget.currentRoomCharge)}',
              ),
              _BreakdownRow('Change', changeLabel, accent: true),
              _BreakdownRow(
                _qty == 0 ? 'New room charge (waived)' : 'New room charge (${formatRoomHours(_qty)})',
                '₱${formatPrice(newCharge)}',
                emphasize: true,
              ),
            ],
          ),
        ],
      ),
      primaryLabel: 'Update',
      onPrimary: _qty != _current ? () => Navigator.of(context).pop(_qty) : null,
      secondaryLabel: 'Cancel',
      onSecondary: () => Navigator.of(context).pop(),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  final double qty;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;

  const _QtyStepper({required this.qty, required this.onDecrement, required this.onIncrement});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Hours',
          style: GoogleFonts.urbanist(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _muted,
          ),
        ),
        const SizedBox(width: 16),
        _StepperButton(icon: Icons.remove_rounded, onTap: onDecrement),
        SizedBox(
          width: 48,
          child: Text(
            _fmtQty(qty),
            textAlign: TextAlign.center,
            style: GoogleFonts.urbanist(fontSize: 18, fontWeight: FontWeight.w900, color: _navy),
          ),
        ),
        _StepperButton(icon: Icons.add_rounded, onTap: onIncrement),
      ],
    );
  }
}

/// Navy circle with a white icon — same as the cart sheet's steppers.
class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _StepperButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _navy.withValues(alpha: enabled ? 1 : 0.2),
          ),
          child: Icon(icon, size: 20, color: Colors.white),
        ),
      ),
    );
  }
}

/// Success dialog after a room charge is changed. [added] is negative when
/// it went down; a [newRoomCharge] of 0 means it was waived.
Future<void> showRoomChargeExtendedResult(
  BuildContext context, {
  required String tableName,
  required double added,
  required double newRoomCharge,
  required double newGrandTotal,
  double? units,
}) {
  final waived = newRoomCharge.abs() < 0.005;
  final title = waived
      ? 'Room Charge Waived'
      : (added < 0 ? 'Room Charge Reduced' : 'Room Charge Extended');
  return showBlurredDialog<void>(
    context,
    useRootNavigator: false,
    builder: (ctx) => _ExtendDialogShell(
      icon: Icons.check_rounded,
      showLogo: true,
      title: title,
      accent: _gold,
      subtitle: !waived && units != null
          ? '$tableName • now ${formatRoomHours(units)}'
          : tableName,
      body: _BreakdownBox(
        rows: [
          _BreakdownRow(
            'Change',
            added < 0 ? '− ₱${formatPrice(-added)}' : '+ ₱${formatPrice(added)}',
            accent: true,
          ),
          _BreakdownRow(
            'Room charge total',
            waived ? 'Waived (₱0.00)' : '₱${formatPrice(newRoomCharge)}',
          ),
          _BreakdownRow('New order total', '₱${formatPrice(newGrandTotal)}', emphasize: true),
        ],
      ),
      primaryLabel: 'Done',
      onPrimary: () => Navigator.of(ctx).pop(),
    ),
  );
}

/// Error dialog when extending fails.
Future<void> showExtendRoomChargeError(BuildContext context, String message) {
  return showBlurredDialog<void>(
    context,
    useRootNavigator: false,
    builder: (ctx) => _ExtendDialogShell(
      icon: Icons.error_outline_rounded,
      title: 'Update Failed',
      accent: _red,
      subtitle: message,
      primaryLabel: 'Close',
      onPrimary: () => Navigator.of(ctx).pop(),
    ),
  );
}

class _ExtendDialogShell extends StatelessWidget {
  final IconData icon;
  final bool showLogo;
  final String title;
  final String subtitle;
  final Color accent;
  final Widget? body;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const _ExtendDialogShell({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.primaryLabel,
    required this.onPrimary,
    this.showLogo = false,
    this.body,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    // Decode the badge bitmap at the exact pixel size it will occupy on this
    // screen (logical size × device pixel ratio) so it maps ~1:1 instead of
    // the GPU shrinking the full 1024px asset down and smearing it.
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final logoCachePx = (70 * (dpr <= 0 ? 1 : dpr)).ceil();
    final enabled = onPrimary != null;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(clipBehavior: Clip.none, child: Container(
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
              Container(
                width: 74,
                height: 74,
                padding: showLogo ? const EdgeInsets.all(3) : EdgeInsets.zero,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.12),
                  border: Border.all(color: accent.withValues(alpha: showLogo ? 0.9 : 0.4), width: 1.5),
                ),
                child: showLogo
                    ? ClipOval(
                        child: Image.asset(
                          'assets/images/logo.png',
                          fit: BoxFit.cover,
                          cacheWidth: logoCachePx,
                          cacheHeight: logoCachePx,
                          filterQuality: FilterQuality.high,
                          isAntiAlias: true,
                        ),
                      )
                    : Icon(icon, color: accent, size: 34),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.urbanist(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: _navy,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.urbanist(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: _muted,
                ),
              ),
              if (body != null) ...[
                const SizedBox(height: 18),
                body!,
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  if (secondaryLabel != null) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onSecondary,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _navy,
                          side: const BorderSide(color: _navy, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          secondaryLabel!,
                          style: GoogleFonts.urbanist(fontWeight: FontWeight.w800, fontSize: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: enabled ? const LinearGradient(colors: [_navy, _navyLight]) : null,
                        color: enabled ? null : const Color(0xFFE2E8F0),
                      ),
                      child: ElevatedButton(
                        onPressed: onPrimary,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.transparent,
                          disabledForegroundColor: _muted,
                          shadowColor: Colors.transparent,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          primaryLabel,
                          style: GoogleFonts.urbanist(fontWeight: FontWeight.w900, fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),),
      ),
    );
  }
}

class _BreakdownRow {
  final String label;
  final String value;
  final bool accent;
  final bool emphasize;
  const _BreakdownRow(this.label, this.value, {this.accent = false, this.emphasize = false});
}

class _BreakdownBox extends StatelessWidget {
  final List<_BreakdownRow> rows;
  const _BreakdownBox({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1, color: Color(0xFFE2E8F0)),
              ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    rows[i].label,
                    style: GoogleFonts.urbanist(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _muted,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  rows[i].value,
                  style: GoogleFonts.urbanist(
                    fontSize: rows[i].emphasize ? 16 : 13.5,
                    fontWeight: rows[i].emphasize ? FontWeight.w900 : FontWeight.w800,
                    color: rows[i].accent ? _amber : _navy,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
