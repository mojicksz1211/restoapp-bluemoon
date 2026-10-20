import 'package:flutter/foundation.dart';
import 'sound_service_io.dart' if (dart.library.js_interop) 'sound_service_web.dart';

class SoundService {
  static final ValueNotifier<bool> isMutedNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<String?> activeAlertTextNotifier = ValueNotifier<String?>(null);

  static bool get isMuted => isMutedNotifier.value;
  static bool get isAlertActive => activeAlertTextNotifier.value != null;

  static void toggleMute() {
    isMutedNotifier.value = !isMutedNotifier.value;
    if (isMutedNotifier.value) {
      stopRepeatingAlert();
    }
  }

  static void setMuted(bool value) {
    isMutedNotifier.value = value;
    if (value) {
      stopRepeatingAlert();
    }
  }

  static void playOrderAlert() {
    if (isMuted) return;
    try {
      playNotificationChime();
    } catch (e) {
      debugPrint('Error playing sound notification: $e');
    }
  }

  /// Chime + speak [text] once (e.g. a room's "15 minutes left"). A running
  /// repeating new-order announcement is paused for it and picks up again
  /// right after.
  static void announceOnce(String text) {
    if (isMuted) return;
    try {
      speakOncePlatform(text, resumeLoopText: activeAlertTextNotifier.value);
    } catch (e) {
      debugPrint('Error playing announcement: $e');
    }
  }

  static void startRepeatingAlert(String announcementText) {
    activeAlertTextNotifier.value = announcementText;
    if (isMuted) return;
    try {
      startRepeatingPlatformAlert(announcementText);
    } catch (e) {
      debugPrint('Error starting repeating alert: $e');
    }
  }

  static void stopRepeatingAlert() {
    activeAlertTextNotifier.value = null;
    try {
      stopRepeatingPlatformAlert();
    } catch (e) {
      debugPrint('Error stopping repeating alert: $e');
    }
  }
}
