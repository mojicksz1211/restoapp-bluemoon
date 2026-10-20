import 'dart:convert';

import 'package:bluemoon_resto_app/shared/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('picking an account signs in without a password field', (tester) async {
    final errors = <String>[];
    FlutterError.onError = (d) {
      final msg = d.exceptionAsString();
      if (msg.contains('google_fonts') || msg.contains('GoogleFonts')) return;
      errors.add(msg);
    };
    SharedPreferences.setMockInitialValues({
      'login_accounts_cache': jsonEncode([
        {'username': 'gfwaiter1', 'firstname': 'Ana', 'lastname': 'Reyes', 'permissions': 14, 'role': 'WAITER', 'floor': 'gf'},
        {'username': '2fwaiter', 'firstname': 'Carla', 'lastname': 'Santos', 'permissions': 14, 'role': 'WAITER', 'floor': '2f'},
      ]),
      'custom_api_url': 'http://127.0.0.1:9',
    });
    tester.view.physicalSize = const Size(1248, 879);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    await tester.runAsync(() => Future.delayed(const Duration(seconds: 2)));
    await tester.pumpAndSettle();

    expect(find.text('Password'), findsNothing);
    await tester.tap(find.text('Select your account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ana Reyes'));
    await tester.pump();
    // Sign-in started straight away (spinner on the button), still no password field.
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(find.text('Password'), findsNothing);
    await tester.runAsync(() => Future.delayed(const Duration(seconds: 3)));
    await tester.pumpAndSettle();
    // Unreachable server → connection error shown, password still not asked for.
    expect(find.textContaining('Connection error'), findsOneWidget);
    expect(find.text('Password'), findsNothing);
    expect(find.text('Sign in as Ana'), findsOneWidget);
    expect(errors, isEmpty, reason: errors.join('\n'));
  });
}
