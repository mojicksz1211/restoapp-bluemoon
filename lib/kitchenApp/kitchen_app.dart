import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'home_page.dart';
// import 'widgets/auth_wrapper.dart';

final GlobalKey<NavigatorState> kitchenNavigatorKey =
    GlobalKey<NavigatorState>();

class KitchenApp extends StatelessWidget {
  const KitchenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Restaurant Kitchen',
      debugShowCheckedModeBanner: false,
      navigatorKey: kitchenNavigatorKey,
      theme: ThemeData(
        primarySwatch: Colors.brown,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0C0E2B),
          brightness: Brightness.light,
        ).copyWith(
          primary: const Color(0xFF0C0E2B),
          secondary: const Color(0xFF1B1E4A),
          surface: const Color(0xFFF5F6F0),
        ),
        useMaterial3: true,
        textTheme: GoogleFonts.urbanistTextTheme(),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
        ),
      ),
      home: const KitchenHomePage(),
    );
  }
}
