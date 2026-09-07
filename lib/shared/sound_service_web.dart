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
