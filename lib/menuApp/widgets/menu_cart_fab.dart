import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class MenuCartFab extends StatelessWidget {
  final bool isWide;
  final bool isCartPanelOpen;
  final bool isCartSheetOpen;
  final bool shouldShowTrackingButton;
  final bool hasCartItems;
  final int combinedFabCount;
  final double totalPrice;
  final GlobalKey cartFabKey;
  final VoidCallback onTogglePanel;
  final VoidCallback onOpenSheet;

  const MenuCartFab({
    super.key,
    required this.isWide,
    required this.isCartPanelOpen,
    required this.isCartSheetOpen,
    required this.shouldShowTrackingButton,
    required this.hasCartItems,
    required this.combinedFabCount,
    required this.totalPrice,
    required this.cartFabKey,
    required this.onTogglePanel,
    required this.onOpenSheet,
  });

  @override
  Widget build(BuildContext context) {
    final showFab = !(isWide && isCartPanelOpen) && !isCartSheetOpen;
    if (!showFab) {
      return IgnorePointer(
        child: Opacity(
          opacity: 0,
          child: Container(
            key: cartFabKey,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)],
              ),
            ),
            child: const SizedBox(
              width: 56,
              height: 56,
            ),
          ),
        ),
      );
    }

    return Container(
      key: cartFabKey,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)], // Maroon gradient
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0C0E2B).withValues(alpha: 0.4), // Maroon shadow
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        onPressed: () {
          if (!hasCartItems && !shouldShowTrackingButton) {
            return;
          }
          if (isWide) {
            onTogglePanel();
            return;
          }
          onOpenSheet();
        },
        backgroundColor: Colors.transparent,
        elevation: 0,
        icon: combinedFabCount > 0
            ? Badge(
                label: Text('$combinedFabCount'),
                child: const Icon(
                  Icons.shopping_cart_outlined,
                  color: Colors.white,
                ),
              )
            : const Icon(
                Icons.shopping_cart_outlined,
                color: Colors.white,
              ),
        label: Text(
          hasCartItems ? '₱${totalPrice.toStringAsFixed(2)}' : 'Cart',
          style: GoogleFonts.urbanist(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

