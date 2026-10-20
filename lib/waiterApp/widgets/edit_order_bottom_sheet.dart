import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models.dart';
import '../waiter_models.dart';
import '../../shared/widgets/floating_result.dart';

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

  static const _navy = Color(0xFF0C0E2B);
  static const _navyLight = Color(0xFF1B1E4A);
  static const _cream = Color(0xFFF5F6F0);
  static const _gold = Color(0xFFE8C468);
  static const _amber = Color(0xFFD97706);
  static const _red = Color(0xFFDC2626);
  static const _ink = Color(0xFF1A1C18);

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

  // True once the list differs from the order as it was opened (item added,
  // removed, swapped, or qty changed). Undoing a change back to the original
  // counts as no change.
  bool get _hasChanges {
    final original = widget.initialItems;
    if (_items.length != original.length) return true;
    for (var i = 0; i < _items.length; i++) {
      final a = _items[i];
      final b = original[i];
      if (a.menuId != b.menuId ||
          a.quantity != b.quantity ||
          a.unitPrice != b.unitPrice) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final canSave = _hasChanges;
    final total = _items.fold<double>(0, (sum, item) => sum + item.lineTotal);
    final unitCount = _items.fold<double>(0, (sum, item) => sum + item.quantity);

    // The sheet is only as tall as its content (one or two items = a short
    // sheet) and caps at 92% of the screen, scrolling the item list beyond
    // that. It used to be a fixed 75-80% tall sheet with a big empty gap.
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      child: Builder(
        builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: EdgeInsets.fromLTRB(isMobile ? 16 : 22, 10, isMobile ? 12 : 16, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_navy, _navyLight],
                ),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _gold.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _gold.withValues(alpha: 0.35)),
                        ),
                        child: const Icon(Icons.edit_note_rounded, color: _gold, size: 26),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.urbanist(
                                fontSize: isMobile ? 18 : 20,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 1,
                              ),
                            ),
                            Text(
                              widget.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.urbanist(
                                fontSize: isMobile ? 13 : 14.5,
                                fontWeight: FontWeight.w800,
                                color: _gold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                        ),
                        child: Text(
                          '${_items.length} item${_items.length == 1 ? '' : 's'}',
                          style: GoogleFonts.urbanist(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Material(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.pop(context),
                          child: const SizedBox(
                            width: 40,
                            height: 40,
                            child: Tooltip(
                              message: 'Close',
                              child: Icon(Icons.close_rounded, color: Colors.white, size: 22),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Item list
            Flexible(
              child: Container(
                color: _cream,
                child: _items.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 36),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long_rounded, size: 48, color: _navy.withValues(alpha: 0.2)),
                            const SizedBox(height: 8),
                            Text(
                              'No items — tap "Add item" below',
                              style: GoogleFonts.urbanist(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.fromLTRB(isMobile ? 12 : 16, 14, isMobile ? 12 : 16, 14),
                  itemCount: _items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final isUnset = item.menuId == null;
                    return Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isUnset ? _amber.withValues(alpha: 0.7) : Colors.grey.shade200,
                          width: isUnset ? 1.5 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _navy.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // Narrow cards move the line total under the name.
                          final compact = constraints.maxWidth < 420;
                          return Row(
                            children: [
                              // Name (tap to change the menu item) + unit price.
                              Expanded(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () async {
                                    final selected = await widget.onPickMenuItem(context);
                                    if (selected == null) return;
                                    setState(() {
                                      item.menuId = selected.id ?? item.menuId;
                                      item.name = selected.name;
                                      item.unitPrice = selected.price;
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 2),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                isUnset ? 'Select menu item' : item.name,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.urbanist(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w800,
                                                  color: isUnset ? _amber : _ink,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Icon(
                                              isUnset ? Icons.arrow_drop_down_rounded : Icons.swap_horiz_rounded,
                                              size: isUnset ? 22 : 16,
                                              color: isUnset ? _amber : Colors.grey.shade500,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          compact
                                              ? '₱${_formatPrice(item.unitPrice)} each · ₱${_formatPrice(item.lineTotal)}'
                                              : '₱${_formatPrice(item.unitPrice)} each',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.urbanist(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Quantity stepper.
                              Container(
                                decoration: BoxDecoration(
                                  color: _cream,
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(color: _navy.withValues(alpha: 0.12)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _StepperButton(
                                      icon: Icons.remove_rounded,
                                      onTap: item.quantity <= 1
                                          ? null
                                          : () {
                                              setState(() {
                                                item.quantity -= 1;
                                              });
                                            },
                                    ),
                                    SizedBox(
                                      width: 30,
                                      child: Text(
                                        item.quantity.toStringAsFixed(0),
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.urbanist(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          color: _navy,
                                        ),
                                      ),
                                    ),
                                    _StepperButton(
                                      icon: Icons.add_rounded,
                                      filled: true,
                                      onTap: () {
                                        setState(() {
                                          item.quantity += 1;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              if (!compact) ...[
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 92,
                                  child: Text(
                                    '₱${_formatPrice(item.lineTotal)}',
                                    textAlign: TextAlign.right,
                                    maxLines: 1,
                                    style: GoogleFonts.urbanist(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w900,
                                      color: _ink,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(width: 4),
                              IconButton(
                                tooltip: 'Remove item',
                                icon: const Icon(Icons.delete_outline_rounded, color: _red, size: 22),
                                onPressed: () {
                                  setState(() {
                                    _items.removeAt(index);
                                  });
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
            // Footer: add item, total, save
            Container(
              padding: EdgeInsets.fromLTRB(isMobile ? 16 : 22, 12, isMobile ? 16 : 22, isMobile ? 14 : 18),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: OutlinedButton.icon(
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
                        icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                        label: Text(
                          'Add item',
                          style: GoogleFonts.urbanist(fontSize: 14.5, fontWeight: FontWeight.w800),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _navy,
                          backgroundColor: _gold.withValues(alpha: 0.12),
                          side: BorderSide(color: _gold.withValues(alpha: 0.8), width: 1.3),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'NEW TOTAL · ${unitCount.toStringAsFixed(0)} QTY',
                                style: GoogleFonts.urbanist(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.grey.shade600,
                                  letterSpacing: 1,
                                ),
                              ),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '₱${_formatPrice(total)}',
                                  style: GoogleFonts.urbanist(
                                    fontWeight: FontWeight.w900,
                                    fontSize: isMobile ? 24 : 28,
                                    color: _amber,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            height: 54,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: canSave
                                  ? const LinearGradient(
                                      colors: [_navy, _navyLight],
                                    )
                                  : null,
                              color: canSave ? null : Colors.grey.shade400,
                              boxShadow: canSave
                                  ? [
                                      BoxShadow(
                                        color: _navy.withValues(alpha: 0.3),
                                        blurRadius: 12,
                                        offset: const Offset(0, 5),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: ElevatedButton.icon(
                              // Nothing to save until the order is changed.
                              onPressed: !canSave ? null : () {
                                final hasMissingMenu =
                                    _items.any((item) => item.menuId == null);
                                if (hasMissingMenu) {
                                  showFloatingError(
                                    context,
                                    title: 'Cannot save order',
                                    message: 'Please select a menu for all items.',
                                  );
                                  return;
                                }
                                widget.onSave(_items);
                                Navigator.pop(context, _items);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                shadowColor: Colors.transparent,
                                disabledBackgroundColor: Colors.transparent,
                                disabledForegroundColor: Colors.white70,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ).copyWith(
                                overlayColor: WidgetStateProperty.all(Colors.transparent),
                              ),
                              icon: Icon(
                                canSave ? Icons.check_circle_rounded : Icons.lock_outline_rounded,
                                size: 20,
                              ),
                              label: Text(
                                canSave ? 'Save Changes' : 'No Changes',
                                style: GoogleFonts.urbanist(
                                  fontSize: isMobile ? 15 : 16.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
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
            ),
          ],
        );
        },
      ),
    );
  }

  String _formatPrice(double value) {
    return formatPrice(value);
  }
}

/// Round − / + button of the quantity stepper; disabled when [onTap] is null.
class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;

  const _StepperButton({required this.icon, required this.onTap, this.filled = false});

  static const _navy = Color(0xFF0C0E2B);

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: filled && enabled ? _navy : Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(
              icon,
              size: 19,
              color: !enabled
                  ? Colors.grey.shade400
                  : (filled ? Colors.white : _navy),
            ),
          ),
        ),
      ),
    );
  }
}
