import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../shared/globals.dart';
import '../shared/settings_sheet.dart';
import '../shared/app_translations.dart';
import 'pages/menu_home_page.dart';
import 'services/api_service.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  // Brand palette — sampled from the Blue Moon badge (navy + gold).
  static const Color navy = Color(0xFF0C0E2B);
  static const Color gold = Color(0xFFF1C83E);
  static const Color cream = Color(0xFFF5F6F0);
  static const Color textDark = Color(0xFF4A4945);

  // Logo Size Settings - Adjust these values to change logo size
  static const double logoHeightPortrait = 240.0; // Logo height in portrait mode
  static const double logoHeightLandscape = 280.0; // Logo height in landscape mode

  // Logo Image Settings - Different images for portrait and landscape
  static const String logoImagePortrait = 'assets/images/logo1.png'; // Portrait image
  static const String logoImageLandscape = 'assets/images/logo.png'; // Landscape image

  @override
  Widget build(BuildContext context) {
    // Rebuilds whenever the selected language changes (e.g. from the
    // settings sheet) so the tagline/CTA/disclaimers below re-translate —
    // this is a plain StatelessWidget with no listener of its own otherwise.
    return ValueListenableBuilder<String>(
      valueListenable: languageNotifier,
      builder: (context, _, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final screenSize = size;
    final isPortrait = size.height >= size.width;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SizedBox(
        width: screenSize.width,
        height: screenSize.height,
        child: Stack(
            fit: StackFit.expand,
            children: [
              // Night-sky gradient — navy fading into cream, in the same
              // palette as the Blue Moon badge, with a soft gold "moonlight"
              // glow behind the logo.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [navy, Color(0xFF3A3D6B), cream],
                    stops: [0.0, 0.32, 0.62],
                  ),
                ),
              ),
              Positioned(
                top: -80,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 420,
                    height: 420,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [gold.withOpacity(0.35), gold.withOpacity(0.0)],
                      ),
                    ),
                  ),
                ),
              ),
              // Child content on top (with SafeArea applied inside)
              SafeArea(
                child: GestureDetector(
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const MenuHomePage()),
                    );
                  },
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 32, top: 24, right: 32, bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      Center(
                        child: Image.asset(
                          isPortrait ? logoImagePortrait : logoImageLandscape,
                          height: isPortrait ? logoHeightPortrait : logoHeightLandscape,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Portrait mode layout
                      if (isPortrait) ...[
                        Text(
                          'home_tagline'.tr.toUpperCase(),
                          style: GoogleFonts.urbanist(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: navy,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        _LocationChip(),
                        const SizedBox(height: 32),
                        Center(
                          child: SizedBox(
                            width: size.width * 0.5,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(builder: (context) => const MenuHomePage()),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: navy,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(50),
                                  side: const BorderSide(color: gold, width: 1.5),
                                ),
                                elevation: 0,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'order_now'.tr,
                                    style: GoogleFonts.urbanist(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'touch_to_order'.tr,
                                    style: GoogleFonts.urbanist(
                                      fontSize: 14,
                                      fontWeight: FontWeight.normal,
                                      color: gold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 48),
                        Column(
                          children: [
                            Text(
                              '* ${'price_note_peso'.tr}',
                              style: GoogleFonts.urbanist(
                                fontSize: 14,
                                color: textDark,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '* ${'price_note_photo'.tr}',
                              style: GoogleFonts.urbanist(
                                fontSize: 14,
                                color: textDark,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'all_set_menu'.tr,
                              style: GoogleFonts.urbanist(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: textDark,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ] else ...[
                        // Landscape mode layout
                        Text(
                          'home_tagline'.tr,
                          style: GoogleFonts.urbanist(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: navy,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        Center(
                          child: SizedBox(
                            width: size.width * 0.5,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(builder: (context) => const MenuHomePage()),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: navy,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(50),
                                  side: const BorderSide(color: gold, width: 1.5),
                                ),
                                elevation: 0,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'order_now'.tr,
                                    style: GoogleFonts.urbanist(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'touch_to_order'.tr,
                                    style: GoogleFonts.urbanist(
                                      fontSize: 14,
                                      fontWeight: FontWeight.normal,
                                      color: gold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 54),
                        _LocationChip(),
                        const SizedBox(height: 70),
                        Text(
                          '* ${'price_note_peso'.tr}',
                          style: GoogleFonts.urbanist(
                            fontSize: 24,
                            color: textDark,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                      ),
                    ),
                  ),
                ),
              ),
              // Settings button (place last so it stays on top)
              Positioned(
                top: 12,
                right: 12,
                child: SafeArea(
                  child: IconButton(
                    icon: const Icon(Icons.settings, size: 40),
                    color: navy,
                    onPressed: () {
                      showAppSettingsSheet(
                        context: context,
                        onLogout: () async {
                          await ApiService.logout();
                          if (context.mounted) {
                            refreshAppAuth();
                          }
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
    );
  }
}

/// Small pill showing the branch address, styled with the brand's gold accent.
class _LocationChip extends StatelessWidget {
  const _LocationChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: HomePage.gold, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.place_outlined, size: 20, color: HomePage.navy),
          const SizedBox(width: 8),
          Text(
            'Friendship, Angeles City',
            style: GoogleFonts.urbanist(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: HomePage.navy,
            ),
          ),
        ],
      ),
    );
  }
}
