import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pages/menu_home_page.dart';
import 'home_page.dart';
import 'models.dart';
import 'services/api_service.dart';
import '../shared/login_page.dart';
import '../shared/globals.dart';
import '../shared/settings_sheet.dart';

class CategoryPage extends StatefulWidget {
  const CategoryPage({super.key});

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  List<Map<String, dynamic>> categories = [];
  Map<int, int> categoryItemCounts = {};
  bool isLoading = true;
  String? errorMessage;
  String _activeLanguage = languageNotifier.value;

  void _onLanguageChanged() {
    final nextLanguage = languageNotifier.value;
    if (nextLanguage == _activeLanguage) return;
    _activeLanguage = nextLanguage;
    _loadCategories();
  }

  @override
  void initState() {
    super.initState();
    languageNotifier.addListener(_onLanguageChanged);
    _initLanguageAndLoad();
  }

  Future<void> _initLanguageAndLoad() async {
    final prefs = await SharedPreferences.getInstance();
    final lang = prefs.getString('language') ?? 'en';
    _activeLanguage = lang;
    setAppLanguage(lang);
    await _loadCategories();
  }

  @override
  void dispose() {
    languageNotifier.removeListener(_onLanguageChanged);
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      // Fetch categories
      final categoriesResult = await ApiService.getCategories();
      
      // Check if unauthorized - redirect to login
      if (categoriesResult['unauthorized'] == true) {
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginPage()),
            (route) => false,
          );
        }
        return;
      }
      
      if (categoriesResult['success'] == true) {
        final cats = List<Map<String, dynamic>>.from(categoriesResult['data']);
        // Keep API order for categories (ascending order)
        final orderedCats = cats;
        
        // Fetch menu items to get counts
        final menuResult = await ApiService.getMenuItems();
        
        // Check if unauthorized - redirect to login
        if (menuResult['unauthorized'] == true) {
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const LoginPage()),
              (route) => false,
            );
          }
          return;
        }
        
        List<MenuItem> allMenuItems = [];
        
        if (menuResult['success'] == true) {
          final menuData = List<Map<String, dynamic>>.from(menuResult['data']);
          allMenuItems = menuData.map((item) => MenuItem.fromApi(item)).toList();
        }

        // Calculate item counts per category
        Map<int, int> counts = {};
        for (var cat in orderedCats) {
          final catId = cat['id'] as int;
          counts[catId] = allMenuItems.where((item) => item.id != null && item.category == cat['name']).length;
        }

        if (!mounted) return;
        setState(() {
          categories = orderedCats;
          categoryItemCounts = counts;
          isLoading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          errorMessage = categoriesResult['error'] ?? 'Failed to load categories';
          isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = 'Error loading categories: ${e.toString()}';
        isLoading = false;
      });
    }
  }

  // Get item count for a category
  int _getItemCount(int categoryId) {
    return categoryItemCounts[categoryId] ?? 0;
  }

  // Get icon for each category. Keyword-matched (case-insensitive) instead
  // of an exact-name switch, since it needs to cover whatever categories a
  // branch actually has (was hardcoded to Daraejung's Korean category names,
  // so every Blue Moon category silently fell through to the default icon).
  IconData _getCategoryIcon(String category) {
    final name = category.toLowerCase();
    bool has(String kw) => name.contains(kw);

    if (has('cocktail') || has('liquor') || has('shot')) return Icons.local_bar_outlined;
    if (has('wine') || has('champagne')) return Icons.wine_bar_outlined;
    if (has('whiskey') || has('whisky') || has('tequila') || has('soju') || has('gin') || has('vodka') || has('cognac') || has('bourbon')) {
      return Icons.liquor_outlined;
    }
    if (has('beer')) return Icons.sports_bar_outlined;
    if (has('coffee') || has('frappe')) return Icons.coffee_outlined;
    if (has('shake') || has('ade') || has('soda') || has('drink') || has('mixer') || has('water')) {
      return Icons.local_drink_outlined;
    }
    if (has('pizza')) return Icons.local_pizza_outlined;
    if (has('pasta') || has('spaghetti')) return Icons.dinner_dining_outlined;
    if (has('noodle') || has('ramen') || has('soup')) return Icons.ramen_dining_outlined;
    if (has('rice')) return Icons.rice_bowl_outlined;
    if (has('salad')) return Icons.eco_outlined;
    if (has('dessert') || has('ice cream') || has('sweet')) return Icons.icecream_outlined;
    if (has('platter') || has('sando') || has('sandwich')) return Icons.tapas_outlined;
    if (has('chicken') || has('bbq') || has('barbecue') || has('grill')) return Icons.local_fire_department_outlined;
    if (has('seafood') || has('shrimp') || has('fish')) return Icons.set_meal_outlined;
    if (has('fries') || has('side')) return Icons.lunch_dining_outlined;
    if (has('set menu') || has('promo') || has('package')) return Icons.set_meal_outlined;
    if (has('game')) return Icons.sports_esports_outlined;
    if (has('room') || has('ktv') || has('charge')) return Icons.meeting_room_outlined;
    if (has('delivery')) return Icons.delivery_dining_outlined;
    if (has('star') || has('recommend')) return Icons.star_outline;
    return Icons.restaurant_outlined;
  }

  // Category tile — square glassmorphism card: frosted/blurred translucent
  // surface (so the logo watermark diffuses through it, not just tints it),
  // thin light border for the "glass edge" highlight, gold icon + accents.
  Widget _buildCategoryItem(
    BuildContext context,
    Map<String, dynamic> category,
    int itemCount,
    bool isMobile,
    bool isTablet,
  ) {
    const navy = Color(0xFF0C0E2B);
    const gold = Color(0xFFE8C468);
    final radius = BorderRadius.circular(20);

    final categoryName = category['name'] ?? '';
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: () {
          final categoryId = category['id'] is int
              ? category['id'] as int
              : (category['id'] as num?)?.toInt();

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => MenuHomePage(
                initialCategory: categoryName,
                initialCategoryId: categoryId,
              ),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding: EdgeInsets.all(isMobile ? 12 : 16),
              decoration: BoxDecoration(
                borderRadius: radius,
                // Frosted glass: light, mostly-transparent tint over the
                // blurred watermark instead of a solid/near-opaque navy fill.
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.16),
                    Colors.white.withValues(alpha: 0.05),
                  ],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: navy.withValues(alpha: 0.20),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.all(isMobile ? 9 : 11),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: gold.withValues(alpha: 0.16),
                      border: Border.all(color: gold.withValues(alpha: 0.55), width: 1.2),
                    ),
                    child: Icon(
                      _getCategoryIcon(categoryName),
                      size: isMobile ? 20 : (isTablet ? 22 : 24),
                      color: gold,
                    ),
                  ),
                  SizedBox(height: isMobile ? 10 : 14),
                  Text(
                    categoryName,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.urbanist(
                      fontSize: isMobile ? 13.5 : (isTablet ? 15 : 16),
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.15,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: isMobile ? 4 : 6),
                  Text(
                    '$itemCount items',
                    style: GoogleFonts.urbanist(
                      fontSize: isMobile ? 11 : 12.5,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final screenWidth = size.width;
    final orientation = MediaQuery.of(context).orientation;
    final shortestSide = size.shortestSide;
    final isMobile = shortestSide < 600;
    final isTablet = shortestSide >= 600 && shortestSide < 1024;
    final isLargeTablet = shortestSide >= 1024;
    final isPortrait = orientation == Orientation.portrait;

    if (isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F6F0),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0C0E2B)),
              ),
              const SizedBox(height: 16),
              Text(
                'Loading categories...',
                style: GoogleFonts.urbanist(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (errorMessage != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F6F0),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(
                errorMessage!,
                style: GoogleFonts.urbanist(
                  fontSize: 16,
                  color: Colors.red[700],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadCategories,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0C0E2B),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SizedBox.expand(
        child: Container(
          width: screenSize.width,
          height: screenSize.height,
          color: const Color(0xFFF5F6F0),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Centered logo watermark — replaces the old boxed logo panel.
              // Sized off the shorter screen dimension so it stays a sane
              // watermark instead of overwhelming small phones or shrinking
              // to nothing on ultra-wide desktop windows.
              Center(
                child: Opacity(
                  opacity: 0.4,
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: (size.shortestSide * 0.68).clamp(220.0, 520.0),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const SizedBox(),
                  ),
                ),
              ),
              // Child content on top (with SafeArea applied inside)
              SafeArea(
                child: Column(
                  children: [
                    // Back button only (no header bar)
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 12 : 16,
                        vertical: isMobile ? 6 : 8,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.black),
                            iconSize: isMobile ? 40 : 48,
                            onPressed: () {
                              final navigator = Navigator.of(context);
                              if (navigator.canPop()) {
                                navigator.pop();
                              } else {
                                navigator.pushReplacement(
                                  MaterialPageRoute(builder: (context) => const HomePage()),
                                );
                              }
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),

                    // Category grid — the logo now lives as a centered
                    // background watermark (see the Stack layer above), so
                    // there's no separate logo panel eating into the layout
                    // and one grid works for both orientations.
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 14 : (isLargeTablet ? 28 : 20),
                          vertical: isMobile ? 10 : 16,
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final crossAxisCount = isLargeTablet
                                ? (isPortrait ? 4 : 5)
                                : isTablet
                                    ? (isPortrait ? 3 : 4)
                                    : (isPortrait ? 2 : 3);
                            final spacing = isMobile ? 12.0 : 16.0;
                            return GridView.builder(
                              itemCount: categories.length,
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                crossAxisSpacing: spacing,
                                mainAxisSpacing: spacing,
                                // Square tiles.
                                childAspectRatio: 1,
                              ),
                              itemBuilder: (context, index) {
                                final category = categories[index];
                                return _buildCategoryItem(
                                  context,
                                  category,
                                  _getItemCount(category['id']),
                                  isMobile,
                                  isTablet,
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Settings button (place last so it stays on top)
              Positioned(
                top: 12,
                right: 12,
                child: SafeArea(
                  child: IconButton(
                    icon: const Icon(Icons.settings, size: 40),
                    color: const Color(0xFF0C0E2B),
                    onPressed: () {
                      showAppSettingsSheet(
                        context: context,
                        onLogout: () async {
                          await ApiService.logout();
                          if (context.mounted) {
                            refreshAppAuth();
                          }
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

