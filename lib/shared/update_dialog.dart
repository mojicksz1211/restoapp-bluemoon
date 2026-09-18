import 'package:flutter/material.dart';

import 'app_update_service.dart';

/// Runs a background update check and, if a newer build is published, shows
/// a small dialog offering to download+install it. Safe to fire from any
/// home page's initState — silently does nothing on failure, no update, or
/// no internet, so it never interrupts a shift with an error popup.
Future<void> checkAndPromptAppUpdate(BuildContext context) async {
  final info = await AppUpdateService.checkForUpdate();
  if (info == null || !context.mounted) return;
  await showUpdateAvailableDialog(context, info);
}

/// Same check as [checkAndPromptAppUpdate], but for a manual "Check for
/// updates" button — silence would look broken there, so this surfaces a
/// "you're up to date" message when there's nothing new instead of just
/// doing nothing.
Future<void> checkForUpdateManually(BuildContext context) async {
  final info = await AppUpdateService.checkForUpdate();
  if (!context.mounted) return;
  if (info == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("You're on the latest version.")),
    );
    return;
  }
  await showUpdateAvailableDialog(context, info);
}

Future<void> showUpdateAvailableDialog(
  BuildContext context,
  AppUpdateInfo info,
) {
  return showDialog(
    context: context,
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

  Future<void> _install() async {
    setState(() {
      _downloading = true;
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_downloading,
      child: AlertDialog(
        title: const Text('Update available'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version ${widget.info.versionName} is ready to install.'),
            if (widget.info.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                widget.info.releaseNotes,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_downloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress > 0 ? _progress : null),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
        actions: _downloading
            ? const []
            : [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Later'),
                ),
                ElevatedButton(
                  onPressed: _install,
                  child: const Text('Update now'),
                ),
              ],
      ),
    );
  }
}
