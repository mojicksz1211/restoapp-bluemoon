// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bluemoon_resto_app/shared/offline_db.dart';
import 'package:bluemoon_resto_app/waiterApp/waiter_app.dart';

void main() {
  setUpAll(() {
    // sqflite has no platform channel in a plain `flutter test` run — swap
    // in the FFI (pure-Dart sqlite3) factory so OfflineDb (which the app's
    // offline-fallback data loading touches) can actually open.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    OfflineDb.testOverridePath = inMemoryDatabasePath;
    await OfflineDb.instance.resetForTest();
  });

  testWidgets('Waiter app loads correctly and shows login page', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const WaiterApp());

    // Wait for the auth check to complete.
    // We use pump() instead of pumpAndSettle() because the loading indicator 
    // might be an infinite animation.
    await tester.pump(); // Start the async check
    await tester.pump(const Duration(seconds: 1)); // Wait for it to finish

    // Verify that the login page is present.
    expect(find.text('Sign in'), findsWidgets);

    // Verify that username field is present.
    expect(find.text('Username'), findsOneWidget);

    // Verify that password field is present.
    expect(find.text('Password'), findsOneWidget);
  });
}
