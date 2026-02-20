import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/shop_deletion_service.dart';
import '../services/event_bus.dart';

/// SafeStreamBuilder: Wrapper cho StreamBuilder để xử lý lỗi PERMISSION_DENIED gracefully
/// 
/// Features:
/// 1. Kiểm tra shopId trước khi subscribe
/// 2. Auto-cancel stream khi shop bị xóa
/// 3. Hiển thị thông báo thân thiện khi mất quyền truy cập
/// 4. Skip render nếu shop đang bị xóa
class SafeStreamBuilder<T> extends StatefulWidget {
  /// Stream từ Firestore (e.g., collection.snapshots())
  final Stream<T> stream;
  
  /// Builder function
  final Widget Function(BuildContext context, AsyncSnapshot<T> snapshot) builder;
  
  /// ShopId để kiểm tra quyền truy cập (optional nhưng recommended)
  final String? shopId;
  
  /// Widget hiển thị khi shop bị xóa hoặc mất quyền
  final Widget? noAccessWidget;
  
  /// Widget hiển thị khi loading
  final Widget? loadingWidget;
  
  /// Callback khi có lỗi permission
  final VoidCallback? onPermissionError;
  
  /// Initial data (như StreamBuilder.initialData)
  final T? initialData;

  const SafeStreamBuilder({
    super.key,
    required this.stream,
    required this.builder,
    this.shopId,
    this.noAccessWidget,
    this.loadingWidget,
    this.onPermissionError,
    this.initialData,
  });

  @override
  State<SafeStreamBuilder<T>> createState() => _SafeStreamBuilderState<T>();
}

class _SafeStreamBuilderState<T> extends State<SafeStreamBuilder<T>> {
  StreamSubscription<T>? _subscription;
  StreamSubscription<String>? _eventSubscription;
  AsyncSnapshot<T>? _lastSnapshot;
  bool _hasPermissionError = false;
  bool _shopDeleted = false;

  @override
  void initState() {
    super.initState();
    _initStream();
    _listenToShopDeletion();
  }

  @override
  void didUpdateWidget(covariant SafeStreamBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.stream != oldWidget.stream || widget.shopId != oldWidget.shopId) {
      _cancelSubscriptions();
      _hasPermissionError = false;
      _shopDeleted = false;
      _initStream();
    }
  }

  void _initStream() {
    // Skip nếu shop đang bị xóa
    if (widget.shopId != null && ShopDeletionService.isShopBeingDeleted(widget.shopId)) {
      _shopDeleted = true;
      return;
    }
    
    // Initialize với initial data nếu có
    if (widget.initialData != null) {
      _lastSnapshot = AsyncSnapshot.withData(ConnectionState.waiting, widget.initialData as T);
    } else {
      _lastSnapshot = const AsyncSnapshot.waiting();
    }
    
    _subscription = widget.stream.listen(
      (data) {
        if (mounted && !_shopDeleted) {
          setState(() {
            _lastSnapshot = AsyncSnapshot.withData(ConnectionState.active, data);
            _hasPermissionError = false;
          });
        }
      },
      onError: (error, stackTrace) {
        if (mounted) {
          final isPermissionDenied = _isPermissionDeniedError(error);
          
          setState(() {
            if (isPermissionDenied) {
              _hasPermissionError = true;
              debugPrint('🔒 SafeStreamBuilder: Permission denied for shop ${widget.shopId}');
              widget.onPermissionError?.call();
            } else {
              _lastSnapshot = AsyncSnapshot.withError(ConnectionState.active, error, stackTrace);
            }
          });
        }
      },
      onDone: () {
        if (mounted) {
          setState(() {
            _lastSnapshot = _lastSnapshot?.inState(ConnectionState.done);
          });
        }
      },
    );
  }

  void _listenToShopDeletion() {
    // Listen to shop deletion events
    _eventSubscription = EventBus().stream
      .where((event) => 
        event == 'shop_deleting:${widget.shopId}' ||
        event == 'shop_deleted:${widget.shopId}')
      .listen((_) {
        if (mounted) {
          _cancelSubscriptions();
          setState(() {
            _shopDeleted = true;
          });
        }
      }) as StreamSubscription<String>?;
  }

  void _cancelSubscriptions() {
    _subscription?.cancel();
    _subscription = null;
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    _eventSubscription?.cancel();
    super.dispose();
  }

  bool _isPermissionDeniedError(dynamic error) {
    if (error is FirebaseException) {
      return error.code == 'permission-denied' || 
             error.message?.contains('PERMISSION_DENIED') == true;
    }
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('permission') || 
           errorStr.contains('denied') ||
           errorStr.contains('missing or insufficient');
  }

  @override
  Widget build(BuildContext context) {
    // Shop đang bị xóa hoặc đã xóa
    if (_shopDeleted) {
      return widget.noAccessWidget ?? _buildNoAccessWidget(context, isDeleted: true);
    }
    
    // Lỗi permission
    if (_hasPermissionError) {
      return widget.noAccessWidget ?? _buildNoAccessWidget(context, isDeleted: false);
    }
    
    // Loading
    if (_lastSnapshot == null || _lastSnapshot!.connectionState == ConnectionState.waiting) {
      return widget.loadingWidget ?? const Center(child: CircularProgressIndicator());
    }
    
    return widget.builder(context, _lastSnapshot!);
  }

  Widget _buildNoAccessWidget(BuildContext context, {required bool isDeleted}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isDeleted ? Icons.store_outlined : Icons.lock_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              isDeleted
                  ? 'Chi nhánh đã bị xóa'
                  : 'Không có quyền truy cập',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isDeleted
                  ? 'Vui lòng chọn chi nhánh khác để tiếp tục.'
                  : 'Chi nhánh đã bị xóa hoặc bạn không còn quyền truy cập.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Extension để tạo SafeStream từ Query
extension SafeFirestoreQuery on Query<Map<String, dynamic>> {
  /// Tạo safe stream với shop validation
  Stream<QuerySnapshot<Map<String, dynamic>>> safeSnapshots({
    String? shopId,
    bool includeMetadataChanges = false,
  }) {
    // Nếu shop đang bị xóa, trả về empty stream
    if (shopId != null && ShopDeletionService.isShopBeingDeleted(shopId)) {
      return const Stream.empty();
    }
    
    // Wrap stream với error handling
    return snapshots(includeMetadataChanges: includeMetadataChanges)
        .handleError((error, stackTrace) {
      if (_isPermissionDenied(error)) {
        debugPrint('🔒 SafeSnapshots: Permission denied, returning empty');
        return const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
      }
      throw error;
    });
  }
  
  bool _isPermissionDenied(dynamic error) {
    if (error is FirebaseException) {
      return error.code == 'permission-denied';
    }
    return error.toString().toLowerCase().contains('permission');
  }
}

/// Extension để tạo SafeStream từ DocumentReference
extension SafeFirestoreDocument on DocumentReference<Map<String, dynamic>> {
  /// Tạo safe stream với shop validation
  Stream<DocumentSnapshot<Map<String, dynamic>>> safeSnapshots({
    String? shopId,
    bool includeMetadataChanges = false,
  }) {
    // Nếu shop đang bị xóa, trả về empty stream
    if (shopId != null && ShopDeletionService.isShopBeingDeleted(shopId)) {
      return const Stream.empty();
    }
    
    return snapshots(includeMetadataChanges: includeMetadataChanges)
        .handleError((error, stackTrace) {
      if (_isPermissionDenied(error)) {
        debugPrint('🔒 SafeDocSnapshots: Permission denied for $path');
        return const Stream<DocumentSnapshot<Map<String, dynamic>>>.empty();
      }
      throw error;
    });
  }
  
  bool _isPermissionDenied(dynamic error) {
    if (error is FirebaseException) {
      return error.code == 'permission-denied';
    }
    return error.toString().toLowerCase().contains('permission');
  }
}

/// Helper để bọc một Stream với error handling cho permission denied
Stream<T> wrapStreamWithPermissionHandling<T>(
  Stream<T> stream, {
  String? shopId,
  T? fallbackValue,
}) {
  // Skip nếu shop đang bị xóa
  if (shopId != null && ShopDeletionService.isShopBeingDeleted(shopId)) {
    return fallbackValue != null 
        ? Stream.value(fallbackValue)
        : const Stream.empty();
  }
  
  return stream.handleError((error, stackTrace) {
    final isPermission = error is FirebaseException && 
        (error.code == 'permission-denied' || 
         error.message?.contains('PERMISSION_DENIED') == true);
    
    if (isPermission) {
      debugPrint('🔒 Stream permission denied, returning fallback');
      if (fallbackValue != null) {
        return Stream.value(fallbackValue);
      }
      return const Stream.empty();
    }
    throw error;
  });
}

/// Mixin để tự động cancel stream subscriptions khi shop bị xóa
mixin ShopAwareStateMixin<T extends StatefulWidget> on State<T> {
  final List<StreamSubscription> _shopAwareSubscriptions = [];
  StreamSubscription? _shopDeletionSubscription;
  String? _currentShopId;
  
  /// Override trong subclass để set shopId
  String? get watchedShopId => _currentShopId;
  
  /// Gọi trong initState sau khi có shopId
  void initShopAwareState(String? shopId) {
    _currentShopId = shopId;
    
    // Listen to shop deletion events
    _shopDeletionSubscription = EventBus().stream
        .where((event) => 
          event == 'shop_deleting:$shopId' ||
          event == 'shop_deleted:$shopId')
        .listen((_) {
      onShopDeleted();
    });
  }
  
  /// Thêm subscription để auto-cancel khi shop bị xóa
  void addShopAwareSubscription(StreamSubscription subscription) {
    _shopAwareSubscriptions.add(subscription);
  }
  
  /// Override để handle shop deletion
  void onShopDeleted() {
    cancelAllShopAwareSubscriptions();
  }
  
  /// Cancel tất cả subscriptions
  void cancelAllShopAwareSubscriptions() {
    for (var sub in _shopAwareSubscriptions) {
      sub.cancel();
    }
    _shopAwareSubscriptions.clear();
  }
  
  @override
  void dispose() {
    cancelAllShopAwareSubscriptions();
    _shopDeletionSubscription?.cancel();
    super.dispose();
  }
}
