import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _navy = Color(0xFF0C0E2B);
const _gold = Color(0xFFE8C468);
const _goldDeep = Color(0xFFB8902F);

/// Centered title between thin gold rules with a small count underneath --
/// the same section header the Switch Menu and Table Monitoring use. The title
/// keeps its natural width (capped at 70%) and the two rules split what is
/// left equally, so the whole line stays centered.
class CenteredSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const CenteredSectionHeader({super.key, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    Widget rule(bool left) => Expanded(
      child: Container(
        height: 1.2,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: left ? Alignment.centerLeft : Alignment.centerRight,
            end: left ? Alignment.centerRight : Alignment.centerLeft,
            colors: [_gold.withValues(alpha: 0), _gold.withValues(alpha: 0.9)],
          ),
        ),
      ),
    );

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, c) => Row(
            children: [
              rule(true),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: c.maxWidth * 0.7),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    title.toUpperCase(),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.urbanist(
                      color: _navy,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.6,
                      height: 1.15,
                    ),
                  ),
                ),
              ),
              rule(false),
            ],
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: GoogleFonts.urbanist(
              color: _goldDeep,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ],
    );
  }
}
