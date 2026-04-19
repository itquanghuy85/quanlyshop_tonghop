import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'user_service.dart';

class FirestoreConnectivityReport {
  final DateTime checkedAt;
  final bool hasNetwork;
  final bool hasAuthenticatedUser;
  final bool hasShopContext;
  final bool canReachFirestoreServer;
  final bool canReadCurrentUserDocument;
  final bool canReadShopScopedData;
  final int latencyMs;
  final List<String> warnings;
  final List<String> errors;

  const FirestoreConnectivityReport({
    required this.checkedAt,
    required this.hasNetwork,
    required this.hasAuthenticatedUser,
    required this.hasShopContext,
    required this.canReachFirestoreServer,
    required this.canReadCurrentUserDocument,
    required this.canReadShopScopedData,
    required this.latencyMs,
    this.warnings = const [],
    this.errors = const [],
  });

  bool get isHealthy {
    final hasMandatorySignals =
        hasNetwork && hasAuthenticatedUser && canReachFirestoreServer;
    final hasDataAccess =
        canReadCurrentUserDocument &&
        (!hasShopContext || canReadShopScopedData);
    return hasMandatorySignals && hasDataAccess && errors.isEmpty;
  }

  String get summary {
    if (isHealthy) {
      return 'Ket noi Firestore on dinh';
    }

    if (!hasNetwork) {
      return 'Khong co ket noi internet';
    }

    if (!canReachFirestoreServer) {
      return 'Khong the ket noi Firestore server';
    }

    if (!canReadShopScopedData && hasShopContext) {
      return 'Khong doc duoc du lieu theo shop';
    }

    return 'Ket noi chua on dinh, can kiem tra them';
  }

  List<String> get recommendations {
    final tips = <String>[];

    if (!hasNetwork) {
      tips.add('Kiem tra Wi-Fi/4G va thu doi mang.');
    }
    if (!hasAuthenticatedUser) {
      tips.add('Dang xuat va dang nhap lai tai khoan.');
    }
    if (hasNetwork && !canReachFirestoreServer) {
      tips.add('Kiem tra VPN, firewall hoac DNS tren thiet bi.');
    }
    if (canReachFirestoreServer && !canReadCurrentUserDocument) {
      tips.add('Kiem tra Firestore rules cho users/{uid}.');
    }
    if (hasShopContext && !canReadShopScopedData) {
      tips.add('Kiem tra shopId hien tai va rules filter theo shopId.');
    }

    if (tips.isEmpty) {
      tips.add('He thong dang hoat dong on dinh.');
    }

    return tips;
  }
}

class FirestoreConnectivityService {
  static const Duration _stepTimeout = Duration(seconds: 8);

  static Future<FirestoreConnectivityReport> runDiagnostics() async {
    final warnings = <String>[];
    final errors = <String>[];
    final latencies = <int>[];

    final connectivity = await Connectivity().checkConnectivity();
    final hasNetwork = connectivity.any((r) => r != ConnectivityResult.none);

    if (!hasNetwork) {
      return FirestoreConnectivityReport(
        checkedAt: DateTime.now(),
        hasNetwork: false,
        hasAuthenticatedUser: false,
        hasShopContext: false,
        canReachFirestoreServer: false,
        canReadCurrentUserDocument: false,
        canReadShopScopedData: false,
        latencyMs: 0,
        warnings: const ['Khong co mang internet.'],
        errors: const ['No network'],
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    final hasAuthenticatedUser = user != null;

    if (!hasAuthenticatedUser) {
      errors.add('Chua dang nhap tai khoan Firebase Auth.');
    }

    final shopId = await UserService.getCurrentShopId();
    final hasShopContext = shopId != null && shopId.isNotEmpty;
    if (!hasShopContext) {
      warnings.add('Khong tim thay shopId hien tai.');
    }

    bool canReachFirestoreServer = false;
    bool canReadCurrentUserDocument = false;
    bool canReadShopScopedData = false;

    if (user != null) {
      final userStep = await _runStep(() async {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get(const GetOptions(source: Source.server));
      });

      canReachFirestoreServer = userStep.reachedServer;
      canReadCurrentUserDocument = userStep.success;
      if (userStep.latencyMs > 0) {
        latencies.add(userStep.latencyMs);
      }
      if (!userStep.success && userStep.message != null) {
        errors.add('Doc users/${user.uid} that bai: ${userStep.message}');
      }
    }

    if (hasShopContext) {
      final shopStep = await _runStep(() async {
        await FirebaseFirestore.instance
            .collection('products')
            .where('shopId', isEqualTo: shopId)
            .limit(1)
            .get(const GetOptions(source: Source.server));
      });

      canReachFirestoreServer =
          canReachFirestoreServer || shopStep.reachedServer;
      canReadShopScopedData = shopStep.success;
      if (shopStep.latencyMs > 0) {
        latencies.add(shopStep.latencyMs);
      }
      if (!shopStep.success && shopStep.message != null) {
        errors.add(
          'Doc du lieu products theo shop that bai: ${shopStep.message}',
        );
      }
    }

    if (!canReachFirestoreServer) {
      errors.add('Khong the ket noi toi Firestore server.');
    }

    final latencyMs = latencies.isEmpty
        ? 0
        : (latencies.reduce((a, b) => a + b) / latencies.length).round();

    return FirestoreConnectivityReport(
      checkedAt: DateTime.now(),
      hasNetwork: hasNetwork,
      hasAuthenticatedUser: hasAuthenticatedUser,
      hasShopContext: hasShopContext,
      canReachFirestoreServer: canReachFirestoreServer,
      canReadCurrentUserDocument: canReadCurrentUserDocument,
      canReadShopScopedData: canReadShopScopedData,
      latencyMs: latencyMs,
      warnings: warnings,
      errors: errors,
    );
  }

  static Future<_StepResult> _runStep(Future<void> Function() action) async {
    final watch = Stopwatch()..start();
    try {
      await action().timeout(_stepTimeout);
      watch.stop();
      return _StepResult(
        success: true,
        reachedServer: true,
        latencyMs: watch.elapsedMilliseconds,
      );
    } on TimeoutException {
      watch.stop();
      return _StepResult(
        success: false,
        reachedServer: false,
        latencyMs: watch.elapsedMilliseconds,
        message: 'Timeout sau ${_stepTimeout.inSeconds}s',
      );
    } on FirebaseException catch (e) {
      watch.stop();
      final reachedServer = _isServerReachableError(e.code);
      return _StepResult(
        success: false,
        reachedServer: reachedServer,
        latencyMs: watch.elapsedMilliseconds,
        message: '${e.code}: ${e.message ?? 'unknown'}',
      );
    } catch (e) {
      watch.stop();
      return _StepResult(
        success: false,
        reachedServer: false,
        latencyMs: watch.elapsedMilliseconds,
        message: e.toString(),
      );
    }
  }

  static bool _isServerReachableError(String code) {
    return code == 'permission-denied' ||
        code == 'unauthenticated' ||
        code == 'failed-precondition';
  }
}

class _StepResult {
  final bool success;
  final bool reachedServer;
  final int latencyMs;
  final String? message;

  const _StepResult({
    required this.success,
    required this.reachedServer,
    required this.latencyMs,
    this.message,
  });
}
