// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bluemoon_resto_app/waiterApp/waiter_app.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
