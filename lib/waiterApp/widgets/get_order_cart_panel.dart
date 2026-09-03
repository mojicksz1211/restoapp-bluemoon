import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models.dart';
import 'item_note_modal.dart';
import 'quick_add_drinks_carousel.dart';

const _navy = Color(0xFF0C0E2B);
const _navyLight = Color(0xFF1B1E4A);

/// Ported from menuApp/widgets/cart_side_panel.dart's header/body/footer
/// chrome (same "ORDER" header, item rows, Order Type toggle, place-order
/// button) — an always-visible side panel instead of the old FAB + modal
/// bottom sheet, so the whole ordering screen (sidebar + grid + cart) is
/// the same layout as the guest-facing menu app. The waiter-specific submit
/// flow (ConfirmOrderBottomSheet, existing-order "additional items" path)
/// stays in GetOrderPage — this widget is just the cart display + the
/// callbacks it needs.
class GetOrderCartPanel extends StatelessWidget {
  final List<CartItem> cart;
  final double totalPrice;
  final GlobalKey? cartIconKey;
  final String? selectedOrderType;
  final ValueChanged<String> onOrderTypeChanged;
  final void Function(MenuItem item) onIncrease;
  final void Function(MenuItem item) onDecrease;
  final VoidCallback? onRemarksChanged;
  final VoidCallback onClose;
  final VoidCallback? onPlaceOrder;
  final bool isAdditionalOrder;
  final String? title;
  final List<MenuItem>? suggestedDrinks;

  const GetOrderCartPanel({
    super.key,
    required this.cart,
    required this.totalPrice,
    this.cartIconKey,
    required this.selectedOrderType,
    required this.onOrderTypeChanged,
    required this.onIncrease,
    required this.onDecrease,
    this.onRemarksChanged,
    required this.onClose,
    required this.onPlaceOrder,
    required this.isAdditionalOrder,
    this.title,
    this.suggestedDrinks,
  });

  @override
  Widget build(BuildContext context) {
    final cartCount = cart.fold<int>(0, (sum, item) => sum + item.quantity);

    return Column(
      children: [
        _Header(
          cartCount: cartCount,
          cartIconKey: cartIconKey,
          onClose: onClose,
          title: title ?? 'ORDER',
        ),
        Expanded(
          child: Container(
            color: const Color(0xFFF5F6F0),
            child: cart.isEmpty
                ? Center(
                    child: Text(
                      'Cart is empty',
                      style: GoogleFonts.urbanist(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8, left: 4, top: 4),
                        child: Text(
                          isAdditionalOrder ? 'Additional Order' : 'Current Order',
                          style: GoogleFonts.urbanist(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _navy,
                          ),
                        ),
                      ),
                      for (final cartItem in cart)
                        _CartRow(
                          cartItem: cartItem,
                          onIncrease: () => onIncrease(cartItem.item),
                          onDecrease: () => onDecrease(cartItem.item),
                          onRemarksChanged: onRemarksChanged,
                        ),
                    ],
                  ),
          ),
        ),
        if (suggestedDrinks != null && suggestedDrinks!.isNotEmpty)
          QuickAddDrinksCarousel(
            suggestedDrinks: suggestedDrinks!,
            getItemQuantity: (item) {
              final idx = cart.indexWhere((ci) => ci.item.name == item.name);
              return idx >= 0 ? cart[idx].quantity : 0;
            },
            onAdd: onIncrease,
            onRemove: onDecrease,
            isMobile: false,
          ),
        // Breakdown / Summary Section
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Colors.grey.shade200),
              bottom: BorderSide(color: Colors.grey.shade200),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Total Amount',
                    style: GoogleFonts.urbanist(fontSize: 16, fontWeight: FontWeight.w800, color: _navy),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Items (${cart.fold<int>(0, (sum, ci) => sum + ci.quantity)})',
                    style: GoogleFonts.urbanist(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                  ),
                ],
              ),
              Text(
                '₱${formatPrice(totalPrice)}',
                style: GoogleFonts.urbanist(fontSize: 21, fontWeight: FontWeight.w900, color: const Color(0xFFD97706)),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(color: Color(0xFFF5F6F0)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Order Type',
                style: GoogleFonts.urbanist(fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _OrderTypeChip(
                      label: 'Dine In',
                      icon: Icons.restaurant,
                      isSelected: selectedOrderType == 'DINE_IN',
                      onTap: () => onOrderTypeChanged('DINE_IN'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _OrderTypeChip(
                      label: 'Take Out',
                      icon: Icons.shopping_bag,
                      isSelected: selectedOrderType == 'TAKE_OUT',
                      onTap: () => onOrderTypeChanged('TAKE_OUT'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          decoration: const BoxDecoration(color: Color(0xFFF5F6F0)),
          child: SizedBox(
            width: double.infinity,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(colors: [_navy, _navyLight]),
                boxShadow: [
                  BoxShadow(
                    color: _navy.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: onPlaceOrder,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.transparent,
                  disabledBackgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white.withValues(alpha: 0.5),
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(
                  isAdditionalOrder ? 'Add Items' : 'Place Order',
                  style: GoogleFonts.urbanist(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final int cartCount;
  final GlobalKey? cartIconKey;
  final VoidCallback onClose;
  final String title;

  const _Header({
    required this.cartCount,
    this.cartIconKey,
    required this.onClose,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(gradient: LinearGradient(colors: [_navy, _navyLight])),
      child: Row(
        children: [
          Badge(
            label: Text('$cartCount'),
            child: Icon(Icons.shopping_cart_outlined, key: cartIconKey, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.urbanist(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close, color: Colors.white, size: 24),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }
}

class _CartRow extends StatelessWidget {
  final CartItem cartItem;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback? onRemarksChanged;

  const _CartRow({
    required this.cartItem,
    required this.onIncrease,
    required this.onDecrease,
    this.onRemarksChanged,
  });

  @override
  Widget build(BuildContext context) {
    final item = cartItem.item;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.name,
                  style: GoogleFonts.urbanist(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0C0E2B),
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (cartItem.quantity > 1) ...[
                  const SizedBox(height: 2),
                  Text(
                    '₱${formatPrice(item.price)} each',
                    style: GoogleFonts.urbanist(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                if (cartItem.remarks != null && cartItem.remarks!.trim().isNotEmpty)
                  InkWell(
                    onTap: () => showItemNoteModal(
                      context: context,
                      cartItem: cartItem,
                      onSaved: () => onRemarksChanged?.call(),
                    ),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8C468).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFE8C468).withValues(alpha: 0.6)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.edit_note_rounded, size: 14, color: Color(0xFFB45309)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              cartItem.remarks!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.urbanist(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFB45309),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  InkWell(
                    onTap: () => showItemNoteModal(
                      context: context,
                      cartItem: cartItem,
                      onSaved: () => onRemarksChanged?.call(),
                    ),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_comment_outlined, size: 13, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            '+ Add note',
                            style: GoogleFonts.urbanist(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '₱${formatPrice(item.price * cartItem.quantity)}',
            style: GoogleFonts.urbanist(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: const Color(0xFFD97706),
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: const LinearGradient(colors: [_navy, _navyLight]),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove, size: 16, color: Colors.white),
                  onPressed: onDecrease,
                  padding: const EdgeInsets.all(5),
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  style: IconButton.styleFrom(backgroundColor: Colors.transparent, foregroundColor: Colors.white),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '${cartItem.quantity}',
                    style: GoogleFonts.urbanist(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 16, color: Colors.white),
                  onPressed: onIncrease,
                  padding: const EdgeInsets.all(5),
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  style: IconButton.styleFrom(backgroundColor: Colors.transparent, foregroundColor: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumbFallback(MenuItem item) {
    return Container(
      color: Colors.grey[200],
      child: Icon(item.icon, color: Colors.grey[500], size: 24),
    );
  }
}

class _OrderTypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _OrderTypeChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: isSelected ? _navy : Colors.white,
            border: Border.all(color: isSelected ? _navy : Colors.grey.shade300),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: isSelected ? Colors.white : _navy),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.urbanist(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : _navy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
