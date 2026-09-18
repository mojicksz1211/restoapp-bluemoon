import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../shared/globals.dart';
import '../shared/app_translations.dart';
import '../shared/update_dialog.dart';

typedef AsyncCallback = Future<void> Function();

Future<void> showAppSettingsSheet({
  required BuildContext context,
  AsyncCallback? onLogout,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFFF5F6F0),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => _AppSettingsSheet(
      onLogout: onLogout,
    ),
  );
}

class _AppSettingsSheet extends StatefulWidget {
  const _AppSettingsSheet({this.onLogout});

  final AsyncCallback? onLogout;

  @override
  State<_AppSettingsSheet> createState() => _AppSettingsSheetState();
}

class _AppSettingsSheetState extends State<_AppSettingsSheet> {
  static const _languageKey = 'language';
  static const _languageOptions = <Map<String, String>>[
    {'code': 'en', 'label': 'English'},
    {'code': 'ko', 'label': 'Korean'},
    {'code': 'ja', 'label': 'Japanese'},
    {'code': 'zh', 'label': 'Chinese'},
  ];

  String _selectedLanguage = 'en';
  bool _loadingLanguage = true;
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final lang = prefs.getString(_languageKey) ?? 'en';
    if (!mounted) return;
    setState(() {
      _selectedLanguage = lang;
      _loadingLanguage = false;
    });
    setAppLanguage(lang);
  }

  Future<void> _checkForUpdate() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    await checkForUpdateManually(context);
    if (mounted) setState(() => _checkingUpdate = false);
  }

  Future<void> _setLanguage(String code) async {
    if (code == _selectedLanguage) return;
    setState(() => _selectedLanguage = code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, code);
    await prefs.setBool('language_initialized', true);
    setAppLanguage(code);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'settings'.tr,
                  style: GoogleFonts.urbanist(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF4A4945),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF4A4945), size: 22),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.language, color: Color(0xFF0C0E2B)),
              title: Text(
                'language'.tr,
                style: GoogleFonts.urbanist(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF4A4945),
                ),
              ),
              trailing: _loadingLanguage
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedLanguage,
                        items: _languageOptions
                            .map(
                              (opt) => DropdownMenuItem<String>(
                                value: opt['code'],
                                child: Text(
                                  opt['label'] ?? opt['code']!,
                                  style: GoogleFonts.urbanist(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF4A4945),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            _setLanguage(value);
                          }
                        },
                      ),
                    ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.system_update, color: Color(0xFF0C0E2B)),
              title: Text(
                'check_for_updates'.tr,
                style: GoogleFonts.urbanist(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF4A4945),
                ),
              ),
              trailing: _checkingUpdate
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: _checkingUpdate ? null : _checkForUpdate,
            ),
            if (widget.onLogout != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.logout, color: Color(0xFF0C0E2B)),
                title: Text(
                  'logout'.tr,
                  style: GoogleFonts.urbanist(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF4A4945),
                  ),
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  await widget.onLogout!();
                },
              ),
          ],
        ),
      ),
    );
  }
}

