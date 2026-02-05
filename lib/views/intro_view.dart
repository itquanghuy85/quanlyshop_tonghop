import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart'; // Đảm bảo import main để dùng AuthGate
import '../theme/app_text_styles.dart';
import '../l10n/app_localizations.dart';

class IntroView extends StatefulWidget {
  final void Function(Locale)? setLocale;
  const IntroView({super.key, this.setLocale});

  @override
  State<IntroView> createState() => _IntroViewState();
}

class _IntroViewState extends State<IntroView> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  List<Map<String, String>> get _introData {
    final loc = AppLocalizations.of(context)!;
    return [
      {
        "title": loc.welcomeToShopManager,
        "desc": loc.welcomeDesc,
        "icon": "🏪"
      },
      {
        "title": loc.professionalSalesManagement,
        "desc": loc.salesDesc,
        "icon": "🛒"
      },
      {
        "title": loc.repairAndWarranty,
        "desc": loc.repairDesc,
        "icon": "🔧"
      },
      {
        "title": loc.smartInventoryManagement,
        "desc": loc.inventoryDesc,
        "icon": "📦"
      },
      {
        "title": loc.staffAndAttendance,
        "desc": loc.staffDesc,
        "icon": "👥"
      },
      {
        "title": loc.financeAndReports,
        "desc": loc.financeDesc,
        "icon": "💰"
      },
      {
        "title": loc.internalChatAndNotifications,
        "desc": loc.chatDesc,
        "icon": "💬"
      },
      {
        "title": loc.printReceiptsAndDeviceConnection,
        "desc": loc.printDesc,
        "icon": "🖨️"
      },
      {
        "title": loc.cloudSync247,
        "desc": loc.cloudDesc,
        "icon": "☁️"
      },
      {
        "title": loc.startJourney,
        "desc": loc.startDesc,
        "icon": "🚀"
      }
    ];
  }

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
              child: Text(AppLocalizations.of(context)!.skip, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))
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
