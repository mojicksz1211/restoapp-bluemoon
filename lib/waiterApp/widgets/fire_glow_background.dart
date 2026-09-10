import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A looping "burning" fire animation for [child]. Flames leap up from behind
/// the child's silhouette only — nothing paints over the child. Purely
/// decorative: pointer events pass straight through, so the child stays fully
/// tappable.
///
/// Tuned to stay cheap while scrolling: no `MaskFilter.blur`, one gradient
/// shader per layer per frame (not per flame), and the repaint is quantised to
/// ~30fps.
class FireGlowBackground extends StatefulWidget {
  const FireGlowBackground({
    super.key,
    required this.child,
    this.flameCount = 9,
    this.spread = const EdgeInsets.fromLTRB(22, 46, 22, 12),
  });

  final Widget child;

  /// Number of flame tongues along the base.
  final int flameCount;

  /// How far the fire canvas reaches beyond the child on each side.
  final EdgeInsets spread;

  @override
  State<FireGlowBackground> createState() => _FireGlowBackgroundState();
}

class _FireGlowBackgroundState extends State<FireGlowBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Clock: value climbs 1.0 per second, loops after 600s so the sine-based
    // flicker never visibly jumps.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 600),
      upperBound: 600,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Positioned(
          left: -widget.spread.left,
          right: -widget.spread.right,
          top: -widget.spread.top,
          bottom: -widget.spread.bottom,
          child: IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  // Quantise to ~30fps so we repaint at most every other frame
                  // on a 60Hz display — plenty for flicker, half the work.
                  final t = (_controller.value * 30).floorToDouble() / 30;
                  return CustomPaint(
                    size: Size.infinite,
                    isComplex: true,
                    willChange: true,
                    painter: _FirePainter(
                      t: t,
                      flameCount: widget.flameCount,
                      spread: widget.spread,
                    ),
                    child: const SizedBox.expand(),
                  );
                },
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _FirePainter extends CustomPainter {
  _FirePainter({
    required this.t,
    required this.flameCount,
    required this.spread,
  });

  /// Seconds since start, quantised to 1/30s steps.
  final double t;
  final int flameCount;
  final EdgeInsets spread;

  // Cooler outer body first, hot core last. Additive blending blooms the
  // overlaps toward white, the way a real flame does. Soft alpha falloff
  // stands in for a blur so we never touch MaskFilter.
  static const List<List<Color>> _layerColors = [
    [Color(0x99FF2A00), Color(0x1AFF4A00), Color(0x00FF5A00)], // red halo
    [Color(0xE6FF8A12), Color(0x33FFA020), Color(0x00FFB020)], // orange body
    [Color(0xFFFFF0B0), Color(0x59FFD060), Color(0x00FFC24B)], // yellow core
  ];
  static const List<double> _layerStops = [0.0, 0.5, 1.0];
  static const List<double> _layerScale = [1.18, 0.8, 0.48];
  static const List<double> _layerWidth = [1.15, 0.85, 0.55];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // Where the child sits inside our oversized canvas.
    final childRect = Rect.fromLTRB(
      spread.left,
      spread.top,
      size.width - spread.right,
      size.height - spread.bottom,
    );
    final baseY = childRect.bottom;
    final spanLeft = childRect.left - spread.left * 0.4;
    final spanRight = childRect.right + spread.right * 0.4;
    final usableWidth = spanRight - spanLeft;
    final gap = usableWidth / (flameCount - 1);
    final maxHeight = childRect.height + spread.top * 1.05;

    for (var layer = 0; layer < _layerColors.length; layer++) {
      final scale = _layerScale[layer];

      // ONE shader for the whole layer — colour depends only on height, so
      // every flame in the layer can share it.
      final paint = Paint()
        ..blendMode = BlendMode.plus
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: _layerColors[layer],
          stops: _layerStops,
        ).createShader(
          Rect.fromLTRB(0, baseY - maxHeight * scale, 0, baseY),
        );

      final path = Path();
      for (var i = 0; i < flameCount; i++) {
        final phase = i * 1.7 + layer * 0.9;
        final flicker = 0.78 +
            0.17 * math.sin(t * 7.3 + phase) +
            0.09 * math.sin(t * 16.5 + phase * 2.3);
        final sway = math.sin(t * 3.1 + phase) * gap * 0.6 +
            math.sin(t * 6.7 + phase * 1.7) * gap * 0.28;

        // Middle flames burn taller than the edges.
        final edgeFalloff =
            1 - 0.4 * (((i / (flameCount - 1)) - 0.5).abs() * 2);
        final height = maxHeight * scale * flicker * (0.6 + 0.4 * edgeFalloff);
        final baseX = spanLeft + gap * i;
        final flameWidth = gap * _layerWidth[layer];
        final tipX = baseX + sway;
        final tipY = baseY - height;

        path
          ..moveTo(baseX - flameWidth / 2, baseY)
          ..quadraticBezierTo(
            baseX - flameWidth * 0.5 + sway * 0.3,
            baseY - height * 0.5,
            tipX,
            tipY,
          )
          ..quadraticBezierTo(
            baseX + flameWidth * 0.5 + sway * 0.3,
            baseY - height * 0.5,
            baseX + flameWidth / 2,
            baseY,
          )
          ..close();
      }
      canvas.drawPath(path, paint);
    }

    _paintEmbers(canvas, size, baseY, spanLeft, usableWidth);
  }

  void _paintEmbers(
      Canvas canvas, Size size, double baseY, double spanLeft, double span) {
    final paint = Paint()..blendMode = BlendMode.plus;
    const count = 6;
    for (var i = 0; i < count; i++) {
      final phase = i * 2.399;
      final life = (t * 0.3 + i / count) % 1.0;
      final x = spanLeft +
          span * ((i + 0.5) / count) +
          math.sin(t * 2.0 + phase) * span * 0.08;
      final y = baseY - life * (baseY + size.height * 0.12);
      final radius = (2.0 + math.sin(t * 9 + phase)) * (1 - life);
      final opacity = (1 - life) * 0.75;
      if (radius <= 0 || opacity <= 0) continue;
      paint.color = Color.lerp(
        const Color(0xFFFFE08A),
        const Color(0xFFFF4D1A),
        life,
      )!
          .withValues(alpha: opacity);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_FirePainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.flameCount != flameCount;
}
