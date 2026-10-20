import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../menuApp/services/api_service.dart';
import 'floor_utils.dart';
import 'login_accounts.dart';
import 'settings_sheet.dart';

const _navyPrimary = Color(0xFF0C0E2B);
const _navySecondary = Color(0xFF1B1E4A);
const _gold = Color(0xFFF2C230);
const _cream = Color(0xFFF5F6F0);
const _fieldFill = Color(0xFFFAF7F2);

const _groundFloorColor = Color(0xFF1F7A63);
const _secondFloorColor = Color(0xFFB4741A);
const _allFloorsColor = Color(0xFF5B5F7A);

class LoginPage extends StatefulWidget {
  final Function(BuildContext context, String? permissions, String? role)?
  onLoginSuccess;

  const LoginPage({super.key, this.onLoginSuccess});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();
  final _menuController = MenuController();

  bool _passwordVisible = false;
  bool _isLoading = false;
  String? _errorMessage;

  List<LoginAccount> _accounts = const [];
  bool _loadingAccounts = true;

  /// Last fetch of the account list failed (server unreachable, or one that
  /// predates `GET /api/login/accounts`).
  bool _accountsLoadFailed = false;
  String? _branchName;
  LoginAccount? _selected;

  /// Username whose automatic sign-in was rejected (it doesn't use the default
  /// staff password) — only this account asks for a typed password.
  String? _passwordRequiredFor;

  /// The user chose "Sign in with a username instead".
  bool _manualMode = false;

  /// No list to pick from (server unreachable on a fresh tablet, or no staff
  /// accounts) → fall back to typing a username.
  bool get _isManual => _manualMode || (!_loadingAccounts && _accounts.isEmpty);

  /// Picking an account signs in straight away, no password typed.
  bool get _autoSignIn =>
      !_isManual &&
      _selected != null &&
      _passwordRequiredFor != _selected!.username;

  bool get _showPasswordField =>
      _isManual ||
      (_selected != null && _passwordRequiredFor == _selected!.username);

  bool get _anyAccountHasFloor => _accounts.any((a) => a.floor != null);

  /// Re-reads the account list while the page is open, so an account that
  /// just signed in on another tablet disappears from this one's picker.
  Timer? _listRefreshTimer;

  @override
  void initState() {
    super.initState();
    _init();
    _listRefreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted ||
          _isLoading ||
          _loadingAccounts ||
          _menuController.isOpen) {
        return;
      }
      _refreshAccounts(silent: true);
    });
  }

  @override
  void dispose() {
    _listRefreshTimer?.cancel();
    _usernameController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await LoginAccountsStore.removeLegacyRememberMe();
    final cached = await LoginAccountsStore.cachedAccounts();
    final branchName = await LoginAccountsStore.deviceBranchName();
    if (!mounted) return;
    setState(() {
      _accounts = cached;
      _branchName = branchName;
    });
    await _refreshAccounts();
  }

  /// [silent]: the background refresh — no spinner, and a failed fetch keeps
  /// the list on screen as it is.
  Future<void> _refreshAccounts({bool silent = false}) async {
    if (!silent) setState(() => _loadingAccounts = true);
    final fresh = await LoginAccountsStore.fetchAccounts();
    if (!mounted) return;
    if (silent && fresh == null) return;
    setState(() {
      _loadingAccounts = false;
      _accountsLoadFailed = fresh == null;
      if (fresh != null) _accounts = fresh;
      final selected = _selected;
      if (selected != null &&
          !_accounts.any((a) => a.username == selected.username)) {
        _selected = null;
      }
    });
  }

  void _selectAccount(LoginAccount account) {
    setState(() {
      _selected = account;
      _errorMessage = null;
      _passwordController.clear();
      _passwordVisible = false;
    });
    if (_passwordRequiredFor == account.username) {
      _focusPasswordSoon();
    } else {
      _submit();
    }
  }

  /// Focus the password field once it has been built (it appears/animates in
  /// on the same setState that asks for it).
  void _focusPasswordSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _passwordFocus.requestFocus();
    });
  }

  void _toggleManualMode() {
    setState(() {
      _manualMode = !_manualMode;
      _errorMessage = null;
      _passwordController.clear();
      if (_manualMode && _selected != null) {
        _usernameController.text = _selected!.username;
      }
    });
  }

  Future<void> _openSettings() async {
    await showAppSettingsSheet(context: context);
    // The server URL may have changed — reload that server's accounts.
    ApiService.clearBaseUrlCache();
    if (mounted) await _refreshAccounts();
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    final String username;
    final List<String> passwords;
    var automatic = false;
    // Picked from the list (not typed): the server refuses an account that's
    // already signed in on another tablet instead of taking it over.
    final viaPicker = !_isManual;

    if (_isManual) {
      if (!_formKey.currentState!.validate()) return;
      username = _usernameController.text.trim();
      passwords = [_passwordController.text];
    } else {
      final account = _selected;
      if (account == null) {
        setState(() => _errorMessage = 'Please select your account.');
        return;
      }
      username = account.username;
      if (_autoSignIn) {
        // A password typed earlier for this account (one that doesn't use the
        // default) first, then the shared staff password.
        final saved = await LoginAccountsStore.savedPassword(username);
        passwords = {?saved, kDefaultStaffPassword}.toList();
        automatic = true;
      } else {
        if (!_formKey.currentState!.validate()) return;
        passwords = [_passwordController.text];
      }
    }

    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      var result = <String, dynamic>{};
      var usedPassword = passwords.first;
      for (final password in passwords) {
        usedPassword = password;
        result = await ApiService.login(
          username,
          password,
          rejectIfActive: viaPicker,
        );
        // Only a wrong password is worth another try; a network error or a
        // disabled account would fail the same way again.
        if (result['success'] == true ||
            result['error'] != 'Incorrect password') {
          break;
        }
      }

      if (result['success'] == true) {
        final data = result['data'] is Map
            ? Map<String, dynamic>.from(result['data'] as Map)
            : <String, dynamic>{};
        await LoginAccountsStore.rememberLogin(
          password: usedPassword,
          data: data,
        );

        if (mounted) {
          final permissions = data['permissions']?.toString();
          final role = data['role']?.toString();
          widget.onLoginSuccess?.call(context, permissions, role);
        }
        return;
      }

      final error = (result['error'] ?? 'Login failed').toString();
      final needsPassword = automatic && error == 'Incorrect password';
      final inUse = result['code'] == 'ACCOUNT_IN_USE';
      if (needsPassword) {
        // Any saved password was wrong too — drop it.
        await LoginAccountsStore.forgetPassword(username);
      }
      if (!mounted) return;
      final pickedName = _selected?.displayName ?? username;
      setState(() {
        if (needsPassword) _passwordRequiredFor = username;
        if (inUse) _selected = null;
        _errorMessage = needsPassword
            ? "This account doesn't use the default password. Please type its password."
            : inUse
            ? '$pickedName is already signed in on another tablet. '
                  'Choose your own account.'
            : error;
        _isLoading = false;
      });
      if (needsPassword) _focusPasswordSoon();
      // The list was out of date — drop the account that's in use.
      if (inUse) _refreshAccounts();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'An error occurred: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  // ==================== Layout ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cream,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide =
              constraints.maxWidth >= 720 &&
              constraints.maxWidth > constraints.maxHeight * 0.9;
          final compact =
              constraints.maxWidth < 380 || constraints.maxHeight < 560;

          final body = isWide
              ? Row(
                  children: [
                    SizedBox(
                      width: math.min(constraints.maxWidth * 0.42, 520),
                      child: _buildBrandPanel(),
                    ),
                    Expanded(child: _buildFormArea(compact: compact)),
                  ],
                )
              : _buildStackedLayout(compact: compact);

          return Stack(
            children: [
              Positioned.fill(child: body),
              Positioned(
                top: 8,
                right: 8,
                child: SafeArea(
                  child: IconButton(
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: _navyPrimary,
                      size: 26,
                    ),
                    tooltip: 'Server Connection Settings',
                    onPressed: _isLoading ? null : _openSettings,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'Good morning';
    if (hour >= 12 && hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  Widget _buildBrandPanel() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_navyPrimary, _navySecondary],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -90,
            right: -130,
            child: _ring(380, _gold.withValues(alpha: 0.35)),
          ),
          Positioned(
            bottom: -120,
            left: -100,
            child: _softBlob(320, Colors.white.withValues(alpha: 0.04)),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, c) {
                final logoSize = math.min(240.0, c.maxWidth * 0.6);
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 32,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _logo(logoSize, glow: true),
                        const SizedBox(height: 32),
                        Text(
                          'STAFF PORTAL',
                          style: GoogleFonts.urbanist(
                            color: _gold,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 3,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${_greeting()}!',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.urbanist(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Sign in to start your shift.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.urbanist(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 15,
                          ),
                        ),
                        if (_branchName != null) ...[
                          const SizedBox(height: 22),
                          _branchChip(_branchName!, onDark: true),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormArea({required bool compact}) {
    return Stack(
      children: [
        Positioned(
          bottom: -140,
          right: -120,
          child: _softBlob(340, _navyPrimary.withValues(alpha: 0.04)),
        ),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 16 : 40,
                vertical: compact ? 16 : 32,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: _buildFormCard(compact: compact),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStackedLayout({required bool compact}) {
    return Stack(
      children: [
        Positioned(
          top: -120,
          right: -100,
          child: _softBlob(320, _navyPrimary.withValues(alpha: 0.05)),
        ),
        Positioned(
          bottom: -140,
          left: -120,
          child: _softBlob(360, _navySecondary.withValues(alpha: 0.05)),
        ),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 16 : 24,
                vertical: compact ? 16 : 28,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: compact ? 8 : 24),
                    _logo(compact ? 150 : 190),
                    const SizedBox(height: 18),
                    Text(
                      'STAFF PORTAL',
                      style: GoogleFonts.urbanist(
                        color: _navySecondary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_greeting()}!',
                      style: GoogleFonts.urbanist(
                        color: _navyPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (_branchName != null) ...[
                      const SizedBox(height: 12),
                      _branchChip(_branchName!, onDark: false),
                    ],
                    SizedBox(height: compact ? 18 : 26),
                    _buildFormCard(compact: compact),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFormCard({required bool compact}) {
    final manual = _isManual;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _navyPrimary.withValues(alpha: 0.08),
            blurRadius: 32,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 18 : 28,
        vertical: compact ? 22 : 30,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sign in',
              style: GoogleFonts.urbanist(
                color: _navyPrimary,
                fontSize: compact ? 24 : 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              manual
                  ? 'Enter your username and password.'
                  : 'Tap your account to sign in.',
              style: GoogleFonts.urbanist(
                color: Colors.grey[600],
                fontSize: 14.5,
              ),
            ),
            const SizedBox(height: 22),
            if (manual && !_manualMode && _accountsLoadFailed) ...[
              _buildAccountsUnavailableNote(),
              const SizedBox(height: 14),
            ],
            if (manual)
              _buildField(
                label: 'Username',
                icon: Icons.person_outline,
                controller: _usernameController,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your username';
                  }
                  return null;
                },
              )
            else ...[
              _sectionLabel(),
              const SizedBox(height: 8),
              _buildAccountPicker(),
            ],
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: _showPasswordField
                  ? Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: _buildField(
                        label: 'Password',
                        icon: Icons.lock_outline,
                        controller: _passwordController,
                        focusNode: _passwordFocus,
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
                    )
                  : const SizedBox(width: double.infinity),
            ),
            _buildErrorBox(),
            SizedBox(height: compact ? 18 : 22),
            _buildSubmitButton(),
            const SizedBox(height: 10),
            if (!(manual && _accounts.isEmpty))
              Center(
                child: TextButton.icon(
                  onPressed: _isLoading ? null : _toggleManualMode,
                  icon: Icon(
                    manual
                        ? Icons.people_alt_outlined
                        : Icons.keyboard_outlined,
                    size: 18,
                    color: _navySecondary,
                  ),
                  label: Text(
                    manual
                        ? 'Choose from the account list'
                        : 'Sign in with a username instead',
                    style: GoogleFonts.urbanist(
                      color: _navySecondary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel() {
    return Row(
      children: [
        Text(
          'ACCOUNT',
          style: GoogleFonts.urbanist(
            color: Colors.grey[600],
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
        const Spacer(),
        SizedBox(
          height: 28,
          child: _loadingAccounts
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _navySecondary,
                    ),
                  ),
                )
              : IconButton(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  iconSize: 19,
                  tooltip: 'Refresh accounts',
                  onPressed: _isLoading ? null : _refreshAccounts,
                  icon: Icon(Icons.refresh_rounded, color: Colors.grey[600]),
                ),
        ),
      ],
    );
  }

  // ==================== Account picker ====================

  Widget _buildAccountPicker() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Phone-width cards: short floor chips ("GF") so names keep room.
        final compactChips = width < 380;
        return MenuAnchor(
          controller: _menuController,
          alignmentOffset: const Offset(0, 6),
          style: MenuStyle(
            backgroundColor: const WidgetStatePropertyAll(Colors.white),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.white),
            elevation: const WidgetStatePropertyAll(10),
            shadowColor: WidgetStatePropertyAll(
              _navyPrimary.withValues(alpha: 0.25),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(vertical: 8),
            ),
            minimumSize: WidgetStatePropertyAll(Size(width, 0)),
            maximumSize: WidgetStatePropertyAll(Size(width, 400)),
          ),
          menuChildren: _buildMenuEntries(width, compactChips: compactChips),
          builder: (context, controller, _) {
            final enabled = !_isLoading && _accounts.isNotEmpty;
            return _accountFieldButton(
              isOpen: controller.isOpen,
              compactChips: compactChips,
              onTap: enabled
                  ? () => controller.isOpen
                        ? controller.close()
                        : controller.open()
                  : null,
            );
          },
        );
      },
    );
  }

  Widget _accountFieldButton({
    required bool isOpen,
    required bool compactChips,
    VoidCallback? onTap,
  }) {
    final selected = _selected;
    final Widget content;
    if (selected != null) {
      content = _accountRow(
        selected,
        emphasize: true,
        compactChips: compactChips,
      );
    } else {
      content = Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _navyPrimary.withValues(alpha: 0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person_search_outlined,
              color: _navyPrimary.withValues(alpha: 0.6),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _loadingAccounts && _accounts.isEmpty
                  ? 'Loading accounts…'
                  : 'Select your account',
              style: GoogleFonts.urbanist(
                color: Colors.grey[600],
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }

    return Material(
      color: _fieldFill,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isOpen
                  ? _navyPrimary
                  : _navyPrimary.withValues(alpha: 0.14),
              width: isOpen ? 1.6 : 1.25,
            ),
          ),
          child: Row(
            children: [
              Expanded(child: content),
              const SizedBox(width: 6),
              AnimatedRotation(
                turns: isOpen ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: _navyPrimary.withValues(alpha: 0.7),
                  size: 26,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMenuEntries(double width, {required bool compactChips}) {
    final groups = <String?, List<LoginAccount>>{
      kFloorGround: [],
      kFloorSecond: [],
      null: [],
    };
    for (final account in _accounts) {
      groups[normalizeFloor(account.floor)]!.add(account);
    }
    final showHeaders =
        _anyAccountHasFloor &&
        groups.values.where((g) => g.isNotEmpty).length > 1;

    final entries = <Widget>[];
    groups.forEach((floor, accounts) {
      if (accounts.isEmpty) return;
      if (showHeaders) {
        entries.add(
          Padding(
            padding: EdgeInsets.fromLTRB(18, entries.isEmpty ? 6 : 14, 18, 6),
            child: Text(
              _floorLabel(floor).toUpperCase(),
              style: GoogleFonts.urbanist(
                color: _floorColor(floor),
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.3,
              ),
            ),
          ),
        );
      }
      for (final account in accounts) {
        final isSelected = _selected?.username == account.username;
        entries.add(
          MenuItemButton(
            onPressed: () => _selectAccount(account),
            style: ButtonStyle(
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              minimumSize: const WidgetStatePropertyAll(Size(0, 62)),
              backgroundColor: WidgetStatePropertyAll(
                isSelected
                    ? _navyPrimary.withValues(alpha: 0.06)
                    : Colors.transparent,
              ),
            ),
            child: SizedBox(
              width: width - 24,
              child: _accountRow(
                account,
                showCheck: isSelected,
                compactChips: compactChips,
              ),
            ),
          ),
        );
      }
    });
    return entries;
  }

  Widget _accountRow(
    LoginAccount account, {
    bool emphasize = false,
    bool showCheck = false,
    bool compactChips = false,
  }) {
    return Row(
      children: [
        _avatar(account),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                account.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.urbanist(
                  color: _navyPrimary,
                  fontSize: emphasize ? 16 : 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      '@${account.username} · ${account.roleLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.urbanist(
                        color: Colors.grey[600],
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_anyAccountHasFloor) ...[
          const SizedBox(width: 8),
          _floorChip(account.floor, compact: compactChips),
        ],
        if (showCheck) ...[
          const SizedBox(width: 8),
          const Icon(
            Icons.check_circle_rounded,
            color: _navySecondary,
            size: 20,
          ),
        ],
      ],
    );
  }

  Widget _avatar(LoginAccount account) {
    final color = _floorColor(account.floor);
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Text(
        account.initials,
        style: GoogleFonts.urbanist(
          color: color,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _floorChip(String? floor, {bool compact = false}) {
    final color = _floorColor(floor);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!compact) ...[
            Icon(Icons.layers_outlined, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            compact ? _floorShortLabel(floor) : _floorLabel(floor),
            style: GoogleFonts.urbanist(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  String _floorLabel(String? floor) {
    switch (normalizeFloor(floor)) {
      case kFloorGround:
        return 'Ground Floor';
      case kFloorSecond:
        return '2nd Floor';
      default:
        return 'All Floors';
    }
  }

  String _floorShortLabel(String? floor) {
    switch (normalizeFloor(floor)) {
      case kFloorGround:
        return 'GF';
      case kFloorSecond:
        return '2F';
      default:
        return 'All';
    }
  }

  Color _floorColor(String? floor) {
    switch (normalizeFloor(floor)) {
      case kFloorGround:
        return _groundFloorColor;
      case kFloorSecond:
        return _secondFloorColor;
      default:
        return _allFloorsColor;
    }
  }

  // ==================== Form pieces ====================

  Widget _buildAccountsUnavailableNote() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: _navyPrimary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _navyPrimary.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_rounded,
            color: _navyPrimary.withValues(alpha: 0.6),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Couldn't load the account list from the server. "
              'You can still sign in with your username.',
              style: GoogleFonts.urbanist(
                color: _navyPrimary.withValues(alpha: 0.8),
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
          ),
          TextButton(
            onPressed: _isLoading || _loadingAccounts ? null : _refreshAccounts,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: _loadingAccounts
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _navySecondary,
                    ),
                  )
                : Text(
                    'Retry',
                    style: GoogleFonts.urbanist(
                      color: _navySecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBox() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: _errorMessage == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 12),
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
                    Icon(Icons.error_outline, color: Colors.red[700], size: 19),
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
    );
  }

  Widget _buildSubmitButton() {
    final quick = _autoSignIn;
    final label = quick ? 'Sign in as ${_selected!.shortName}' : 'Sign in';
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: _isLoading
              ? null
              : const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [_navyPrimary, _navySecondary],
                ),
          boxShadow: _isLoading
              ? null
              : [
                  BoxShadow(
                    color: _navySecondary.withValues(alpha: 0.32),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _isLoading
                ? _navySecondary.withValues(alpha: 0.6)
                : Colors.transparent,
            disabledBackgroundColor: _navySecondary.withValues(alpha: 0.6),
            shadowColor: Colors.transparent,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation<Color>(_cream),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (quick) ...[
                      const Icon(Icons.bolt_rounded, color: _gold, size: 22),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.urbanist(
                          fontWeight: FontWeight.w800,
                          fontSize: 16.5,
                          letterSpacing: 0.2,
                          color: _cream,
                        ),
                      ),
                    ),
                    if (!quick) ...[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: _cream,
                        size: 20,
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Widget _branchChip(String name, {required bool onDark}) {
    final fg = onDark ? Colors.white : _navyPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: onDark
            ? Colors.white.withValues(alpha: 0.08)
            : _navyPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: onDark
              ? Colors.white.withValues(alpha: 0.16)
              : _navyPrimary.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.storefront_outlined,
            size: 16,
            color: onDark ? _gold : _navySecondary,
          ),
          const SizedBox(width: 6),
          Text(
            name,
            style: GoogleFonts.urbanist(
              color: fg,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _logo(double size, {bool glow = false}) {
    // logo.png is the Blue Moon circular badge mark (1024x1024, square).
    return Container(
      width: size,
      height: size,
      decoration: glow
          ? BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _gold.withValues(alpha: 0.22),
                  blurRadius: 48,
                  spreadRadius: 2,
                ),
              ],
            )
          : null,
      child: Image.asset(
        'assets/images/logo.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
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

  Widget _ring(double size, Color color) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    String? Function(String?)? validator,
    FocusNode? focusNode,
    bool obscureText = false,
    bool isPasswordField = false,
    TextInputAction? textInputAction,
    void Function(String)? onFieldSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      validator: validator,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      enabled: !_isLoading,
      style: GoogleFonts.urbanist(fontSize: 15.5, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.urbanist(color: Colors.grey[600], fontSize: 14),
        prefixIcon: Icon(
          icon,
          color: _navyPrimary.withValues(alpha: 0.65),
          size: 20,
        ),
        filled: true,
        fillColor: _fieldFill,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: _navyPrimary.withValues(alpha: 0.14),
            width: 1.25,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: _navyPrimary.withValues(alpha: 0.08),
            width: 1.25,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _navyPrimary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.red[300]!, width: 1.25),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.red[400]!, width: 1.6),
        ),
        suffixIcon: isPasswordField
            ? IconButton(
                icon: Icon(
                  _passwordVisible ? Icons.visibility : Icons.visibility_off,
                  color: _navyPrimary.withValues(alpha: 0.65),
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
