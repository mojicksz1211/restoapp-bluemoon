import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'menuApp/menu_app.dart';
import 'waiterApp/waiter_app.dart';
import 'cashierApp/cashier_app.dart';
import 'kitchenApp/kitchen_app.dart';
import 'menuApp/services/api_service.dart';
import 'shared/login_page.dart';
import 'shared/globals.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Enable fullscreen mode for Android (hide status bar and navigation bar)
  // Skip on web since Platform.isAndroid doesn't work there
  if (!kIsWeb) {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.immersiveSticky,
          overlays: [],
        );
      }
    } catch (e) {
      debugPrint('SystemChrome configuration skipped: $e');
    }
  }

  runApp(RootApp(key: rootAppKey));
}

class RootApp extends StatefulWidget {
  const RootApp({super.key});

  @override
  State<RootApp> createState() => RootAppState();
}

class RootAppState extends State<RootApp> {
  bool _isLoading = true;
  int? _permissionId;
  String? _role;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  // Method to be called externally to refresh auth state
  Future<void> refreshAuth() async {
    setState(() => _isLoading = true);
    await _checkAuth();
  }

  Future<void> _checkAuth() async {
    final isLoggedIn = await ApiService.isLoggedIn();
    int? permissionId;
    String? role;
    
    if (isLoggedIn) {
      final userData = await ApiService.getUserData();
      permissionId = int.tryParse(userData['permissions'] ?? '');
      role = userData['role'];
    }

    if (mounted) {
      setState(() {
        _isLoggedIn = isLoggedIn;
        _permissionId = permissionId;
        _role = role;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        home: Scaffold(
          backgroundColor: const Color(0xFFF5F6F0),
          body: Center(
            child: Image.asset('assets/images/logo.png', height: 100),
          ),
        ),
      );
    }

    if (!_isLoggedIn) {
      return MaterialApp(
        title: 'Blue Moon Staff App',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        home: LoginPage(
          onLoginSuccess: (context, permissions, role) {
            final pId = int.tryParse(permissions ?? '');
            _updateState(pId, role);
          },
        ),
      );
    }

    // 14 = Waiter, 16 = Kitchen, 2 = Menu/Tablet, 15 = Cashier (Assumed common pattern)
    final normalizedRole = _role?.toLowerCase() ?? '';
    if (_permissionId == 14 || normalizedRole.contains('waiter')) {
      return const WaiterApp();
    }
    if (_permissionId == 15 || normalizedRole.contains('cashier')) {
      return const CashierApp();
    }
    if (_permissionId == 16 || normalizedRole.contains('kitchen')) {
      return const KitchenApp();
    }
    if (_permissionId == 2 || normalizedRole.contains('menu')) {
      return const MenuApp();
    }

    // Default or access denied
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: Scaffold(
        backgroundColor: const Color(0xFFF5F6F0),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/logo.png',
                    height: 120,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Access denied',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0C0E2B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This account is not allowed to use the app.',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: 200,
                    child: ElevatedButton(
                      onPressed: () async {
                        await ApiService.logout();
                        if (mounted) {
                          setState(() {
                            _permissionId = null;
                            _role = null;
                            _isLoggedIn = false;
                          });
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0C0E2B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Log out'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
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
    );
  }

  void _updateState(int? pId, String? role) {
    setState(() {
      _isLoggedIn = true;
      _permissionId = pId;
      _role = role;
    });
  }
}
