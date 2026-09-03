import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models.dart';

class ConfirmOrderLine {
  final String name;
  final double quantity;
  final double unitPrice;
  final double? lineTotal;
  final String? remarks;

  const ConfirmOrderLine({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    this.lineTotal,
    this.remarks,
  });

  double get total => lineTotal ?? quantity * unitPrice;
}

class ConfirmOrderBottomSheet extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<ConfirmOrderLine> items;
  final double total;
  final String? orderTypeLabel;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  const ConfirmOrderBottomSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.items,
    required this.total,
    this.orderTypeLabel,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenWidth = mq.size.width;
    final isMobile = screenWidth < 600;
    // Landscape tablet has very little vertical height — open the sheet
    // much higher so order details are immediately visible without dragging.
    final isTabletLandscape = !isMobile && mq.orientation == Orientation.landscape;

    return DraggableScrollableSheet(
      initialChildSize: isMobile ? 0.75 : (isTabletLandscape ? 0.88 : 0.65),
      minChildSize: isMobile ? 0.6 : (isTabletLandscape ? 0.75 : 0.5),
      maxChildSize: isTabletLandscape ? 0.97 : 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Container(
              padding: EdgeInsets.all(isMobile ? 16 : 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)],
                ),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.urbanist(
                            fontSize: isMobile ? 18 : 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: GoogleFonts.urbanist(
                            fontSize: isMobile ? 13 : 14.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 26),
                    onPressed: onCancel,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                color: const Color(0xFFF5F6F0),
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.all(isMobile ? 16 : 20),
                  children: [
                    Text(
                      'Order Details',
                      style: GoogleFonts.urbanist(
                        fontSize: isMobile ? 16 : 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...items.map(
                      (line) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              line.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.urbanist(
                                fontSize: isMobile ? 14 : 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (line.remarks != null && line.remarks!.trim().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8C468).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFE8C468).withValues(alpha: 0.6)),
                                ),
                                child: Text(
                                  '📝 ${line.remarks}',
                                  style: GoogleFonts.urbanist(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFFB45309),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(
                                  '${line.quantity.toStringAsFixed(line.quantity % 1 == 0 ? 0 : 2)} × ₱${formatPrice(line.unitPrice)}',
                                  style: GoogleFonts.urbanist(
                                    fontSize: isMobile ? 12 : 14,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '₱${formatPrice(line.total)}',
                                  style: GoogleFonts.urbanist(
                                    fontSize: isMobile ? 12 : 14,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF0C0E2B),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (orderTypeLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Text(
                              'Order Type',
                              style: GoogleFonts.urbanist(
                                fontSize: isMobile ? 12 : 14,
                                color: Colors.grey[700],
                              ),
                            ),
                            const Spacer(),
                            Text(
                              orderTypeLabel!,
                              style: GoogleFonts.urbanist(
                                fontSize: isMobile ? 12 : 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        Text(
                          'Total',
                          style: GoogleFonts.urbanist(
                            fontSize: isMobile ? 14 : 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '₱${formatPrice(total)}',
                          style: GoogleFonts.urbanist(
                            fontSize: isMobile ? 14 : 16,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0C0E2B),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.all(isMobile ? 16 : 20),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F6F0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          onCancel();
                          Navigator.pop(context, false);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0C0E2B),
                          side: const BorderSide(color: Color(0xFF0C0E2B)),
                          padding: EdgeInsets.symmetric(
                            vertical: isMobile ? 14 : 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.urbanist(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0C0E2B).withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () {
                            onConfirm();
                            Navigator.pop(context, true);
                          },
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              vertical: isMobile ? 14 : 16,
                            ),
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ).copyWith(
                            overlayColor: WidgetStateProperty.all(Colors.transparent),
                          ),
                          child: Text(
                            'Confirm',
                            style: GoogleFonts.urbanist(
                              fontWeight: FontWeight.bold,
                              fontSize: isMobile ? 14 : 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

