import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models.dart';

/// Searchable, paginated bottom sheet for picking a menu item — used by
/// [EditOrderBottomSheet] in both waiterApp and cashierApp (edit-order flow).
class MenuPickerSheet extends StatefulWidget {
  final List<MenuItem> menuItems;

  const MenuPickerSheet({super.key, required this.menuItems});

  @override
  State<MenuPickerSheet> createState() => _MenuPickerSheetState();
}

class _MenuPickerSheetState extends State<MenuPickerSheet> {
  static const int _pageSize = 15;

  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  int _page = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0C0E2B);
    const navyLight = Color(0xFF1B1E4A);
    const gold = Color(0xFFE8C468);

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final query = _query.trim().toLowerCase();
    final items = query.isEmpty
        ? widget.menuItems
        : widget.menuItems
            .where((m) => m.name.toLowerCase().contains(query) || m.category.toLowerCase().contains(query))
            .toList();

    final maxPage = items.isEmpty ? 0 : (items.length - 1) ~/ _pageSize;
    final page = _page > maxPage ? maxPage : _page;
    final start = page * _pageSize;
    final end = (start + _pageSize).clamp(0, items.length);
    final pageItems = items.isEmpty ? const <MenuItem>[] : items.sublist(start, end);

    return DraggableScrollableSheet(
      initialChildSize: isMobile ? 0.8 : 0.7,
      minChildSize: isMobile ? 0.5 : 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF5F6F0),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                padding: EdgeInsets.fromLTRB(isMobile ? 16 : 20, isMobile ? 16 : 20, isMobile ? 16 : 20, 14),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [navy, navyLight]),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Select Menu Item',
                          style: GoogleFonts.urbanist(
                            fontSize: isMobile ? 18 : 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        InkWell(
                          onTap: () => Navigator.pop(context),
                          borderRadius: BorderRadius.circular(20),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.close, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _searchController,
                      onChanged: (value) => setState(() {
                        _query = value;
                        _page = 0;
                      }),
                      style: GoogleFonts.urbanist(color: Colors.white, fontSize: 14.5),
                      cursorColor: gold,
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.08),
                        hintText: 'Search menu item or category',
                        hintStyle: GoogleFonts.urbanist(color: Colors.white.withValues(alpha: 0.45), fontSize: 13.5),
                        prefixIcon: Icon(Icons.search, size: 20, color: Colors.white.withValues(alpha: 0.55)),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                icon: Icon(Icons.close, size: 18, color: Colors.white.withValues(alpha: 0.55)),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _query = '';
                                    _page = 0;
                                  });
                                },
                                splashRadius: 16,
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: gold, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          'No items found',
                          style: GoogleFonts.urbanist(color: Colors.grey[600]),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: EdgeInsets.fromLTRB(16, 12, 16, isMobile ? 16 : 20),
                        itemCount: pageItems.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final menuItem = pageItems[index];
                          return Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => Navigator.pop(context, menuItem),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: SizedBox(
                                        width: 42,
                                        height: 42,
                                        child: menuItem.imageUrl != null && menuItem.imageUrl!.startsWith('http')
                                            ? CachedNetworkImage(
                                                imageUrl: menuItem.imageUrl!,
                                                cacheKey: '${menuItem.imageUrl}_menupicker',
                                                fit: BoxFit.cover,
                                                memCacheWidth: 84,
                                                memCacheHeight: 84,
                                                fadeInDuration: const Duration(milliseconds: 150),
                                                placeholder: (context, url) => Container(
                                                  color: gold.withValues(alpha: 0.14),
                                                  child: Icon(menuItem.icon, size: 20, color: gold),
                                                ),
                                                errorWidget: (context, url, error) => Container(
                                                  color: gold.withValues(alpha: 0.14),
                                                  child: Icon(menuItem.icon, size: 20, color: gold),
                                                ),
                                              )
                                            : Container(
                                                color: gold.withValues(alpha: 0.14),
                                                child: Icon(menuItem.icon, size: 20, color: gold),
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            menuItem.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.urbanist(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14.5,
                                              color: navy,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            menuItem.category,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.urbanist(fontSize: 12, color: Colors.grey[600]),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '₱${formatPrice(menuItem.price)}',
                                      style: GoogleFonts.urbanist(fontWeight: FontWeight.bold, fontSize: 14, color: navy),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (items.length > _pageSize)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: gold.withValues(alpha: 0.25))),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      MenuPickerPageButton(
                        icon: Icons.chevron_left,
                        onTap: page > 0 ? () => setState(() => _page = page - 1) : null,
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'Page ${page + 1} of ${maxPage + 1}',
                        style: GoogleFonts.urbanist(fontWeight: FontWeight.w600, fontSize: 13.5, color: navy),
                      ),
                      const SizedBox(width: 16),
                      MenuPickerPageButton(
                        icon: Icons.chevron_right,
                        onTap: page < maxPage ? () => setState(() => _page = page + 1) : null,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class MenuPickerPageButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const MenuPickerPageButton({super.key, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0C0E2B);
    const gold = Color(0xFFE8C468);
    final enabled = onTap != null;
    return Material(
      color: enabled ? navy : Colors.grey.shade200,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 20, color: enabled ? gold : Colors.grey.shade400),
        ),
      ),
    );
  }
}
