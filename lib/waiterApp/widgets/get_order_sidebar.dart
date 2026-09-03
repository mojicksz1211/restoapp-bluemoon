import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models.dart';

/// Ported from menuApp/widgets/category_sidebar.dart so the waiter's "Get
/// Order" screen is the same UI as the guest-facing menu, not a lookalike —
/// search box, category rail with icons/counts, gold accents. Kept as its
/// own copy (own MenuItem type) rather than a shared cross-app import.
class GetOrderSidebar extends StatefulWidget {
  final List<String> categories;
  final String selectedCategory;
  final Map<String, int> itemCounts;
  final ValueChanged<String> onCategoryTap;
  final List<MenuItem> allMenuItems;
  final ValueChanged<MenuItem> onItemTap;
  final double width;

  const GetOrderSidebar({
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
  State<GetOrderSidebar> createState() => _GetOrderSidebarState();
}

class _GetOrderSidebarState extends State<GetOrderSidebar> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static IconData _iconFor(String category) {
    final name = category.toLowerCase();
    bool has(String kw) => name.contains(kw);
    if (category.contains('Top') || category.contains('🔥') || category.contains('Best')) {
      return Icons.local_fire_department_rounded;
    }
    if (category.contains('Sizzling') || category.contains('Pulutan') || has('sizzling') || has('pulutan')) {
      return Icons.outdoor_grill_outlined;
    }
    if (category.contains('Chicken') || category.contains('Wing')) {
      return Icons.kebab_dining_outlined;
    }
    if (category.contains('Beer') || has('beer')) return Icons.sports_bar_outlined;
    if (category.contains('Pizza') || category.contains('Rice')) return Icons.local_pizza_outlined;
    if (category.contains('Shake') || category.contains('Dessert')) return Icons.icecream_outlined;
    if (has('cocktail') || has('liquor') || has('shot')) return Icons.local_bar_outlined;
    if (has('wine') || has('champagne')) return Icons.wine_bar_outlined;
    if (has('whiskey') || has('whisky') || has('tequila') || has('soju') || has('gin') || has('vodka')) {
      return Icons.liquor_outlined;
    }
    if (has('coffee') || has('frappe')) return Icons.coffee_outlined;
    if (has('shake') || has('ade') || has('soda') || has('drink')) return Icons.local_drink_outlined;
    if (has('pizza')) return Icons.local_pizza_outlined;
    if (has('pasta') || has('noodle') || has('soup')) return Icons.ramen_dining_outlined;
    if (has('rice')) return Icons.rice_bowl_outlined;
    if (has('salad')) return Icons.eco_outlined;
    if (has('dessert') || has('sweet')) return Icons.icecream_outlined;
    if (has('chicken') || has('bbq') || has('grill')) return Icons.local_fire_department_outlined;
    if (has('seafood') || has('shrimp') || has('fish')) return Icons.set_meal_outlined;
    if (has('fries') || has('side')) return Icons.lunch_dining_outlined;
    if (has('game')) return Icons.sports_esports_outlined;
    if (has('room') || has('ktv')) return Icons.meeting_room_outlined;
    if (category == 'All') return Icons.apps_rounded;
    return Icons.restaurant_outlined;
  }

  @override
  Widget build(BuildContext context) {
    const navy = GetOrderSidebar.navy;
    const navyLight = GetOrderSidebar.navyLight;
    const gold = GetOrderSidebar.gold;
    final isSearching = _query.trim().isNotEmpty;

    List<String> matchingCategories = const [];
    List<MenuItem> matchingItems = const [];
    if (isSearching) {
      final q = _query.trim().toLowerCase();
      matchingCategories =
          widget.categories.where((c) => c != 'All' && c.toLowerCase().contains(q)).toList();
      matchingItems = widget.allMenuItems.where((item) => item.name.toLowerCase().contains(q)).take(40).toList();
    }

    // Solid, fully-opaque gradient — no BackdropFilter — so this matches
    // WaiterSidebar (the Tables screen's left rail) exactly instead of the
    // softer/blurred ~90%-opacity look the ported menuApp version had.
    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [navy, navyLight],
        ),
        border: Border(right: BorderSide(color: gold.withValues(alpha: 0.25), width: 1)),
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
                      iconFor: _iconFor,
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
                          icon: _iconFor(category),
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

  const _SearchField({required this.controller, required this.onChanged, required this.onClear});

  @override
  Widget build(BuildContext context) {
    const gold = GetOrderSidebar.gold;
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
          hintText: 'Search category or menu',
          hintStyle: GoogleFonts.urbanist(color: Colors.white.withValues(alpha: 0.45), fontSize: 13.5),
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
  final IconData Function(String) iconFor;

  const _SearchResults({
    required this.categories,
    required this.items,
    required this.itemCounts,
    required this.onCategoryTap,
    required this.onItemTap,
    required this.iconFor,
  });

  @override
  Widget build(BuildContext context) {
    const gold = GetOrderSidebar.gold;

    if (categories.isEmpty && items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          children: [
            Icon(Icons.search_off, color: Colors.white.withValues(alpha: 0.35), size: 32),
            const SizedBox(height: 10),
            Text(
              'No matches found',
              style: GoogleFonts.urbanist(color: Colors.white.withValues(alpha: 0.55), fontSize: 13),
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
          _SectionLabel('Categories'),
          for (final category in categories)
            _CategoryRow(
              category: category,
              isSelected: false,
              count: itemCounts[category] ?? 0,
              showCount: true,
              icon: iconFor(category),
              onTap: () => onCategoryTap(category),
            ),
        ],
        if (items.isNotEmpty) ...[
          _SectionLabel('Menu Items'),
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
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: item.imageUrl != null && item.imageUrl!.startsWith('http')
                                ? CachedNetworkImage(
                                    imageUrl: item.imageUrl!,
                                    cacheKey: '${item.imageUrl}_waitersearch',
                                    fit: BoxFit.cover,
                                    memCacheWidth: 88,
                                    memCacheHeight: 88,
                                    fadeInDuration: const Duration(milliseconds: 150),
                                    placeholder: (context, url) => Container(
                                      color: gold.withValues(alpha: 0.14),
                                      child: Icon(item.icon, size: 18, color: gold),
                                    ),
                                    errorWidget: (context, url, error) => Container(
                                      color: gold.withValues(alpha: 0.14),
                                      child: Icon(item.icon, size: 18, color: gold),
                                    ),
                                  )
                                : Container(
                                    color: gold.withValues(alpha: 0.14),
                                    child: Icon(item.icon, size: 18, color: gold),
                                  ),
                          ),
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
                          style: GoogleFonts.urbanist(fontSize: 14.0, fontWeight: FontWeight.w800, color: gold),
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
          color: GetOrderSidebar.gold.withValues(alpha: 0.75),
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
  final IconData icon;
  final VoidCallback onTap;

  const _CategoryRow({
    required this.category,
    required this.isSelected,
    required this.count,
    required this.showCount,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const gold = GetOrderSidebar.gold;
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
                left: BorderSide(color: isSelected ? gold : Colors.transparent, width: 4),
              ),
            ),
            child: Row(
              children: [
                AnimatedScale(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  scale: isSelected ? 1.12 : 1.0,
                  child: Icon(icon, size: 26, color: isSelected ? gold : Colors.white.withValues(alpha: 0.75)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    category,
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
