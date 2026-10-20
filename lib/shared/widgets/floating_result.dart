import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _navy = Color(0xFF0C0E2B);
const _gold = Color(0xFFE8C468);
const _subtitle = Color(0xFF64748B);

/// Centered result card (Blue Moon logo in a gold ring with a check badge) on
/// a white card over a blurred, dimmed screen, so only the message stands out.
/// Fades away by itself; tapping anywhere closes it sooner.
/// [warning] swaps the green check for an amber clock, e.g. "saved offline".
void showFloatingResult(
  BuildContext context, {
  required String title,
  String? subtitle,
  bool warning = false,
  bool error = false,
  Duration duration = const Duration(milliseconds: 2000),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _FloatingResult(
      title: title,
      subtitle: subtitle,
      warning: warning,
      error: error,
      duration: duration,
      onDone: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

/// Same floating card for failures: red X badge, stays a bit longer so the
/// message can be read. Replaces the red snackbar.
void showFloatingError(
  BuildContext context, {
  required String message,
  String title = 'Something went wrong',
}) {
  showFloatingResult(
    context,
    title: title,
    subtitle: message,
    error: true,
    duration: const Duration(milliseconds: 3600),
  );
}

class _FloatingResult extends StatefulWidget {
  final String title;
  final String? subtitle;
  final bool warning;
  final bool error;
  final Duration duration;
  final VoidCallback onDone;

  const _FloatingResult({
    required this.title,
    required this.subtitle,
    required this.warning,
    required this.error,
    required this.duration,
    required this.onDone,
  });

  @override
  State<_FloatingResult> createState() => _FloatingResultState();
}

class _FloatingResultState extends State<_FloatingResult>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _timer = Timer(widget.duration, _close);
  }

  Future<void> _close() async {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    await _c.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final badgeColor = widget.error
        ? const Color(0xFFDC2626)
        : (widget.warning ? const Color(0xFFD97706) : const Color(0xFF16A34A));
    final fade = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Blurred, dimmed screen behind the card; a tap closes it early.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: AnimatedBuilder(
                animation: fade,
                builder: (context, _) => BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 8 * fade.value,
                    sigmaY: 8 * fade.value,
                  ),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.35 * fade.value),
                  ),
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Center(
              child: FadeTransition(
                opacity: fade,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.88, end: 1).animate(
                    CurvedAnimation(parent: _c, curve: Curves.easeOutBack),
                  ),
                  child: Container(
                    width: 260,
                    padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 36,
                          offset: const Offset(0, 16),
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
                            clipBehavior: Clip.none,
                            children: [
                              const SizedBox(
                                width: 86,
                                height: 86,
                                child: CircularProgressIndicator(
                                  value: 1,
                                  strokeWidth: 3.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    _gold,
                                  ),
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
                              Positioned(
                                right: -4,
                                bottom: -2,
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: badgeColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 3,
                                    ),
                                  ),
                                  child: Icon(
                                    widget.error
                                        ? Icons.close_rounded
                                        : (widget.warning
                                              ? Icons.schedule_rounded
                                              : Icons.check_rounded),
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          widget.title,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.urbanist(
                            color: _navy,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (widget.subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            widget.subtitle!,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.urbanist(
                              color: _subtitle,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
