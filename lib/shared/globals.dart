import 'package:flutter/material.dart';

// Global key to trigger rebuild of RootApp from anywhere
final GlobalKey<State> rootAppKey = GlobalKey<State>();

// Global language notifier for simple cross-app updates
final ValueNotifier<String> languageNotifier = ValueNotifier<String>('en');

// Helper to refresh auth from anywhere
void refreshAppAuth() {
  final dynamic state = rootAppKey.currentState;
  if (state != null) {
    try {
      state.refreshAuth();
    } catch (e) {
      // Ignore if method doesn't exist
    }
  }
}

void setAppLanguage(String languageCode) {
  languageNotifier.value = languageCode;
}
