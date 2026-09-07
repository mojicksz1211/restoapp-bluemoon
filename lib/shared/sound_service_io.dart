import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

final FlutterTts _flutterTts = FlutterTts();
int _activeLoopId = 0;
bool _ttsInitialized = false;

Future<void> _initTtsIfNeeded() async {
  if (_ttsInitialized) return;
  try {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5); // Standard normal speaking speed on Android
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.awaitSpeakCompletion(true);

    _flutterTts.setErrorHandler((msg) {
      debugPrint('TTS Error: $msg');
    });

    _ttsInitialized = true;
  } catch (e) {
    debugPrint('Error initializing FlutterTts: $e');
  }
}

void playNotificationChime() {
  try {
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.mediumImpact();
  } catch (_) {}
}

void startRepeatingPlatformAlert(String text, {int intervalMs = 5500}) {
  stopRepeatingPlatformAlert();
  final currentLoopId = ++_activeLoopId;

  // Run non-blocking async speech loop that awaits full speech completion
  () async {
    while (_activeLoopId == currentLoopId) {
      try {
        await _initTtsIfNeeded();
        if (_activeLoopId != currentLoopId) break;

        playNotificationChime();
        // Short pause so chime/vibe plays cleanly first
        await Future.delayed(const Duration(milliseconds: 350));
        if (_activeLoopId != currentLoopId) break;

        // Speak the full text and await completion (never cuts off prematurely)
        await _flutterTts.stop();
        await _flutterTts.speak(text);

        // Pause for ~3.5 seconds of silence after speech completes before repeating
        for (int i = 0; i < 35; i++) {
          if (_activeLoopId != currentLoopId) break;
          await Future.delayed(const Duration(milliseconds: 100));
        }
      } catch (e) {
        debugPrint('Error in TTS alert loop: $e');
        break;
      }
    }
  }();
}

void stopRepeatingPlatformAlert() {
  _activeLoopId++;
  try {
    _flutterTts.stop();
  } catch (_) {}
}
