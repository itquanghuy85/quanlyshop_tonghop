import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'firebase_options.dart';
import 'views/home_view.dart';
import 'views/login_view.dart';
import 'views/splash_view.dart'; // Import màn hình Splash mới
import 'views/currency_input_demo.dart'; // Import demo currency input
import 'views/shop_selector_view.dart'; // Màn hình chọn shop cho super admin
import 'theme/app_theme.dart'; // Import theme thống nhất
import 'services/user_service.dart';
import 'services/notification_service.dart';
import 'services/connectivity_service.dart';
import 'services/sync_service.dart';
import 'services/sync_health_check.dart'; // Kiểm tra sync health
import 'services/sync_orchestrator.dart'; // Quản lý đồng bộ local -> cloud
import 'services/cash_closing_notifier.dart'; // Realtime notify chốt quỹ
import 'data/db_helper.dart'; // Local database helper
import 'package:firebase_messaging/firebase_messaging.dart';

// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase if needed
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Handle background message
  await NotificationService.handleBackgroundMessage(message);
}

Future<void> main() async {
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting('vi_VN');
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // Set up Firebase Messaging background handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    } catch (e) {
      debugPrint('Firebase initialization failed: $e');
      rethrow;
    }
    try {
      await NotificationService.init();
    } catch (e) {
      debugPrint('NotificationService initialization failed: $e');
      // Continue, as notifications are not critical for launch
    }
    try {
      await ConnectivityService.instance.initialize();
    } catch (e) {
      debugPrint('ConnectivityService initialization failed: $e');
      // Continue, as connectivity monitoring is not critical for launch
    }
    runApp(const MyApp());
  }, (error, stack) {
    debugPrint('GLOBAL ERROR: $error');
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Locale? _locale;

  @override
  void initState() {
    super.initState();
    _loadSavedLocale();
  }

  Future<void> _loadSavedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final languageCode = prefs.getString('app_language');
    final supportedCodes = ['vi', 'en'];
    final code = supportedCodes.contains(languageCode) ? languageCode : 'vi';
    setState(() {
      _locale = Locale(code!);
    });
  }

  void setLocale(Locale locale) {
    setState(() {
      _locale = locale;
    });
    SharedPreferences.getInstance().then((p) => p.setString('app_language', locale.languageCode));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quan Ly Shop',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: NotificationService.messengerKey,
      theme: AppTheme.lightTheme,
      locale: _locale,
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      localeResolutionCallback: (locale, supportedLocales) {
        for (var supportedLocale in supportedLocales) {
          if (supportedLocale.languageCode == locale?.languageCode) {
            return supportedLocale;
          }
        }
        return supportedLocales.first;
      },
      routes: {
        '/currency-demo': (context) => const CurrencyInputDemo(),
      },
      home: SplashView(setLocale: setLocale), // Luôn bắt đầu từ SplashView để khởi tạo mượt mà
    );
  }
}

class AuthGate extends StatefulWidget {
  final void Function(Locale)? setLocale;
  const AuthGate({super.key, this.setLocale});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  // Cache future để tránh gọi lại khi rebuild
  Future<Map<String, dynamic>>? _roleFuture;
  String? _currentUid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initNotificationListener();
    _initSyncOrchestrator();
  }

  void _initSyncOrchestrator() async {
    try {
      await SyncOrchestrator().init();
      debugPrint('✅ SyncOrchestrator initialized');
    } catch (e) {
      debugPrint('❌ SyncOrchestrator init failed: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Khi app resume từ background, kiểm tra và đảm bảo FCM token vẫn hợp lệ
      debugPrint('App resumed - checking FCM token validity...');
      NotificationService.ensureFCMTokenValid();
    }
  }

  void _initNotificationListener() {
    NotificationService.listenToNotifications((title, body) {
      if (mounted) {
        NotificationService.showSnackBar("$title: $body", color: const Color(0xFF2962FF));
      }
    });
  }

  /// Lấy hoặc tạo future cho user - chỉ tạo mới khi user thay đổi
  Future<Map<String, dynamic>> _getOrCreateRoleFuture(String uid, String email) {
    if (_roleFuture == null || _currentUid != uid) {
      _currentUid = uid;
      _roleFuture = _getRoleAfterSync(uid, email).timeout(const Duration(seconds: 30));
    }
    return _roleFuture!;
  }

  /// Reset khi đăng xuất
  void _resetCache() {
    _roleFuture = null;
    _currentUid = null;
  }

  /// Kiểm tra role và xử lý super admin
  /// Trả về Map với 'role' và 'isSuperAdmin'
  Future<Map<String, dynamic>> _getRoleAfterSync(String uid, String email) async {
    await UserService.syncUserInfo(uid, email);
    
    // Kiểm tra super admin TRƯỚC - không cần sync data
    final bool isSuperAdmin = UserService.isCurrentUserSuperAdmin();
    if (isSuperAdmin) {
      debugPrint('🔑 Super admin đăng nhập - chờ chọn shop');
      // Super admin: Không download data, chờ chọn shop
      return {
        'role': 'admin',
        'isSuperAdmin': true,
      };
    }
    
    // User thường: Kiểm tra và sync data
    final currentShopId = await UserService.getCurrentShopId();
    await _checkAndClearLocalDataIfShopChanged(currentShopId);
    
    // Download dữ liệu từ cloud về
    try {
      await SyncService.downloadAllFromCloud().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          debugPrint('⚠️ Sync timeout sau 15s, tiếp tục với data local...');
        },
      );
      debugPrint('✅ Sync hoàn thành');
      
      // Khởi tạo CashClosingNotifier để theo dõi trạng thái chốt quỹ realtime
      await CashClosingNotifier.instance.init();
      debugPrint('✅ CashClosingNotifier initialized');
    } catch (e) {
      debugPrint('❌ Lỗi đồng bộ: $e');
    }
    
    // Chạy health check ngầm
    // ignore: unawaited_futures
    Future.microtask(() async {
      try {
        await SyncHealthCheck.runFullCheck();
      } catch (e) {
        debugPrint('❌ Lỗi health check: $e');
      }
    });
    
    final role = await UserService.getUserRole(uid);
    return {
      'role': role,
      'isSuperAdmin': false,
    };
  }

  /// Kiểm tra và xóa local data nếu shop thay đổi
  Future<void> _checkAndClearLocalDataIfShopChanged(String? currentShopId) async {
    if (currentShopId == null) return; // Super admin - không kiểm tra
    
    final prefs = await SharedPreferences.getInstance();
    final lastShopId = prefs.getString('last_synced_shop_id');
    
    if (lastShopId != null && lastShopId != currentShopId) {
      debugPrint('⚠️ ShopId đã thay đổi từ $lastShopId -> $currentShopId. Xóa local data cũ...');
      await DBHelper().clearAllData();
      debugPrint('✅ Đã xóa local data cũ của shop $lastShopId');
    }
    
    // Lưu shopId hiện tại
    await prefs.setString('last_synced_shop_id', currentShopId);
    debugPrint('📝 Đã lưu last_synced_shop_id = $currentShopId');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _buildLoadingScreen('Đang kiểm tra phiên đăng nhập...');
        }
        
        // Không có user = đã đăng xuất
        if (snap.hasError || !snap.hasData) {
          _resetCache(); // Reset cache khi đăng xuất
          return LoginView(setLocale: widget.setLocale);
        }

        final uid = snap.data!.uid;
        final email = snap.data!.email!;

        return FutureBuilder<Map<String, dynamic>>(
          future: _getOrCreateRoleFuture(uid, email),
          builder: (context, roleSnap) {
            if (roleSnap.connectionState == ConnectionState.waiting) {
              // Super admin kiểm tra nhanh hơn vì không cần sync
              final isSuperAdmin = email == 'admin@huluca.com';
              return _buildLoadingScreen(
                isSuperAdmin ? 'Đang kiểm tra quyền...' : 'Đang đồng bộ dữ liệu cửa hàng...',
              );
            }
            if (roleSnap.hasError || !roleSnap.hasData) {
              UserService.clearCache(); // Xóa cache khi có lỗi
              _resetCache();
              FirebaseAuth.instance.signOut();
              return LoginView(setLocale: widget.setLocale);
            }
            
            final data = roleSnap.data!;
            final role = data['role'] as String;
            final isSuperAdmin = data['isSuperAdmin'] as bool;
            
            // Super admin: Chuyển đến màn hình chọn shop
            if (isSuperAdmin) {
              return ShopSelectorView(setLocale: widget.setLocale);
            }
            
            // User thường: Vào HomeView
            return HomeView(role: role, setLocale: widget.setLocale);
          },
        );
      },
    );
  }

  Widget _buildLoadingScreen(String message) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 50,
                    height: 50,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2962FF)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    message,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF424242),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Vui lòng đợi trong giây lát...',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
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
}
