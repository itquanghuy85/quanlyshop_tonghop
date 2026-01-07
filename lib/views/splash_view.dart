import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import 'intro_view.dart';

class SplashView extends StatefulWidget {
  final void Function(Locale)? setLocale;
  const SplashView({super.key, this.setLocale});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> {
  String _status = "Đang khởi tạo hệ thống...";

  @override
  void initState() {
    super.initState();
    _startInit();
  }

  Future<void> _startInit() async {
    // Giả lập nạp dữ liệu để người dùng thấy app đang chạy
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) setState(() => _status = "Đang nạp cấu hình cửa hàng...");
    
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) setState(() => _status = "Đang kết nối đám mây an toàn...");

    final prefs = await SharedPreferences.getInstance();
    final isFirstTime = prefs.getBool('is_first_time') ?? true;

    if (!mounted) return;
    
    if (isFirstTime) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => IntroView(setLocale: widget.setLocale)));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AuthGate(setLocale: widget.setLocale)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // LOGO APP (Bạn có thể thay bằng Image.asset nếu có file ảnh)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF2962FF).withAlpha(25),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.store_rounded, size: 80, color: Color(0xFF2962FF)),
            ),
            const SizedBox(height: 30),
            const Text(
              "QUẢN LÝ SHOP",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1A237E), letterSpacing: 2),
            ),
            const SizedBox(height: 50),
            const SizedBox(
              width: 40, height: 40,
              child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF2962FF)),
            ),
            const SizedBox(height: 20),
            Text(
              _status,
              style: const TextStyle(color: Colors.grey, fontSize: 13, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
}
