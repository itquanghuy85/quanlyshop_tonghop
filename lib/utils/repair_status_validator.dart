/// Repair Status State Machine
/// 
/// Validates repair status transitions to prevent invalid state changes.
/// 
/// Status values:
/// - 1: PENDING (MÁY CHỜ) - Initial state
/// - 2: REPAIRING (ĐANG SỬA) - In progress
/// - 3: COMPLETED (ĐÃ XONG) - Repair finished
/// - 4: DELIVERED (ĐÃ GIAO) - Terminal state

class RepairStatusValidator {
  /// Status constants
  static const int pending = 1;
  static const int repairing = 2;
  static const int completed = 3;
  static const int delivered = 4;

  /// Valid status transitions map
  /// Key: current status, Value: list of allowed next statuses
  static const Map<int, List<int>> validTransitions = {
    pending: [repairing, completed], // Có thể sửa trực tiếp hoặc xong luôn (sửa nhanh)
    repairing: [completed, pending], // Có thể xong hoặc quay lại chờ (cancel sửa)
    completed: [delivered, repairing], // Giao máy hoặc phải sửa lại
    delivered: [], // Terminal state - không thể thay đổi
  };

  /// Check if a status transition is valid
  static bool canTransition(int fromStatus, int toStatus) {
    // Same status is always invalid (no change)
    if (fromStatus == toStatus) return false;
    
    // Check if transition is in allowed list
    final allowedStatuses = validTransitions[fromStatus];
    if (allowedStatuses == null) return false;
    
    return allowedStatuses.contains(toStatus);
  }

  /// Get validation error message for invalid transition
  /// Returns null if transition is valid
  static String? getTransitionError(int fromStatus, int toStatus) {
    if (fromStatus == toStatus) {
      return 'Trạng thái không thay đổi';
    }
    
    if (!canTransition(fromStatus, toStatus)) {
      final fromText = getStatusText(fromStatus);
      final toText = getStatusText(toStatus);
      
      if (fromStatus == delivered) {
        return 'Đơn đã giao không thể thay đổi trạng thái';
      }
      
      final allowedStatuses = validTransitions[fromStatus];
      if (allowedStatuses == null || allowedStatuses.isEmpty) {
        return 'Không thể chuyển từ "$fromText" sang trạng thái khác';
      }
      
      final allowedTexts = allowedStatuses.map((s) => '"${getStatusText(s)}"').join(', ');
      return 'Không thể chuyển từ "$fromText" sang "$toText".\nChỉ được chuyển sang: $allowedTexts';
    }
    
    return null; // Valid transition
  }

  /// Get human-readable status text
  static String getStatusText(int status) {
    switch (status) {
      case pending:
        return 'MÁY CHỜ';
      case repairing:
        return 'ĐANG SỬA';
      case completed:
        return 'ĐÃ XONG';
      case delivered:
        return 'ĐÃ GIAO';
      default:
        return 'KHÔNG XÁC ĐỊNH';
    }
  }

  /// Get all valid next statuses from current status
  static List<int> getValidNextStatuses(int currentStatus) {
    return validTransitions[currentStatus] ?? [];
  }

  /// Check if status is a terminal state (cannot be changed)
  static bool isTerminalState(int status) {
    final transitions = validTransitions[status];
    return transitions == null || transitions.isEmpty;
  }

  /// Get status color for UI
  static int getStatusColor(int status) {
    switch (status) {
      case pending:
        return 0xFFFF9800; // Orange
      case repairing:
        return 0xFF2196F3; // Blue
      case completed:
        return 0xFF4CAF50; // Green
      case delivered:
        return 0xFF9E9E9E; // Grey
      default:
        return 0xFF757575;
    }
  }

  /// Get status icon
  static int getStatusIcon(int status) {
    switch (status) {
      case pending:
        return 0xe0ce; // Icons.hourglass_empty
      case repairing:
        return 0xe1b1; // Icons.build
      case completed:
        return 0xe156; // Icons.check_circle
      case delivered:
        return 0xe531; // Icons.local_shipping
      default:
        return 0xe8fd; // Icons.help
    }
  }
}
