import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';

/// Tells the server this tablet's account is still signed in, so the login
/// picker on other tablets keeps it hidden (`user_info.LAST_SEEN_AT`, 180s
/// window). Waiter/cashier tablets already poll the API every few seconds,
/// which counts too; the heartbeat covers apps that can sit idle (kitchen,
/// menu kiosk). Started by RootApp while someone is signed in.
class SessionPresence {
  static const Duration _interval = Duration(seconds: 60);
  static const Duration _timeout = Duration(seconds: 8);

  static Timer? _timer;

  static void start() {
    if (_timer != null) return;
    _beat();
    _timer = Timer.periodic(_interval, (_) => _beat());
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  static Future<void> _beat() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      if (token.isEmpty) return;
      final base = await AppConfig.getBaseUrl();
      await http
          .post(
            Uri.parse('$base/api/session/heartbeat'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(_timeout);
    } catch (_) {
      // Offline / server down: the account simply frees up after the window.
    }
  }

  /// Ends the session on the server so the account shows up in the login
  /// picker again right away. Best effort and short — logout must never hang
  /// on a dead connection (the server window frees it anyway). Call with the
  /// token captured before the local session is cleared.
  static Future<void> endOnServer(String? accessToken, String baseUrl) async {
    stop();
    if (accessToken == null || accessToken.isEmpty) return;
    try {
      await http
          .post(
            Uri.parse('$baseUrl/api/logout'),
            headers: {'Authorization': 'Bearer $accessToken'},
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
  }
}
