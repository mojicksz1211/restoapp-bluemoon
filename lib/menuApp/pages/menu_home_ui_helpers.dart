part of 'menu_home_page.dart';

extension _MenuHomeUiHelpers on _MenuHomePageState {
  void _resetDisplayLimit() {
    setState(() {
      _displayLimit = 9; // Reset to initial limit
    });
  }

  Future<void> _showFlyAnimation(BuildContext context, MenuItem item) {
    _flyInFlight = (_flyInFlight ?? Future.value()).then((_) {
      final completer = Completer<void>();

      // Use post frame callback to ensure the widget tree is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          completer.complete();
          return;
        }

        // Use side panel cart icon if panel is open, otherwise use FAB.
        final isWide = _isWideLayout(context);
        final targetKey = (isWide && _isCartPanelOpen) ? _cartIconKey : _cartFabKey;
        final cartContext = targetKey.currentContext;
        if (cartContext == null) {
          completer.complete();
          return;
        }

        final startBox = context.findRenderObject() as RenderBox?;
        if (startBox == null) {
          completer.complete();
          return;
        }
        // Start from center of the tapped item
        final startSize = startBox.size;
        final startPosition = startBox.localToGlobal(
          Offset(startSize.width / 2, startSize.height / 2),
        );

        final endBox = cartContext.findRenderObject() as RenderBox?;
        if (endBox == null) {
          completer.complete();
          return;
        }
        // End at center of the cart icon
        final endSize = endBox.size;
        final endPosition = endBox.localToGlobal(
          Offset(endSize.width / 2, endSize.height / 2),
        );

        // Update animations with positions
        _flyAnimation = Tween<Offset>(
          begin: startPosition,
          end: endPosition,
        ).animate(CurvedAnimation(parent: _flyController, curve: Curves.easeInOut));

        final overlay = Overlay.of(context);
        final overlayEntry = OverlayEntry(
          builder: (context) => AnimatedBuilder(
            animation: _flyController,
            builder: (context, child) {
              final progress = _flyController.value;
              const holdDelayMs = 1000;
              final totalMs = _flyController.duration?.inMilliseconds ?? 1000;
              final holdPortion =
                  (holdDelayMs / totalMs).clamp(0.0, 0.9);
              final flyT =
                  progress < holdPortion ? 0.0 : (progress - holdPortion) / (1 - holdPortion);
              final t = Curves.easeInOutCubic.transform(flyT.clamp(0.0, 1.0));
              final dx = startPosition.dx + (endPosition.dx - startPosition.dx) * t;
              final dy = startPosition.dy + (endPosition.dy - startPosition.dy) * t;
              // Add a smooth arc to the path for a more natural "fly" feel.
              final distance = (endPosition - startPosition).distance;
              final arcHeight = (distance * 0.22).clamp(70.0, 160.0);
              final arcOffset = math.sin(t * math.pi) * arcHeight;
              final position = Offset(dx, dy - arcOffset);

              // Adjust position to center the flying item (80x80, so center is at 40,40)
              return Positioned(
                left: position.dx - 40,
                top: position.dy - 40,
                child: Opacity(
                  opacity: _flyOpacity.value,
                  child: Transform.rotate(
                    angle: _flyRotation.value,
                    child: Transform.scale(
                      scale: _flyScale.value,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.28),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                              ? Image.network(
                                  item.imageUrl!,
                                  fit: BoxFit.cover,
                                  width: 80,
                                  height: 80,
                                  errorBuilder: (context, error, stackTrace) => Container(
                                    color: Colors.red,
                                    child: const Icon(
                                      Icons.restaurant_menu,
                                      color: Colors.white,
                                      size: 30,
                                    ),
                                  ),
                                )
                              : Container(
                                  color: Colors.red,
                                  child: const Icon(
                                    Icons.restaurant_menu,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );

        overlay.insert(overlayEntry);
        _flyController
            .forward(from: 0)
            .then((_) {
          overlayEntry.remove();
          _flyController.reset();
          // Trigger cart shake animation when flying animation completes
          _cartShakeController.forward(from: 0);
        }).whenComplete(() {
          if (!completer.isCompleted) {
            completer.complete();
          }
        });
      });

      return completer.future;
    });
    return _flyInFlight!;
  }

  // Returns the in-flight future (not just fire-and-forget) so callers that
  // need to know when the animation + actual cart increase are done — e.g.
  // the item detail modal refreshing its own displayed quantity — can await
  // it. Existing IconButton.onPressed callers can keep ignoring the result.
  Future<void> _onAddPressed(BuildContext context, MenuItem item) {
    return _showFlyAnimation(context, item).whenComplete(() {
      if (!mounted) return;
      increaseItemQuantity(item);
    });
  }

  Widget _buildQuantityControl({
    required MenuItem item,
    required int quantity,
    required bool isMobile,
    required bool isLargeTablet,
    Key? key,
  }) {
    return Builder(
      builder: (context) => quantity == 0
          ? Container(
              key: key ?? ValueKey('${item.name}_0'),
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
                icon:
                    Icon(Icons.add, size: isMobile ? 20 : (isLargeTablet ? 32 : 22), color: Colors.white),
                onPressed: () => _onAddPressed(context, item),
                padding: EdgeInsets.all(isMobile ? 4 : (isLargeTablet ? 10 : 5)),
                constraints: BoxConstraints(
                  minWidth: isMobile ? 32 : (isLargeTablet ? 48 : 36),
                  minHeight: isMobile ? 32 : (isLargeTablet ? 48 : 36),
                ),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  alignment: Alignment.center,
                ),
              ),
            )
          : Container(
              key: key ?? ValueKey('${item.name}_$quantity'),
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
                      size: isMobile ? 20 : (isLargeTablet ? 32 : 22),
                      color: Colors.white,
                    ),
                    onPressed: () => decreaseItemQuantity(item),
                    padding: EdgeInsets.all(isMobile ? 4 : (isLargeTablet ? 10 : 5)),
                    constraints: BoxConstraints(
                      minWidth: isMobile ? 32 : (isLargeTablet ? 48 : 36),
                      minHeight: isMobile ? 32 : (isLargeTablet ? 48 : 36),
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      alignment: Alignment.center,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: isMobile ? 6 : (isLargeTablet ? 12 : 8)),
                    child: Text(
                      '$quantity',
                      style: GoogleFonts.urbanist(
                        fontWeight: FontWeight.bold,
                        fontSize: isMobile ? 14 : (isLargeTablet ? 24 : 16),
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.add,
                      size: isMobile ? 20 : (isLargeTablet ? 32 : 22),
                      color: Colors.white,
                    ),
                    onPressed: () => _onAddPressed(context, item),
                    padding: EdgeInsets.all(isMobile ? 4 : (isLargeTablet ? 10 : 5)),
                    constraints: BoxConstraints(
                      minWidth: isMobile ? 32 : (isLargeTablet ? 48 : 36),
                      minHeight: isMobile ? 32 : (isLargeTablet ? 48 : 36),
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      alignment: Alignment.center,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

