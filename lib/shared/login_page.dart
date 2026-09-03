import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../menuApp/services/api_service.dart';
import 'settings_sheet.dart';

class LoginPage extends StatefulWidget {
  final Function(BuildContext context, String? permissions, String? role)?
      onLoginSuccess;

  const LoginPage({
    super.key,
    this.onLoginSuccess,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _passwordVisible = false;
  bool _isLoading = false;
  bool _rememberMe = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRememberedCredentials();
  }

  Future<void> _loadRememberedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool('remember_me') ?? false;
    if (!rememberMe) {
      return;
    }

    setState(() {
      _rememberMe = rememberMe;
      _usernameController.text = prefs.getString('saved_username') ?? '';
      _passwordController.text = prefs.getString('saved_password') ?? '';
    });
  }

  Future<void> _handleRememberChanged(bool? value) async {
    final shouldRemember = value ?? false;
    setState(() {
      _rememberMe = shouldRemember;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remember_me', shouldRemember);
    if (!shouldRemember) {
      await prefs.remove('saved_username');
      await prefs.remove('saved_password');
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    FocusScope.of(context).unfocus();
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await ApiService.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );

      if (result['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        if (_rememberMe) {
          await prefs.setString('saved_username', _usernameController.text.trim());
          await prefs.setString('saved_password', _passwordController.text);
          await prefs.setBool('remember_me', true);
        } else {
          await prefs.remove('saved_username');
          await prefs.remove('saved_password');
          await prefs.setBool('remember_me', false);
        }

        // Login successful
        if (mounted) {
          final permissions = result['data']?['permissions']?.toString();
          final role = result['data']?['role']?.toString();
          
          if (widget.onLoginSuccess != null) {
            widget.onLoginSuccess!(context, permissions, role);
          }
        }
      } else {
        // Login failed
        setState(() {
          _errorMessage = result['error'] ?? 'Login failed';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'An error occurred: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const navyPrimary = Color(0xFF0C0E2B);
    const navySecondary = Color(0xFF1B1E4A);
    const cream = Color(0xFFF5F6F0);

    final media = MediaQuery.of(context);
    final isPortrait = media.orientation == Orientation.portrait;
    final screenWidth = media.size.width;
    final screenHeight = media.size.height;

    // Responsive sizing driven by the shortest usable dimension.
    final isCompact = screenWidth < 360 || screenHeight < 560;
    final isTabletUp = screenWidth >= 600;

    final horizontalPadding = screenWidth < 400 ? 16.0 : (isTabletUp ? 40.0 : 24.0);
    // logo.png is the Blue Moon circular badge mark (1024x1024, square).
    final logoWidth = () {
      if (isCompact) return 220.0;
      if (isTabletUp) return 320.0;
      return isPortrait ? 280.0 : 230.0;
    }();
    final subtitleFontSize = isCompact ? 12.0 : 13.5;
    final topSpacing = isCompact ? 16.0 : (isPortrait ? 32.0 : 20.0);

    return Scaffold(
      backgroundColor: cream,
      body: Stack(
        children: [
          // Soft decorative backdrop — a couple of oversized, low-opacity
          // blobs so large screens don't feel like an empty void.
          Positioned(
            top: -120,
            right: -100,
            child: _softBlob(320, navyPrimary.withOpacity(0.05)),
          ),
          Positioned(
            bottom: -140,
            left: -120,
            child: _softBlob(360, navySecondary.withOpacity(0.05)),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.settings_outlined, color: navyPrimary, size: 28),
                tooltip: 'Server Connection Settings',
                onPressed: () => showAppSettingsSheet(context: context),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: isCompact ? 16 : 32,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(top: topSpacing),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: logoWidth,
                              child: AspectRatio(
                                // logo.png (Blue Moon badge) is 1024x1024.
                                aspectRatio: 1,
                                child: Image.asset(
                                  'assets/images/logo.png',
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                  isAntiAlias: true,
                                ),
                              ),
                            ),
                            SizedBox(height: isCompact ? 10 : 14),
                            Text(
                              'Sign in to continue browsing the menu',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.urbanist(
                                color: Colors.grey[600],
                                fontSize: subtitleFontSize,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: isCompact ? 20 : 28),
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: navyPrimary.withOpacity(0.07),
                              blurRadius: 28,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: isCompact ? 18 : 24,
                          vertical: isCompact ? 22 : 28,
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildField(
                                label: 'Username',
                                icon: Icons.person_outline,
                                controller: _usernameController,
                                textInputAction: TextInputAction.next,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter your username';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),
                              _buildField(
                                label: 'Password',
                                icon: Icons.lock_outline,
                                controller: _passwordController,
                                obscureText: !_passwordVisible,
                                isPasswordField: true,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter your password';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: _isLoading
                                        ? null
                                        : () => _handleRememberChanged(!_rememberMe),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: Checkbox(
                                              value: _rememberMe,
                                              onChanged: _isLoading
                                                  ? null
                                                  : _handleRememberChanged,
                                              activeColor: navySecondary,
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize.shrinkWrap,
                                              visualDensity: VisualDensity.compact,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Remember me',
                                            style: GoogleFonts.urbanist(
                                              color: Colors.grey[800],
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 4),
                                      minimumSize: const Size(0, 0),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () {},
                                    child: Text(
                                      'Forgot password?',
                                      style: GoogleFonts.urbanist(
                                        color: navyPrimary,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOut,
                                alignment: Alignment.topCenter,
                                child: _errorMessage == null
                                    ? const SizedBox(width: double.infinity)
                                    : Padding(
                                        padding: const EdgeInsets.only(top: 10),
                                        child: Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.red[50],
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: Colors.red[200]!),
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Icon(Icons.error_outline,
                                                  color: Colors.red[700], size: 19),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  _errorMessage ?? '',
                                                  style: GoogleFonts.urbanist(
                                                    color: Colors.red[700],
                                                    fontSize: 13.5,
                                                    height: 1.3,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                              ),
                              SizedBox(height: isCompact ? 18 : 22),
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    gradient: _isLoading
                                        ? null
                                        : const LinearGradient(
                                            begin: Alignment.centerLeft,
                                            end: Alignment.centerRight,
                                            colors: [navyPrimary, navySecondary],
                                          ),
                                    boxShadow: _isLoading
                                        ? null
                                        : [
                                            BoxShadow(
                                              color: navySecondary.withOpacity(0.32),
                                              blurRadius: 16,
                                              offset: const Offset(0, 6),
                                            ),
                                          ],
                                  ),
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          _isLoading ? navySecondary.withOpacity(0.6) : Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    onPressed: _isLoading ? null : _submit,
                                    child: _isLoading
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.2,
                                              valueColor: AlwaysStoppedAnimation<Color>(cream),
                                            ),
                                          )
                                        : Text(
                                            'Sign in',
                                            style: GoogleFonts.urbanist(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                              letterSpacing: 0.2,
                                              color: cream,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: isCompact ? 16 : 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _softBlob(double size, Color color) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    String? Function(String?)? validator,
    bool obscureText = false,
    bool isPasswordField = false,
    TextInputAction? textInputAction,
    void Function(String)? onFieldSubmitted,
  }) {
    const navyPrimary = Color(0xFF0C0E2B);
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      validator: validator,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      style: GoogleFonts.urbanist(fontSize: 15, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.urbanist(color: Colors.grey[600], fontSize: 14),
        prefixIcon: Icon(icon, color: navyPrimary.withOpacity(0.65), size: 20),
        filled: true,
        fillColor: const Color(0xFFFAF7F2),
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: navyPrimary.withOpacity(0.14),
            width: 1.25,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: navyPrimary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.red[300]!, width: 1.25),
        ),
        suffixIcon: isPasswordField
            ? IconButton(
                icon: Icon(
                  _passwordVisible ? Icons.visibility : Icons.visibility_off,
                  color: navyPrimary.withOpacity(0.65),
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    _passwordVisible = !_passwordVisible;
                  });
                },
              )
            : null,
      ),
    );
  }
}

