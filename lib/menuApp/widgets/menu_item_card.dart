import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models.dart';

class _MenuItemCardPerformance {
  final int memCacheWidth;
  final int memCacheHeight;
  final int maxDiskWidth;
  final int maxDiskHeight;
  final FilterQuality filterQuality;
  final Duration fadeInDuration;
  final Widget placeholder;

  const _MenuItemCardPerformance({
    required this.memCacheWidth,
    required this.memCacheHeight,
    required this.maxDiskWidth,
    required this.maxDiskHeight,
    required this.filterQuality,
    required this.fadeInDuration,
    required this.placeholder,
  });
}

class _MenuItemCardPerformanceHelper {
  static _MenuItemCardPerformance performanceFor({
    required bool isMobile,
    required bool isLargeTablet,
    required double devicePixelRatio,
  }) {
    final isTabletOrLarger = !isMobile;
    // Base sizes are the LOGICAL pixel dimensions the card image actually
    // renders at. They must be scaled by devicePixelRatio, otherwise on any
    // display denser than 1x (the vast majority) CachedNetworkImage decodes
    // a bitmap smaller than the physical pixels it gets stretched across,
    // which is what was causing the blur.
    // Capped at 2.0 (not 3.0) — a category page shows 9-12 cards at once,
    // and decoding every one of them at 3x on top of FilterQuality.high was
    // the main render-cost/lag contributor once the (much bigger) broken-
    // image-URL bug was fixed. 2x already covers virtually every real
    // display without the extra cost of the rarely-seen 3x tier.
    final dpr = devicePixelRatio.clamp(1.0, 2.0);
    final baseWidth = isMobile ? 400 : (isLargeTablet ? 700 : 560);
    final baseHeight = isMobile ? 300 : (isLargeTablet ? 520 : 420);
    return _MenuItemCardPerformance(
      memCacheWidth: (baseWidth * dpr).round(),
      memCacheHeight: (baseHeight * dpr).round(),
      maxDiskWidth: isMobile ? 800 : (isLargeTablet ? 1400 : 1100),
      maxDiskHeight: isMobile ? 600 : (isLargeTablet ? 1040 : 840),
      // High quality filtering is the expensive part when many cards decode
      // at once; large tablet/desktop shows fewer, bigger cards per screen
      // so the cost is worth it there, but mobile/tablet grids (more,
      // smaller cards) use medium — still sharp, noticeably cheaper.
      filterQuality: isLargeTablet ? FilterQuality.high : FilterQuality.medium,
      fadeInDuration: isTabletOrLarger ? Duration.zero : const Duration(milliseconds: 250),
      // Avoid animating spinners for every tile on tablets.
      placeholder: Container(color: Colors.transparent),
    );
  }
}

class MenuItemCard extends StatelessWidget {
  final MenuItem item;
  final int estimatedMinutes;
  final VoidCallback onTap;
  final Widget quantityControl;

  const MenuItemCard({
    super.key,
    required this.item,
    required this.estimatedMinutes,
    required this.onTap,
    required this.quantityControl,
  });

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final orientation = mediaQuery.orientation;
    // Use shortestSide para tama detection kahit malapad ang phone sa landscape
    final shortestSide = size.shortestSide;
    final isMobile = shortestSide < 600;
    final isMobileLandscape = isMobile && orientation == Orientation.landscape;
    final isTablet = shortestSide >= 600 && shortestSide < 1024;
    final isTabletPortrait = isTablet && orientation == Orientation.portrait;
    final isLargeTablet = shortestSide >= 1024; // iPad Pro and larger
    final perf = _MenuItemCardPerformanceHelper.performanceFor(
      isMobile: isMobile,
      isLargeTablet: isLargeTablet,
      devicePixelRatio: mediaQuery.devicePixelRatio,
    );

    final borderRadius = BorderRadius.circular(12);
    // Reduced padding for compact design
    final infoPadding = EdgeInsets.fromLTRB(
      isMobileLandscape ? 8 : (isMobile ? 10 : (isLargeTablet ? 20 : 14)),
      isMobileLandscape ? 2 : (isMobile ? 4 : (isLargeTablet ? 10 : (isTabletPortrait ? 6 : 8))),
      isMobileLandscape ? 8 : (isMobile ? 10 : (isLargeTablet ? 20 : 14)),
      isMobileLandscape ? 2 : (isMobile ? 4 : (isLargeTablet ? 12 : (isTabletPortrait ? 6 : 10))),
    );
    final titleFontSize = isMobileLandscape
        ? 11.0 // Smaller for mobile landscape
        : (isMobile ? 14.0 : (isLargeTablet ? 24.0 : (isTabletPortrait ? 16.0 : 18.0)));

    return Material(
      color: Colors.transparent, // Transparent para makita ang image
      borderRadius: borderRadius,
      elevation: 0,
      shadowColor: Colors.transparent,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
        // Scale the bottom scrim off the card's ACTUAL rendered height
        // instead of a fixed guess — the grid's childAspectRatio varies a lot
        // by breakpoint/orientation, so a fixed pixel height can end up
        // covering way more (or less) than intended.
        final gradientHeight = (constraints.maxHeight * 0.32).clamp(70.0, 150.0);
        return Container(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 18,
                offset: const Offset(0, 13),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Plain white backdrop behind the image so BoxFit.contain's
              // letterbox gaps (when the photo's aspect ratio doesn't match
              // the card) read as intentional whitespace, not a hole.
              Container(color: Colors.white),
              // Full image — contain (not cover) so the whole photo shows
              // instead of being cropped/zoomed to fill the card.
              item.imageUrl != null && item.imageUrl!.startsWith('http')
                  ? CachedNetworkImage(
                      imageUrl: item.imageUrl!,
                      // Distinct cache identity from the detail/full-screen
                      // viewers' CachedNetworkImage for the same URL — those
                      // request larger sizes and get disposed quickly when
                      // the user backs out fast, which can cancel a shared
                      // in-flight download in flutter_cache_manager and take
                      // this grid card's own (still-mounted) request down
                      // with it, showing broken/blank images. Separate keys
                      // make each usage's download independent.
                      cacheKey: '${item.imageUrl}_grid',
                      fit: BoxFit.contain,
                      memCacheWidth: perf.memCacheWidth,
                      memCacheHeight: perf.memCacheHeight,
                      maxWidthDiskCache: perf.maxDiskWidth,
                      maxHeightDiskCache: perf.maxDiskHeight,
                      filterQuality: perf.filterQuality,
                      fadeInDuration: perf.fadeInDuration,
                      fadeOutDuration: const Duration(milliseconds: 100),
                      placeholder: (context, url) => perf.placeholder,
                      errorWidget: (context, url, error) => _imageFallback(context),
                    )
                  : item.imageUrl != null
                      ? Image.asset(
                          item.imageUrl!,
                          fit: BoxFit.contain,
                      cacheWidth: perf.memCacheWidth,
                      cacheHeight: perf.memCacheHeight,
                      filterQuality: perf.filterQuality,
                      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                        if (wasSynchronouslyLoaded) return child;
                        return frame == null ? perf.placeholder : child;
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return _imageFallback(context);
                      },
                    )
                      : _imageFallback(context),

              // Dark bottom scrim, back the way it was — but darker/more
              // opaque than the original 0.62, since the backdrop behind it
              // is now white (BoxFit.contain) instead of a full-bleed photo.
              // At 0.62 over white it only reached medium-gray, which is why
              // white text on top of it wasn't reading clearly; at this
              // alpha it's dark enough for white text again regardless of
              // what's behind it.
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: gradientHeight,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.0),
                        Colors.black.withValues(alpha: 0.88),
                      ],
                    ),
                  ),
                ),
              ),

              // Content overlay at bottom
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Padding(
                  padding: infoPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.category.toUpperCase(),
                              style: GoogleFonts.raleway(
                                fontSize: isMobileLandscape
                                    ? 9.0
                                    : (isMobile
                                        ? 12.0
                                        : (isLargeTablet ? 18.0 : (isTabletPortrait ? 12.0 : 13.0))),
                                letterSpacing: isMobileLandscape ? 1.2 : 2,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF0C0E2B),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '₱${formatPrice(item.price)}',
                            style: GoogleFonts.raleway(
                              fontSize: isMobileLandscape
                                  ? 14.0
                                  : (isMobile
                                      ? 16.0
                                      : (isLargeTablet ? 24.0 : (isTabletPortrait ? 17.0 : 18.0))),
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0C0E2B),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(
                        height: isMobileLandscape
                            ? 1.0
                            : (isMobile
                                ? 2.0
                                : (isLargeTablet ? 6.0 : (isTabletPortrait ? 2.0 : 3.0))),
                      ),
                      Text(
                        item.name,
                        style: GoogleFonts.robotoSlab(
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0C0E2B),
                          height: isMobileLandscape ? 1.0 : 1.05,
                        ),
                        maxLines: (isMobileLandscape) ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(
                        height: (isMobileLandscape
                                ? 1.0
                                : (isMobile
                                    ? 3.0
                                    : (isLargeTablet ? 8.0 : (isTabletPortrait ? 3.0 : 5.0)))) *
                            0.5,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          quantityControl,
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
          },
        ),
      ),
    );
  }

  Widget _imageFallback(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0C0E2B).withValues(alpha: 0.12), // Maroon gradient
            const Color(0xFF1B1E4A).withValues(alpha: 0.12),
          ],
        ),
      ),
      child: Center(
        child: Icon(item.icon, color: const Color(0xFF0C0E2B), size: 56), // Maroon
      ),
    );
  }
}
