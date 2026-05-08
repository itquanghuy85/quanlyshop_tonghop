import 'package:flutter/material.dart';
import '../core/app_mode.dart';
import '../main.dart';

/// Màn hình chọn chế độ hoạt động lần đầu tiên (hiển thị một lần duy nhất).
class ChooseModeScreen extends StatefulWidget {
  final void Function(Locale)? setLocale;
  const ChooseModeScreen({super.key, this.setLocale});

  @override
  State<ChooseModeScreen> createState() => _ChooseModeScreenState();
}

class _ChooseModeScreenState extends State<ChooseModeScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = false;
  late AnimationController _animController;
  late Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeIn = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _chooseOffline() async {
    if (_loading) return;
    setState(() => _loading = true);
    await AppMode.setOfflineMode(true);
    if (!mounted) return;
    _navigateToMain();
  }

  Future<void> _chooseOnline() async {
    if (_loading) return;
    setState(() => _loading = true);
    await AppMode.setOfflineMode(false);
    if (!mounted) return;
    _navigateToMain();
  }

  void _navigateToMain() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => AuthGate(setLocale: widget.setLocale),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0A1628), Color(0xFF0F3460), Color(0xFF1A1A2E)],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeIn,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(height: size.height * 0.07),
                  // Icon & tiêu đề
                  const Icon(
                    Icons.store_mall_directory_rounded,
                    size: 72,
                    color: Color(0xFF42A5F5),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Chọn chế độ sử dụng',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Bạn có thể đổi sang bản trả phí sau trong Cài đặt.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: size.height * 0.06),

                  // --- Thẻ Offline (Miễn phí) ---
                  _ModeCard(
                    icon: Icons.phonelink_off_rounded,
                    color: const Color(0xFF26A69A),
                    title: 'Dùng miễn phí (Offline)',
                    description:
                        'Không cần internet, không cần đăng nhập.\n'
                        'Dữ liệu lưu hoàn toàn trên thiết bị.\n'
                        'Phù hợp cửa hàng nhỏ, dùng một mình.',
                    badge: 'MIỄN PHÍ',
                    badgeColor: const Color(0xFF26A69A),
                    loading: _loading,
                    onTap: _chooseOffline,
                  ),
                  const SizedBox(height: 16),

                  // --- Thẻ Online (Trả phí) ---
                  _ModeCard(
                    icon: Icons.cloud_sync_rounded,
                    color: const Color(0xFF42A5F5),
                    title: 'Dùng trả phí (Online)',
                    description:
                        'Đồng bộ dữ liệu lên cloud Firebase.\n'
                        'Hỗ trợ nhiều nhân viên, nhiều thiết bị.\n'
                        'Yêu cầu đăng nhập và kết nối internet.',
                    badge: 'TRẢ PHÍ',
                    badgeColor: const Color(0xFF42A5F5),
                    loading: _loading,
                    onTap: _chooseOnline,
                  ),

                  const Spacer(),
                  Text(
                    'Lựa chọn này chỉ hiển thị một lần.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white38,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final String badge;
  final Color badgeColor;
  final bool loading;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.badge,
    required this.badgeColor,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedOpacity(
        opacity: loading ? 0.6 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.4), width: 1.5),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: badgeColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              color: badgeColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
