import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models.dart';

/// Shows a sleek, compact bottom sheet or dialog to add/edit special kitchen instructions.
Future<void> showItemNoteModal({
  required BuildContext context,
  required CartItem cartItem,
  required VoidCallback onSaved,
}) async {
  final currentNotes = cartItem.remarks ?? '';
  final controller = TextEditingController(text: currentNotes);

  const presets = <String>[
    'Less Ice',
    'No Ice',
    'Extra Spicy',
    'Mild Spicy',
    'No Onion',
    'Less Sugar',
    'Serve Later',
    'To-Go / Takeout',
    'Separate Sauce',
    'Well Done',
  ];

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (modalContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final isMobile = MediaQuery.of(context).size.width < 600;

          void togglePreset(String preset) {
            final currentText = controller.text.trim();
            List<String> parts = currentText.isEmpty
                ? []
                : currentText.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

            if (parts.contains(preset)) {
              parts.remove(preset);
            } else {
              parts.add(preset);
            }

            setSheetState(() {
              controller.text = parts.join(', ');
              controller.selection = TextSelection.fromPosition(
                TextPosition(offset: controller.text.length),
              );
            });
          }

          bool isSelected(String preset) {
            final currentText = controller.text.trim();
            if (currentText.isEmpty) return false;
            final parts = currentText.split(',').map((s) => s.trim()).toList();
            return parts.contains(preset);
          }

          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFFF5F6F0),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  isMobile ? 18 : 24,
                  14,
                  isMobile ? 18 : 24,
                  isMobile ? 18 : 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle Bar
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade400,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Header Row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8C468).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.edit_note_rounded,
                            color: Color(0xFFB45309),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Special Instructions',
                                style: GoogleFonts.urbanist(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF0C0E2B),
                                ),
                              ),
                              Text(
                                cartItem.item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.urbanist(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (controller.text.isNotEmpty)
                          TextButton(
                            onPressed: () {
                              setSheetState(() {
                                controller.clear();
                              });
                            },
                            child: Text(
                              'Clear',
                              style: GoogleFonts.urbanist(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Quick Presets
                    Text(
                      'Quick Tags',
                      style: GoogleFonts.urbanist(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: presets.map((preset) {
                        final active = isSelected(preset);
                        return InkWell(
                          onTap: () => togglePreset(preset),
                          borderRadius: BorderRadius.circular(18),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: active ? const Color(0xFF0C0E2B) : Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: active ? const Color(0xFF0C0E2B) : Colors.grey.shade300,
                                width: 1.2,
                              ),
                              boxShadow: [
                                if (active)
                                  BoxShadow(
                                    color: const Color(0xFF0C0E2B).withValues(alpha: 0.2),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (active)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 5),
                                    child: Icon(Icons.check, size: 14, color: Color(0xFFE8C468)),
                                  ),
                                Text(
                                  preset,
                                  style: GoogleFonts.urbanist(
                                    fontSize: 13,
                                    fontWeight: active ? FontWeight.bold : FontWeight.w600,
                                    color: active ? Colors.white : const Color(0xFF0C0E2B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    // Custom Instruction Text Input
                    Text(
                      'Custom Instruction / Note',
                      style: GoogleFonts.urbanist(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade300, width: 1.2),
                      ),
                      child: TextField(
                        controller: controller,
                        onChanged: (_) => setSheetState(() {}),
                        maxLines: 2,
                        style: GoogleFonts.urbanist(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF0C0E2B),
                        ),
                        decoration: InputDecoration(
                          hintText: 'e.g. Extra spicy, serve after appetizer...',
                          hintStyle: GoogleFonts.urbanist(
                            fontSize: 13,
                            color: Colors.grey.shade400,
                          ),
                          contentPadding: const EdgeInsets.all(12),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(modalContext),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(color: Colors.grey.shade400),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              'Cancel',
                              style: GoogleFonts.urbanist(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: const LinearGradient(
                                colors: [Color(0xFF0C0E2B), Color(0xFF1B1E4A)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF0C0E2B).withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: () {
                                final text = controller.text.trim();
                                cartItem.remarks = text.isEmpty ? null : text;
                                Navigator.pop(modalContext);
                                onSaved();
                              },
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                backgroundColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: Text(
                                'Save Instruction',
                                style: GoogleFonts.urbanist(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
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
          );
        },
      );
    },
  );
}
