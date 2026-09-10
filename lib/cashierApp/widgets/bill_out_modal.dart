import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../waiterApp/waiter_models.dart';

class BillOutModal extends StatelessWidget {
  final WaiterOrder order;
  final VoidCallback onSettle;

  const BillOutModal({
    super.key,
    required this.order,
    required this.onSettle,
  });

  static void show(BuildContext context, {required WaiterOrder order, required VoidCallback onSettle}) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => BillOutModal(order: order, onSettle: onSettle),
    );
  }

  String _formatCurrency(double amount) {
    return amount.toStringAsFixed(2).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  /// How many room-charge units the service charge represents, when it
  /// divides evenly into the table's base ROOM_CHARGE; null otherwise.
  int? get _roomChargeUnits {
    final rate = order.roomCharge;
    final total = order.serviceCharge;
    if (rate <= 0 || total <= 0) return null;
    final q = total / rate;
    final rounded = q.round();
    if (rounded >= 1 && (q - rounded).abs() < 0.01) return rounded;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0C0E2B);
    const gold = Color(0xFFD97706);

    final rawTableName = (order.tableNumber ?? '').trim();
    final displayTable = rawTableName.isEmpty
        ? 'Dine-In'
        : (rawTableName.toLowerCase().startsWith('table') ? rawTableName : 'Table $rawTableName');

    final itemsSubtotal = order.items.fold<double>(0, (sum, it) => sum + it.lineTotal);
    final roomCharge = order.serviceCharge;
    final totalQty = order.items.fold<double>(0, (sum, it) => sum + it.quantity);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Center(
        child: Container(
          width: 420,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)],
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long_rounded, color: Color(0xFFE8C468), size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'STATEMENT OF ACCOUNT',
                            style: GoogleFonts.urbanist(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              letterSpacing: 0.8,
                            ),
                          ),
                          Text(
                            'Bill Out Preview',
                            style: GoogleFonts.urbanist(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                      splashRadius: 18,
                    ),
                  ],
                ),
              ),

              // Receipt Body (Scrollable)
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    children: [
                      // Restaurant Branding
                      Text(
                        'BLUE MOON',
                        style: GoogleFonts.cinzel(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          color: navy,
                        ),
                      ),
                      Text(
                        'BAR & RESTAURANT',
                        style: GoogleFonts.urbanist(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildDottedDivider(),
                      const SizedBox(height: 12),

                      // Order Meta Info
                      _buildMetaRow('Order No:', order.orderNo ?? '#${order.id}'),
                      const SizedBox(height: 4),
                      _buildMetaRow('Table:', displayTable),
                      const SizedBox(height: 4),
                      _buildMetaRow('Order Type:', order.orderType ?? 'DINE-IN'),
                      const SizedBox(height: 4),
                      _buildMetaRow('Date / Time:', order.formatGmt8DateTime(use12Hour: true)),
                      const SizedBox(height: 12),
                      _buildDottedDivider(),
                      const SizedBox(height: 12),

                      // Column Headers
                      Row(
                        children: [
                          Expanded(
                            flex: 5,
                            child: Text(
                              'ITEM',
                              style: GoogleFonts.urbanist(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.grey.shade700, letterSpacing: 0.5),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              'QTY',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.urbanist(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.grey.shade700, letterSpacing: 0.5),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              'PRICE',
                              textAlign: TextAlign.right,
                              style: GoogleFonts.urbanist(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.grey.shade700, letterSpacing: 0.5),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Order Items List
                      ...order.items.map((item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 5,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: GoogleFonts.urbanist(fontWeight: FontWeight.w700, fontSize: 14, color: navy),
                                  ),
                                  if (item.remarks != null && item.remarks!.trim().isNotEmpty)
                                    Text(
                                      '(${item.remarks})',
                                      style: GoogleFonts.urbanist(fontSize: 11.5, fontStyle: FontStyle.italic, color: Colors.grey.shade500),
                                    ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                item.quantity % 1 == 0 ? item.quantity.toInt().toString() : item.quantity.toStringAsFixed(1),
                                textAlign: TextAlign.center,
                                style: GoogleFonts.urbanist(fontWeight: FontWeight.w900, fontSize: 14.5, color: navy),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                '₱${_formatCurrency(item.lineTotal)}',
                                textAlign: TextAlign.right,
                                style: GoogleFonts.urbanist(fontWeight: FontWeight.w800, fontSize: 14.5, color: navy),
                              ),
                            ),
                          ],
                        ),
                      )),
                      if (roomCharge > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 5,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Room Charge (${order.tableNumber ?? 'VIP Room'})',
                                      style: GoogleFonts.urbanist(fontWeight: FontWeight.w800, fontSize: 14, color: const Color(0xFFD97706)),
                                    ),
                                    if (_roomChargeUnits != null && order.roomCharge > 0)
                                      Text(
                                        _roomChargeUnits! > 1
                                            ? 'Base ₱${_formatCurrency(order.roomCharge)} + ${_roomChargeUnits! - 1} extension${_roomChargeUnits! - 1 == 1 ? '' : 's'}  (₱${_formatCurrency(order.roomCharge)} × ${_roomChargeUnits!})'
                                            : 'Base rate ₱${_formatCurrency(order.roomCharge)}',
                                        style: GoogleFonts.urbanist(fontWeight: FontWeight.w600, fontSize: 11, color: Colors.grey.shade500),
                                      ),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '${_roomChargeUnits ?? 1}',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.urbanist(fontWeight: FontWeight.w900, fontSize: 14.5, color: const Color(0xFFD97706)),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  '₱${_formatCurrency(roomCharge)}',
                                  textAlign: TextAlign.right,
                                  style: GoogleFonts.urbanist(fontWeight: FontWeight.w900, fontSize: 14.5, color: const Color(0xFFD97706)),
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 12),
                      _buildDottedDivider(),
                      const SizedBox(height: 12),

                      // Totals Breakdown
                      _buildSummaryRow('Total Items:', '${totalQty % 1 == 0 ? totalQty.toInt() : totalQty.toStringAsFixed(1)} item(s)'),
                      const SizedBox(height: 6),
                      if (roomCharge > 0) ...[
                        _buildSummaryRow('Items Subtotal:', '₱${_formatCurrency(itemsSubtotal)}'),
                        const SizedBox(height: 6),
                        _buildSummaryRow(
                          _roomChargeUnits != null && _roomChargeUnits! > 1 && order.roomCharge > 0
                              ? 'Room Charge (₱${_formatCurrency(order.roomCharge)} × ${_roomChargeUnits!}):'
                              : 'Room Charge:',
                          '₱${_formatCurrency(roomCharge)}',
                          valueColor: const Color(0xFFD97706),
                        ),
                        const SizedBox(height: 6),
                        _buildSummaryRow('Subtotal:', '₱${_formatCurrency(itemsSubtotal + roomCharge)}'),
                      ] else ...[
                        _buildSummaryRow('Subtotal:', '₱${_formatCurrency(itemsSubtotal > 0 ? itemsSubtotal : order.grandTotal)}'),
                      ],
                      if (order.discountAmount > 0) ...[
                        const SizedBox(height: 6),
                        _buildSummaryRow(
                          'Discount:',
                          '-₱${_formatCurrency(order.discountAmount)}',
                          valueColor: Colors.red.shade700,
                        ),
                      ],
                      const SizedBox(height: 10),
                      _buildDottedDivider(),
                      const SizedBox(height: 10),

                      // Grand Total Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'AMOUNT DUE',
                            style: GoogleFonts.urbanist(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: navy,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            '₱${_formatCurrency(order.grandTotal)}',
                            style: GoogleFonts.urbanist(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: gold,
                            ),
                          ),
                        ],
                      ),
                      if (order.status == 1) ...[
                        const SizedBox(height: 10),
                        _buildDottedDivider(),
                        const SizedBox(height: 10),
                        _buildSummaryRow('Payment Method:', (order.paymentMethod ?? 'CASH').toUpperCase()),
                        const SizedBox(height: 6),
                        _buildSummaryRow(
                          (order.paymentMethod ?? 'CASH').toUpperCase() == 'CASH'
                              ? 'Cash Tendered:'
                              : 'Amount Paid:',
                          '₱${_formatCurrency(order.amountPaid > 0 ? order.amountPaid : order.grandTotal)}',
                        ),
                        if ((order.amountPaid - order.grandTotal) > 0) ...[
                          const SizedBox(height: 6),
                          _buildSummaryRow(
                            'Change:',
                            '₱${_formatCurrency((order.amountPaid - order.grandTotal).clamp(0.0, double.infinity))}',
                            valueColor: const Color(0xFF059669),
                          ),
                        ],
                        if (order.paymentRef != null && order.paymentRef!.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          _buildSummaryRow('Payment Ref / Slip:', order.paymentRef!),
                        ],
                      ],
                      Text(
                        '*** THIS IS NOT AN OFFICIAL RECEIPT ***',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.urbanist(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom Actions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey.shade700,
                          side: BorderSide(color: Colors.grey.shade300),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          'Close',
                          style: GoogleFonts.urbanist(fontWeight: FontWeight.w700, fontSize: 13.5),
                        ),
                      ),
                    ),
                    if (order.status != 1) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            onSettle();
                          },
                          icon: const Icon(Icons.payments_rounded, size: 18),
                          label: Text(
                            'Settle Payment',
                            style: GoogleFonts.urbanist(fontWeight: FontWeight.w800, fontSize: 14),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: navy,
                            foregroundColor: const Color(0xFFE8C468),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          decoration: BoxDecoration(
                            color: const Color(0xFF059669).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF059669)),
                              const SizedBox(width: 8),
                              Text(
                                'ORDER SETTLED',
                                style: GoogleFonts.urbanist(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13.5,
                                  color: const Color(0xFF059669),
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetaRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.urbanist(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
        ),
        Text(
          value,
          style: GoogleFonts.urbanist(fontSize: 13.5, fontWeight: FontWeight.w800, color: const Color(0xFF0C0E2B)),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.urbanist(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.grey.shade700),
        ),
        Text(
          value,
          style: GoogleFonts.urbanist(
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            color: valueColor ?? const Color(0xFF0C0E2B),
          ),
        ),
      ],
    );
  }

  Widget _buildDottedDivider() {
    return Row(
      children: List.generate(
        36,
        (index) => Expanded(
          child: Container(
            color: index % 2 == 0 ? Colors.grey.shade300 : Colors.transparent,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
