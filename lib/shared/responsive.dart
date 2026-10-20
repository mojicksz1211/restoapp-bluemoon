import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Tablet-first layout helpers. The target devices are 11–12.1" 16:10 tablets
/// (Redmi Pad 2 / Redmi Pad Pro, 2560×1600) which report roughly 1280×800
/// logical pixels; [designShortestSide] is that 800.
class Responsive {
  Responsive._();

  /// Shortest side (logical px) the layouts were tuned on.
  static const double designShortestSide = 800;

  /// Width cap for forms, inputs and popup cards so they don't stretch across
  /// a 12" landscape screen.
  static const double formMaxWidth = 480;
  static const double popupMaxWidth = 500;

  static bool isPhone(BuildContext context) =>
      MediaQuery.sizeOf(context).shortestSide < 600;

  static bool isLandscape(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width > size.height;
  }

  /// Screen-size factor relative to the target tablet, clamped so phones get a
  /// little smaller and bigger screens a little larger — never drastically.
  /// Based on the shortest side, so rotating the device doesn't change it.
  static double scaleOf(BuildContext context) {
    final shortest = MediaQuery.sizeOf(context).shortestSide;
    if (shortest <= 0) return 1;
    return (shortest / designShortestSide).clamp(0.85, 1.1);
  }

  /// Column count for a grid of tiles at least [minTileWidth] wide in
  /// [availableWidth], with [spacing] between tiles.
  static int columns(
    double availableWidth, {
    required double minTileWidth,
    double spacing = 12,
    int min = 1,
    int max = 6,
  }) {
    if (!availableWidth.isFinite || availableWidth <= 0) return min;
    final count = ((availableWidth + spacing) / (minTileWidth + spacing)).floor();
    return count.clamp(min, max);
  }
}

/// Goes in each MaterialApp's `builder`: scales text with the screen size
/// (see [Responsive.scaleOf]) on top of the user's system font size, clamped
/// so neither a large system setting nor a big screen blows text out of its
/// cards. Popups pushed on the app's navigator inherit it too.
class ResponsiveScope extends StatelessWidget {
  final Widget child;
  const ResponsiveScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final system = mq.textScaler.scale(14) / 14;
    final factor =
        (system.clamp(0.9, 1.2) * Responsive.scaleOf(context)).clamp(0.85, 1.25);
    return MediaQuery(
      data: mq.copyWith(textScaler: TextScaler.linear(factor)),
      child: child,
    );
  }
}

/// Centers [child] and caps its width — for forms, popup cards and buttons
/// that would otherwise stretch across a wide tablet screen.
class MaxWidthBox extends StatelessWidget {
  final double maxWidth;
  final Widget child;
  final AlignmentGeometry alignment;

  const MaxWidthBox({
    super.key,
    this.maxWidth = Responsive.formMaxWidth,
    this.alignment = Alignment.topCenter,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Scrolls [child] only when it can't fit (rotation, on-screen keyboard),
/// otherwise lays it out exactly as before at full available height.
class OverflowSafeScroll extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const OverflowSafeScroll({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: padding,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.hasBoundedHeight
                ? math.max(
                    0,
                    constraints.maxHeight -
                        (padding?.resolve(Directionality.of(context)).vertical ?? 0),
                  )
                : 0,
          ),
          child: child,
        ),
      ),
    );
  }
}
