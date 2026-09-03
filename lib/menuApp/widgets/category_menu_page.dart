import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/app_translations.dart';
import '../models.dart';
import 'menu_item_card.dart';

class CategoryMenuPage extends StatefulWidget {
  final List<MenuItem> itemsForCategory;
  final int displayLimit;
  final VoidCallback onLoadMore;
  final Function(MenuItem) onItemTap;
  final Function(MenuItem) getItemQuantity;
  final Function({
    required MenuItem item,
    required int quantity,
    required bool isMobile,
    required bool isLargeTablet,
    Key? key,
  }) buildQuantityControl;
  final Function(MenuItem) estimateMinutes;

  final bool isMobile;
  final bool isTablet;
  final bool isLargeTablet;
  final int crossAxisCount;
  final double childAspectRatio;
  final double spacing;
  final double bottomBarHeight; // Height ng bottom bar para sa padding

  const CategoryMenuPage({
    super.key,
    required this.itemsForCategory,
    required this.displayLimit,
    required this.onLoadMore,
    required this.onItemTap,
    required this.getItemQuantity,
    required this.buildQuantityControl,
    required this.estimateMinutes,
    required this.isMobile,
    required this.isTablet,
    required this.isLargeTablet,
    required this.crossAxisCount,
    required this.childAspectRatio,
    required this.spacing,
    required this.bottomBarHeight,
  });

  @override
  State<CategoryMenuPage> createState() => _CategoryMenuPageState();
}

class _CategoryMenuPageState extends State<CategoryMenuPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final fullItems = widget.itemsForCategory;
    final items = fullItems.take(widget.displayLimit).toList();
    final hasMore = fullItems.length > widget.displayLimit;

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: widget.isMobile ? 48 : 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'no_items_found'.tr,
              style: GoogleFonts.urbanist(
                fontSize: widget.isMobile ? 16 : 18,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      physics: const ClampingScrollPhysics(),
      cacheExtent: widget.isMobile ? 500 : 800,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.all(widget.spacing),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: widget.crossAxisCount,
              childAspectRatio: widget.childAspectRatio,
              crossAxisSpacing: widget.spacing,
              mainAxisSpacing: widget.spacing,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = items[index];
                return RepaintBoundary(
                  // Explicit identity key so Flutter always matches the right
                  // Element/State to the right item across rebuilds — without
                  // one, list/grid children are matched by index only, which
                  // can misattribute state (including in-flight image
                  // decodes) when an ancestor far above (e.g. MenuHomePage's
                  // setState() after returning from the item detail page)
                  // forces this grid to rebuild.
                  key: ValueKey('menu-item-${item.id?.toString() ?? item.name}'),
                  child: MenuItemCard(
                    item: item,
                    estimatedMinutes: widget.estimateMinutes(item),
                    quantityControl: RepaintBoundary(
                      child: AnimatedSwitcher(
                        duration: Duration.zero,
                        switchInCurve: Curves.linear,
                        switchOutCurve: Curves.linear,
                        child: widget.buildQuantityControl(
                          item: item,
                          quantity: widget.getItemQuantity(item),
                          isMobile: widget.isMobile,
                          isLargeTablet: widget.isLargeTablet,
                          key: ValueKey(
                            '${item.name}_${widget.getItemQuantity(item)}',
                          ),
                        ),
                      ),
                    ),
                    onTap: () => widget.onItemTap(item),
                  ),
                );
              },
              childCount: items.length,
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
            ),
          ),
        ),
        if (hasMore)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(
                left: widget.spacing,
                right: widget.spacing,
                bottom: widget.spacing,
                top: 0,
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)], // Maroon gradient
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0C0E2B).withValues(alpha: 0.3), // Maroon shadow
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: widget.onLoadMore,
                  icon: Icon(
                    Icons.add_circle_outline,
                    color: Colors.white,
                    size: widget.isMobile ? 20 : 24,
                  ),
                  label: Text(
                    'load_more_menu'.tr,
                    style: GoogleFonts.urbanist(
                      fontSize: widget.isMobile ? 14 : 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shadowColor: Colors.transparent,
                    padding: EdgeInsets.symmetric(
                      horizontal: widget.isMobile ? 24 : 32,
                      vertical: widget.isMobile ? 12 : 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ).copyWith(
                    overlayColor: WidgetStateProperty.all(Colors.transparent),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

