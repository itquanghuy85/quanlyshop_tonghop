import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../l10n/app_localizations.dart';
import '../utils/app_info.dart';

/// Professional loading screen shown after login while data syncs.
/// Features glassmorphism design, floating particles, and elegant animations.
class LoadingIntroScreen extends StatefulWidget {
  final String message;
  final String? subMessage;

  const LoadingIntroScreen({
    super.key,
    required this.message,
    this.subMessage,
  });

  @override
  State<LoadingIntroScreen> createState() => _LoadingIntroScreenState();
}

class _LoadingIntroScreenState extends State<LoadingIntroScreen>
    with TickerProviderStateMixin {
  // Core animations
  late AnimationController _entranceController;
  late AnimationController _pulseController;
  late AnimationController _featureController;

  // Entrance animations
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _titleOpacity;
  late Animation<Offset> _titleSlide;
  late Animation<double> _contentOpacity;

  // Pulse glow for logo
  late Animation<double> _pulseAnimation;

  int _currentFeatureIndex = 0;

  // Floating particles data
  late List<_Particle> _particles;

  List<FeatureItem> get _features {
    final loc = AppLocalizations.of(context)!;
    return [
      FeatureItem(
        icon: Icons.phone_android,
        title: loc.repairManagement,
        subtitle: loc.repairManagementDesc,
        gradient: const [Color(0xFF00BCD4), Color(0xFF0097A7)],
      ),
      FeatureItem(
        icon: Icons.inventory_2,
        title: loc.inventoryManagement,
        subtitle: loc.inventoryManagementDesc,
        gradient: const [Color(0xFF4CAF50), Color(0xFF388E3C)],
      ),
      FeatureItem(
        icon: Icons.point_of_sale,
        title: loc.salesAndDebt,
        subtitle: loc.salesAndDebtDesc,
        gradient: const [Color(0xFFFF9800), Color(0xFFF57C00)],
      ),
      FeatureItem(
        icon: Icons.people,
        title: loc.supplierAndPartnerManagement,
        subtitle: loc.supplierAndPartnerManagementDesc,
        gradient: const [Color(0xFF7C4DFF), Color(0xFF651FFF)],
      ),
      FeatureItem(
        icon: Icons.analytics,
        title: loc.reportsAndStatistics,
        subtitle: loc.reportsAndStatisticsDesc,
        gradient: const [Color(0xFFE91E63), Color(0xFFC2185B)],
      ),
      FeatureItem(
        icon: Icons.cloud_sync,
        title: loc.cloudSync,
        subtitle: loc.cloudSyncDesc,
        gradient: const [Color(0xFF42A5F5), Color(0xFF1E88E5)],
      ),
    ];
  }

  @override
  void initState() {
    super.initState();

    // Generate particles
    final rng = math.Random(42);
    _particles = List.generate(18, (i) => _Particle(rng));

    // Entrance animation (1.2s total)
    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );

    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack),
      ),
    );

    _titleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.35, 0.65, curve: Curves.easeOut),
      ),
    );

    _titleSlide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.35, 0.65, curve: Curves.easeOut),
    ));

    _contentOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.55, 0.85, curve: Curves.easeOut),
      ),
    );

    // Subtle pulse for logo glow
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Feature carousel timer
    _featureController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          if (mounted) {
            setState(() {
              _currentFeatureIndex =
                  (_currentFeatureIndex + 1) % _features.length;
            });
          }
          _featureController.forward(from: 0);
        }
      });

    // Start sequence
    _entranceController.forward().then((_) {
      if (mounted) _featureController.forward();
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _pulseController.dispose();
    _featureController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0068FF), // Zalo Blue
                  Color(0xFF0052CC), // Deeper blue
                  Color(0xFF003D99), // Dark blue
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),

          // Floating particles layer
          ...(_particles.map((p) => _buildParticle(p, size))),

          // Main content
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),

                // Logo section
                _buildLogoSection(),

                const SizedBox(height: 28),

                // App title & tagline
                _buildTitleSection(),

                const Spacer(flex: 1),

                // Feature showcase card
                FadeTransition(
                  opacity: _contentOpacity,
                  child: _buildFeatureShowcase(),
                ),

                const Spacer(flex: 1),

                // Loading section
                FadeTransition(
                  opacity: _contentOpacity,
                  child: _buildLoadingSection(),
                ),

                const SizedBox(height: 12),

                // Version
                _buildVersionLabel(),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticle(_Particle p, Size screenSize) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final drift = math.sin(_pulseAnimation.value * math.pi + p.phase) * 8;
        return Positioned(
          left: p.x * screenSize.width,
          top: p.y * screenSize.height + drift,
          child: Opacity(
            opacity: p.opacity * (0.5 + 0.5 * _pulseAnimation.value),
            child: Container(
              width: p.size,
              height: p.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.15),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLogoSection() {
    return AnimatedBuilder(
      animation: Listenable.merge([_entranceController, _pulseController]),
      builder: (context, child) {
        final glowRadius = 12.0 + _pulseAnimation.value * 10.0;
        return Transform.scale(
          scale: _logoScale.value,
          child: Opacity(
            opacity: _logoOpacity.value,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF42A5F5).withOpacity(
                      0.25 + _pulseAnimation.value * 0.15,
                    ),
                    blurRadius: glowRadius,
                    spreadRadius: 2,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Container(
                  color: Colors.white,
                  child: Image.asset(
                    'assets/images/logo.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFF0068FF),
                      child: const Icon(
                        Icons.store_rounded,
                        size: 52,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTitleSection() {
    return SlideTransition(
      position: _titleSlide,
      child: FadeTransition(
        opacity: _titleOpacity,
        child: Column(
          children: [
            Text(
              AppLocalizations.of(context)!.hulucaShop,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 1.5,
                height: 1.2,
                shadows: [
                  Shadow(
                    color: Color(0x40000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                AppLocalizations.of(context)!.phoneRepairShopManagement,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withOpacity(0.85),
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureShowcase() {
    if (_features.isEmpty) return const SizedBox();
    final feature = _features[_currentFeatureIndex];

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.05, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: Container(
        key: ValueKey(_currentFeatureIndex),
        margin: const EdgeInsets.symmetric(horizontal: 28),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.14),
              Colors.white.withOpacity(0.06),
            ],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: Colors.white.withOpacity(0.18),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icon circle with feature-specific gradient
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: feature.gradient,
                ),
                boxShadow: [
                  BoxShadow(
                    color: feature.gradient.first.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(feature.icon, size: 28, color: Colors.white),
            ),
            const SizedBox(width: 16),
            // Text content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    feature.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    feature.subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.white.withOpacity(0.75),
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Dot indicators for features
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _features.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: i == _currentFeatureIndex ? 22 : 7,
                height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: i == _currentFeatureIndex
                      ? Colors.white
                      : Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 5,
              child: LinearProgressIndicator(
                backgroundColor: Colors.white.withOpacity(0.15),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Loading message
          Text(
            widget.message,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
            textAlign: TextAlign.center,
          ),
          if (widget.subMessage != null) ...[
            const SizedBox(height: 4),
            Text(
              widget.subMessage!,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withOpacity(0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVersionLabel() {
    return FutureBuilder<String>(
      future: AppInfo.getVersion(),
      builder: (context, snapshot) {
        final loc = AppLocalizations.of(context)!;
        final versionText = snapshot.data != null && snapshot.data!.isNotEmpty
            ? loc.versionFormat(snapshot.data!)
            : loc.version;
        return Text(
          versionText,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withOpacity(0.4),
            letterSpacing: 0.5,
          ),
        );
      },
    );
  }
}

/// Data class for animated floating particles
class _Particle {
  final double x;
  final double y;
  final double size;
  final double opacity;
  final double phase;

  _Particle(math.Random rng)
      : x = rng.nextDouble(),
        y = rng.nextDouble(),
        size = 4 + rng.nextDouble() * 18,
        opacity = 0.06 + rng.nextDouble() * 0.12,
        phase = rng.nextDouble() * 2 * math.pi;
}

class FeatureItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradient;

  const FeatureItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
  });
}
