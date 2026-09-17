import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const SectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0C0E2B);
    const gold = Color(0xFFE8C468);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              color: gold,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.urbanist(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: navy,
              ),
            ),
          ),
          Text(
            subtitle,
            style: GoogleFonts.urbanist(
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  final int status;

  const StatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final info = orderStatusInfo(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: info.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        info.label,
        style: TextStyle(
          color: info.color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final String message;

  const EmptyState({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey[600]),
      ),
    );
  }
}

class StatusInfo {
  final String label;
  final Color color;

  const StatusInfo(this.label, this.color);
}

StatusInfo orderStatusInfo(int status) {
  switch (status) {
    case 3:
      return const StatusInfo('Pending', Colors.red);
    case 2:
      return const StatusInfo('Confirmed', Colors.orange);
    case 1:
      return const StatusInfo('Settled', Colors.green);
    case -1:
      return const StatusInfo('Cancelled', Colors.red);
    default:
      return const StatusInfo('Unknown', Colors.grey);
  }
}

