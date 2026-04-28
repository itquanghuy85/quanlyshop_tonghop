import 'package:flutter/material.dart';

import '../../../expansion/safe_mode/expansion_feature_flags.dart';
import 'branch_switch_view.dart';

/// Alias view để dùng tên BranchSelectorView khi tích hợp vào app.
class BranchSelectorView extends StatelessWidget {
  final String shopId;
  final String? currentUserId;
  final ExpansionFeatureFlags flags;

  const BranchSelectorView({
    super.key,
    required this.shopId,
    this.currentUserId,
    this.flags = const ExpansionFeatureFlags.safeDefaults(),
  });

  @override
  Widget build(BuildContext context) {
    return BranchSwitchView(
      shopId: shopId,
      currentUserId: currentUserId,
      flags: flags,
    );
  }
}
