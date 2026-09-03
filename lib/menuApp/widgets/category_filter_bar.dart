import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CategoryFilterBar extends StatelessWidget {
  final List<String> categories;
  final String selectedCategory;
  final bool isMobile;
  final ScrollController scrollController;
  final ValueChanged<String> onCategoryTap;

  const CategoryFilterBar({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.isMobile,
    required this.scrollController,
    required this.onCategoryTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: isMobile ? 45 : 50,
      child: ListView.builder(
        controller: scrollController,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          final isSelected = category == selectedCategory;
          return Padding(
            padding: EdgeInsets.only(right: isMobile ? 8 : 12),
            child: Transform(
              transform: Matrix4.identity(),
              child: isSelected
                  ? Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(25),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)], // Maroon gradient
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0C0E2B).withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: () => onCategoryTap(category),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shadowColor: Colors.transparent,
                          elevation: 0,
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 16 : 20,
                            vertical: isMobile ? 10 : 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ).copyWith(
                          overlayColor: WidgetStateProperty.all(Colors.transparent),
                        ),
                        child: Text(
                          category,
                          style: GoogleFonts.urbanist(
                            fontWeight: FontWeight.bold,
                            fontSize: isMobile ? 12 : 14,
                          ),
                        ),
                      ),
                    )
                  : ElevatedButton(
                      onPressed: () => onCategoryTap(category),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF5F6F0), // Cream background
                        foregroundColor: Colors.black87,
                        elevation: 1,
                        shadowColor: Colors.black.withValues(alpha: 0.1),
                        padding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 16 : 20,
                          vertical: isMobile ? 10 : 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                          side: BorderSide(
                            color: Colors.grey.shade300,
                            width: 1,
                          ),
                        ),
                      ).copyWith(
                        overlayColor: WidgetStateProperty.all(Colors.transparent),
                      ),
                      child: Text(
                        category,
                        style: GoogleFonts.urbanist(
                          fontWeight: FontWeight.w500,
                          fontSize: isMobile ? 12 : 14,
                        ),
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}

