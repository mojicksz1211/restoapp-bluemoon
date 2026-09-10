import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Application configuration for API URLs and other settings
class AppConfig {
  /// Local backend for development — LAN IP so the app works from a phone on
  /// the same network as the dev machine.
  static const String _defaultDevUrl = 'http://192.168.110.44:2000';

  /// Cloud / production backend (restoAdmin API + socket.io). Release builds
  /// point here by default, so every distributed APK and web build talks to
  /// the cloud server (and the cloud database) with no manual setup.
  static const String _defaultProdUrl = 'https://moonctgroup.com';

  // Key for storing custom API URL in SharedPreferences
  static const String _customUrlKey = 'custom_api_url';

  /// Last value returned by [getBaseUrl], cached so synchronous code (model
  /// parsing, image URL resolution) can reach the active host without awaiting.
  static String? _lastResolvedBaseUrl;

  /// Best-effort synchronous base URL: the last resolved value, or the
  /// build-mode default if [getBaseUrl] hasn't run yet.
  static String get syncBaseUrl =>
      _lastResolvedBaseUrl ?? (kReleaseMode ? _defaultProdUrl : _defaultDevUrl);

  /// Normalises an asset/image URL coming from the API so it always points at
  /// the active backend host. Seeded data often stores absolute
  /// `http://localhost:2000/...` URLs; those (and bare relative paths) are
  /// rewritten onto [syncBaseUrl]. Returns null for empty input.
  static String? resolveAssetUrl(dynamic raw) {
    if (raw == null) return null;
    var s = raw.toString().trim();
    if (s.isEmpty) return null;

    final base = syncBaseUrl;
    final localHost = RegExp(
      r'^https?://(localhost|127\.0\.0\.1|0\.0\.0\.0|10\.0\.2\.2)(:\d+)?',
      caseSensitive: false,
    );
    if (localHost.hasMatch(s)) {
      return s.replaceFirst(localHost, base);
    }
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    return s.startsWith('/') ? '$base$s' : '$base/$s';
  }

  /// Get the base API URL.
  ///
  /// Priority:
  ///   1. Custom URL (if the user set one in-app)
  ///   2. Production URL — for release builds (distributed APK / web build)
  ///   3. Browser host — for debug builds running on Web
  ///   4. Dev LAN URL — for debug builds running on a device/emulator
  static Future<String> getBaseUrl() async {
    // Check if user has set a custom URL
    final prefs = await SharedPreferences.getInstance();
    final customUrl = prefs.getString(_customUrlKey);

    if (customUrl != null && customUrl.isNotEmpty) {
      return _lastResolvedBaseUrl = customUrl;
    }

    // Distributed builds (release mode) always talk to the cloud server.
    if (kReleaseMode) {
      return _lastResolvedBaseUrl = _defaultProdUrl;
    }

    // On Web (debug), dynamically use whatever host/IP the browser opened.
    if (kIsWeb) {
      final host = Uri.base.host;
      if (host.isNotEmpty) {
        return _lastResolvedBaseUrl = 'http://$host:2000';
      }
    }

    return _lastResolvedBaseUrl = _defaultDevUrl;
  }

  /// Set a custom API URL (useful for testing or different environments)
  static Future<void> setCustomUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url.isEmpty) {
      await prefs.remove(_customUrlKey);
    } else {
      // Ensure URL doesn't end with /
      final cleanUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
      await prefs.setString(_customUrlKey, cleanUrl);
    }
  }

  /// Get the current custom URL (if set)
  static Future<String?> getCustomUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_customUrlKey);
  }

  /// Clear custom URL and use default
  static Future<void> clearCustomUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_customUrlKey);
  }

  /// Get the default URL based on build mode
  static String getDefaultUrl() {
    return kReleaseMode ? _defaultProdUrl : _defaultDevUrl;
  }

  /// Check if using custom URL
  static Future<bool> isUsingCustomUrl() async {
    final customUrl = await getCustomUrl();
    return customUrl != null && customUrl.isNotEmpty;
  }
}
