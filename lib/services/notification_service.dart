import 'dart:async';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/utils/money_utils.dart';
import 'user_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  static final _db = FirebaseFirestore.instance;
  static final FirebaseMessaging _firebaseMessaging =
      FirebaseMessaging.instance;
  static final DateTime _appStartTime = DateTime.now().subtract(
    const Duration(minutes: 1),
  );

  // Rate limiting: max 3 notifications per 10 seconds
  static final List<DateTime> _recentNotifications = [];
  static const int _maxNotificationsPerPeriod = 3;
  static const Duration _rateLimitPeriod = Duration(seconds: 10);

  // Singleton listener subscription - prevent duplicate listeners
  static StreamSubscription? _notificationSubscription;
  // Track processed notification IDs to avoid showing same one twice
  static final Set<String> _processedNotificationIds = {};

  // FCM Token management
  static DateTime? _lastTokenCheck;
  static const Duration _tokenCheckInterval = Duration(
    hours: 6,
  ); // Kiểm tra token mỗi 6 giờ
  static String? _cachedToken;

  // Notification settings keys
  static const String _newOrderKey = 'notification_new_order';
  static const String _paymentKey = 'notification_payment';
  static const String _inventoryKey = 'notification_inventory';
  static const String _staffKey = 'notification_staff';
  static const String _systemKey = 'notification_system';

  // Handle background messages
  static Future<void> handleBackgroundMessage(RemoteMessage message) async {
    debugPrint('Handling background message: ${message.messageId}');
    await _showLocalNotification(
      message.notification?.title ?? 'Thông báo mới',
      message.notification?.body ?? '',
      channelId: _getChannelId(message.data['type']),
      payload: message.data.toString(),
    );
  }

  static Future<void> init() async {
    // Request permissions
    await _requestPermissions();

    // Initialize local notifications
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const InitializationSettings initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create notification channels
    await _createNotificationChannels();

    // Initialize FCM
    await _initFirebaseMessaging();
  }

  static Future<void> _requestPermissions() async {
    // On iOS, Firebase Messaging requestPermission is the AUTHORITATIVE source.
    // permission_handler on iOS often returns 'permanentlyDenied' incorrectly.
    // So: call FCM first (reliable on iOS), then permission_handler (reliable on Android).

    // Step 1: Firebase Messaging (primary for iOS, also works on Android)
    try {
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
        announcement: false,
        carPlay: false,
        criticalAlert: false,
      );

      debugPrint('FCM permission status: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('FCM permission denied - notifications may not work');
      } else if (settings.authorizationStatus ==
          AuthorizationStatus.provisional) {
        debugPrint('FCM provisional permission - limited notifications');
      }
    } catch (e) {
      debugPrint('FCM requestPermission error: $e');
    }

    // Step 2: permission_handler (important for Android 13+ POST_NOTIFICATIONS)
    try {
      final currentStatus = await Permission.notification.status;
      if (currentStatus.isDenied) {
        final status = await Permission.notification.request();
        if (status.isPermanentlyDenied) {
          debugPrint(
            'permission_handler: permanently denied (may be inaccurate on iOS)',
          );
        }
      }
    } catch (e) {
      // permission_handler can crash on some iOS versions
      debugPrint('permission_handler request error: $e');
    }
  }

  // Check notification permission status (for UI feedback)
  static Future<PermissionStatus> getNotificationPermissionStatus() async {
    return await Permission.notification.status;
  }

  /// Kiểm tra trạng thái thông báo đầy đủ: quyền + FCM token
  /// Trả về Map với các key: permissionGranted, hasFcmToken, isFullyWorking
  /// Dùng cả permission_handler + Firebase Messaging để tránh false-negative trên iOS
  static Future<Map<String, bool>> checkNotificationStatus() async {
    bool permissionGranted = false;
    bool hasFcmToken = false;

    try {
      // Check 1: permission_handler (chính xác trên Android, có thể sai trên iOS)
      final permissionStatus = await Permission.notification.status;
      permissionGranted = permissionStatus.isGranted;

      // Check 2: Firebase Messaging authorizationStatus (tin cậy hơn trên iOS)
      // iOS sometimes reports "denied" via permission_handler but "authorized" via FCM
      if (!permissionGranted) {
        try {
          final fcmSettings = await _firebaseMessaging.getNotificationSettings();
          if (fcmSettings.authorizationStatus == AuthorizationStatus.authorized ||
              fcmSettings.authorizationStatus == AuthorizationStatus.provisional) {
            permissionGranted = true;
            debugPrint('Notification permission: permission_handler=denied but FCM=authorized (iOS quirk)');
          }
        } catch (e) {
          debugPrint('FCM getNotificationSettings fallback error: $e');
        }
      }

      // Kiểm tra FCM token
      final token = await _firebaseMessaging.getToken();
      hasFcmToken = token != null && token.isNotEmpty;

      debugPrint(
        'Notification status check: permission=$permissionGranted, fcmToken=$hasFcmToken',
      );
    } catch (e) {
      debugPrint('Error checking notification status: $e');
    }

    return {
      'permissionGranted': permissionGranted,
      'hasFcmToken': hasFcmToken,
      'isFullyWorking': permissionGranted && hasFcmToken,
    };
  }

  // Guide user to enable notifications in settings
  static Future<bool> openNotificationSettings() async {
    return await openAppSettings();
  }

  /// Hiển thị banner trạng thái thông báo - gọi ở màn hình chính
  /// Trả về true nếu thông báo đang hoạt động bình thường
  static Future<bool> showNotificationStatusIfNeeded() async {
    try {
      final status = await checkNotificationStatus();
      final isWorking = status['isFullyWorking'] ?? false;

      if (!isWorking) {
        final permissionGranted = status['permissionGranted'] ?? false;
        final hasFcmToken = status['hasFcmToken'] ?? false;

        String message;
        if (!permissionGranted) {
          message = '⚠️ Thông báo bị tắt. Bấm để bật thông báo.';
        } else if (!hasFcmToken) {
          message = '⚠️ Không thể nhận thông báo đẩy. Bấm để làm mới.';
        } else {
          message = '⚠️ Thông báo có thể không hoạt động.';
        }

        final messenger = messengerKey.currentState;
        if (messenger != null) {
          messenger.showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(
                    Icons.notifications_off,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.orange.shade700,
              duration: const Duration(seconds: 8),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              action: SnackBarAction(
                label: permissionGranted ? 'LÀM MỚI' : 'BẬT',
                textColor: Colors.white,
                onPressed: () async {
                  if (!permissionGranted) {
                    await openNotificationSettings();
                  } else {
                    final success = await forceRefreshFCMToken();
                    showSnackBar(
                      success
                          ? '✅ Đã làm mới thông báo'
                          : '❌ Không thể làm mới, thử lại sau',
                      color: success ? Colors.green : Colors.red,
                    );
                  }
                },
              ),
            ),
          );
        }
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('Error checking notification status: $e');
      return false;
    }
  }

  static Future<void> _createNotificationChannels() async {
    const AndroidNotificationChannel newOrderChannel =
        AndroidNotificationChannel(
          'new_order_channel',
          'Đơn hàng mới',
          description: 'Thông báo khi có đơn hàng mới',
          importance: Importance.high,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('notification_sound'),
        );

    const AndroidNotificationChannel paymentChannel =
        AndroidNotificationChannel(
          'payment_channel',
          'Thanh toán',
          description: 'Thông báo về thanh toán',
          importance: Importance.high,
          playSound: true,
        );

    const AndroidNotificationChannel inventoryChannel =
        AndroidNotificationChannel(
          'inventory_channel',
          'Kho hàng',
          description: 'Thông báo về tình trạng kho',
          importance: Importance.defaultImportance,
          playSound: false,
        );

    const AndroidNotificationChannel staffChannel = AndroidNotificationChannel(
      'staff_channel',
      'Nhân viên',
      description: 'Thông báo về nhân viên',
      importance: Importance.defaultImportance,
      playSound: false,
    );

    const AndroidNotificationChannel systemChannel = AndroidNotificationChannel(
      'system_channel',
      'Hệ thống',
      description: 'Thông báo hệ thống',
      importance: Importance.defaultImportance,
      playSound: true,
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(newOrderChannel);
    await androidPlugin?.createNotificationChannel(paymentChannel);
    await androidPlugin?.createNotificationChannel(inventoryChannel);
    await androidPlugin?.createNotificationChannel(staffChannel);
    await androidPlugin?.createNotificationChannel(systemChannel);
  }

  static Future<void> _initFirebaseMessaging() async {
    // iOS: Hiển thị notification banner khi app đang mở (foreground)
    await _firebaseMessaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle when app is opened from notification
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    // Subscribe to staff topic for business notifications
    await _firebaseMessaging.subscribeToTopic('staff');

    // On iOS, wait for APNs token before requesting FCM token
    if (Platform.isIOS) {
      String? apnsToken;
      for (int i = 0; i < 10; i++) {
        apnsToken = await _firebaseMessaging.getAPNSToken();
        if (apnsToken != null) {
          debugPrint('APNs token ready after ${i + 1} attempts');
          break;
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
      if (apnsToken == null) {
        debugPrint('APNs token not available - FCM may not work on iOS');
      }
    }

    // Get FCM token
    String? token;
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        token = await _firebaseMessaging.getToken();
        if (token != null && token.isNotEmpty) break;
      } catch (e) {
        debugPrint('FCM getToken attempt $attempt failed: $e');
      }
      if (attempt < 3) await Future.delayed(Duration(seconds: attempt));
    }
    debugPrint('FCM Token: $token');

    // Save token to user profile
    if (token != null) {
      await _saveFCMToken(token);
      _cachedToken = token;
      _lastTokenCheck = DateTime.now();
    }

    // Listen for token refresh
    FirebaseMessaging.instance.onTokenRefresh.listen(_saveFCMToken);
  }

  static Future<void> refreshFCMToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      String? token = await _firebaseMessaging.getToken();
      if (token != null) {
        await _saveFCMToken(token);
        _cachedToken = token;
        debugPrint('FCM token refreshed: $token');
      }
    } catch (e) {
      debugPrint('Error refreshing FCM token: $e');
    }
  }

  /// Gọi khi app resume từ background hoặc khi cần đảm bảo FCM hoạt động
  /// Kiểm tra và refresh token nếu cần thiết
  static Future<void> ensureFCMTokenValid() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('ensureFCMTokenValid: No user logged in');
        return;
      }

      // Kiểm tra xem có cần refresh token không (mỗi 6 giờ)
      final now = DateTime.now();
      if (_lastTokenCheck != null &&
          now.difference(_lastTokenCheck!) < _tokenCheckInterval) {
        debugPrint('ensureFCMTokenValid: Token was checked recently, skipping');
        return;
      }

      debugPrint('ensureFCMTokenValid: Checking FCM token validity...');

      // Lấy token hiện tại
      String? currentToken = await _firebaseMessaging.getToken();
      if (currentToken == null || currentToken.isEmpty) {
        debugPrint('ensureFCMTokenValid: No FCM token available!');
        // Xóa token cũ để force refresh lần sau
        await _firebaseMessaging.deleteToken();
        // Thử lấy token mới
        currentToken = await _firebaseMessaging.getToken();
      }

      if (currentToken == null || currentToken.isEmpty) {
        debugPrint('ensureFCMTokenValid: Still no FCM token after refresh!');
        return;
      }

      // Kiểm tra xem token trên server có khớp không
      final userDoc = await _db.collection('users').doc(user.uid).get();
      final serverToken = userDoc.data()?['fcmToken'] as String?;

      if (serverToken != currentToken) {
        debugPrint(
          'ensureFCMTokenValid: Token mismatch! Server: ${serverToken?.substring(0, 20) ?? "null"}... Current: ${currentToken.substring(0, 20)}...',
        );
        await _saveFCMToken(currentToken);
      } else {
        debugPrint('ensureFCMTokenValid: Token is valid and up-to-date');
      }

      _lastTokenCheck = now;
      _cachedToken = currentToken;
    } catch (e) {
      debugPrint('ensureFCMTokenValid error: $e');
    }
  }

  /// Force refresh FCM token (dùng khi user nhấn nút làm mới thông báo)
  static Future<bool> forceRefreshFCMToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      // On iOS, ensure APNs token is available first
      if (Platform.isIOS) {
        debugPrint('forceRefreshFCMToken: iOS - checking APNs token...');
        String? apnsToken;
        for (int i = 0; i < 10; i++) {
          apnsToken = await _firebaseMessaging.getAPNSToken();
          if (apnsToken != null) {
            debugPrint('forceRefreshFCMToken: APNs token available');
            break;
          }
          debugPrint('forceRefreshFCMToken: APNs token not ready, retry ${i + 1}/10');
          await Future.delayed(const Duration(milliseconds: 800));
        }
        if (apnsToken == null) {
          debugPrint('forceRefreshFCMToken: APNs token unavailable - trying getToken anyway');
        }
      }

      // Try to delete old token (non-fatal on failure)
      debugPrint('forceRefreshFCMToken: Deleting old token...');
      try {
        await _firebaseMessaging.deleteToken();
      } catch (deleteError) {
        debugPrint('forceRefreshFCMToken: deleteToken failed (non-fatal): $deleteError');
      }

      // Wait for FCM reset
      await Future.delayed(Duration(milliseconds: Platform.isIOS ? 2000 : 500));

      debugPrint('forceRefreshFCMToken: Getting new token...');
      String? newToken;

      // Retry up to 5 times with increasing delays
      for (int attempt = 1; attempt <= 5; attempt++) {
        try {
          newToken = await _firebaseMessaging.getToken();
          if (newToken != null && newToken.isNotEmpty) break;
        } catch (getError) {
          debugPrint('forceRefreshFCMToken: getToken attempt $attempt failed: $getError');
        }
        if (attempt < 5) {
          await Future.delayed(Duration(seconds: attempt));
        }
      }

      if (newToken == null || newToken.isEmpty) {
        debugPrint('forceRefreshFCMToken: Failed to get new token after all retries!');
        return false;
      }

      debugPrint(
        'forceRefreshFCMToken: Saving new token: ${newToken.substring(0, 30)}...',
      );
      await _saveFCMToken(newToken);

      _cachedToken = newToken;
      _lastTokenCheck = DateTime.now();

      debugPrint('forceRefreshFCMToken: Success!');
      return true;
    } catch (e) {
      debugPrint('forceRefreshFCMToken error: $e');
      return false;
    }
  }

  /// Kiểm tra FCM token có tồn tại trên server không
  static Future<bool> hasFCMTokenOnServer() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      final userDoc = await _db.collection('users').doc(user.uid).get();
      final serverToken = userDoc.data()?['fcmToken'] as String?;

      return serverToken != null && serverToken.isNotEmpty;
    } catch (e) {
      debugPrint('hasFCMTokenOnServer error: $e');
      return false;
    }
  }

  static Future<void> _saveFCMToken(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('Cannot save FCM token: no authenticated user');
        return;
      }

      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) {
        debugPrint('Cannot save FCM token: no shop ID available');
        return;
      }

      // Check for duplicate tokens with better error handling
      try {
        final existingTokens = await _db
            .collection('users')
            .where('fcmToken', isEqualTo: token)
            .where('shopId', isEqualTo: shopId)
            .get();

        // Remove duplicate tokens from other users
        final batch = _db.batch();
        bool hasDuplicates = false;

        for (final doc in existingTokens.docs) {
          if (doc.id != user.uid) {
            batch.update(doc.reference, {
              'fcmToken': FieldValue.delete(),
              'fcmTokenUpdatedAt': FieldValue.delete(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
            hasDuplicates = true;
            debugPrint('Removing duplicate FCM token from user: ${doc.id}');
          }
        }

        if (hasDuplicates) {
          await batch.commit();
          debugPrint('Cleaned up duplicate FCM tokens');
        }
      } catch (e) {
        debugPrint('Error checking for duplicate tokens: $e');
        // Continue with token save even if duplicate check fails
      }

      // Save the new token
      await _db.collection('users').doc(user.uid).set({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        'devicePlatform': _getDevicePlatform(),
        'lastTokenUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('FCM token saved successfully for user: ${user.uid}');
    } catch (e) {
      debugPrint('Error saving FCM token: $e');
      // Don't throw - token save failure shouldn't crash the app
    }
  }

  static String _getDevicePlatform() {
    // Simple platform detection
    // In a real app, you might use device_info_plus for more accurate detection
    return 'flutter_app'; // Generic identifier
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('Foreground message received: ${message.notification?.title}');

    // Show in-app snackbar notification
    final title = message.notification?.title ?? 'Thông báo mới';
    final body = message.notification?.body ?? '';
    showSnackBar('$title: $body', color: Colors.blueAccent);

    // Check if notifications are enabled for this type
    _shouldShowNotification(message.data['type']).then((shouldShow) {
      if (shouldShow) {
        _showLocalNotification(
          title,
          body,
          channelId: _getChannelId(message.data['type']),
          payload: message.data.toString(),
        );
      }
    });
  }

  static void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('Message opened app: ${message.notification?.title}');
    // Handle navigation based on message type
    _handleNotificationNavigation(message.data);
  }

  static void _onNotificationTapped(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');
    if (response.payload != null) {
      // Parse payload and navigate
      final data = _parsePayload(response.payload!);
      _handleNotificationNavigation(data);
    }
  }

  static Map<String, dynamic> _parsePayload(String payload) {
    try {
      // Simple parsing - in production, use proper JSON parsing
      final Map<String, dynamic> data = {};
      final pairs = payload.replaceAll('{', '').replaceAll('}', '').split(', ');
      for (final pair in pairs) {
        final keyValue = pair.split(': ');
        if (keyValue.length == 2) {
          data[keyValue[0]] = keyValue[1];
        }
      }
      return data;
    } catch (e) {
      return {};
    }
  }

  static void _handleNotificationNavigation(Map<String, dynamic> data) {
    final type = data['type'];
    final id = data['id'];

    // Navigate based on notification type
    switch (type) {
      case 'new_order':
        // Navigate to order details
        debugPrint('Navigate to order: $id');
        break;
      case 'payment':
        // Navigate to payment details
        debugPrint('Navigate to payment: $id');
        break;
      case 'inventory':
        // Navigate to inventory
        debugPrint('Navigate to inventory');
        break;
      default:
        debugPrint('Unknown notification type: $type');
    }
  }

  static String _getChannelId(String? type) {
    switch (type) {
      case 'new_order':
        return 'new_order_channel';
      case 'payment':
        return 'payment_channel';
      case 'inventory':
        return 'inventory_channel';
      case 'staff':
        return 'staff_channel';
      case 'system':
        return 'system_channel';
      default:
        return 'system_channel';
    }
  }

  // MẠCH LẮNG NGHE GIA CỐ (KHÓA CHẶT SHOP ID)
  // Singleton pattern: cancel previous listener before creating new one
  static void listenToNotifications(
    Function(String, String) onMessageReceived,
  ) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Cancel existing subscription to prevent duplicate listeners
    _notificationSubscription?.cancel();
    _notificationSubscription = null;

    // Lắng nghe thay đổi ShopId liên tục để đảm bảo không mất kết nối
    UserService.getCurrentShopId().then((shopId) {
      if (shopId == null) return;

      _notificationSubscription = _db
          .collection('shop_notifications')
          .where('shopId', isEqualTo: shopId)
          .where('createdAt', isGreaterThan: Timestamp.fromDate(_appStartTime))
          .snapshots()
          .listen((snapshot) {
            debugPrint(
              'Received ${snapshot.docChanges.length} notification changes',
            );
            for (var change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added) {
                final docId = change.doc.id;
                // Skip if already processed (avoid duplicate display)
                if (_processedNotificationIds.contains(docId)) {
                  debugPrint('Skipping already processed notification: $docId');
                  continue;
                }
                _processedNotificationIds.add(docId);
                // Limit memory: keep only last 100 processed IDs
                if (_processedNotificationIds.length > 100) {
                  _processedNotificationIds.remove(_processedNotificationIds.first);
                }

                final data = change.doc.data() as Map<String, dynamic>;
                debugPrint(
                  'New notification: ${data['title']} from ${data['senderId']} (current user: ${user.uid})',
                );
                // Hiển thị thông báo nếu không phải do chính mình gửi
                // Với hệ thống test: chỉ hiện 1 lần qua snackbar (không show local notification cho sender)
                final isSelf = data['senderId'] == user.uid;
                final isSystem = data['type'] == 'system';
                if (!isSelf || isSystem) {
                  String title = data['title'] ?? "THÔNG BÁO MỚI";
                  String body = data['body'] ?? "";
                  String type = data['type'] ?? 'system';

                  // Check if notification should be shown
                  _shouldShowNotification(type).then((shouldShow) {
                    debugPrint(
                      'Should show notification for type $type: $shouldShow',
                    );
                    if (shouldShow) {
                      // Self-sent system notification: only show snackbar, no local push
                      if (isSelf && isSystem) {
                        onMessageReceived(title, body);
                      } else {
                        _showLocalNotification(
                          title,
                          body,
                          channelId: _getChannelId(type),
                        );
                        onMessageReceived(title, body);
                      }
                    }
                  });
                } else {
                  debugPrint('Skipping notification from self');
                }
              }
            }
          }, onError: (e) => debugPrint("LỖI MẠCH THÔNG BÁO: $e"));
    });
  }

  static Future<void> sendCloudNotification({
    required String title,
    required String body,
    required String type,
    String? targetUserId,
  }) async {
    try {
      // Kiểm tra settings trước khi gửi
      final shouldSend = await _shouldSendNotification(type, targetUserId);
      if (!shouldSend) {
        debugPrint('Notification $type blocked by user settings');
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return;

      final notificationData = {
        'shopId': shopId,
        'title': title,
        'body': body,
        'type': type,
        'senderId': user?.uid,
        'senderName': user?.email?.split('@').first.toUpperCase() ?? "NV",
        'createdAt': FieldValue.serverTimestamp(),
        'targetUserId': targetUserId, // null = broadcast to all shop users
      };

      debugPrint('Creating shop notification: $notificationData');
      await _db.collection('shop_notifications').add(notificationData);
      debugPrint('Shop notification created successfully');

      // Send FCM push notification
      await _sendFCMNotification(notificationData);
    } catch (e) {
      debugPrint("LỖI GỬI: $e");
    }
  }

  static Future<void> _sendFCMNotification(
    Map<String, dynamic> notificationData,
  ) async {
    const int maxRetries = 3;
    int retryCount = 0;

    while (retryCount < maxRetries) {
      try {
        debugPrint(
          'Sending FCM notification (attempt ${retryCount + 1}): ${notificationData['title']}',
        );

        final callable = FirebaseFunctions.instanceFor(
          region: 'asia-southeast1',
        ).httpsCallable('sendShopNotification');

        final shopId = await UserService.getCurrentShopId();

        final result = await callable
            .call({
              'title': notificationData['title'],
              'body': notificationData['body'],
              'type': notificationData['type'],
              'targetUserId': notificationData['targetUserId'],
              'shopId': shopId,
            })
            .timeout(const Duration(seconds: 30)); // Add timeout

        final data = result.data as Map<String, dynamic>;
        debugPrint(
          'FCM sent successfully: ${data['sentCount']} success, ${data['failedCount']} failed',
        );

        // If some messages failed, log but don't retry (Cloud Function handles individual failures)
        if (data['failedCount'] > 0) {
          debugPrint(
            'Warning: ${data['failedCount']} FCM messages failed to send',
          );
        }

        return; // Success, exit retry loop
      } on FirebaseFunctionsException catch (e) {
        debugPrint(
          'Firebase Functions error (attempt ${retryCount + 1}): ${e.code} - ${e.message}',
        );

        // Don't retry for certain errors
        if (e.code == 'functions/cancelled' ||
            e.code == 'functions/invalid-argument') {
          debugPrint('Non-retryable error, giving up');
          break;
        }

        retryCount++;
        if (retryCount < maxRetries) {
          // Exponential backoff
          final delay = Duration(seconds: 1 << retryCount); // 2, 4, 8 seconds
          debugPrint('Retrying FCM send in ${delay.inSeconds} seconds...');
          await Future.delayed(delay);
        }
      } catch (e) {
        debugPrint('General FCM error (attempt ${retryCount + 1}): $e');

        retryCount++;
        if (retryCount < maxRetries) {
          final delay = Duration(seconds: 1 << retryCount);
          debugPrint('Retrying FCM send in ${delay.inSeconds} seconds...');
          await Future.delayed(delay);
        }
      }
    }

    // All retries failed, fallback to local notification
    debugPrint(
      'FCM failed after $maxRetries attempts, falling back to local notification',
    );
    _showLocalNotification(
      notificationData['title'],
      notificationData['body'],
      channelId: _getChannelId(notificationData['type']),
    );

    // Show user-friendly error message
    showSnackBar(
      'Không thể gửi thông báo push, đã hiển thị thông báo local',
      color: Colors.orange,
    );
  }

  static Future<void> _showLocalNotification(
    String title,
    String body, {
    String channelId = 'system_channel',
    String? payload,
    bool showInAppFallback = true,
  }) async {
    // Kiểm tra permission trước (dùng cả permission_handler + FCM cho iOS)
    bool hasPermission = false;
    try {
      final permissionStatus = await Permission.notification.status;
      hasPermission = permissionStatus.isGranted;
      // iOS fallback: permission_handler có thể sai → check FCM
      if (!hasPermission) {
        final fcmSettings = await _firebaseMessaging.getNotificationSettings();
        hasPermission = fcmSettings.authorizationStatus == AuthorizationStatus.authorized ||
            fcmSettings.authorizationStatus == AuthorizationStatus.provisional;
      }
    } catch (e) {
      debugPrint('Permission check error: $e');
      // Nếu lỗi, vẫn thử hiển thị notification
      hasPermission = true;
    }

    if (hasPermission) {
      try {
        final int id = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        final AndroidNotificationDetails androidDetails =
            AndroidNotificationDetails(
              channelId,
              _getChannelName(channelId),
              channelDescription: _getChannelDescription(channelId),
              importance: _getChannelImportance(channelId),
              priority: Priority.high,
              showWhen: true,
              icon: '@mipmap/launcher_icon',
              playSound: _shouldPlaySound(channelId),
            );

        const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        );

        final NotificationDetails details = NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        );

        await _localNotifications.show(
          id,
          title,
          body,
          details,
          payload: payload,
        );
        return; // Success, no need fallback
      } catch (e) {
        debugPrint('Error showing local notification: $e');
        // Fall through to in-app fallback
      }
    }

    // Fallback: Hiển thị thông báo trên màn hình khi push notification không hoạt động
    if (showInAppFallback) {
      _showInAppNotification(title, body);
    }
  }

  /// Hiển thị thông báo trực tiếp trong app (fallback khi push notification bị tắt)
  static void _showInAppNotification(String title, String body) {
    try {
      final messenger = messengerKey.currentState;
      if (messenger != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.notifications_active,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
            backgroundColor: Colors.indigo.shade700,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            action: SnackBarAction(
              label: 'BẬT TB',
              textColor: Colors.yellow,
              onPressed: () => openNotificationSettings(),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error showing in-app notification: $e');
    }
  }

  static String _getChannelName(String channelId) {
    switch (channelId) {
      case 'new_order_channel':
        return 'Đơn hàng mới';
      case 'payment_channel':
        return 'Thanh toán';
      case 'inventory_channel':
        return 'Kho hàng';
      case 'staff_channel':
        return 'Nhân viên';
      case 'system_channel':
        return 'Hệ thống';
      default:
        return 'Thông báo';
    }
  }

  static String _getChannelDescription(String channelId) {
    switch (channelId) {
      case 'new_order_channel':
        return 'Thông báo khi có đơn hàng mới';
      case 'payment_channel':
        return 'Thông báo về thanh toán';
      case 'inventory_channel':
        return 'Thông báo về tình trạng kho';
      case 'staff_channel':
        return 'Thông báo về nhân viên';
      case 'system_channel':
        return 'Thông báo hệ thống';
      default:
        return 'Thông báo từ ứng dụng';
    }
  }

  static Importance _getChannelImportance(String channelId) {
    switch (channelId) {
      case 'new_order_channel':
      case 'payment_channel':
        return Importance.high;
      case 'inventory_channel':
      case 'staff_channel':
        return Importance.defaultImportance;
      case 'system_channel':
        return Importance.defaultImportance;
      default:
        return Importance.defaultImportance;
    }
  }

  static bool _shouldPlaySound(String channelId) {
    return channelId == 'new_order_channel' || channelId == 'payment_channel' || channelId == 'system_channel';
  }

  // Notification Settings Management
  static Future<bool> _shouldShowNotification(String? type) async {
    if (type == null) return true;

    // Check rate limiting
    if (!_isWithinRateLimit()) {
      debugPrint('Notification rate limited: $type');
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    final key = _getNotificationSettingKey(type);
    return prefs.getBool(key) ?? _getDefaultNotificationSetting(type);
  }

  static bool _isWithinRateLimit() {
    final now = DateTime.now();

    // Remove old notifications outside the rate limit period
    _recentNotifications.removeWhere(
      (time) => now.difference(time) > _rateLimitPeriod,
    );

    // Check if we're within the limit
    if (_recentNotifications.length >= _maxNotificationsPerPeriod) {
      return false;
    }

    // Add current notification to the list
    _recentNotifications.add(now);
    return true;
  }

  static Future<void> setNotificationEnabled(String type, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getNotificationSettingKey(type);
    await prefs.setBool(key, enabled);
  }

  static Future<bool> getNotificationEnabled(String type) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getNotificationSettingKey(type);
    return prefs.getBool(key) ?? _getDefaultNotificationSetting(type);
  }

  static String _getNotificationSettingKey(String type) {
    switch (type) {
      case 'new_order':
        return _newOrderKey;
      case 'payment':
        return _paymentKey;
      case 'inventory':
        return _inventoryKey;
      case 'staff':
        return _staffKey;
      case 'system':
        return _systemKey;
      default:
        return _systemKey;
    }
  }

  static bool _getDefaultNotificationSetting(String type) {
    // Critical notifications are enabled by default
    return type == 'new_order' || type == 'payment' || type == 'system';
  }

  // Business Logic Integration Methods

  // Inventory monitoring - called when stock levels change
  static Future<void> checkAndNotifyLowInventory(
    String productId,
    String productName,
    int currentStock,
    int minStock,
  ) async {
    if (currentStock <= minStock) {
      await sendLowInventoryNotification(productName, currentStock, minStock);
    }
  }

  // Attendance tracking - called when staff check in/out
  static Future<void> notifyStaffAttendance(
    String staffName,
    String action,
    DateTime timestamp,
  ) async {
    final timeString =
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    final status = action == 'check_in' ? 'đã check-in' : 'đã check-out';

    await sendAttendanceNotification(staffName, status, timeString);
  }

  // Payment processing - called when payment is completed
  static Future<void> notifyPaymentCompleted(
    String orderId,
    double amount,
    String paymentMethod,
  ) async {
    await sendPaymentNotification(orderId, amount, paymentMethod);
  }

  // New repair order notifications - Admin & Technician roles
  static Future<void> sendNewOrderNotification(
    String orderId,
    String customerName,
    int price,
  ) async {
    const title = 'ĐƠN SỬA MỚI';
    final body = 'Khách $customerName - ${MoneyUtils.formatVND(price)}đ';

    // Cloud Function sẽ lọc người nhận theo role, không cần check ở đây
    await sendCloudNotification(title: title, body: body, type: 'new_order');
  }

  // System maintenance notifications
  static Future<void> notifySystemMaintenance(String message) async {
    await sendSystemAlert(message);
  }

  // Critical alerts for all users
  static Future<void> notifyCriticalAlert(String title, String message) async {
    await sendCloudNotification(title: title, body: message, type: 'system');
  }

  // Business Logic Notifications with Role-based Permissions

  // Payment notifications - Admin & Sales roles
  static Future<void> sendPaymentNotification(
    String orderId,
    double amount,
    String paymentMethod,
  ) async {
    const title = 'THANH TOÁN THÀNH CÔNG';
    final body = '${amount.toStringAsFixed(0)}đ qua $paymentMethod';

    // Cloud Function sẽ lọc người nhận theo role, không cần check ở đây
    await sendCloudNotification(title: title, body: body, type: 'payment');
  }

  // Low inventory notifications - Admin & Technician roles
  static Future<void> sendLowInventoryNotification(
    String productName,
    int currentStock,
    int minStock,
  ) async {
    const title = 'CẢNH BÁO KHO HÀNG';
    final body =
        '$productName chỉ còn $currentStock sản phẩm (tối thiểu: $minStock)';

    // Cloud Function sẽ lọc người nhận theo role, không cần check ở đây
    await sendCloudNotification(title: title, body: body, type: 'inventory');
  }

  // Attendance notifications - Admin & Manager roles
  static Future<void> sendAttendanceNotification(
    String staffName,
    String status,
    String time,
  ) async {
    const title = 'ĐIỂM DANH NHÂN VIÊN';
    final body = '$staffName đã $status lúc $time';

    // Cloud Function sẽ lọc người nhận theo role, không cần check ở đây
    await sendCloudNotification(title: title, body: body, type: 'staff');
  }

  // Critical system alerts - All roles
  static Future<void> sendSystemAlert(
    String message, {
    String? targetUserId,
  }) async {
    const title = 'CẢNH BÁO HỆ THỐNG';

    // System alerts go to all users regardless of role
    await sendCloudNotification(
      title: title,
      body: message,
      type: 'system',
      targetUserId: targetUserId,
    );
  }

  static Future<void> sendStaffNotification(
    String message, {
    String? targetUserId,
  }) async {
    const title = 'THÔNG BÁO NHÂN VIÊN';
    await sendCloudNotification(
      title: title,
      body: message,
      type: 'staff',
      targetUserId: targetUserId,
    );
  }

  static Future<void> sendSystemNotification(String message) async {
    const title = 'THÔNG BÁO HỆ THỐNG';
    await sendCloudNotification(title: title, body: message, type: 'system');
  }

  static Future<bool> _shouldSendNotification(
    String type,
    String? targetUserId,
  ) async {
    // Nếu là broadcast, kiểm tra settings của từng user
    if (targetUserId == null) {
      // Cho broadcast, chỉ gửi nếu type được bật mặc định
      return _getDefaultNotificationSetting(type);
    }

    // Nếu target specific user, kiểm tra settings của họ
    // Note: Trong implementation thực tế, cần lưu settings trên server
    // Hiện tại dùng local settings của current user
    final prefs = await SharedPreferences.getInstance();
    final key = _getNotificationSettingKey(type);
    return prefs.getBool(key) ?? _getDefaultNotificationSetting(type);
  }

  // Cleanup dead tokens (gọi định kỳ)
  static Future<void> cleanupDeadTokens() async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return;

      // Lấy tất cả users có token trong shop
      final usersWithTokens = await _db
          .collection('users')
          .where('shopId', isEqualTo: shopId)
          .where('fcmToken', isNotEqualTo: null)
          .get();

      for (final doc in usersWithTokens.docs) {
        final userData = doc.data();
        final lastUpdate = userData['lastTokenUpdate'] as Timestamp?;

        // Xóa token nếu không update quá 30 ngày
        if (lastUpdate != null) {
          final daysSinceUpdate = DateTime.now()
              .difference(lastUpdate.toDate())
              .inDays;
          if (daysSinceUpdate > 30) {
            await doc.reference.update({
              'fcmToken': FieldValue.delete(),
              'lastTokenUpdate': FieldValue.serverTimestamp(),
            });
            debugPrint('Cleaned up dead token for user: ${doc.id}');
          }
        }
      }
    } catch (e) {
      debugPrint('Error cleaning up dead tokens: $e');
    }
  }

  static void showSnackBar(String message, {Color color = Colors.blueAccent}) {
    messengerKey.currentState?.hideCurrentSnackBar();
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
