import 'package:flutter/material.dart';

import 'center_popup_card.dart';

/// Shows a centered, animated popup notification (scale + fade in over a
/// dimmed backdrop) instead of an edge-docked SnackBar/banner — used for
/// "new order" events (order placed, items added, new order received) so
/// they're hard to miss instead of blending into a corner.
///
/// Stays open until the user closes it (tap the X, or tap outside the
/// card) — no auto-dismiss timer, so it can't disappear before it's read.
///
/// Self-contained: inserted into the app's root Overlay and manages its own
/// AnimationController internally, so the caller doesn't need a
/// TickerProvider and the popup survives the calling page being popped
/// (e.g. GetOrderPage popping itself right after placing an order).
void showCenterPopup(
  BuildContext context, {
  required IconData icon,
  required Color accentColor,
  required String title,
  String? subtitle,
  String? actionLabel,
  VoidCallback? onAction,
  bool shakeIcon = false,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _CenterPopupOverlay(
      icon: icon,
      accentColor: accentColor,
      title: title,
      subtitle: subtitle,
      actionLabel: actionLabel,
      onAction: onAction,
      shakeIcon: shakeIcon,
      onClosed: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _CenterPopupOverlay extends StatefulWidget {
  final IconData icon;
  final Color accentColor;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool shakeIcon;
  final VoidCallback onClosed;

  const _CenterPopupOverlay({
    required this.icon,
    required this.accentColor,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    required this.shakeIcon,
    required this.onClosed,
  });

  @override
  State<_CenterPopupOverlay> createState() => _CenterPopupOverlayState();
}

class _CenterPopupOverlayState extends State<_CenterPopupOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    _controller.reverse().whenComplete(widget.onClosed);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: FadeTransition(
        opacity: _fade,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _close,
          child: Container(
            color: Colors.black.withValues(alpha: 0.35),
            child: Center(
              child: GestureDetector(
                // Absorb taps on the card itself so they don't fall through
                // to the scrim's dismiss-on-tap-outside above.
                onTap: () {},
                child: ScaleTransition(
                  scale: _scale,
                  child: CenterPopupCard(
                    icon: widget.icon,
                    accentColor: widget.accentColor,
                    title: widget.title,
                    subtitle: widget.subtitle,
                    actionLabel: widget.actionLabel,
                    onAction: widget.onAction == null
                        ? null
                        : () {
                            widget.onAction!();
                            _close();
                          },
                    onClose: _close,
                    shakeIcon: widget.shakeIcon,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
