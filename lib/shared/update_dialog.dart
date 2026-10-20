import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_update_service.dart';
import 'widgets/blurred_dialog.dart';
import 'widgets/floating_result.dart';
import 'widgets/loading_overlay.dart';

// White card over a blurred, dimmed screen — same look as the app's other
// popups.
const _navy = Color(0xFF0C0E2B);
const _gold = Color(0xFFE8C468);
const _goldText = Color(0xFFB8902F); // gold that reads on white
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE2E8F0);

/// Runs a background update check and, if a newer build is published, shows
/// the update dialog offering to download+install it. Safe to fire from any
/// home page's initState — silently does nothing on failure, no update, or
/// no internet, so it never interrupts a shift with an error popup.
Future<void> checkAndPromptAppUpdate(BuildContext context) async {
  final info = await AppUpdateService.checkForUpdate();
  if (info == null || !context.mounted) return;
  await showUpdateAvailableDialog(context, info);
}

/// Same check as [checkAndPromptAppUpdate], but for the manual "Check for
/// updates" button — silence would look broken there, so it shows the loading
/// card while checking and a "you're up to date" card when nothing is new.
Future<void> checkForUpdateManually(BuildContext context) async {
  // Min 800ms so the loader is visible even when the server answers instantly.
  final results = await runWithLoader<List<Object?>>(
    context,
    message: 'Checking for updates…',
    task: () => Future.wait<Object?>([
      AppUpdateService.checkForUpdate(),
      Future<void>.delayed(const Duration(milliseconds: 800)),
    ]),
  );
  final info = results.first as AppUpdateInfo?;
  if (!context.mounted) return;
  if (info == null) {
    String? current;
    try {
      final pkg = await PackageInfo.fromPlatform();
      current = 'Build ${pkg.buildNumber}';
    } catch (_) {}
    if (!context.mounted) return;
    showFloatingResult(
      context,
      title: "You're up to date",
      subtitle: current,
    );
    return;
  }
  await showUpdateAvailableDialog(context, info);
}

Future<void> showUpdateAvailableDialog(
  BuildContext context,
  AppUpdateInfo info,
) {
  return showBlurredDialog<void>(
    context,
    barrierDismissible: true,
    builder: (dialogContext) => _UpdateDialog(info: info),
  );
}

class _UpdateDialog extends StatefulWidget {
  final AppUpdateInfo info;
  const _UpdateDialog({required this.info});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;
  String? _installedBuild;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((pkg) {
      if (mounted) setState(() => _installedBuild = pkg.buildNumber);
    }).catchError((_) {});
  }

  Future<void> _install() async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });
    try {
      await AppUpdateService.downloadAndInstall(
        widget.info,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      // Android's installer UI takes over from here (its own "Install this
      // update?" confirmation); nothing more to do on this side once it's
      // launched successfully.
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _error = 'Update failed: $e';
        });
      }
    }
  }

  List<String> get _notes => widget.info.releaseNotes
      .split(RegExp(r'[\r\n]+'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    final pct = (_progress * 100).clamp(0, 100).round();
    final notes = _notes;

    return PopScope(
      canPop: !_downloading,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            padding: const EdgeInsets.fromLTRB(26, 30, 26, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 44,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo in a gold ring. While downloading the ring fills up
                  // with the real progress.
                  SizedBox(
                    width: 104,
                    height: 104,
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        SizedBox(
                          width: 104,
                          height: 104,
                          child: CircularProgressIndicator(
                            value: _downloading
                                ? (_progress > 0 ? _progress : null)
                                : 1,
                            strokeWidth: 4.5,
                            strokeCap: StrokeCap.round,
                            valueColor:
                                const AlwaysStoppedAnimation<Color>(_gold),
                            backgroundColor:
                                _gold.withValues(alpha: 0.15),
                          ),
                        ),
                        ClipOval(
                          child: Image.asset(
                            'assets/images/logo.png',
                            width: 82,
                            height: 82,
                            fit: BoxFit.cover,
                          ),
                        ),
                        if (!_downloading)
                          Positioned(
                            right: -6,
                            bottom: -2,
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: _gold,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                              ),
                              child: const Icon(
                                Icons.arrow_upward_rounded,
                                color: _navy,
                                size: 22,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _downloading ? 'Downloading update…' : 'Update Available',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.urbanist(
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _downloading
                        ? '$pct%  •  Please keep the app open'
                        : 'A new version of Blue Moon is ready to install.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.urbanist(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _muted,
                    ),
                  ),
                  if (!_downloading) ...[
                    const SizedBox(height: 20),
                    // Installed -> New
                    Row(
                      children: [
                        Expanded(
                          child: _VersionBox(
                            label: 'INSTALLED',
                            value: _installedBuild == null
                                ? '—'
                                : 'Build $_installedBuild',
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: const Icon(
                            Icons.arrow_forward_rounded,
                            color: _goldText,
                            size: 26,
                          ),
                        ),
                        Expanded(
                          child: _VersionBox(
                            label: 'NEW',
                            value: 'Build ${widget.info.versionCode}',
                            sub: widget.info.versionName.isEmpty
                                ? null
                                : 'v${widget.info.versionName}',
                            highlight: true,
                          ),
                        ),
                      ],
                    ),
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxHeight: 150),
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _line),
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "WHAT'S NEW",
                                style: GoogleFonts.urbanist(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.4,
                                  color: _goldText,
                                ),
                              ),
                              const SizedBox(height: 8),
                              for (final line in notes)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (notes.length > 1)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            right: 8,
                                            top: 1,
                                          ),
                                          child: Text(
                                            '•',
                                            style: GoogleFonts.urbanist(
                                              fontSize: 15,
                                              color: _goldText,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      Expanded(
                                        child: Text(
                                          line,
                                          style: GoogleFonts.urbanist(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: _navy,
                                            height: 1.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color:
                              const Color(0xFFEF4444).withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        _error!,
                        style: GoogleFonts.urbanist(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFDC2626),
                        ),
                      ),
                    ),
                  ],
                  if (!_downloading) ...[
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _navy,
                              side: const BorderSide(color: _navy, width: 1.5),
                              minimumSize: const Size.fromHeight(58),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              'Later',
                              style: GoogleFonts.urbanist(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 3,
                          child: FilledButton.icon(
                            onPressed: _install,
                            icon: const Icon(Icons.download_rounded, size: 24),
                            style: FilledButton.styleFrom(
                              backgroundColor: _navy,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(58),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            label: Text(
                              _error == null ? 'Update Now' : 'Try Again',
                              style: GoogleFonts.urbanist(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VersionBox extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final bool highlight;

  const _VersionBox({
    required this.label,
    required this.value,
    this.sub,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: highlight ? _gold.withValues(alpha: 0.14) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlight ? _gold.withValues(alpha: 0.7) : _line,
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: GoogleFonts.urbanist(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.3,
              color: highlight ? _goldText : _muted,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: GoogleFonts.urbanist(
                fontSize: 21,
                fontWeight: FontWeight.w900,
                color: highlight ? _goldText : _navy,
              ),
            ),
          ),
          if (sub != null)
            Text(
              sub!,
              style: GoogleFonts.urbanist(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _muted,
              ),
            ),
        ],
      ),
    );
  }
}
