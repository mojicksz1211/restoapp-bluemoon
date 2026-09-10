import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models.dart';

// Shared palette — matches the waiter table cards (navy gradient + gold accent).
const _navy = Color(0xFF0C0E2B);
const _navyLight = Color(0xFF1B1E4A);
const _gold = Color(0xFFE8C468);

/// Confirmation shown before extending a room's charge. Returns `true` when
/// the waiter confirms.
Future<bool?> showExtendRoomChargeConfirm(
  BuildContext context, {
  required String tableName,
  required String orderLabel,
  required double roomCharge,
  required double currentRoomCharge,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _ExtendDialogShell(
      icon: Icons.more_time_rounded,
      showLogo: true,
      title: 'Extend Room Charge',
      accent: _gold,
      subtitle: '$tableName • $orderLabel',
      body: _BreakdownBox(
        rows: [
          _BreakdownRow('Current room charge', '₱${formatPrice(currentRoomCharge)}'),
          _BreakdownRow('Additional session', '+ ₱${formatPrice(roomCharge)}', accent: true),
          _BreakdownRow(
            'Total Room Charge',
            '₱${formatPrice(currentRoomCharge + roomCharge)}',
            emphasize: true,
          ),
        ],
      ),
      primaryLabel: 'Extend',
      onPrimary: () => Navigator.of(ctx).pop(true),
      secondaryLabel: 'Cancel',
      onSecondary: () => Navigator.of(ctx).pop(false),
    ),
  );
}

/// Success dialog after a room charge is extended.
Future<void> showRoomChargeExtendedResult(
  BuildContext context, {
  required String tableName,
  required double added,
  required double newRoomCharge,
  required double newGrandTotal,
  int? units,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _ExtendDialogShell(
      icon: Icons.check_rounded,
      showLogo: true,
      title: 'Room Charge Extended',
      accent: _gold,
      subtitle: units != null && units > 1
          ? '$tableName • now ×$units sessions'
          : tableName,
      body: _BreakdownBox(
        rows: [
          _BreakdownRow('Added', '+ ₱${formatPrice(added)}', accent: true),
          _BreakdownRow('Room charge total', '₱${formatPrice(newRoomCharge)}'),
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
  return showDialog<void>(
    context: context,
    builder: (ctx) => _ExtendDialogShell(
      icon: Icons.error_outline_rounded,
      title: 'Extend Failed',
      accent: const Color(0xFFEF6B6B),
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
  final VoidCallback onPrimary;
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
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_navy, _navyLight],
            ),
            border: Border.all(color: _gold.withValues(alpha: 0.3), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
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
                  color: accent.withValues(alpha: 0.16),
                  border: Border.all(color: accent.withValues(alpha: 0.5), width: 1.5),
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
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.urbanist(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: _gold.withValues(alpha: 0.9),
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
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
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
                    child: ElevatedButton(
                      onPressed: onPrimary,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _gold,
                        foregroundColor: _navy,
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
                ],
              ),
            ],
          ),
        ),
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
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
              ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    rows[i].label,
                    style: GoogleFonts.urbanist(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  rows[i].value,
                  style: GoogleFonts.urbanist(
                    fontSize: rows[i].emphasize ? 16 : 13.5,
                    fontWeight: rows[i].emphasize ? FontWeight.w900 : FontWeight.w800,
                    color: rows[i].accent
                        ? _gold
                        : (rows[i].emphasize ? Colors.white : Colors.white.withValues(alpha: 0.92)),
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
