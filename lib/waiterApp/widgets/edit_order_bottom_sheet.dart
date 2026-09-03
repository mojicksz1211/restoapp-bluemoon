import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models.dart';
import '../waiter_models.dart';

class EditOrderBottomSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<MenuItem> menuItems;
  final List<EditableOrderItem> initialItems;
  final Future<MenuItem?> Function(BuildContext context) onPickMenuItem;
  final void Function(List<EditableOrderItem> items) onSave;
  final VoidCallback onCancel;

  const EditOrderBottomSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.menuItems,
    required this.initialItems,
    required this.onPickMenuItem,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<EditOrderBottomSheet> createState() => _EditOrderBottomSheetState();
}

class _EditOrderBottomSheetState extends State<EditOrderBottomSheet> {
  late List<EditableOrderItem> _items;

  @override
  void initState() {
    super.initState();
    _items = widget.initialItems.map((item) {
      return EditableOrderItem(
        menuId: item.menuId,
        name: item.name,
        quantity: item.quantity,
        unitPrice: item.unitPrice,
        status: item.status,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return DraggableScrollableSheet(
      initialChildSize: isMobile ? 0.8 : 0.75,
      minChildSize: isMobile ? 0.6 : 0.55,
      maxChildSize: 0.95,
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
                          widget.title,
                          style: GoogleFonts.urbanist(
                            fontSize: isMobile ? 18 : 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          widget.subtitle,
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
                    onPressed: () => Navigator.pop(context),
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
                child: ListView.separated(
                  controller: scrollController,
                  padding: EdgeInsets.all(isMobile ? 12 : 16),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            onTap: () async {
                              final selected = await widget.onPickMenuItem(context);
                              if (selected == null) return;
                              setState(() {
                                item.menuId = selected.id ?? item.menuId;
                                item.name = selected.name;
                                item.unitPrice = selected.price;
                              });
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Menu item',
                                border: OutlineInputBorder(),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.menuId == null
                                          ? 'Select menu'
                                          : item.name,
                                      style: TextStyle(
                                        color: item.menuId == null
                                            ? Colors.grey[600]
                                            : Colors.black87,
                                      ),
                                    ),
                                  ),
                                  const Icon(Icons.arrow_drop_down),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text('₱${_formatPrice(item.unitPrice)}'),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: item.quantity <= 1
                                    ? null
                                    : () {
                                        setState(() {
                                          item.quantity -= 1;
                                        });
                                      },
                              ),
                              Text(item.quantity.toStringAsFixed(0)),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: () {
                                  setState(() {
                                    item.quantity += 1;
                                  });
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: () {
                                  setState(() {
                                    _items.removeAt(index);
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Line total: ₱${_formatPrice(item.lineTotal)}',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 16 : 20,
                vertical: isMobile ? 12 : 16,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFFF5F6F0),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    final defaultItem = widget.menuItems.firstWhere(
                      (menuItem) => menuItem.id != null,
                      orElse: () => widget.menuItems.first,
                    );
                    setState(() {
                      _items.insert(
                        0,
                        EditableOrderItem(
                          menuId: null,
                          name: 'Select menu',
                          quantity: 1,
                          unitPrice: 0,
                          status: 3,
                        ),
                      );
                    });
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add item'),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Total: ₱${_formatPrice(_items.fold<double>(0, (sum, item) => sum + item.lineTotal))}',
                      style: GoogleFonts.urbanist(
                        fontWeight: FontWeight.bold,
                        fontSize: isMobile ? 16 : 18,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
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
                            final hasMissingMenu =
                                _items.any((item) => item.menuId == null);
                            if (hasMissingMenu) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Please select a menu for all items.'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }
                            widget.onSave(_items);
                            Navigator.pop(context, _items);
                          },
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              vertical: isMobile ? 16 : 18,
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
                            'Save',
                            style: GoogleFonts.urbanist(
                              fontSize: isMobile ? 16 : 18,
                              fontWeight: FontWeight.bold,
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

  String _formatPrice(double value) {
    return value.toStringAsFixed(2);
  }
}

