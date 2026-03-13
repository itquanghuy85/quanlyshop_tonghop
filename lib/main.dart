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
import 'services/payment_intent_service.dart'; // Payment intents management
import 'services/current_shop_service.dart'; // Multi-shop support
import 'data/db_helper.dart'; // Local database helper
import 'utils/perf_monitor.dart'; // Performance monitoring
import 'utils/seed_test_data.dart'; // Test data seeder
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'widgets/loading_intro_screen.dart'; // Loading intro animation

final Completer<void> _firebaseBootstrapCompleter = Completer<void>();

Future<void> get firebaseBootstrapReady => _firebaseBootstrapCompleter.future;

void _markFirebaseBootstrapReady() {
  if (!_firebaseBootstrapCompleter.isCompleted) {
    _firebaseBootstrapCompleter.complete();
  }
}

Future<void> _initializeDeferredAppServices() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    _markFirebaseBootstrapReady();
    debugPrint('✅ Firebase initialized');
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
    _markFirebaseBootstrapReady();
    return;
  }

  await Future.delayed(const Duration(milliseconds: 150));

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
}

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
      final binding = WidgetsFlutterBinding.ensureInitialized();
      if (!kIsWeb) {
        FlutterNativeSplash.preserve(widgetsBinding: binding);
      }
      await initializeDateFormatting('vi_VN');

      // iOS-specific: Run app FIRST to show splash screen immediately
      // This prevents the "freeze" perception on iOS
      final bool isIOS = !kIsWeb && Platform.isIOS;

      if (isIOS) {
        // On iOS, start app immediately to show UI, then init services in background
        runApp(const MyApp());
        Future.microtask(_initializeDeferredAppServices);
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
          _markFirebaseBootstrapReady();
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
      // One-time cleanup: remove duplicate financial activity entries
      DBHelper().deduplicateFinancialActivities();
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
      _roleFuture = _getRoleAfterSync(uid, email);
      if (!kIsWeb) {
        // Mobile: timeout 30s vì có SQLite persistent
        _roleFuture = _roleFuture!.timeout(const Duration(seconds: 30));
      }
      // Web: không timeout — function tự quản lý timeout từng bước
    }
    return _roleFuture!;
  }

  /// Reset khi đăng xuất
  void _resetCache() {
    _roleFuture = null;
    _currentUid = null;
  }

  void _startBackgroundUserWarmup(String uid, String email) {
    Future.microtask(() async {
      try {
        await UserService.syncUserInfo(uid, email).timeout(
          const Duration(seconds: 20),
          onTimeout: () {
            debugPrint('⚠️ [MOBILE] background syncUserInfo timeout, continue');
          },
        );
        await CurrentShopService().init();
      } catch (e) {
        debugPrint('⚠️ background user warmup failed: $e');
      }

      final currentShopId = UserService.getShopIdSync();
      if (currentShopId != null && currentShopId.isNotEmpty) {
        try {
          await SyncService.downloadAllFromCloud(force: true).timeout(
            const Duration(seconds: 20),
            onTimeout: () {
              debugPrint('⚠️ Background sync timeout sau 20s');
            },
          );
          await _initSyncOrchestrator();
          await CashClosingNotifier.instance.init();
          await PaymentIntentService.initialize();
        } catch (e) {
          debugPrint('⚠️ background app services sync failed: $e');
        }
      }

      try {
        await SyncHealthCheck.runFullCheck();
      } catch (e) {
        debugPrint('⚠️ background health check failed: $e');
      }
    });
  }

  /// Kiểm tra role và xử lý super admin
  /// Trả về Map với 'role' và 'isSuperAdmin'
  Future<Map<String, dynamic>> _getRoleAfterSync(
    String uid,
    String email,
  ) async {
    PerfMonitor.start('_getRoleAfterSync');
    debugPrint('🚀 _getRoleAfterSync: START for uid=$uid, email=$email');

    // ═════ STEP 0: Khôi phục cache từ SharedPreferences (lần đăng nhập trước) ═════
    final hasLocalCache = await UserService.restoreAuthCache(uid);
    if (hasLocalCache) {
      debugPrint(
        '♻️ _getRoleAfterSync: Restored shopId from prefs = ${UserService.getShopIdSync()}',
      );
    }

    if (!kIsWeb && hasLocalCache) {
      final cachedRole = await UserService.getCachedRole();
      final cachedShopId = UserService.getShopIdSync();
      if (cachedRole != null &&
          cachedRole.isNotEmpty &&
          cachedShopId != null &&
          cachedShopId.isNotEmpty) {
        debugPrint(
          '⚡ _getRoleAfterSync: Using cached mobile session role=$cachedRole, shopId=$cachedShopId',
        );
        _startBackgroundUserWarmup(uid, email);
        PerfMonitor.stop('_getRoleAfterSync');
        return {'role': cachedRole, 'isSuperAdmin': false};
      }
    }

    // Kiểm tra super admin TRƯỚC - không cần sync data
    final bool isSuperAdmin = email.toLowerCase() == 'admin@huluca.com';
    if (isSuperAdmin) {
      // Vẫn sync nhưng không chặn
      try {
        await UserService.syncUserInfo(
          uid,
          email,
        ).timeout(const Duration(seconds: 10));
        await CurrentShopService().init();
      } catch (e) {
        debugPrint('⚠️ Super admin sync error (non-fatal): $e');
      }
      debugPrint('🔑 Super admin đăng nhập - chờ chọn shop');
      PerfMonitor.stop('_getRoleAfterSync');
      return {'role': 'admin', 'isSuperAdmin': true};
    }

    // ═══════════ STEP 1: syncUserInfo (với timeout cho web) ═══════════
    try {
      if (kIsWeb) {
        await UserService.syncUserInfo(uid, email).timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            debugPrint('⚠️ [WEB] syncUserInfo timeout 15s, tiếp tục...');
          },
        );
      } else {
        await UserService.syncUserInfo(uid, email).timeout(
          const Duration(seconds: 20),
          onTimeout: () {
            debugPrint('⚠️ [MOBILE] syncUserInfo timeout 20s, tiếp tục...');
          },
        );
      }
      debugPrint('✅ _getRoleAfterSync: syncUserInfo completed');

      try {
        await CurrentShopService().init();
      } catch (e) {
        debugPrint('⚠️ CurrentShopService.init error (non-fatal): $e');
      }
    } catch (e) {
      debugPrint('❌ syncUserInfo error: $e');
    }

    // ═══════════ STEP 2: Lấy shopId (nhiều fallback) ═══════════
    String? currentShopId = UserService.getShopIdSync();
    debugPrint('📌 shopId from cache: $currentShopId');

    // Fallback 1: ensureShopId nếu cache trống
    if (currentShopId == null || currentShopId.isEmpty) {
      try {
        currentShopId = await UserService.ensureShopId(
          maxRetries: 2,
        ).timeout(const Duration(seconds: 8));
        debugPrint('✅ shopId from ensureShopId: $currentShopId');
      } catch (e) {
        debugPrint('⚠️ ensureShopId failed: $e');
      }
    }

    // Fallback 2: Claims
    if (currentShopId == null || currentShopId.isEmpty) {
      try {
        currentShopId = await ClaimsService().getShopIdFromClaims().timeout(
          const Duration(seconds: 5),
        );
        debugPrint('📌 shopId from claims: $currentShopId');
      } catch (e) {
        debugPrint('⚠️ getShopIdFromClaims failed: $e');
      }
    }

    // Fallback 3: TRÊN WEB - thử dùng uid làm shopId (owner mặc định)
    // Chỉ dùng uid khi KHÔNG có cache từ lần đăng nhập trước
    if (kIsWeb &&
        (currentShopId == null || currentShopId.isEmpty) &&
        !hasLocalCache) {
      debugPrint('⚠️ [WEB] Tất cả cách lấy shopId thất bại, thử uid=$uid');
      currentShopId = uid;
      UserService.updateCachedShopId(currentShopId);
    }

    // Mobile: throw nếu vẫn không có shopId
    if (currentShopId == null || currentShopId.isEmpty) {
      debugPrint('⛔ _getRoleAfterSync: CRITICAL - No shopId available!');
      throw Exception(
        'Không thể xác định cửa hàng cho tài khoản này. Vui lòng đăng xuất và đăng nhập lại.',
      );
    }

    debugPrint('✅ _getRoleAfterSync: Using shopId=$currentShopId');

    // ═══════════ STEP 3: Clear local data nếu shop thay đổi ═══════════
    try {
      await _checkAndClearLocalDataIfShopChanged(currentShopId);
    } catch (e) {
      debugPrint(
        '⚠️ _checkAndClearLocalDataIfShopChanged error (non-fatal): $e',
      );
    }

    // ═══════════ STEP 4: Download dữ liệu ═══════════
    if (currentShopId.isNotEmpty) {
      if (kIsWeb) {
        try {
          debugPrint('🔄 [WEB] Đồng bộ dữ liệu trước khi hiển thị...');
          await SyncService.downloadAllFromCloud(force: true).timeout(
            const Duration(seconds: 20),
            onTimeout: () {
              debugPrint(
                '⚠️ [WEB] Sync timeout sau 20s, tiếp tục với data hiện có...',
              );
            },
          );
          debugPrint('✅ [WEB] Sync hoàn thành');
        } catch (e) {
          debugPrint('❌ [WEB] Lỗi đồng bộ (non-fatal): $e');
        }
        // Init services in background - không chặn login
        Future.microtask(() async {
          try {
            await _initSyncOrchestrator();
            await CashClosingNotifier.instance.init();
            await PaymentIntentService.initialize();
          } catch (e) {
            debugPrint('⚠️ [WEB] Init services error: $e');
          }
        });
      } else {
        // MOBILE: Chạy background - SQLite có data persistent
        Future.microtask(() async {
          try {
            debugPrint('🔄 Bắt đầu sync ở background...');
            await SyncService.downloadAllFromCloud(force: true).timeout(
              const Duration(seconds: 20),
              onTimeout: () {
                debugPrint(
                  '⚠️ Sync timeout sau 20s, tiếp tục với data local...',
                );
              },
            );
            debugPrint('✅ Sync hoàn thành');
            await _initSyncOrchestrator();
            await CashClosingNotifier.instance.init();
            await PaymentIntentService.initialize();
          } catch (e) {
            debugPrint('❌ Lỗi đồng bộ background: $e');
          }
        });
      }
    }

    // Health check ngầm
    Future.microtask(() async {
      try {
        await SyncHealthCheck.runFullCheck();
      } catch (e) {
        debugPrint('❌ Lỗi health check: $e');
      }
    });

    // ═══════════ STEP 5: Lấy role ═══════════
    String role = 'user';
    try {
      role = await UserService.getUserRole(
        uid,
      ).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('⚠️ getUserRole failed: $e');
      // Fallback: dùng role đã lưu từ lần đăng nhập trước
      final cachedRole = await UserService.getCachedRole();
      if (cachedRole != null && cachedRole.isNotEmpty) {
        role = cachedRole;
        debugPrint('♻️ Using cached role from prefs: $role');
      }
    }

    // Lưu role vào prefs cho lần sau
    UserService.saveAuthCache(role: role);

    PerfMonitor.stop('_getRoleAfterSync');
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
                showIntro: !isSuperAdmin, // Hiển thị intro cho user thường
              );
            }
            if (roleSnap.hasError || !roleSnap.hasData) {
              final errorMsg =
                  roleSnap.error?.toString() ?? 'Không thể tải dữ liệu';
              debugPrint('❌ AuthGate error: $errorMsg');
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.cloud_off,
                          size: 64,
                          color: Colors.orange,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Lỗi kết nối',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          kIsWeb
                              ? 'Không thể đồng bộ dữ liệu cửa hàng. Kiểm tra kết nối mạng và thử lại.'
                              : 'Vui lòng kiểm tra kết nối mạng.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: () {
                            _resetCache();
                            setState(() {});
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Thử lại'),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () {
                            UserService.clearCache();
                            CurrentShopService().clear();
                            _resetCache();
                            FirebaseAuth.instance.signOut();
                          },
                          child: const Text('Đăng xuất'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final data = roleSnap.data!;
            final role = data['role'] as String;
            final isSuperAdmin = data['isSuperAdmin'] as bool;

            // Super admin: Chuyển đến màn hình chọn shop
            if (isSuperAdmin) {
              return ShopSelectorView(
                key: const ValueKey('shop_selector'),
                setLocale: widget.setLocale,
              );
            }

            // Seed test data cho tài khoản debug (1 lần duy nhất)
            if (!kIsWeb && email == 'tuan@mobile.com') {
              SharedPreferences.getInstance().then((prefs) {
                if (prefs.getBool('seed_done') != true) {
                  SeedTestData.run().then((_) {
                    prefs.setBool('seed_done', true);
                    debugPrint('🌱 Seed flag saved');
                  });
                }
                // Force refresh claims to fix permission-denied
                if (prefs.getBool('claims_refreshed') != true) {
                  ClaimsService()
                      .refreshMyClaims()
                      .then((_) {
                        prefs.setBool('claims_refreshed', true);
                        debugPrint('🔑 Claims refreshed for test account');
                      })
                      .catchError(
                        (e) => debugPrint('⚠️ Claims refresh failed: $e'),
                      );
                }
              });
            }

            // User thường: Vào HomeView
            // Use ValueKey to prevent State recreation on StreamBuilder rebuilds (iOS auth re-emit)
            return HomeView(
              key: const ValueKey('home_view'),
              role: role,
              setLocale: widget.setLocale,
            );
          },
        );
      },
    );
  }

  Widget _buildLoadingScreen(String message, {bool showIntro = false}) {
    // Sử dụng LoadingIntroScreen với animation khi sync data
    if (showIntro) {
      return LoadingIntroScreen(
        message: message,
        subMessage: 'Vui lòng đợi trong giây lát...',
      );
    }

    // Fallback simple loading cho các trường hợp nhanh
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
