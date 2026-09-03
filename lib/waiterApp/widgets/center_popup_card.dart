import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _navy = Color(0xFF0C0E2B);

/// Shared visual for center-screen popup notifications ("Order placed
/// successfully", "New Order Received!") — a rounded card with an
/// accent-colored icon badge, title, optional subtitle, and an optional
/// action button. Positioning/animation/dismissal is handled by the caller
/// (see center_popup.dart, or home_page.dart's own AnimationController).
class CenterPopupCard extends StatefulWidget {
  final IconData icon;
  final Color accentColor;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onClose;
  // "New Order Received!" wants the bell to ring/shake so it reads as an
  // alert, not a static icon — off by default so other popups (e.g. the
  // green checkmark on "Order Placed Successfully") stay still.
  final bool shakeIcon;

  const CenterPopupCard({
    super.key,
    required this.icon,
    required this.accentColor,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    required this.onClose,
    this.shakeIcon = false,
  });

  @override
  State<CenterPopupCard> createState() => _CenterPopupCardState();
}

class _CenterPopupCardState extends State<CenterPopupCard> with SingleTickerProviderStateMixin {
  late final AnimationController _shakeController;
  late final Animation<double> _shake;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    // A short shake burst (the first ~45% of the cycle) followed by an idle
    // hold, looped — reads as a bell "ringing" every couple seconds instead
    // of shaking nonstop.
    _shake = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -0.14), weight: 4),
      TweenSequenceItem(tween: Tween(begin: -0.14, end: 0.14), weight: 6),
      TweenSequenceItem(tween: Tween(begin: 0.14, end: -0.1), weight: 6),
      TweenSequenceItem(tween: Tween(begin: -0.1, end: 0.1), weight: 5),
      TweenSequenceItem(tween: Tween(begin: 0.1, end: 0.0), weight: 4),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 25),
    ]).animate(_shakeController);
    if (widget.shakeIcon) {
      _shakeController.repeat();
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Material(
          color: Colors.transparent,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 40,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: widget.accentColor.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      // Only the icon itself rocks, top-pivoted so it reads
                      // as the bell's clapper swinging — the badge circle
                      // stays put instead of the whole thing swaying.
                      child: Center(
                        child: AnimatedBuilder(
                          animation: _shake,
                          builder: (context, child) => Transform.rotate(
                            angle: _shake.value,
                            alignment: Alignment.topCenter,
                            child: child,
                          ),
                          child: Icon(widget.icon, color: widget.accentColor, size: 52),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.urbanist(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: _navy,
                      ),
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        widget.subtitle!,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.urbanist(fontSize: 16, color: Colors.grey[600]),
                      ),
                    ],
                    if (widget.actionLabel != null) ...[
                      const SizedBox(height: 26),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: widget.onAction,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _navy,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text(
                            widget.actionLabel!,
                            style: GoogleFonts.urbanist(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Positioned(
                top: 14,
                right: 14,
                child: InkWell(
                  onTap: widget.onClose,
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.close, size: 22, color: Colors.grey[700]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
