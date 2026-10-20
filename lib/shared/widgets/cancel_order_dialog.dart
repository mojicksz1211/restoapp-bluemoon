import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'blurred_dialog.dart';

const _navy = Color(0xFF0C0E2B);
const _red = Color(0xFFDC2626);
const _muted = Color(0xFF64748B);

/// "Cancel this order?" confirmation, shared by the waiter and cashier apps:
/// a white card over a blurred, dimmed screen. Returns true only when the
/// user taps the red confirm button.
Future<bool> showCancelOrderConfirm(
  BuildContext context, {
  required String orderLabel,
  String? tableName,
}) async {
  final result = await showBlurredDialog<bool>(
    context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
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
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _red.withValues(alpha: 0.1),
                  border: Border.all(color: _red.withValues(alpha: 0.4), width: 1.5),
                ),
                child: const Icon(Icons.delete_outline_rounded, color: _red, size: 36),
              ),
              const SizedBox(height: 16),
              Text(
                'Cancel this order?',
                textAlign: TextAlign.center,
                style: GoogleFonts.urbanist(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  color: _navy,
                ),
              ),
              const SizedBox(height: 12),
              // Which order, so the wrong card can't be cancelled by mistake.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    if (tableName != null && tableName.isNotEmpty)
                      Text(
                        tableName.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.urbanist(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: _navy,
                          letterSpacing: 1,
                        ),
                      ),
                    Text(
                      orderLabel,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.urbanist(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'The order will be marked as cancelled.',
                textAlign: TextAlign.center,
                style: GoogleFonts.urbanist(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: _muted,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _navy,
                        side: const BorderSide(color: _navy, width: 1.5),
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        'Keep Order',
                        style: GoogleFonts.urbanist(fontWeight: FontWeight.w800, fontSize: 15.5),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: _red,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        'Yes, Cancel',
                        style: GoogleFonts.urbanist(fontWeight: FontWeight.w900, fontSize: 15.5),
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
  );
  return result == true;
}
