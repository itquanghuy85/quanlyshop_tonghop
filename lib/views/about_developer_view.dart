import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_text_styles.dart';
import '../utils/app_info.dart';
import '../l10n/app_localizations.dart';

class AboutDeveloperView extends StatelessWidget {
  const AboutDeveloperView({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(loc.aboutDeveloper),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF2962FF),
              Color(0xFF1976D2),
              Color(0xFF0D47A1),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                // Header Section
                _buildHeader(loc),

                // Main Content
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      const SizedBox(height: 30),

                      // Developer Card
                      _buildDeveloperCard(loc),

                      const SizedBox(height: 20),

                      // Store Card
                      _buildStoreCard(loc),

                      const SizedBox(height: 20),

                      // Contact Card
                      _buildContactCard(loc),

                      const SizedBox(height: 20),

                      // App Info Card
                      _buildAppInfoCard(loc),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations loc) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      child: Column(
        children: [
          // Logo/Icon
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(
                color: Colors.white.withOpacity(0.9),
                width: 5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  spreadRadius: 3,
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: Colors.white.withOpacity(0.1),
                  spreadRadius: -2,
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/images/logo.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.white.withOpacity(0.2),
                    child: const Icon(
                      Icons.business,
                      size: 70,
                      color: Colors.white,
                    ),
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 24),

          Text(
            loc.hulucaStoreDongNai,
            style: TextStyle(
              fontSize: AppTextStyles.headline1.fontSize,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 1.5,
              shadows: const [
                Shadow(
                  color: Colors.black26,
                  offset: Offset(0, 2),
                  blurRadius: 4,
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 12),

          Text(
            loc.aboutDeveloper,
            style: TextStyle(
              fontSize: AppTextStyles.headline1.fontSize,
              fontWeight: FontWeight.w500,
              color: Colors.white,
              letterSpacing: 0.8,
              shadows: const [
                Shadow(
                  color: Colors.black26,
                  offset: Offset(0, 1),
                  blurRadius: 2,
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 8),

          Text(
            loc.professionalStoreManagementApp,
            style: TextStyle(
              fontSize: AppTextStyles.headline3.fontSize,
              color: Colors.white.withOpacity(0.95),
              fontWeight: FontWeight.w400,
              shadows: const [
                Shadow(
                  color: Colors.black26,
                  offset: Offset(0, 1),
                  blurRadius: 2,
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDeveloperCard(AppLocalizations loc) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              Color(0xFFF8F9FA),
            ],
          ),
        ),
        child: Column(
          children: [
            // Avatar
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF2962FF),
                    Color(0xFF1976D2),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2962FF).withOpacity(0.3),
                    spreadRadius: 2,
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.code,
                size: 40,
                color: Colors.white,
              ),
            ),

            const SizedBox(height: 16),

            Text(
              'Quang Huy',
              style: TextStyle(
                fontSize: AppTextStyles.headline1.fontSize,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF2D3748),
              ),
            ),

            const SizedBox(height: 8),

            Text(
              loc.developerAndDesigner,
              style: TextStyle(
                fontSize: AppTextStyles.headline3.fontSize,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),

            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF2962FF).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF2962FF).withOpacity(0.2),
                ),
              ),
              child: Text(
                'HUY AKA',
                style: TextStyle(
                  color: const Color(0xFF2962FF),
                  fontWeight: FontWeight.w600,
                  fontSize: AppTextStyles.headline4.fontSize,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoreCard(AppLocalizations loc) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              Color(0xFFF8F9FA),
            ],
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFF6B35),
                    Color(0xFFF7931E),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF6B35).withOpacity(0.3),
                    spreadRadius: 2,
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.store,
                size: 40,
                color: Colors.white,
              ),
            ),

            const SizedBox(height: 16),

            Text(
              loc.hulucaStore,
              style: TextStyle(
                fontSize: AppTextStyles.headline1.fontSize,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF2D3748),
                letterSpacing: 1.5,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              loc.dongNai,
              style: TextStyle(
                fontSize: AppTextStyles.headline2.fontSize,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFFF6B35),
                letterSpacing: 2,
              ),
            ),

            const SizedBox(height: 12),

            Text(
              loc.professionalPhoneRepairShop,
              style: TextStyle(
                fontSize: AppTextStyles.headline4.fontSize,
                color: Colors.grey[600],
                fontWeight: FontWeight.w400,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactCard(AppLocalizations loc) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              Color(0xFFF8F9FA),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.phone,
                    color: Color(0xFF25D366),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Liên Hệ',
                        style: TextStyle(
                          fontSize: AppTextStyles.headline2.fontSize,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF2D3748),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        loc.hotlineAndZalo,
                        style: TextStyle(
                          fontSize: AppTextStyles.headline4.fontSize,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.grey[200]!,
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '📱',
                    style: TextStyle(fontSize: AppTextStyles.headline1.fontSize),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '0964.09.59.79',
                      style: TextStyle(
                        fontSize: AppTextStyles.headline2.fontSize,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF2D3748),
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _launchPhone('0964095979'),
                    icon: const Icon(
                      Icons.call,
                      color: Color(0xFF25D366),
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366).withOpacity(0.1),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.grey[200]!,
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '💬',
                    style: TextStyle(fontSize: AppTextStyles.headline1.fontSize),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Zalo: 0964.09.59.79',
                      style: TextStyle(
                        fontSize: AppTextStyles.headline3.fontSize,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF2D3748),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _launchZalo('0964095979'),
                    icon: const Icon(
                      Icons.message,
                      color: Color(0xFF0068FF),
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF0068FF).withOpacity(0.1),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppInfoCard(AppLocalizations loc) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              Color(0xFFF8F9FA),
            ],
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0068FF),
                    Color(0xFF0084FF),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0068FF).withOpacity(0.3),
                    spreadRadius: 2,
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.phone_android,
                size: 40,
                color: Colors.white,
              ),
            ),

            const SizedBox(height: 16),

            Text(
              loc.shopManagerApp,
              style: TextStyle(
                fontSize: AppTextStyles.headline1.fontSize,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF2D3748),
              ),
            ),

            const SizedBox(height: 8),

            FutureBuilder<String>(
              future: AppInfo.getVersion(),
              builder: (context, snapshot) {
                final versionText = snapshot.data != null ? loc.versionLabel(snapshot.data!) : loc.versionLabel('...');
                return Text(
                  versionText,
                  style: TextStyle(
                    fontSize: AppTextStyles.headline4.fontSize,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF4CAF50).withOpacity(0.2),
                ),
              ),
              child: Text(
                '',
                style: TextStyle(
                  color: const Color(0xFF4CAF50),
                  fontWeight: FontWeight.w600,
                  fontSize: AppTextStyles.headline4.fontSize,
                ),
              ),
            ),

            const SizedBox(height: 12),

            Text(
              loc.appFullDescription,
              style: TextStyle(
                fontSize: AppTextStyles.headline4.fontSize,
                color: Colors.grey[600],
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchPhone(String phoneNumber) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
    }
  }

  Future<void> _launchZalo(String phoneNumber) async {
    final Uri zaloUri = Uri.parse('https://zalo.me/$phoneNumber');
    if (await canLaunchUrl(zaloUri)) {
      await launchUrl(zaloUri);
    }
  }
}
