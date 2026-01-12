import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import 'services/claims_service.dart'; // Custom claims management
import 'data/db_helper.dart'; // Local database helper
import 'package:firebase_messaging/firebase_messaging.dart';

// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase if needed
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Handle background message
  await NotificationService.handleBackgroundMessage(message);
}

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await initializeDateFormatting('vi_VN');
      
      // iOS-specific: Run app FIRST to show splash screen immediately
      // This prevents the "freeze" perception on iOS
      final bool isIOS = !kIsWeb && Platform.isIOS;
      
      if (isIOS) {
        // On iOS, start app immediately to show UI, then init Firebase in background
        runApp(const MyApp());
        
        // Initialize Firebase and services after first frame renders
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          try {
            await Firebase.initializeApp(
              options: DefaultFirebaseOptions.currentPlatform,
            );
            
            // Set up Firebase Messaging background handler
            FirebaseMessaging.onBackgroundMessage(
              _firebaseMessagingBackgroundHandler,
            );
            
            debugPrint('✅ Firebase initialized (iOS deferred)');
          } catch (e) {
            debugPrint('Firebase initialization failed: $e');
          }
          
          // Delay notification init to avoid blocking UI
          await Future.delayed(const Duration(milliseconds: 300));
          
          try {
            await NotificationService.init();
          } catch (e) {
            debugPrint('NotificationService initialization failed: $e');
          }
          try {
            await ConnectivityService.instance.initialize();
          } catch (e) {
            debugPrint('ConnectivityService initialization failed: $e');
          }
        });
      } else {
        // Android/Web: Initialize Firebase before running app (original behavior)
        try {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );

          // Set up Firebase Messaging background handler
          FirebaseMessaging.onBackgroundMessage(
            _firebaseMessagingBackgroundHandler,
          );
        } catch (e) {
          debugPrint('Firebase initialization failed: $e');
          rethrow;
        }
        
        // Defer heavy initialization to next frame to allow splash screen to render
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          try {
            await NotificationService.init();
          } catch (e) {
            debugPrint('NotificationService initialization failed: $e');
          }
          try {
            await ConnectivityService.instance.initialize();
          } catch (e) {
            debugPrint('ConnectivityService initialization failed: $e');
          }
        });
        
        runApp(const MyApp());
      }
    },
    (error, stack) {
      debugPrint('GLOBAL ERROR: $error');
    },
  );
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
    SharedPreferences.getInstance().then(
      (p) => p.setString('app_language', locale.languageCode),
    );
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
      routes: {'/currency-demo': (context) => const CurrencyInputDemo()},
      home: SplashView(
        setLocale: setLocale,
      ), // Luôn bắt đầu từ SplashView để khởi tạo mượt mà
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

  // Track if sync orchestrator is initialized
  bool _syncOrchestratorInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Delay notification listener to next frame to avoid blocking startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initNotificationListener();
    });
  }

  /// Initialize SyncOrchestrator - called after user login completes
  Future<void> _initSyncOrchestrator() async {
    if (_syncOrchestratorInitialized) return;
    try {
      await SyncOrchestrator().init();
      _syncOrchestratorInitialized = true;
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

    // Super admin: Tự động logout khi thoát app (paused/detached) để bảo mật
    // NOTE: Tạm tắt để Super Admin có thể sync claims trước
    // TODO: Bật lại sau khi claims đã được sync
    // if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
    //   final user = FirebaseAuth.instance.currentUser;
    //   if (user != null && user.email?.toLowerCase() == 'admin@huluca.com') {
    //     debugPrint('🔒 Super admin leaving app - signing out for security...');
    //     UserService.clearCache();
    //     FirebaseAuth.instance.signOut();
    //   }
    // }
  }

  void _initNotificationListener() {
    NotificationService.listenToNotifications((title, body) {
      if (mounted) {
        NotificationService.showSnackBar(
          "$title: $body",
          color: const Color(0xFF2962FF),
        );
      }
    });
  }

  /// Lấy hoặc tạo future cho user - chỉ tạo mới khi user thay đổi
  Future<Map<String, dynamic>> _getOrCreateRoleFuture(
    String uid,
    String email,
  ) {
    if (_roleFuture == null || _currentUid != uid) {
      _currentUid = uid;
      _roleFuture = _getRoleAfterSync(
        uid,
        email,
      ).timeout(const Duration(seconds: 30));
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
  Future<Map<String, dynamic>> _getRoleAfterSync(
    String uid,
    String email,
  ) async {
    try {
      await UserService.syncUserInfo(uid, email);
    } catch (e) {
      debugPrint('⚠️ syncUserInfo error (continuing): $e');
    }

    // Kiểm tra super admin TRƯỚC - không cần sync data
    final bool isSuperAdmin = UserService.isCurrentUserSuperAdmin();
    if (isSuperAdmin) {
      debugPrint('🔑 Super admin đăng nhập - chờ chọn shop');
      // Super admin: Không download data, chờ chọn shop
      return {'role': 'admin', 'isSuperAdmin': true};
    }

    // User thường: Kiểm tra và sync data
    String? currentShopId;
    try {
      currentShopId = await UserService.getCurrentShopId();
      // Nếu vẫn null, thử refresh claims
      if (currentShopId == null) {
        debugPrint('⚠️ shopId null, thử refresh claims lần cuối...');
        await ClaimsService().refreshMyClaims();
        await Future.delayed(const Duration(seconds: 2));
        currentShopId = await UserService.getCurrentShopId();
      }
    } catch (e) {
      debugPrint('⚠️ Error getting shopId: $e');
    }

    if (currentShopId != null) {
      await _checkAndClearLocalDataIfShopChanged(currentShopId);
    } else {
      debugPrint('⚠️ Vẫn không có shopId, tiếp tục với data rỗng...');
    }

    // Download dữ liệu từ cloud về
    try {
      await SyncService.downloadAllFromCloud().timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          debugPrint('⚠️ Sync timeout sau 20s, tiếp tục với data local...');
        },
      );
      debugPrint('✅ Sync hoàn thành');

      // Initialize SyncOrchestrator AFTER successful login and data sync
      // This prevents blocking startup
      await _initSyncOrchestrator();

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
    return {'role': role, 'isSuperAdmin': false};
  }

  /// Kiểm tra và xóa local data nếu shop hoặc user thay đổi
  Future<void> _checkAndClearLocalDataIfShopChanged(
    String? currentShopId,
  ) async {
    if (currentShopId == null) return; // Super admin - không kiểm tra

    final prefs = await SharedPreferences.getInstance();
    final lastShopId = prefs.getString('last_synced_shop_id');
    final lastUserId = prefs.getString('last_synced_user_id');
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    // Xóa data nếu:
    // 1. lastShopId khác currentShopId (đổi shop)
    // 2. lastShopId == null (lần đầu đăng nhập với shop này)
    // 3. lastUserId khác currentUserId (đổi user cùng shop - để tránh data lẫn do permission khác nhau)
    final needClear =
        lastShopId == null ||
        lastShopId != currentShopId ||
        (lastUserId != null && lastUserId != currentUserId);

    if (needClear) {
      debugPrint(
        '⚠️ Shop hoặc User thay đổi: shop=$lastShopId->$currentShopId, user=$lastUserId->$currentUserId. Xóa local data cũ...',
      );
      await DBHelper().clearAllData();
      debugPrint('✅ Đã xóa local data cũ');
    }

    // Lưu shopId và userId hiện tại
    await prefs.setString('last_synced_shop_id', currentShopId);
    if (currentUserId != null) {
      await prefs.setString('last_synced_user_id', currentUserId);
    }
    debugPrint(
      '📝 Đã lưu last_synced: shopId=$currentShopId, userId=$currentUserId',
    );
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
                isSuperAdmin
                    ? 'Đang kiểm tra quyền...'
                    : 'Đang đồng bộ dữ liệu cửa hàng...',
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
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF2962FF),
                      ),
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
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
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
