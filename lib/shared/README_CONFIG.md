# App Configuration Guide

## API URL Configuration

The API URL is now configurable and can be changed without modifying code.

### How It Works

1. **Default Behavior:**
   - **Debug Mode** (development): Uses `http://192.168.110.44:2000` on a device/emulator,
     or the browser host (`http://<host>:2000`) on Web — i.e. the local restoAdmin backend
   - **Release Mode** (production): Uses `https://moonctgroup.com` (cloud server + cloud DB)

2. **Custom URL:**
   - You can set a custom URL that will override the default
   - Custom URL is stored in SharedPreferences and persists across app restarts

### Usage Examples

```dart
import 'package:bluemoon_resto_app/shared/app_config.dart';

// Get current base URL
final url = await AppConfig.getBaseUrl();

// Set custom URL (e.g., for testing with different server)
await AppConfig.setCustomUrl('http://192.168.1.100:2026');

// Check if using custom URL
final isCustom = await AppConfig.isUsingCustomUrl();

// Get default URL (based on build mode)
final defaultUrl = AppConfig.getDefaultUrl();

// Clear custom URL and use default
await AppConfig.clearCustomUrl();
```

### Changing Default URLs

To change the default URLs, edit `resto/lib/shared/app_config.dart`:

```dart
static const String _defaultDevUrl = 'http://192.168.110.44:2000';  // Change this
static const String _defaultProdUrl = 'https://moonctgroup.com';    // Change this
```

### Notes

- The URL is cached after first access to avoid repeated async calls
- If you change the URL at runtime, call `ApiService.clearBaseUrlCache()` to refresh
- All API services (waiterApp, menuApp) automatically use this config

