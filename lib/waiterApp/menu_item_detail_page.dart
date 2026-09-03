import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'models.dart';

class MenuItemDetailPage extends StatefulWidget {
  final List<MenuItem> items;
  final int initialIndex;
  final Function(MenuItem) getItemQuantity;
  final Function(MenuItem) onIncreaseQuantity;
  final Function(MenuItem) onDecreaseQuantity;

  const MenuItemDetailPage({
    super.key,
    required this.items,
    required this.initialIndex,
    required this.getItemQuantity,
    required this.onIncreaseQuantity,
    required this.onDecreaseQuantity,
  });

  @override
  State<MenuItemDetailPage> createState() => _MenuItemDetailPageState();
}

class _MenuItemDetailPageState extends State<MenuItemDetailPage> {
  late PageController _pageController;
  late int _currentIndex;
  late Map<int, int> _quantities; // Track quantity for each item

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.items.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    // Initialize quantities for all items
    _quantities = {};
    for (var i = 0; i < widget.items.length; i++) {
      _quantities[i] = widget.getItemQuantity(widget.items[i]);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  MenuItem get _currentItem => widget.items[_currentIndex];

  int get _currentQuantity => _quantities[_currentIndex] ?? 0;

  void _updateQuantity(int delta, int itemIndex) {
    setState(() {
      final currentQty = _quantities[itemIndex] ?? 0;
      final newQuantity = (currentQty + delta).clamp(0, double.infinity).toInt();
      _quantities[itemIndex] = newQuantity;
      
      final item = widget.items[itemIndex];
      if (delta > 0) {
        widget.onIncreaseQuantity(item);
      } else if (delta < 0 && newQuantity > 0) {
        widget.onDecreaseQuantity(item);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Scaffold(
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        itemCount: widget.items.length,
        itemBuilder: (context, index) {
          return _buildItemDetailPage(widget.items[index], isMobile, index);
        },
      ),
    );
  }

  Widget _buildItemDetailPage(MenuItem item, bool isMobile, int index) {
    final quantity = _quantities[index] ?? 0;
    
    return Builder(
      builder: (context) => CustomScrollView(
      slivers: [
        // App Bar with Image
        SliverAppBar(
          expandedHeight: isMobile ? 300 : 400,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            background: GestureDetector(
              onTap: () => _showFullScreenImage(context, item, isMobile),
              onVerticalDragEnd: (details) {
                if (details.primaryVelocity != null && details.primaryVelocity! > 500) {
                  _showFullScreenImage(context, item, isMobile);
                }
              },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      item.imageUrl != null && item.imageUrl!.startsWith('http')
                      ? CachedNetworkImage(
                          imageUrl: item.imageUrl!,
                          fit: BoxFit.cover,
                          memCacheWidth: isMobile ? 800 : 1200,
                          memCacheHeight: isMobile ? 600 : 900,
                          maxWidthDiskCache: isMobile ? 1600 : 2400,
                          maxHeightDiskCache: isMobile ? 1200 : 1800,
                          filterQuality: FilterQuality.high,
                          fadeInDuration: const Duration(milliseconds: 400),
                          fadeOutDuration: const Duration(milliseconds: 200),
                          placeholder: (context, url) => Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                            ),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: const Color(0xFF0C0E2B), // Maroon
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(
                                    0xFF0C0E2B, // Maroon
                                  ).withValues(alpha: 0.3),
                                  const Color(
                                    0xFF1B1E4A, // Medium maroon
                                  ).withValues(alpha: 0.3),
                                ],
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                item.icon,
                                color: const Color(0xFF0C0E2B), // Maroon
                                size: 80,
                              ),
                            ),
                          ),
                        )
                      : item.imageUrl != null
                      ? Image.asset(
                          item.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(
                                      0xFF0C0E2B, // Maroon
                                    ).withValues(alpha: 0.3),
                                    const Color(
                                      0xFF1B1E4A, // Medium maroon
                                    ).withValues(alpha: 0.3),
                                  ],
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  item.icon,
                                  color: const Color(0xFF0C0E2B), // Maroon
                                  size: 80,
                                ),
                              ),
                            );
                          },
                        )
                        : Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFF0C0E2B).withValues(alpha: 0.3),
                                  const Color(0xFF1B1E4A).withValues(alpha: 0.3),
                                ],
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                item.icon,
                                color: const Color(0xFF0C0E2B),
                                size: 80,
                              ),
                            ),
                          ),
                  // Dark overlay for better visibility
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.3),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  ],
                ),
              ),
            ),
            backgroundColor: Colors.transparent,
            leading: Builder(
              builder: (context) => IconButton(
                icon: Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: isMobile ? 40 : 48,
                ),
                iconSize: isMobile ? 40 : 48,
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.all(isMobile ? 12 : 16),
                constraints: BoxConstraints(
                  minWidth: isMobile ? 48 : 56,
                  minHeight: isMobile ? 48 : 56,
                ),
              ),
            ),
            iconTheme: const IconThemeData(color: Colors.white),
            elevation: 0,
          ),

          // Content
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF5F6F0), // Cream background
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.all(isMobile ? 20 : 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0C0E2B).withValues(alpha: 0.1), // Maroon
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        item.category,
                        style: GoogleFonts.urbanist(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF0C0E2B), // Maroon
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Item Name
                    Text(
                      item.name,
                      style: GoogleFonts.urbanist(
                        fontSize: isMobile ? 28 : 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Price
                    Text(
                      '₱${formatPrice(item.price)}',
                      style: GoogleFonts.urbanist(
                        fontSize: isMobile ? 32 : 36,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0C0E2B), // Maroon
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Description
                    Text(
                      'Description',
                      style: GoogleFonts.urbanist(
                        fontSize: isMobile ? 18 : 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.description,
                      style: GoogleFonts.urbanist(
                        fontSize: isMobile ? 16 : 18,
                        color: Colors.grey[700],
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Quantity Control
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Quantity',
                          style: GoogleFonts.urbanist(
                            fontSize: isMobile ? 18 : 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        _QuantityControl(
                          quantity: quantity,
                          onIncrease: () {
                            _updateQuantity(1, index);
                          },
                          onDecrease: () {
                            if (quantity > 0) {
                              _updateQuantity(-1, index);
                            }
                          },
                          isMobile: isMobile,
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // Add to Cart Button
                    SizedBox(
                      width: double.infinity,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)], // Maroon gradient
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF0C0E2B, // Maroon
                              ).withValues(alpha: 0.4),
                              blurRadius: 15,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () {
                            final currentQty = _quantities[index] ?? 0;
                            if (currentQty == 0) {
                              _updateQuantity(1, index);
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  (currentQty == 0 && _quantities[index] == 1)
                                      ? '${item.name} added to cart'
                                      : '${item.name} quantity updated',
                                  style: GoogleFonts.urbanist(),
                                ),
                                duration: const Duration(seconds: 1),
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: const Color(0xFF0C0E2B), // Maroon
                              ),
                            );
                            // Navigate back to main menu
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              vertical: isMobile ? 18 : 20,
                            ),
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            quantity == 0
                                ? 'Add to Cart'
                                : 'Update Cart',
                            style: GoogleFonts.urbanist(
                              fontSize: isMobile ? 18 : 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: isMobile ? 20 : 24),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, MenuItem item, bool isMobile) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _FullScreenImageViewer(
          item: item,
          isMobile: isMobile,
        ),
      ),
    );
  }
}

class _FullScreenImageViewer extends StatelessWidget {
  final MenuItem item;
  final bool isMobile;

  const _FullScreenImageViewer({
    required this.item,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: SizedBox.expand(
            child: item.imageUrl != null && item.imageUrl!.startsWith('http')
                ? CachedNetworkImage(
                    imageUrl: item.imageUrl!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    memCacheWidth: isMobile ? 1200 : 2000,
                    memCacheHeight: isMobile ? 1600 : 2400,
                    maxWidthDiskCache: 2400,
                    maxHeightDiskCache: 3200,
                    filterQuality: FilterQuality.high,
                    placeholder: (context, url) => Container(
                      color: Colors.black,
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      width: double.infinity,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF0C0E2B).withValues(alpha: 0.3),
                            const Color(0xFF1B1E4A).withValues(alpha: 0.3),
                          ],
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          item.icon,
                          color: const Color(0xFF0C0E2B),
                          size: 120,
                        ),
                      ),
                    ),
                  )
                : item.imageUrl != null
                    ? Image.asset(
                        item.imageUrl!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: double.infinity,
                            height: double.infinity,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFF0C0E2B).withValues(alpha: 0.3),
                                  const Color(0xFF1B1E4A).withValues(alpha: 0.3),
                                ],
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                item.icon,
                                color: const Color(0xFF0C0E2B),
                                size: 120,
                              ),
                            ),
                          );
                        },
                      )
                    : Container(
                        width: double.infinity,
                        height: double.infinity,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF0C0E2B).withValues(alpha: 0.3),
                              const Color(0xFF1B1E4A).withValues(alpha: 0.3),
                            ],
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            item.icon,
                            color: const Color(0xFF0C0E2B),
                            size: 120,
                          ),
                        ),
                      ),
          ),
        ),
      ),
    );
  }
}

class _QuantityControl extends StatelessWidget {
  final int quantity;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final bool isMobile;

  const _QuantityControl({
    required this.quantity,
    required this.onIncrease,
    required this.onDecrease,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    if (quantity == 0) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
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
        child: IconButton(
          icon: Icon(Icons.add, size: isMobile ? 24 : 28, color: Colors.white),
          onPressed: onIncrease,
          padding: EdgeInsets.all(isMobile ? 8 : 10),
          constraints: const BoxConstraints(),
          style: IconButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              Icons.remove,
              size: isMobile ? 24 : 28,
              color: Colors.white,
            ),
            onPressed: onDecrease,
            padding: EdgeInsets.all(isMobile ? 8 : 10),
            constraints: const BoxConstraints(),
            style: IconButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16),
            child: Text(
              '$quantity',
              style: GoogleFonts.urbanist(
                fontWeight: FontWeight.bold,
                fontSize: isMobile ? 18 : 20,
                color: Colors.white,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.add,
              size: isMobile ? 24 : 28,
              color: Colors.white,
            ),
            onPressed: onIncrease,
            padding: EdgeInsets.all(isMobile ? 8 : 10),
            constraints: const BoxConstraints(),
            style: IconButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
