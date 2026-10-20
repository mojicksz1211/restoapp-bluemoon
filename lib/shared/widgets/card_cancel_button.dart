import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Round "cancel order" X that sits on the top-right corner of an order/table
/// card. 44x44 hit area (the visible circle is 36) and it must be placed
/// INSIDE the parent Stack's bounds -- a button hanging outside the Stack is
/// not tappable, which is what made the old 26px one so hard to press.
class CardCancelButton extends StatelessWidget {
  final VoidCallback? onTap;

  const CardCancelButton({super.key, required this.onTap});

  /// Space the card must leave at its top and right so this fits in the Stack.
  static const double overhang = 14;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Cancel order',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.mediumImpact();
          onTap?.call();
        },
        child: SizedBox(
          width: 44,
          height: 44,
          child: Align(
            alignment: Alignment.topRight,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.red.shade300, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                Icons.close_rounded,
                size: 22,
                color: Colors.red.shade700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
