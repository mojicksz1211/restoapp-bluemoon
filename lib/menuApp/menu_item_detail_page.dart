import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../shared/app_translations.dart';
import 'models.dart';

const _navy = Color(0xFF0C0E2B);
const _navyLight = Color(0xFF1B1E4A);
const _gold = Color(0xFFE8C468);

/// Item quick-view as a centered modal — tap a card, see details, close
/// back to the exact same grid (no page navigation/transition involved).
Future<void> showMenuItemDetailModal(
  BuildContext context, {
  required MenuItem item,
  required int Function(MenuItem) getItemQuantity,
  required void Function(MenuItem) onDecreaseQuantity,
  required Future<void> Function(BuildContext context, MenuItem item) onAddWithAnimation,
}) {
  return showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (context) => MenuItemDetailModal(
      item: item,
      getItemQuantity: getItemQuantity,
      onDecreaseQuantity: onDecreaseQuantity,
      onAddWithAnimation: onAddWithAnimation,
    ),
  );
}

class MenuItemDetailModal extends StatefulWidget {
  final MenuItem item;
  final int Function(MenuItem) getItemQuantity;
  final void Function(MenuItem) onDecreaseQuantity;
  // Same "fly the item photo to the cart icon" animation the grid cards use
  // — takes the tapped button's own context (inside this modal) as the fly
  // start point, runs the animation, then actually increases the cart
  // quantity once it lands. Used for every "+" action here (the stepper,
  // and "Add to Cart" going from 0 → 1) so adding from the modal always
  // gets the same visual feedback as adding from the grid.
  final Future<void> Function(BuildContext context, MenuItem item) onAddWithAnimation;

  const MenuItemDetailModal({
    super.key,
    required this.item,
    required this.getItemQuantity,
    required this.onDecreaseQuantity,
    required this.onAddWithAnimation,
  });

  @override
  State<MenuItemDetailModal> createState() => _MenuItemDetailModalState();
}

class _MenuItemDetailModalState extends State<MenuItemDetailModal> {
  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.shortestSide < 600;
    final quantity = widget.getItemQuantity(item);
    final maxWidth = isMobile ? screenSize.width * 0.94 : 460.0;
    final maxHeight = screenSize.height * 0.86;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: Material(
          color: const Color(0xFFF5F6F0),
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Image area — contain (not cover) so the whole photo shows,
                // same fix as the grid cards, on a white backdrop.
                AspectRatio(
                  aspectRatio: 1.15,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: Colors.white),
                      _buildImage(item, isMobile),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => Navigator.of(context).pop(),
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.close, color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Content
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 18, 20, isMobile ? 20 : 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: _navy.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _gold.withValues(alpha: 0.5), width: 1),
                        ),
                        child: Text(
                          item.category,
                          style: GoogleFonts.urbanist(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: _navy,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        item.name,
                        style: GoogleFonts.urbanist(
                          fontSize: isMobile ? 22 : 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '₱${formatPrice(item.price)}',
                        style: GoogleFonts.urbanist(
                          fontSize: isMobile ? 22 : 24,
                          fontWeight: FontWeight.bold,
                          color: _navy,
                        ),
                      ),
                      if (item.description.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          item.description,
                          style: GoogleFonts.urbanist(
                            fontSize: 14.5,
                            color: Colors.grey[700],
                            height: 1.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          // Builder so the fly animation starts from this
                          // stepper's own on-screen position, not the
                          // dialog's outer context.
                          Builder(
                            builder: (stepperContext) => _QuantityStepper(
                              quantity: quantity,
                              onIncrease: () async {
                                await widget.onAddWithAnimation(stepperContext, item);
                                if (mounted) setState(() {});
                              },
                              onDecrease: () {
                                if (quantity > 0) {
                                  widget.onDecreaseQuantity(item);
                                  setState(() {});
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: SizedBox(
                              height: 50,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  gradient: const LinearGradient(colors: [_navy, _navyLight]),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _navy.withValues(alpha: 0.35),
                                      blurRadius: 14,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Builder(
                                  builder: (buttonContext) => ElevatedButton(
                                    onPressed: () async {
                                      final wasZero = quantity == 0;
                                      if (wasZero) {
                                        // Let the fly animation land (and
                                        // actually bump the cart) before
                                        // closing the modal, so it's visible.
                                        await widget.onAddWithAnimation(buttonContext, item);
                                      }
                                      if (!buttonContext.mounted) return;
                                      ScaffoldMessenger.of(buttonContext).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            wasZero
                                                ? '${item.name} ${'added_to_cart_suffix'.tr}'
                                                : '${item.name} ${'quantity_updated_suffix'.tr}',
                                            style: GoogleFonts.urbanist(),
                                          ),
                                          duration: const Duration(seconds: 1),
                                          behavior: SnackBarBehavior.floating,
                                          backgroundColor: _navy,
                                        ),
                                      );
                                      Navigator.of(buttonContext).pop();
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      foregroundColor: Colors.white,
                                      shadowColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    ),
                                    child: Text(
                                      quantity == 0 ? 'add_to_cart'.tr : 'update_cart'.tr,
                                      style: GoogleFonts.urbanist(fontSize: 15.5, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImage(MenuItem item, bool isMobile) {
    if (item.imageUrl != null && item.imageUrl!.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: item.imageUrl!,
        cacheKey: '${item.imageUrl}_modal',
        fit: BoxFit.contain,
        memCacheWidth: isMobile ? 800 : 1000,
        memCacheHeight: isMobile ? 800 : 1000,
        maxWidthDiskCache: 1600,
        maxHeightDiskCache: 1600,
        filterQuality: FilterQuality.high,
        fadeInDuration: const Duration(milliseconds: 200),
        placeholder: (context, url) => const Center(
          child: CircularProgressIndicator(color: _navy),
        ),
        errorWidget: (context, url, error) => _imageFallback(item),
      );
    }
    if (item.imageUrl != null) {
      return Image.asset(
        item.imageUrl!,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _imageFallback(item),
      );
    }
    return _imageFallback(item);
  }

  Widget _imageFallback(MenuItem item) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [_navy, _navyLight]),
      ),
      child: Center(child: Icon(item.icon, color: Colors.white, size: 64)),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  final int quantity;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;

  const _QuantityStepper({
    required this.quantity,
    required this.onIncrease,
    required this.onDecrease,
  });

  @override
  Widget build(BuildContext context) {
    if (quantity == 0) {
      return SizedBox(
        width: 50,
        height: 50,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onIncrease,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: _navy.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.add, color: _navy),
            ),
          ),
        ),
      );
    }
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        border: Border.all(color: _navy.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(icon: const Icon(Icons.remove, color: _navy), onPressed: onDecrease),
          SizedBox(
            width: 26,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: GoogleFonts.urbanist(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          IconButton(icon: const Icon(Icons.add, color: _navy), onPressed: onIncrease),
        ],
      ),
    );
  }
}
