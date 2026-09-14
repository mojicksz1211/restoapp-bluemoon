import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../offline_sync_service.dart';

class OfflineSyncBanner extends StatelessWidget {
  const OfflineSyncBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SyncStatus>(
      valueListenable: OfflineSyncService.instance.statusNotifier,
      builder: (context, status, _) {
        return ValueListenableBuilder<int>(
          valueListenable: OfflineSyncService.instance.pendingCountNotifier,
          builder: (context, pendingCount, _) {
            if (status == SyncStatus.online && pendingCount == 0) {
              return const SizedBox.shrink();
            }

            final isOffline = status == SyncStatus.offline;
            final isSyncing = status == SyncStatus.syncing;

            final bgColor = isOffline
                ? const Color(0xFFD97706) // Warm amber
                : const Color(0xFF1D4ED8); // Vibrant sync blue

            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: bgColor,
                boxShadow: [
                  BoxShadow(
                    color: bgColor.withOpacity(0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                bottom: false,
                child: Row(
                  children: [
                    if (isSyncing)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    else
                      const Icon(
                        Icons.cloud_off_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isSyncing
                                ? 'Syncing with moonctgroup.com...'
                                : 'Offline Mode (Local Storage Active)',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            isSyncing
                                ? 'Uploading $pendingCount pending transaction${pendingCount == 1 ? '' : 's'} to database...'
                                : pendingCount > 0
                                    ? '$pendingCount action${pendingCount == 1 ? '' : 's'} saved on this tablet. Will auto-sync once WiFi has internet.'
                                    : 'No internet connection. Menu and orders are loaded from local backup.',
                            style: GoogleFonts.poppins(
                              color: Colors.white.withOpacity(0.92),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (isOffline)
                      Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        child: InkWell(
                          onTap: () async {
                            final ok = await OfflineSyncService.instance.probeReachability();
                            if (!ok && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Cannot reach moonctgroup.com yet. Still offline.'),
                                  duration: Duration(seconds: 2),
                                  backgroundColor: Color(0xFFB91C1C),
                                ),
                              );
                            }
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.sync_rounded,
                                  color: Color(0xFFD97706),
                                  size: 15,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Sync Now',
                                  style: GoogleFonts.poppins(
                                    color: const Color(0xFFD97706),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
