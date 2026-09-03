import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Application configuration for API URLs and other settings
class AppConfig {
  // Default URLs for different environments
  // NOTE: Dev URL uses the LAN IP so the app works on any device in the
  // local network (localhost would resolve to the accessing device, not the server).
  static const String _defaultProdUrl = 'http://localhost:2000';
  static const String _defaultDevUrl = 'http://192.168.110.44:2000';
  
  // Key for storing custom API URL in SharedPreferences
  static const String _customUrlKey = 'custom_api_url';
  
  /// Get the base API URL
  /// Priority: Custom URL (if set) > Dynamic Browser Host URL (on Web) > Dev URL (LAN IP)
  static Future<String> getBaseUrl() async {
    // Check if user has set a custom URL
    final prefs = await SharedPreferences.getInstance();
    final customUrl = prefs.getString(_customUrlKey);
    
    if (customUrl != null && customUrl.isNotEmpty) {
      return customUrl;
    }
    
    // On Web, dynamically use whatever host/IP the user opened in the browser
    if (kIsWeb) {
      final host = Uri.base.host;
      if (host.isNotEmpty) {
        return 'http://$host:2000';
      }
    }
    
    return _defaultDevUrl;
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
    return _defaultDevUrl;
  }
  
  /// Check if using custom URL
  static Future<bool> isUsingCustomUrl() async {
    final customUrl = await getCustomUrl();
    return customUrl != null && customUrl.isNotEmpty;
  }
}

