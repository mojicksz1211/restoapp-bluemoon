import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'app_config.dart';

class AppUpdateInfo {
  final int versionCode;
  final String versionName;
  final String apkUrl;
  final String releaseNotes;

  const AppUpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.releaseNotes,
  });
}

/// Self-serve update check against `GET /api/app/version` (see
/// restoAdmin's apiController.js#getAppVersion). There's no Play Store
/// distribution for this app — this is the entire update path: a tablet
/// notices a newer build on its own and prompts to install it, instead of
/// someone visiting all 8 devices with a USB cable every release.
class AppUpdateService {
  AppUpdateService._();

  /// Returns update info only when the server has a strictly newer
  /// versionCode AND an apkUrl is actually published. Never throws — a
  /// failed check (offline, server down, no release published yet) should be
  /// silent, not an error dialog interrupting a waiter mid-shift.
  static Future<AppUpdateInfo?> checkForUpdate() async {
    if (kIsWeb) return null; // Web deploys update on refresh; nothing to install here.
    try {
      final baseUrl = await AppConfig.getBaseUrl();
      final response = await http
          .get(Uri.parse('$baseUrl/api/app/version'))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['success'] != true) return null;
      final data = body['data'] as Map<String, dynamic>?;
      if (data == null) return null;

      final apkUrl = data['apkUrl'] as String?;
      final remoteCode = (data['versionCode'] as num?)?.toInt();
      if (apkUrl == null || apkUrl.isEmpty || remoteCode == null) return null;

      final packageInfo = await PackageInfo.fromPlatform();
      final installedCode = int.tryParse(packageInfo.buildNumber) ?? 0;
      if (remoteCode <= installedCode) return null;

      return AppUpdateInfo(
        versionCode: remoteCode,
        versionName: (data['versionName'] as String?) ?? '',
        apkUrl: apkUrl,
        releaseNotes: (data['releaseNotes'] as String?) ?? '',
      );
    } catch (e) {
      debugPrint('[AppUpdateService] check failed: $e');
      return null;
    }
  }

  /// Downloads [info.apkUrl] to local storage and hands it to Android's own
  /// installer via [OpenFilex.open]. Requires REQUEST_INSTALL_PACKAGES
  /// (AndroidManifest.xml) — Android still shows its own "Install this
  /// update?" confirmation on top of that; there's no way to skip it without
  /// full MDM device-owner enrollment, which this fleet doesn't have.
  static Future<void> downloadAndInstall(
    AppUpdateInfo info, {
    ValueChanged<double>? onProgress,
  }) async {
    if (kIsWeb) return;

    final request = http.Request('GET', Uri.parse(info.apkUrl));
    final response = await http.Client().send(request);
    if (response.statusCode != 200) {
      throw Exception('Download failed (HTTP ${response.statusCode})');
    }

    final dir = await getTemporaryDirectory();
    // Fixed filename (not versioned) so a retried/failed download always
    // overwrites cleanly instead of littering the temp dir every release.
    final file = File('${dir.path}/bluemoon-resto-update.apk');
    final sink = file.openWrite();

    final total = response.contentLength ?? 0;
    var received = 0;
    await response.stream.map((chunk) {
      received += chunk.length;
      if (total > 0) onProgress?.call(received / total);
      return chunk;
    }).pipe(sink);
    await sink.close();

    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      throw Exception(result.message);
    }
  }
}
