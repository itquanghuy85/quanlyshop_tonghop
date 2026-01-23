import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Màn hình loading với animation giới thiệu app
/// Hiển thị khi đăng nhập thành công và đang load dữ liệu
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
  late AnimationController _logoController;
  late AnimationController _textController;
  late AnimationController _featureController;
  late Animation<double> _logoScale;
  late Animation<double> _logoRotation;
  late Animation<double> _textOpacity;
  late Animation<Offset> _textSlide;
  
  int _currentFeatureIndex = 0;
  
  final List<FeatureItem> _features = [
    FeatureItem(
      icon: Icons.phone_android,
      title: 'Quản lý sửa chữa',
      subtitle: 'Theo dõi đơn sửa chữa từ nhận máy đến giao máy',
    ),
    FeatureItem(
      icon: Icons.inventory_2,
      title: 'Quản lý kho hàng',
      subtitle: 'Nhập hàng, xuất kho, kiểm kê linh kiện',
    ),
    FeatureItem(
      icon: Icons.point_of_sale,
      title: 'Bán hàng & Công nợ',
      subtitle: 'Bán hàng nhanh, theo dõi công nợ khách hàng',
    ),
    FeatureItem(
      icon: Icons.people,
      title: 'Quản lý NCC & Đối tác sua chữa',
      subtitle: 'Theo dõi công nợ nhà cung cấp và đối tác',
    ),
    FeatureItem(
      icon: Icons.analytics,
      title: 'Báo cáo thống kê',
      subtitle: 'Doanh thu, lợi nhuận, tồn kho theo thời gian',
    ),
    FeatureItem(
      icon: Icons.cloud_sync,
      title: 'Đồng bộ Cloud',
      subtitle: 'Dữ liệu an toàn, truy cập mọi lúc mọi nơi',
    ),
  ];

  @override
  void initState() {
    super.initState();
    
    // Logo animation
    _logoController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _logoScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );
    
    _logoRotation = Tween<double>(begin: -0.1, end: 0.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );
    
    // Text animation
    _textController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeIn),
    );
    
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _textController, curve: Curves.easeOut));
    
    // Feature rotation animation
    _featureController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _currentFeatureIndex = (_currentFeatureIndex + 1) % _features.length;
        });
        _featureController.forward(from: 0);
      }
    });
    
    // Start animations sequence
    _logoController.forward().then((_) {
      _textController.forward();
      _featureController.forward();
    });
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    _featureController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1A237E), // Dark blue
              Color(0xFF283593), // Indigo
              Color(0xFF303F9F), // Lighter indigo
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 40),
              
              // Logo with animation
              AnimatedBuilder(
                animation: _logoController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _logoScale.value,
                    child: Transform.rotate(
                      angle: _logoRotation.value * math.pi,
                      child: child,
                    ),
                  );
                },
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.store,
                        size: 60,
                        color: Color(0xFF1A237E),
                      ),
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // App name with animation
              SlideTransition(
                position: _textSlide,
                child: FadeTransition(
                  opacity: _textOpacity,
                  child: const Column(
                    children: [
                      Text(
                        'HULUCA SHOP',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Quản lý cửa hàng sửa chữa điện thoại',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 40),
              
              // Features carousel
              Expanded(
                child: FadeTransition(
                  opacity: _textOpacity,
                  child: _buildFeatureCarousel(),
                ),
              ),
              
              // Loading indicator and message
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    // Progress indicator
                    SizedBox(
                      width: 200,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          backgroundColor: Colors.white24,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white.withOpacity(0.9),
                          ),
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Message
                    Text(
                      widget.message,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (widget.subMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        widget.subMessage!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.7),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
              
              // Version info
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'Phiên bản 1.0.0',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildFeatureCarousel() {
    final feature = _features[_currentFeatureIndex];
    
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.1, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: Container(
        key: ValueKey(_currentFeatureIndex),
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                feature.icon,
                size: 36,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            
            // Title
            Text(
              feature.title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            
            // Subtitle
            Text(
              feature.subtitle,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.8),
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 20),
            
            // Feature index indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _features.length,
                (index) => Container(
                  width: index == _currentFeatureIndex ? 24 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: index == _currentFeatureIndex
                        ? Colors.white
                        : Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FeatureItem {
  final IconData icon;
  final String title;
  final String subtitle;
  
  const FeatureItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}
