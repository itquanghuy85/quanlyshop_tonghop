import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart'; // Đảm bảo import main để dùng AuthGate
import '../theme/app_text_styles.dart';

class IntroView extends StatefulWidget {
  final void Function(Locale)? setLocale;
  const IntroView({super.key, this.setLocale});

  @override
  State<IntroView> createState() => _IntroViewState();
}

class _IntroViewState extends State<IntroView> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  final List<Map<String, String>> _introData = [
    {
      "title": "Chào mừng đến với Shop Manager",
      "desc": "Ứng dụng quản lý cửa hàng sửa chữa điện thoại toàn diện. Dễ sử dụng, mạnh mẽ và hiệu quả cho mọi nhu cầu kinh doanh.",
      "icon": "🏪"
    },
    {
      "title": "Quản lý bán hàng chuyên nghiệp",
      "desc": "Tạo đơn bán hàng nhanh chóng, theo dõi doanh thu, quản lý khách hàng và bảo hành sản phẩm một cách dễ dàng.",
      "icon": "🛒"
    },
    {
      "title": "Sửa chữa & Bảo hành",
      "desc": "Theo dõi tiến độ sửa chữa, quản lý linh kiện, cập nhật trạng thái đơn hàng và xử lý bảo hành hiệu quả.",
      "icon": "🔧"
    },
    {
      "title": "Quản lý kho thông minh",
      "desc": "Nhập kho siêu tốc bằng mã QR và IMEI. Kiểm soát hàng hóa chính xác 100% với hệ thống kiểm kho tự động.",
      "icon": "📦"
    },
    {
      "title": "Nhân sự & Chấm công",
      "desc": "Quản lý nhân viên, theo dõi chấm công bằng selfie, tính lương và đánh giá hiệu suất làm việc.",
      "icon": "👥"
    },
    {
      "title": "Tài chính & Báo cáo",
      "desc": "Xem báo cáo doanh thu chi tiết, quản lý chi phí, theo dõi công nợ và phân tích tài chính toàn diện.",
      "icon": "💰"
    },
    {
      "title": "Chat nội bộ & Thông báo",
      "desc": "Giao tiếp với nhân viên real-time, nhận thông báo tức thì và quản lý thông tin chung của cửa hàng.",
      "icon": "💬"
    },
    {
      "title": "In hóa đơn & Kết nối thiết bị",
      "desc": "Kết nối máy in nhiệt Bluetooth/WiFi. In tem nhãn, hóa đơn chuyên nghiệp chỉ với 1 chạm.",
      "icon": "🖨️"
    },
    {
      "title": "Đồng bộ đám mây 24/7",
      "desc": "Dữ liệu luôn an toàn và đồng bộ tức thì giữa tất cả các máy. Quản trị shop từ xa mọi lúc mọi nơi.",
      "icon": "☁️"
    },
    {
      "title": "Bắt đầu hành trình",
      "desc": "Khám phá tất cả tính năng và quản lý cửa hàng của bạn một cách hiệu quả. Chúc bạn thành công!",
      "icon": "🚀"
    }
  ];

  Future<void> _completeIntro() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_first_time', false);
    if (!mounted) return;
    
    // SỬA LỖI Ở ĐÂY: Thay vì vào LoginView, ta vào AuthGate để hệ thống tự điều hướng
    Navigator.pushReplacement(
      context, 
      MaterialPageRoute(builder: (_) => AuthGate(setLocale: widget.setLocale))
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: _introData.length,
            onPageChanged: (v) => setState(() => _currentPage = v),
            itemBuilder: (ctx, i) => _buildSlide(_introData[i]),
          ),
          
          Positioned(
            top: 50, right: 20,
            child: TextButton(
              onPressed: _completeIntro, 
              child: const Text("BỎ QUA", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))
            ),
          ),

          Positioned(
            bottom: 50, left: 20, right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: List.generate(_introData.length, (index) => _buildDot(index)),
                ),
                FloatingActionButton(
                  onPressed: () {
                    if (_currentPage < _introData.length - 1) {
                      _controller.nextPage(duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
                    } else {
                      _completeIntro();
                    }
                  },
                  backgroundColor: const Color(0xFF2962FF),
                  child: Icon(_currentPage == _introData.length - 1 ? Icons.check : Icons.arrow_forward),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSlide(Map<String, String> data) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(data['icon']!, style: const TextStyle(fontSize: 100)), // Emoji icon - keeping large size for visual impact
          const SizedBox(height: 40),
          Text(data['title']!, textAlign: TextAlign.center, style: TextStyle(fontSize: AppTextStyles.headline1.fontSize, fontWeight: FontWeight.bold, color: const Color(0xFF1A237E), letterSpacing: 1.2)),
          const SizedBox(height: 20),
          Text(data['desc']!, textAlign: TextAlign.center, style: TextStyle(fontSize: AppTextStyles.headline3.fontSize, color: Colors.blueGrey, height: 1.5)),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    return Container(
      height: 8, width: _currentPage == index ? 24 : 8,
      margin: const EdgeInsets.only(right: 5),
      decoration: BoxDecoration(color: _currentPage == index ? const Color(0xFF2962FF) : Colors.grey.shade300, borderRadius: BorderRadius.circular(4)),
    );
  }
}
