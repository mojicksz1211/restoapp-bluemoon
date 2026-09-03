import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'widgets/settlement_dialog_listener.dart';
import 'services/notification_service.dart';
import 'home_page.dart';

final GlobalKey<NavigatorState> waiterNavigatorKey = GlobalKey<NavigatorState>();

class WaiterApp extends StatefulWidget {
  const WaiterApp({super.key});

  @override
  State<WaiterApp> createState() => _WaiterAppState();
}

class _WaiterAppState extends State<WaiterApp> {
  @override
  void initState() {
    super.initState();
    // Initialize notifications
    NotificationService.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Restaurant Waiter',
      debugShowCheckedModeBanner: false,
      navigatorKey: waiterNavigatorKey,
      theme: ThemeData(
        primarySwatch: Colors.brown,
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: const Color(0xFF0C0E2B),
              brightness: Brightness.light,
            ).copyWith(
              primary: const Color(0xFF0C0E2B),
              secondary: const Color(0xFF1B1E4A),
              tertiary: const Color(0xFFC44D4D),
              surface: const Color(0xFFF5F6F0),
            ),
        useMaterial3: true,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        textTheme: GoogleFonts.urbanistTextTheme(),
        cardTheme: CardThemeData(
          elevation: 4,
          color: const Color(0xFFF5F6F0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
            overlayColor: WidgetStateProperty.all(Colors.transparent),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: ButtonStyle(
            overlayColor: WidgetStateProperty.all(Colors.transparent),
          ),
        ),
      ),
      builder: (context, child) {
        return SettlementDialogListener(
          navigatorKey: waiterNavigatorKey,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const WaiterHomePage(),
    );
  }
}

