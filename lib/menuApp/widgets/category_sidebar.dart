import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/app_translations.dart';
import '../models.dart';
import 'category_icons.dart';

/// Left-hand category rail for the menu screen — replaces the old
/// "tap a category tile → navigate to a new page" flow. Selecting a row
/// just calls [onCategoryTap], which the menu page uses to swap the
/// right-hand content in place (no Navigator involved).
///
/// Also carries a search box at the top: typing filters the rail down to
/// matching categories AND matching menu items (searched across every
/// category, not just the one currently selected), so staff can jump
/// straight to a dish without knowing which category it lives under.
class CategorySidebar extends StatefulWidget {
  final List<String> categories;
  final String selectedCategory;
  final Map<String, int> itemCounts;
  final ValueChanged<String> onCategoryTap;
  final List<MenuItem> allMenuItems;
  final ValueChanged<MenuItem> onItemTap;
  final double width;

  const CategorySidebar({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.itemCounts,
    required this.onCategoryTap,
    required this.allMenuItems,
    required this.onItemTap,
    this.width = 280,
  });

  static const navy = Color(0xFF0C0E2B);
  static const navyLight = Color(0xFF1B1E4A);
  static const gold = Color(0xFFE8C468);

  @override
  State<CategorySidebar> createState() => _CategorySidebarState();
}

class _CategorySidebarState extends State<CategorySidebar> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final navy = CategorySidebar.navy;
    final navyLight = CategorySidebar.navyLight;
    final gold = CategorySidebar.gold;
    final isSearching = _query.trim().isNotEmpty;

    List<String> matchingCategories = const [];
    List<MenuItem> matchingItems = const [];
    if (isSearching) {
      final q = _query.trim().toLowerCase();
      matchingCategories = widget.categories
          .where((c) => c != 'All' && c.toLowerCase().contains(q))
          .toList();
      matchingItems = widget.allMenuItems
          .where((item) => item.name.toLowerCase().contains(q))
          .take(40)
          .toList();
    }

    // No BackdropFilter here on purpose. A live backdrop blur across this
    // whole (tall, frequently-repainted-behind) sidebar is what was
    // triggering Flutter Web CanvasKit's "GL_INVALID_FRAMEBUFFER_OPERATION /
    // Framebuffer is incomplete" WebGL errors — a known CanvasKit bug class,
    // not an image-loading bug — which then corrupted image texture uploads
    // elsewhere on the page (the broken/blank menu images). The gradient
    // below is already ~90% opaque, so the blur was barely visible anyway.
    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [navy.withValues(alpha: 0.96), navyLight.withValues(alpha: 0.96)],
        ),
        border: Border(
          right: BorderSide(color: gold.withValues(alpha: 0.25), width: 1),
        ),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                  child: _SearchField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    onClear: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                  ),
                ),
                Expanded(
                  child: isSearching
                      ? _SearchResults(
                          categories: matchingCategories,
                          items: matchingItems,
                          itemCounts: widget.itemCounts,
                          onCategoryTap: widget.onCategoryTap,
                          onItemTap: widget.onItemTap,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                          itemCount: widget.categories.length,
                          itemBuilder: (context, index) {
                            final category = widget.categories[index];
                            final isSelected = category == widget.selectedCategory;
                            final count = widget.itemCounts[category] ?? 0;
                            return _CategoryRow(
                              category: category,
                              isSelected: isSelected,
                              count: count,
                              showCount: category != 'All',
                              onTap: () => widget.onCategoryTap(category),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
    );
  }
}

class _SearchField extends StatelessWidget {

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    const gold = CategorySidebar.gold;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: GoogleFonts.urbanist(color: Colors.white, fontSize: 14.5),
        cursorColor: gold,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'search_category_or_menu'.tr,
          hintStyle: GoogleFonts.urbanist(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 13.5,
          ),
          prefixIcon: Icon(Icons.search, size: 20, color: Colors.white.withValues(alpha: 0.55)),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: Icon(Icons.close, size: 18, color: Colors.white.withValues(alpha: 0.55)),
                onPressed: onClear,
                splashRadius: 16,
              );
            },
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  final List<String> categories;
  final List<MenuItem> items;
  final Map<String, int> itemCounts;
  final ValueChanged<String> onCategoryTap;
  final ValueChanged<MenuItem> onItemTap;

  const _SearchResults({
    required this.categories,
    required this.items,
    required this.itemCounts,
    required this.onCategoryTap,
    required this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    const gold = CategorySidebar.gold;

    if (categories.isEmpty && items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          children: [
            Icon(Icons.search_off, color: Colors.white.withValues(alpha: 0.35), size: 32),
            const SizedBox(height: 10),
            Text(
              'no_matches_found'.tr,
              style: GoogleFonts.urbanist(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      children: [
        if (categories.isNotEmpty) ...[
          _SectionLabel('categories_label'.tr),
          for (final category in categories)
            _CategoryRow(
              category: category,
              isSelected: false,
              count: itemCounts[category] ?? 0,
              showCount: true,
              onTap: () => onCategoryTap(category),
            ),
        ],
        if (items.isNotEmpty) ...[
          _SectionLabel('menu_items_label'.tr),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onItemTap(item),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: gold.withValues(alpha: 0.14),
                          ),
                          child: Icon(item.icon, size: 16, color: gold),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: GoogleFonts.urbanist(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                item.category,
                                style: GoogleFonts.urbanist(
                                  fontSize: 11.5,
                                  color: Colors.white.withValues(alpha: 0.5),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '₱${formatPrice(item.price)}',
                          style: GoogleFonts.urbanist(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: gold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.urbanist(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: CategorySidebar.gold.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final String category;
  final bool isSelected;
  final int count;
  final bool showCount;
  final VoidCallback onTap;

  const _CategoryRow({
    required this.category,
    required this.isSelected,
    required this.count,
    required this.showCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const gold = CategorySidebar.gold;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: isSelected ? gold.withValues(alpha: 0.16) : Colors.transparent,
              border: Border(
                left: BorderSide(
                  color: isSelected ? gold : Colors.transparent,
                  width: 4,
                ),
              ),
            ),
            child: Row(
              children: [
                AnimatedScale(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  scale: isSelected ? 1.12 : 1.0,
                  child: Icon(
                    getCategoryIcon(category),
                    size: 26,
                    color: isSelected ? gold : Colors.white.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    // 'All' is a pseudo-category (added client-side, not a
                    // real backend category name), so it's the one label
                    // here that needs translating — everything else comes
                    // pre-translated from the API via the selected language.
                    category == 'All' ? 'all_categories'.tr : category,
                    style: GoogleFonts.urbanist(
                      fontSize: 16.5,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.75),
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (showCount) ...[
                  const SizedBox(width: 8),
                  Text(
                    '$count',
                    style: GoogleFonts.urbanist(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? gold : Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
