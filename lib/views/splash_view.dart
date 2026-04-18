import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import 'intro_view.dart';

class SplashView extends StatefulWidget {
  final void Function(Locale)? setLocale;
  const SplashView({super.key, this.setLocale});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> with TickerProviderStateMixin {
  String _status = "";
  bool _isNavigating = false;
  bool _isDisposed = false;
  final List<Timer> _animationTimers = [];

  // Animation controllers
  late AnimationController _bgController;
  late AnimationController _logoController;
  late AnimationController _textController;
  late AnimationController _progressController;
  late AnimationController _shimmerController;
  late AnimationController _particleController;

  // Animations
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _logoRotation;
  late Animation<double> _titleOpacity;
  late Animation<Offset> _titleSlide;
  late Animation<double> _subtitleOpacity;
  late Animation<double> _progressOpacity;
  late Animation<double> _statusOpacity;
  late Animation<double> _shimmer;
  late Animation<double> _bgAnim;

  // Floating particles
  late List<_SplashParticle> _particles;

  @override
  void initState() {
    super.initState();

    // Generate floating particles
    final rng = math.Random(7);
    _particles = List.generate(24, (_) => _SplashParticle(rng));

    // Background subtle animation
    _bgController = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    )..repeat(reverse: true);
    _bgAnim = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _bgController, curve: Curves.easeInOut));

    // Logo entrance: scale from 0.3 + rotate + fade in
    _logoController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _logoScale = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack),
      ),
    );
    _logoOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );
    _logoRotation = Tween<double>(begin: -0.05, end: 0.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    // Text entrance
    _textController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _titleOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _textController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );
    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _textController,
            curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
          ),
        );
    _subtitleOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _textController,
        curve: const Interval(0.3, 0.7, curve: Curves.easeOut),
      ),
    );

    // Progress entrance
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _progressOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeOut),
    );
    _statusOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _progressController,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
      ),
    );

    // Shimmer on logo
    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 2200),
      vsync: this,
    )..repeat();
    _shimmer = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );

    // Particle float
    _particleController = AnimationController(
      duration: const Duration(seconds: 6),
      vsync: this,
    )..repeat(reverse: true);

    // Staggered entrance sequence
    _startAnimationSequence();
    _startInit();
  }

  void _startAnimationSequence() {
    _registerAnimationTimer(
      const Duration(milliseconds: 100),
      _logoController,
    );
    _registerAnimationTimer(
      const Duration(milliseconds: 600),
      _textController,
    );
    _registerAnimationTimer(
      const Duration(milliseconds: 1000),
      _progressController,
    );
  }

  void _registerAnimationTimer(
    Duration delay,
    AnimationController controller,
  ) {
    final timer = Timer(delay, () => _safeForward(controller));
    _animationTimers.add(timer);
  }

  void _safeForward(AnimationController controller) {
    if (!mounted || _isDisposed || _isNavigating) {
      return;
    }
    try {
      controller.forward();
    } catch (e) {
      debugPrint('Splash animation skipped: $e');
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    for (final timer in _animationTimers) {
      timer.cancel();
    }
    _animationTimers.clear();
    _bgController.dispose();
    _logoController.dispose();
    _textController.dispose();
    _progressController.dispose();
    _shimmerController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  Future<void> _startInit() async {
    // Remove native splash as soon as Flutter splash is visible
    FlutterNativeSplash.remove();
    if (mounted) {
      setState(() => _status = "Đang khởi tạo hệ thống...");
    }

    final prefs = await SharedPreferences.getInstance();
    final isFirstTime = prefs.getBool('is_first_time') ?? true;

    _runStatusSequence(waitForCloud: !isFirstTime);

    if (!isFirstTime) {
      try {
        await firebaseBootstrapReady.timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            debugPrint(
              '⚠️ Firebase bootstrap timeout on splash, continue to AuthGate',
            );
          },
        );
      } catch (e) {
        debugPrint('⚠️ Splash bootstrap wait error: $e');
      }
    }

    if (mounted) {
      setState(() => _status = "Sẵn sàng!");
    }
    await Future.delayed(const Duration(milliseconds: 120));

    if (!mounted) return;

    if (isFirstTime) {
      _isNavigating = true;
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => IntroView(setLocale: widget.setLocale),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    } else {
      _isNavigating = true;
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
  }

  Future<void> _runStatusSequence({required bool waitForCloud}) async {
    await Future.delayed(const Duration(milliseconds: 120));
    if (!mounted || _isNavigating) return;
    setState(() => _status = "Đang nạp cấu hình cửa hàng...");

    if (!waitForCloud) {
      return;
    }

    await Future.delayed(const Duration(milliseconds: 120));
    if (!mounted || _isNavigating) return;
    setState(() => _status = "Đang kết nối đám mây...");
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
              // ── Animated Gradient Background ──
              _buildBackground(),

              // ── Floating Particles ──
              ..._particles.map((p) => _buildParticle(p, size)),

              // ── Main Content ──
              SafeArea(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Spacer(flex: 3),

                      // Logo with glow + shimmer
                      _buildAnimatedLogo(),

                      const SizedBox(height: 36),

                      // App Name
                      _buildTitle(),

                      const SizedBox(height: 8),

                      // Tagline
                      _buildSubtitle(),

                      const Spacer(flex: 2),

                      // Loading indicator + status
                      _buildLoadingSection(),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBackground() {
    // Subtle gradient shift based on _bgAnim
    final t = _bgAnim.value;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-.3 - t * 0.3, -1),
          end: Alignment(.3 + t * 0.3, 1),
          colors: const [
            Color(0xFF0A1628), // Deep navy
            Color(0xFF0D2137), // Dark blue
            Color(0xFF0F3460), // Rich blue center
            Color(0xFF0D2137),
            Color(0xFF0A1628),
          ],
          stops: [0, 0.25, 0.5, 0.75, 1],
        ),
      ),
    );
  }

  Widget _buildParticle(_SplashParticle p, Size screenSize) {
    return AnimatedBuilder(
      animation: _particleController,
      builder: (context, _) {
        final t = _particleController.value;
        final dx = math.sin(t * math.pi * 2 + p.phase) * p.driftX;
        final dy = math.cos(t * math.pi * 2 + p.phaseY) * p.driftY;
        final opacity =
            p.baseOpacity *
            (0.4 + 0.6 * (0.5 + 0.5 * math.sin(t * math.pi * 2 + p.phase)));

        return Positioned(
          left: p.x * screenSize.width + dx,
          top: p.y * screenSize.height + dy,
          child: Container(
            width: p.size,
            height: p.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [p.color.withOpacity(opacity), p.color.withOpacity(0)],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnimatedLogo() {
    return AnimatedBuilder(
      animation: Listenable.merge([_logoController, _shimmerController]),
      builder: (context, _) {
        return Transform.rotate(
          angle: _logoRotation.value,
          child: Transform.scale(
            scale: _logoScale.value,
            child: Opacity(
              opacity: _logoOpacity.value,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    // Outer glow
                    BoxShadow(
                      color: const Color(0xFF42A5F5).withOpacity(0.35),
                      blurRadius: 40,
                      spreadRadius: 2,
                    ),
                    // Soft inner shadow
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: Stack(
                    children: [
                      // Logo image
                      Container(
                        color: Colors.white,
                        child: Image.asset(
                          'assets/images/logo.png',
                          fit: BoxFit.cover,
                          width: 120,
                          height: 120,
                          errorBuilder: (_, __, ___) => Container(
                            width: 120,
                            height: 120,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF0068FF), Color(0xFF42A5F5)],
                              ),
                            ),
                            child: const Icon(
                              Icons.store_rounded,
                              size: 56,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      // Shimmer overlay
                      Positioned.fill(
                        child: ShaderMask(
                          shaderCallback: (rect) {
                            return LinearGradient(
                              begin: Alignment(_shimmer.value - 1, -0.3),
                              end: Alignment(_shimmer.value, 0.3),
                              colors: [
                                Colors.transparent,
                                Colors.white.withOpacity(0.15),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.5, 1.0],
                            ).createShader(rect);
                          },
                          blendMode: BlendMode.srcATop,
                          child: Container(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTitle() {
    return SlideTransition(
      position: _titleSlide,
      child: FadeTransition(
        opacity: _titleOpacity,
        child: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Colors.white, Color(0xFF90CAF9)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(bounds),
          child: const Text(
            "HULUCA SHOP",
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 4,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubtitle() {
    return FadeTransition(
      opacity: _subtitleOpacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
          color: Colors.white.withOpacity(0.06),
        ),
        child: Text(
          "Quản lý cửa hàng chuyên nghiệp",
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: Colors.white.withOpacity(0.7),
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingSection() {
    return FadeTransition(
      opacity: _progressOpacity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 50),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Custom animated loading dots
            _buildLoadingDots(),

            const SizedBox(height: 20),

            // Status text with fade
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: FadeTransition(
                opacity: _statusOpacity,
                child: Text(
                  _status,
                  key: ValueKey(_status),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.3,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingDots() {
    return SizedBox(
      height: 12,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (i) {
          return AnimatedBuilder(
            animation: _shimmerController,
            builder: (context, _) {
              final t = (_shimmerController.value * 3 - i).clamp(0.0, 1.0);
              final scale = 0.5 + 0.5 * math.sin(t * math.pi);
              final opacity = 0.3 + 0.7 * scale;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(opacity),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF42A5F5).withOpacity(opacity * 0.5),
                      blurRadius: 6 * scale,
                    ),
                  ],
                ),
              );
            },
          );
        }),
      ),
    );
  }
}

/// Particle for splash screen floating effect
class _SplashParticle {
  final double x, y, size, baseOpacity, phase, phaseY, driftX, driftY;
  final Color color;

  _SplashParticle(math.Random rng)
    : x = rng.nextDouble(),
      y = rng.nextDouble(),
      size = 3 + rng.nextDouble() * 20,
      baseOpacity = 0.04 + rng.nextDouble() * 0.1,
      phase = rng.nextDouble() * math.pi * 2,
      phaseY = rng.nextDouble() * math.pi * 2,
      driftX = 3 + rng.nextDouble() * 12,
      driftY = 3 + rng.nextDouble() * 12,
      color = [
        const Color(0xFF42A5F5),
        const Color(0xFF64B5F6),
        const Color(0xFF90CAF9),
        const Color(0xFF7C4DFF),
        const Color(0xFF448AFF),
      ][rng.nextInt(5)];
}
