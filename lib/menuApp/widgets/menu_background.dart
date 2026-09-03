import 'package:flutter/material.dart';

/// Custom background widget that preserves the border design of the menu background image
/// without cropping. Uses BoxFit.contain to ensure the entire image is visible including
/// top and bottom borders.
class MenuBackground extends StatelessWidget {
  final Widget child;
  final String imagePath;
  final Color fallbackColor;

  const MenuBackground({
    super.key,
    required this.child,
    this.imagePath = 'assets/images/menubackground.png',
    this.fallbackColor = const Color(0xFFF5F6F0),
  });

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;

    return Container(
      width: screenSize.width,
      height: screenSize.height,
      color: fallbackColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background image that preserves entire image including borders
          // BoxFit.contain ensures no cropping - image scales to fit within bounds
          Image.asset(
            imagePath,
            fit: BoxFit.cover, // Preserves entire image without cropping
            alignment: Alignment.center,
            repeat: ImageRepeat.noRepeat,
            filterQuality: FilterQuality.high,
            width: double.infinity,
            height: double.infinity,
          ),
          // Child content on top (with SafeArea applied inside)
          child,
        ],
      ),
    );
  }
}

