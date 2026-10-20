import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';
import 'floor_utils.dart';

/// Tablet-role permission ids (Menu/Tablet, Waiter, Cashier, Kitchen) — the
/// only accounts `GET /api/login/accounts` lists, and the only ones whose
/// password is kept on the tablet for one-tap sign-in.
const Set<int> kTabletRolePermissions = {2, 14, 15, 16};

/// Shared password of the staff accounts: picking an account in the login
/// picker signs in with it straight away. An account with a different
/// password is asked for it once, and that password is then kept on the tablet.
const String kDefaultStaffPassword = '123';

/// One staff account in the login picker.
class LoginAccount {
  final int? userId;
  final String username;
  final String firstname;
  final String lastname;
  final int? permissions;
  final String? role;

  /// [kFloorGround], [kFloorSecond], or null (unscoped — sees every floor).
  final String? floor;

  const LoginAccount({
    required this.username,
    this.userId,
    this.firstname = '',
    this.lastname = '',
    this.permissions,
    this.role,
    this.floor,
  });

  String get displayName {
    final full = '$firstname $lastname'.trim();
    return full.isEmpty ? username : full;
  }

  String get shortName {
    final first = firstname.trim();
    return first.isEmpty ? displayName : first;
  }

  String get initials {
    final parts = displayName
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  String get roleLabel {
    final r = role?.trim() ?? '';
    if (r.isNotEmpty) {
      return r
          .toLowerCase()
          .split(RegExp(r'[\s_]+'))
          .where((w) => w.isNotEmpty)
          .map((w) => w[0].toUpperCase() + w.substring(1))
          .join(' ');
    }
    switch (permissions) {
      case 14:
        return 'Waiter';
      case 15:
        return 'Cashier';
      case 16:
        return 'Kitchen';
      case 2:
        return 'Menu Tablet';
      default:
        return 'Staff';
    }
  }

  factory LoginAccount.fromJson(Map<String, dynamic> json) {
    return LoginAccount(
      userId: int.tryParse(json['user_id']?.toString() ?? ''),
      username: json['username']?.toString().trim() ?? '',
      firstname: json['firstname']?.toString().trim() ?? '',
      lastname: json['lastname']?.toString().trim() ?? '',
      permissions: int.tryParse(json['permissions']?.toString() ?? ''),
      role: json['role']?.toString(),
      floor: normalizeFloor(json['floor']),
    );
  }

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'username': username,
    'firstname': firstname,
    'lastname': lastname,
    'permissions': permissions,
    'role': role,
    'floor': floor,
  };
}

/// Device-level login data: which branch this tablet belongs to, the last
/// fetched account list (so the picker works offline), and the passwords of
/// accounts that don't use [kDefaultStaffPassword]. Lives in SharedPreferences
/// but survives logout — see [clearPreferencesKeepingLoginData].
///
/// Saved passwords are stored as plain text on the device (same as the old
/// "Remember me"); anyone holding the tablet can sign in as a saved account.
class LoginAccountsStore {
  /// Branch whose accounts a brand-new tablet lists before anyone has signed
  /// in on it (Blue Moon). After the first sign-in the account's own branch
  /// is remembered instead.
  static const int defaultBranchId = 3;

  static const _branchIdKey = 'login_device_branch_id';
  static const _branchNameKey = 'login_device_branch_name';
  static const _accountsKey = 'login_accounts_cache';
  static const _passwordsKey = 'login_saved_passwords';
  static const _preservedKeys = [
    _branchIdKey,
    _branchNameKey,
    _accountsKey,
    _passwordsKey,
  ];
  static const _legacyRememberKeys = [
    'remember_me',
    'saved_username',
    'saved_password',
  ];

  /// `prefs.clear()` for logout, keeping this tablet's login data.
  static Future<void> clearPreferencesKeepingLoginData(
    SharedPreferences prefs,
  ) async {
    final kept = <String, String>{};
    for (final key in _preservedKeys) {
      final value = prefs.getString(key);
      if (value != null) kept[key] = value;
    }
    await prefs.clear();
    for (final entry in kept.entries) {
      await prefs.setString(entry.key, entry.value);
    }
  }

  /// Drops the pre-picker "Remember me" keys (a plaintext password nothing
  /// reads any more).
  static Future<void> removeLegacyRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in _legacyRememberKeys) {
      await prefs.remove(key);
    }
  }

  static Future<int> deviceBranchId() async {
    final prefs = await SharedPreferences.getInstance();
    return int.tryParse(prefs.getString(_branchIdKey) ?? '') ?? defaultBranchId;
  }

  static Future<String?> deviceBranchName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_branchNameKey)?.trim();
    return (name == null || name.isEmpty) ? null : name;
  }

  static Future<List<LoginAccount>> cachedAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_accountsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => LoginAccount.fromJson(Map<String, dynamic>.from(m)))
          .where((a) => a.username.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Fresh account list for this tablet's branch, cached on success. Null when
  /// the server can't be reached (or predates the endpoint) — callers then
  /// keep showing [cachedAccounts].
  static Future<List<LoginAccount>?> fetchAccounts() async {
    try {
      final branchId = await deviceBranchId();
      final base = await AppConfig.getBaseUrl();
      final response = await http
          .get(
            Uri.parse('$base/api/login/accounts?branch_id=$branchId'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body);
      if (body is! Map || body['success'] != true || body['data'] is! List) {
        return null;
      }
      final accounts = (body['data'] as List)
          .whereType<Map>()
          .map((m) => LoginAccount.fromJson(Map<String, dynamic>.from(m)))
          .where((a) => a.username.isNotEmpty)
          .toList();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _accountsKey,
        jsonEncode(accounts.map((a) => a.toJson()).toList()),
      );
      return accounts;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, String>> _readPasswords(
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString(_passwordsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  static Future<Set<String>> savedUsernames() async {
    final prefs = await SharedPreferences.getInstance();
    return (await _readPasswords(prefs)).keys.toSet();
  }

  static Future<String?> savedPassword(String username) async {
    final prefs = await SharedPreferences.getInstance();
    return (await _readPasswords(prefs))[username];
  }

  static Future<void> forgetPassword(String username) async {
    final prefs = await SharedPreferences.getInstance();
    final passwords = await _readPasswords(prefs);
    if (passwords.remove(username) != null) {
      await prefs.setString(_passwordsKey, jsonEncode(passwords));
    }
  }

  /// Called after a successful `/api/login`: remembers the account's branch
  /// for the picker and, for tablet roles whose password isn't
  /// [kDefaultStaffPassword], that password so picking the account signs in
  /// without typing. Admin/manager passwords are never kept on the tablet.
  static Future<void> rememberLogin({
    required String password,
    required Map<String, dynamic> data,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final branchId = int.tryParse(data['branch_id']?.toString() ?? '');
    if (branchId != null && branchId > 0) {
      final previous = prefs.getString(_branchIdKey);
      if (previous != null && previous != '$branchId') {
        // Another branch's list would be wrong for this tablet now.
        await prefs.remove(_accountsKey);
      }
      await prefs.setString(_branchIdKey, '$branchId');
      final branchName = data['branch_name']?.toString().trim() ?? '';
      if (branchName.isNotEmpty) {
        await prefs.setString(_branchNameKey, branchName);
      }
    }

    final username = data['username']?.toString().trim() ?? '';
    final permissions = int.tryParse(data['permissions']?.toString() ?? '');
    if (username.isEmpty) return;
    final passwords = await _readPasswords(prefs);
    if (permissions != null &&
        kTabletRolePermissions.contains(permissions) &&
        password != kDefaultStaffPassword) {
      passwords[username] = password;
    } else {
      passwords.remove(username);
    }
    await prefs.setString(_passwordsKey, jsonEncode(passwords));
  }
}
