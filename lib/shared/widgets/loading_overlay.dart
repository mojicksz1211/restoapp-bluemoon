import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _navy = Color(0xFF0C0E2B);
const _gold = Color(0xFFE8C468);
const _subtitle = Color(0xFF64748B);

/// Just opens the loading card (root navigator, not dismissible). The caller
/// closes it with `Navigator.of(context, rootNavigator: true).pop()`. Use
/// [runWithLoader] instead when the work fits in a single async task.
/// White card over a blurred, dimmed screen — same look as the result popup
/// (floating_result.dart) that usually follows it.
void showLoadingDialog(BuildContext context, String message) {
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Loading',
    barrierColor: Colors.transparent,
    useRootNavigator: true,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => PopScope(
      canPop: false,
      child: _LoaderCard(message: message),
    ),
    transitionBuilder: (_, anim, _, child) {
      final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);
      return Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: 8 * fade.value,
                sigmaY: 8 * fade.value,
              ),
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.35 * fade.value),
              ),
            ),
          ),
          FadeTransition(
            opacity: fade,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.9, end: 1).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
              ),
              child: child,
            ),
          ),
        ],
      );
    },
  );
}

/// Shows a blocking "please wait" dialog (Blue Moon logo inside a spinning gold
/// ring) while [task] runs, then closes it and returns the task's result.
/// The dialog can't be dismissed, so a double tap can't fire the action twice.
Future<T> runWithLoader<T>(
  BuildContext context, {
  required String message,
  required Future<T> Function() task,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  showLoadingDialog(context, message);
  try {
    return await task();
  } finally {
    // The route was pushed synchronously above, so it is always on top here.
    if (navigator.mounted) navigator.pop();
  }
}

class _LoaderCard extends StatelessWidget {
  final String message;
  const _LoaderCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 240,
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 32,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 86,
                height: 86,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const SizedBox(
                      width: 86,
                      height: 86,
                      child: CircularProgressIndicator(
                        strokeWidth: 3.5,
                        strokeCap: StrokeCap.round,
                        valueColor: AlwaysStoppedAnimation<Color>(_gold),
                        backgroundColor: Color(0x33E8C468),
                      ),
                    ),
                    ClipOval(
                      child: Image.asset(
                        'assets/images/logo.png',
                        width: 66,
                        height: 66,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.urbanist(
                  color: _navy,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Please wait…',
                style: GoogleFonts.urbanist(
                  color: _subtitle,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
