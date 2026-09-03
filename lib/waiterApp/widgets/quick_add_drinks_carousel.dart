import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models.dart';

const Color _navy = Color(0xFF0C0E2B);
const Color _gold = Color(0xFFE8C468);
const Color _amber = Color(0xFFD97706);

class QuickAddDrinksCarousel extends StatefulWidget {
  final List<MenuItem> suggestedDrinks;
  final int Function(MenuItem item) getItemQuantity;
  final void Function(MenuItem item) onAdd;
  final void Function(MenuItem item) onRemove;
  final bool isMobile;
  final bool initialExpanded;

  const QuickAddDrinksCarousel({
    super.key,
    required this.suggestedDrinks,
    required this.getItemQuantity,
    required this.onAdd,
    required this.onRemove,
    this.isMobile = true,
    this.initialExpanded = false,
  });

  @override
  State<QuickAddDrinksCarousel> createState() => _QuickAddDrinksCarouselState();
}

class _QuickAddDrinksCarouselState extends State<QuickAddDrinksCarousel> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initialExpanded;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.suggestedDrinks.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: _gold.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.local_bar_rounded,
                      size: 15,
                      color: _amber,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Quick Add Drinks',
                    style: GoogleFonts.urbanist(
                      fontSize: widget.isMobile ? 13.5 : 14.5,
                      fontWeight: FontWeight.w800,
                      color: _navy,
                    ),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: _navy,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: widget.isMobile ? 136 : 144,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    physics: const BouncingScrollPhysics(),
                    itemCount: widget.suggestedDrinks.length,
                    itemBuilder: (context, index) {
                      final drink = widget.suggestedDrinks[index];
                      final qty = widget.getItemQuantity(drink);
                      final inCart = qty > 0;

                      return Container(
                        width: widget.isMobile ? 104 : 112,
                        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: inCart ? _navy : Colors.grey.shade200,
                            width: inCart ? 1.4 : 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: inCart ? 0.08 : 0.03),
                              blurRadius: inCart ? 6 : 3,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Drink Thumbnail
                            SizedBox(
                              height: widget.isMobile ? 44 : 48,
                              width: widget.isMobile ? 44 : 48,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: (drink.imageUrl != null && drink.imageUrl!.isNotEmpty)
                                    ? Image.network(
                                        drink.imageUrl!,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) => _buildFallbackIcon(),
                                      )
                                    : _buildFallbackIcon(),
                              ),
                            ),

                            // Name
                            Text(
                              drink.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.urbanist(
                                fontSize: widget.isMobile ? 11.5 : 12.5,
                                fontWeight: FontWeight.bold,
                                color: _navy,
                                height: 1.1,
                              ),
                            ),

                            // Price
                            Text(
                              '₱${formatPrice(drink.price)}',
                              style: GoogleFonts.urbanist(
                                fontSize: widget.isMobile ? 11.5 : 12.5,
                                fontWeight: FontWeight.w900,
                                color: _amber,
                              ),
                            ),

                            // Action Button (Add vs Stepper)
                            if (!inCart)
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => widget.onAdd(drink),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    height: 24,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: _navy,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    alignment: Alignment.center,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.add, size: 13, color: _gold),
                                        const SizedBox(width: 3),
                                        Text(
                                          'Add',
                                          style: GoogleFonts.urbanist(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                            else
                              Container(
                                height: 24,
                                decoration: BoxDecoration(
                                  color: _navy,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    InkWell(
                                      onTap: () => widget.onRemove(drink),
                                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                                        child: Icon(Icons.remove, size: 12, color: Colors.white),
                                      ),
                                    ),
                                    Text(
                                      '$qty',
                                      style: GoogleFonts.urbanist(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () => widget.onAdd(drink),
                                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                                        child: Icon(Icons.add, size: 12, color: _gold),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
            crossFadeState: _isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackIcon() {
    return Container(
      color: Colors.grey.shade100,
      alignment: Alignment.center,
      child: const Icon(
        Icons.local_drink_rounded,
        color: _navy,
        size: 24,
      ),
    );
  }
}
