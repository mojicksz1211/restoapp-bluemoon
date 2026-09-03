import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models.dart';

// Ported from menuApp/widgets/menu_item_card.dart so the waiter's "Get
// Order" catalog looks like the same app as the guest-facing menu — full
// photo (contain, on white so nothing gets cropped), dark bottom scrim,
// navy text. Kept as its own copy (not a shared import across app
// sections) since each role app owns its own MenuItem model type.

class _CardPerformance {
  final int memCacheWidth;
  final int memCacheHeight;
  final int maxDiskWidth;
  final int maxDiskHeight;
  final FilterQuality filterQuality;

  const _CardPerformance({
    required this.memCacheWidth,
    required this.memCacheHeight,
    required this.maxDiskWidth,
    required this.maxDiskHeight,
    required this.filterQuality,
  });

  static _CardPerformance of({
    required bool isMobile,
    required bool isLargeTablet,
    required double devicePixelRatio,
  }) {
    final dpr = devicePixelRatio.clamp(1.0, 2.0);
    final baseWidth = isMobile ? 400 : (isLargeTablet ? 700 : 560);
    final baseHeight = isMobile ? 300 : (isLargeTablet ? 520 : 420);
    return _CardPerformance(
      memCacheWidth: (baseWidth * dpr).round(),
      memCacheHeight: (baseHeight * dpr).round(),
      maxDiskWidth: isMobile ? 800 : (isLargeTablet ? 1400 : 1100),
      maxDiskHeight: isMobile ? 600 : (isLargeTablet ? 1040 : 840),
      filterQuality: isLargeTablet ? FilterQuality.high : FilterQuality.medium,
    );
  }
}

class GetOrderMenuCard extends StatelessWidget {
  final MenuItem item;
  final VoidCallback onTap;
  final Widget quantityControl;

  const GetOrderMenuCard({
    super.key,
    required this.item,
    required this.onTap,
    required this.quantityControl,
  });

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final shortestSide = mediaQuery.size.shortestSide;
    final isMobile = shortestSide < 600;
    final isLargeTablet = shortestSide >= 1024;
    final perf = _CardPerformance.of(
      isMobile: isMobile,
      isLargeTablet: isLargeTablet,
      devicePixelRatio: mediaQuery.devicePixelRatio,
    );

    final borderRadius = BorderRadius.circular(12);
    final titleFontSize = isMobile ? 13.0 : (isLargeTablet ? 19.0 : 15.5);

    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      elevation: 0,
      shadowColor: Colors.transparent,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final gradientHeight = (constraints.maxHeight * 0.48).clamp(80.0, 145.0);
            return Container(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 14,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Plain white backdrop behind the image so BoxFit.contain's
                  // letterbox gaps read as intentional whitespace, not a hole.
                  Container(color: Colors.white),
                  if (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                    item.imageUrl!.startsWith('http')
                        ? (kIsWeb
                            ? Image.network(
                                item.imageUrl!,
                                key: ValueKey('web_img_${item.imageUrl}'),
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                                filterQuality: perf.filterQuality,
                                errorBuilder: (context, error, stackTrace) => _imageFallback(),
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Container(color: Colors.transparent);
                                },
                              )
                            : CachedNetworkImage(
                                imageUrl: item.imageUrl!,
                                key: ValueKey('cni_${item.imageUrl}'),
                                cacheKey: '${item.imageUrl}_waitergrid',
                                fit: BoxFit.contain,
                                memCacheWidth: perf.memCacheWidth,
                                memCacheHeight: perf.memCacheHeight,
                                maxWidthDiskCache: perf.maxDiskWidth,
                                maxHeightDiskCache: perf.maxDiskHeight,
                                filterQuality: perf.filterQuality,
                                fadeInDuration: Duration.zero,
                                placeholder: (context, url) => Container(color: Colors.transparent),
                                errorWidget: (context, url, error) => _imageFallback(),
                              ))
                        : Image.asset(
                            item.imageUrl!,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            filterQuality: perf.filterQuality,
                            errorBuilder: (context, error, stackTrace) => _imageFallback(),
                          )
                  else
                    _imageFallback(),

                  // Dark bottom scrim + navy text — matches the guest menu's
                  // card treatment (see menuApp/widgets/menu_item_card.dart).
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

                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Padding(
                      padding: EdgeInsets.all(isMobile ? 6 : 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0C0E2B),
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 5,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '₱${formatPrice(item.price)}',
                                    style: GoogleFonts.urbanist(
                                      fontSize: isMobile ? 18.0 : (isLargeTablet ? 23.0 : 20.0),
                                      fontWeight: FontWeight.w900,
                                      color: const Color(0xFFE8C468),
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    item.name,
                                    style: GoogleFonts.urbanist(
                                      fontSize: titleFontSize,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      height: 1.15,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          quantityControl,
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

  Widget _imageFallback() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0x1F0C0E2B), Color(0x1F1B1E4A)],
        ),
      ),
      child: Center(
        child: Icon(item.icon, color: const Color(0xFF0C0E2B), size: 40),
      ),
    );
  }
}
