import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../l10n/app_localizations.dart';

class IntroView extends StatefulWidget {
  final void Function(Locale)? setLocale;
  const IntroView({super.key, this.setLocale});

  @override
  State<IntroView> createState() => _IntroViewState();
}

class _IntroViewState extends State<IntroView> with TickerProviderStateMixin {
  final PageController _controller = PageController();
  int _currentPage = 0;

  late AnimationController _entranceController;
  late AnimationController _bgController;
  late AnimationController _iconPulseController;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideUp;
  late Animation<double> _bgAnim;
  late Animation<double> _iconPulse;

  // Floating particles
  late List<_IntroParticle> _particles;

  // Gradient color pairs for each slide
  static const List<List<Color>> _slideGradients = [
    [Color(0xFF0A1628), Color(0xFF0F3460), Color(0xFF1A5276)], // Welcome - deep blue
    [Color(0xFF0A1628), Color(0xFF1B4332), Color(0xFF2D6A4F)], // Sales - teal
    [Color(0xFF0A1628), Color(0xFF4A1942), Color(0xFF6B2D5B)], // Repair - purple
    [Color(0xFF0A1628), Color(0xFF3D2B1F), Color(0xFF6D4C41)], // Inventory - brown
    [Color(0xFF0A1628), Color(0xFF1A237E), Color(0xFF283593)], // Staff - indigo
    [Color(0xFF0A1628), Color(0xFF004D40), Color(0xFF00695C)], // Finance - deep teal
    [Color(0xFF0A1628), Color(0xFF0D47A1), Color(0xFF1565C0)], // Chat - blue
    [Color(0xFF0A1628), Color(0xFF311B92), Color(0xFF4527A0)], // Print - deep purple
    [Color(0xFF0A1628), Color(0xFF01579B), Color(0xFF0277BD)], // Cloud - light blue
    [Color(0xFF0A1628), Color(0xFF0D3B66), Color(0xFF14919B)], // Start - cyan
  ];

  // Icon data for each slide (Material icons instead of emoji)
  static const List<IconData> _slideIcons = [
    Icons.storefront_rounded,
    Icons.shopping_cart_rounded,
    Icons.build_circle_rounded,
    Icons.inventory_2_rounded,
    Icons.groups_rounded,
    Icons.account_balance_wallet_rounded,
    Icons.chat_bubble_rounded,
    Icons.print_rounded,
    Icons.cloud_sync_rounded,
    Icons.rocket_launch_rounded,
  ];

  // Accent colors for icons
  static const List<Color> _iconAccents = [
    Color(0xFF42A5F5),
    Color(0xFF66BB6A),
    Color(0xFFAB47BC),
    Color(0xFFFF7043),
    Color(0xFF5C6BC0),
    Color(0xFF26A69A),
    Color(0xFF42A5F5),
    Color(0xFF7E57C2),
    Color(0xFF29B6F6),
    Color(0xFFFFCA28),
  ];

  List<Map<String, String>> get _introData {
    final loc = AppLocalizations.of(context)!;
    return [
      {"title": loc.welcomeToShopManager, "desc": loc.welcomeDesc},
      {"title": loc.professionalSalesManagement, "desc": loc.salesDesc},
      {"title": loc.repairAndWarranty, "desc": loc.repairDesc},
      {"title": loc.smartInventoryManagement, "desc": loc.inventoryDesc},
      {"title": loc.staffAndAttendance, "desc": loc.staffDesc},
      {"title": loc.financeAndReports, "desc": loc.financeDesc},
      {"title": loc.internalChatAndNotifications, "desc": loc.chatDesc},
      {"title": loc.printReceiptsAndDeviceConnection, "desc": loc.printDesc},
      {"title": loc.cloudSync247, "desc": loc.cloudDesc},
      {"title": loc.startJourney, "desc": loc.startDesc},
    ];
  }

  @override
  void initState() {
    super.initState();

    final rng = math.Random(42);
    _particles = List.generate(20, (_) => _IntroParticle(rng));

    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeIn = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOut),
    );
    _slideUp = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutCubic),
    );

    _bgController = AnimationController(
      duration: const Duration(seconds: 6),
      vsync: this,
    )..repeat(reverse: true);
    _bgAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _bgController, curve: Curves.easeInOut),
    );

    _iconPulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
    _iconPulse = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _iconPulseController, curve: Curves.easeInOut),
    );

    _entranceController.forward();

    // Set status bar style
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _bgController.dispose();
    _iconPulseController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onPageChanged(int page) {
    setState(() => _currentPage = page);
    _entranceController.reset();
    _entranceController.forward();
  }

  Future<void> _completeIntro() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_first_time', false);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => AuthGate(setLocale: widget.setLocale),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: AnimatedBuilder(
        animation: _bgAnim,
        builder: (context, _) {
          return Stack(
            children: [
              // ── Animated gradient background ──
              _buildBackground(),

              // ── Floating particles ──
              ..._particles.map((p) => _buildParticle(p, size)),

              // ── Page content ──
              PageView.builder(
                controller: _controller,
                itemCount: _introData.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (ctx, i) => _buildSlide(i),
              ),

              // ── Skip button ──
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                right: 16,
                child: TextButton(
                  onPressed: _completeIntro,
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.1),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: Colors.white.withOpacity(0.2)),
                    ),
                  ),
                  child: Text(
                    AppLocalizations.of(context)!.skip,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),

              // ── Bottom controls ──
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildBottomControls(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBackground() {
    final t = _bgAnim.value;
    final colors = _slideGradients[_currentPage.clamp(0, _slideGradients.length - 1)];
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-0.5 - t * 0.3, -1.2),
          end: Alignment(0.5 + t * 0.3, 1.2),
          colors: colors,
          stops: const [0, 0.5, 1],
        ),
      ),
    );
  }

  Widget _buildParticle(_IntroParticle p, Size screenSize) {
    return AnimatedBuilder(
      animation: _bgController,
      builder: (context, _) {
        final t = _bgController.value;
        final dx = math.sin(t * math.pi * 2 + p.phase) * p.driftX;
        final dy = math.cos(t * math.pi * 2 + p.phaseY) * p.driftY;
        final opacity = p.baseOpacity *
            (0.3 + 0.7 * (0.5 + 0.5 * math.sin(t * math.pi * 2 + p.phase)));

        return Positioned(
          left: p.x * screenSize.width + dx,
          top: p.y * screenSize.height + dy,
          child: Container(
            width: p.size,
            height: p.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  _iconAccents[_currentPage.clamp(0, 9)].withOpacity(opacity),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSlide(int index) {
    final data = _introData[index];
    final icon = _slideIcons[index.clamp(0, _slideIcons.length - 1)];
    final accent = _iconAccents[index.clamp(0, _iconAccents.length - 1)];
    final isLast = index == _introData.length - 1;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 60, 32, 120),
        child: FadeTransition(
          opacity: _fadeIn,
          child: SlideTransition(
            position: _slideUp,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 1),

                // ── Animated Icon ──
                ScaleTransition(
                  scale: _iconPulse,
                  child: Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          accent.withOpacity(0.2),
                          accent.withOpacity(0.05),
                        ],
                      ),
                      border: Border.all(
                        color: accent.withOpacity(0.3),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withOpacity(0.25),
                          blurRadius: 40,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Icon(icon, size: 60, color: accent),
                  ),
                ),

                const SizedBox(height: 48),

                // ── Page indicator (inside content) ──
                Text(
                  "${index + 1} / ${_introData.length}",
                  style: TextStyle(
                    color: accent.withOpacity(0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                  ),
                ),

                const SizedBox(height: 16),

                // ── Title ──
                ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    colors: [Colors.white, accent.withOpacity(0.8)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ).createShader(bounds),
                  child: Text(
                    data['title']!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.5,
                      height: 1.3,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Description ──
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    data['desc']!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.white.withOpacity(0.65),
                      height: 1.6,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),

                const Spacer(flex: 2),

                // ── Last page: extra CTA hint ──
                if (isLast)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: accent.withOpacity(0.3)),
                      color: accent.withOpacity(0.08),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.touch_app_rounded, color: accent, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          "Nhấn để bắt đầu",
                          style: TextStyle(
                            color: accent,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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

  Widget _buildBottomControls() {
    final accent = _iconAccents[_currentPage.clamp(0, 9)];
    final isLast = _currentPage == _introData.length - 1;

    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).padding.bottom + 24,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withOpacity(0.3),
          ],
        ),
      ),
      child: Row(
        children: [
          // ── Dot indicators ──
          Expanded(
            child: Row(
              children: List.generate(_introData.length, (i) {
                final isActive = i == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  height: 6,
                  width: isActive ? 28 : 6,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: isActive ? accent : Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: isActive
                        ? [BoxShadow(color: accent.withOpacity(0.4), blurRadius: 8)]
                        : null,
                  ),
                );
              }),
            ),
          ),

          // ── Next / Done button ──
          GestureDetector(
            onTap: () {
              if (isLast) {
                _completeIntro();
              } else {
                _controller.nextPage(
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeInOut,
                );
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: isLast ? 140 : 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(isLast ? 28 : 16),
                gradient: LinearGradient(
                  colors: [accent, accent.withOpacity(0.7)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withOpacity(0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isLast)
                    const Text(
                      "Bắt đầu",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  if (isLast) const SizedBox(width: 6),
                  Icon(
                    isLast ? Icons.arrow_forward_rounded : Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Particle data for intro screen
class _IntroParticle {
  final double x, y, size, baseOpacity, phase, phaseY, driftX, driftY;

  _IntroParticle(math.Random rng)
      : x = rng.nextDouble(),
        y = rng.nextDouble(),
        size = 4 + rng.nextDouble() * 16,
        baseOpacity = 0.03 + rng.nextDouble() * 0.08,
        phase = rng.nextDouble() * math.pi * 2,
        phaseY = rng.nextDouble() * math.pi * 2,
        driftX = 4 + rng.nextDouble() * 10,
        driftY = 4 + rng.nextDouble() * 10;
}
