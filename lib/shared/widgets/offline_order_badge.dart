import 'package:flutter/material.dart';
import '../offline_sync_service.dart';

/// Small amber "not synced yet" chip for an order card — shown when the
/// order either hasn't been created on the server at all yet (still a
/// negative local temp id) or still has some action queued for it (e.g.
/// items were added while offline). Sizing/shape matches the per-app
/// `StatusChip` widgets so it sits naturally alongside them.
///
/// Self-contained: pass just the order's id (temp or real) and it decides
/// on its own whether to render anything, so call sites don't need to
/// duplicate the "is this order unsynced" check.
class OfflineOrderBadge extends StatelessWidget {
  final int orderId;

  const OfflineOrderBadge({super.key, required this.orderId});

  static const Color _amber = Color(0xFFD97706);

  @override
  Widget build(BuildContext context) {
    final isPending =
        orderId < 0 || OfflineSyncService.instance.hasPendingActionsForOrder(orderId);
    if (!isPending) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 13, color: _amber),
          SizedBox(width: 4),
          Text(
            'Not synced',
            style: TextStyle(
              color: _amber,
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}
