import 'dart:js_interop';

@JS('playPosNotificationSound')
external void _playPosNotificationSound();

@JS('startRepeatingOrderAlert')
external void _startRepeatingOrderAlert(JSString text, JSNumber intervalMs);

@JS('stopOrderAlert')
external void _stopOrderAlert();

void playNotificationChime() {
  try {
    _playPosNotificationSound();
  } catch (_) {}
}

@JS('speakOnceAnnouncement')
external void _speakOnceAnnouncement(JSString text);

/// index.html's speakOnceAnnouncement pauses and resumes a running repeating
/// announcement itself, so [resumeLoopText] isn't needed here.
void speakOncePlatform(String text, {String? resumeLoopText}) {
  try {
    _speakOnceAnnouncement(text.toJS);
  } catch (_) {
    playNotificationChime();
  }
}

void startRepeatingPlatformAlert(String text, {int intervalMs = 5500}) {
  try {
    _startRepeatingOrderAlert(text.toJS, intervalMs.toJS);
  } catch (_) {}
}

void stopRepeatingPlatformAlert() {
  try {
    _stopOrderAlert();
  } catch (_) {}
}
