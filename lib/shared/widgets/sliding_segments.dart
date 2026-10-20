import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _navy = Color(0xFF0C0E2B);
const _navy2 = Color(0xFF1B1E4A);
const _gold = Color(0xFFE8C468);
const _line = Color(0xFFDDDED3);
const _muted = Color(0xFF6B6F80);

/// Segmented tab bar: white rounded track with a navy pill that slides under
/// the selected segment. Segments are equal width.
///
/// Pass [position] (e.g. `TabController.animation`) to make the pill follow
/// that value continuously -- it then tracks a finger swipe between pages
/// live instead of jumping once the swipe settles. Without it the pill just
/// animates to [selectedIndex].
class SlidingSegments extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final List<SegmentLabel> segments;
  final Animation<double>? position;

  const SlidingSegments({
    super.key,
    required this.selectedIndex,
    required this.onChanged,
    required this.segments,
    this.position,
  });

  @override
  Widget build(BuildContext context) {
    final pos = position;
    if (pos == null) return _body(selectedIndex, selectedIndex.toDouble());
    return AnimatedBuilder(
      animation: pos,
      builder: (context, _) {
        final v = pos.value.clamp(0.0, (segments.length - 1).toDouble());
        return _body(v.round(), v);
      },
    );
  }

  Widget _body(int selected, double at) {
    final n = segments.length;
    final x = n <= 1 ? 0.0 : -1 + 2 * at / (n - 1);
    final thumb = FractionallySizedBox(
      widthFactor: 1 / n,
      heightFactor: 1,
      child: const DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          gradient: LinearGradient(colors: [_navy, _navy2]),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: SizedBox(
        height: 44,
        child: Stack(
          children: [
            // Following an animation: place the pill exactly at its value.
            // Otherwise ease it to the selected segment.
            if (position != null)
              Align(alignment: Alignment(x, 0), child: thumb)
            else
              AnimatedAlign(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: Alignment(x, 0),
                child: thumb,
              ),
            Row(
              children: [
                for (var i = 0; i < n; i++)
                  Expanded(
                    child: GestureDetector(
                      onTap: () => onChanged(i),
                      behavior: HitTestBehavior.opaque,
                      child: Center(
                        // Scales down instead of overflowing when the
                        // segments share a narrow phone screen.
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: segments[i].withSelected(i == selected),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Icon + uppercase label + optional count for one [SlidingSegments] segment.
/// Colors animate in step with the sliding pill.
class SegmentLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  final int count;

  /// Red pill badge (needs attention) instead of a plain count.
  final bool alert;
  final bool selected;

  const SegmentLabel({
    super.key,
    required this.label,
    required this.icon,
    this.count = 0,
    this.alert = false,
    this.selected = false,
  });

  Widget withSelected(bool value) => SegmentLabel(
    label: label,
    icon: icon,
    count: count,
    alert: alert,
    selected: value,
  );

  @override
  Widget build(BuildContext context) {
    const dur = Duration(milliseconds: 240);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: selected ? _gold : _muted),
          duration: dur,
          builder: (_, c, _) => Icon(icon, size: 19, color: c),
        ),
        const SizedBox(width: 8),
        TweenAnimationBuilder<Color?>(
          tween: ColorTween(
            end: selected ? _gold : _navy.withValues(alpha: 0.75),
          ),
          duration: dur,
          builder: (_, c, _) => Text(
            label.toUpperCase(),
            style: GoogleFonts.urbanist(
              color: c,
              fontWeight: FontWeight.w900,
              fontSize: 14,
              letterSpacing: 1.6,
            ),
          ),
        ),
        if (count > 0) ...[
          const SizedBox(width: 8),
          if (alert)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              constraints: const BoxConstraints(minWidth: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFD32F2F),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                textAlign: TextAlign.center,
                style: GoogleFonts.urbanist(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            )
          else
            TweenAnimationBuilder<Color?>(
              tween: ColorTween(
                end: selected ? _gold.withValues(alpha: 0.8) : _muted,
              ),
              duration: dur,
              builder: (_, c, _) => Text(
                count > 99 ? '99+' : '$count',
                style: GoogleFonts.urbanist(
                  color: c,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ],
    );
  }
}
