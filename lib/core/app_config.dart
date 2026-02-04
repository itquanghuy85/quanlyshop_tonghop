// App Configuration for Production
// Centralized configuration for debug/release builds

import 'package:flutter/foundation.dart';

/// App-wide configuration
class AppConfig {
  // Build mode detection
  static const bool isRelease = kReleaseMode;
  static const bool isDebug = kDebugMode;
  static const bool isProfile = kProfileMode;

  // Feature flags
  static const bool enablePerformanceOverlay = false;
  static const bool enableDebugBanner = !kReleaseMode;
  
  // Sync configuration
  static const Duration syncDebounce = Duration(milliseconds: 500);
  static const Duration syncTimeout = Duration(seconds: 30);
  static const int maxSyncRetries = 3;
  
  // Cache configuration
  static const Duration imageCacheDuration = Duration(days: 7);
  static const int maxMemoryCacheSize = 100; // MB
  
  // Database configuration
  static const int dbVersion = 67;
  static const String dbName = 'repair_shop_v22.db';
  
  // API timeouts
  static const Duration apiTimeout = Duration(seconds: 15);
  static const Duration uploadTimeout = Duration(seconds: 60);
  
  // Image compression (for upload)
  static const int imageQuality = 70;
  static const int maxImageWidth = 1920;
  static const int maxImageHeight = 1920;
  
  // Pagination
  static const int defaultPageSize = 20;
  static const int maxPageSize = 100;
  
  // Notification rate limiting
  static const int maxNotificationsPerMinute = 10;
  
  // Print settings
  static const int printTimeoutSeconds = 30;
  
  // Analytics (only in release)
  static bool get analyticsEnabled => isRelease;
  
  // Crash reporting (always on)
  static const bool crashReportingEnabled = true;
  
  // Performance monitoring
  static bool get performanceMonitoringEnabled => !isRelease;
}

/// Environment-specific configuration
class EnvConfig {
  static const String appName = 'HULUCA Shop Manager';
  static const String packageName = 'com.huluca.shopmanager';
  static const String supportEmail = 'support@huluca.com';
  static const String privacyPolicyUrl = 'https://huluca.com/privacy';
  static const String termsUrl = 'https://huluca.com/terms';
}
