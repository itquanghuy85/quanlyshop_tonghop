enum FinanceV2RolloutStage {
  parallel,
  v2Primary,
  v2Only,
}

class FinanceV2FeatureFlag {
  static const bool enableFinanceV2 = true;

  // Rollout policy for replacing Finance V1 with V2.
  static const FinanceV2RolloutStage rolloutStage =
      FinanceV2RolloutStage.v2Only;

  static bool get showV2Entry => enableFinanceV2;

  static bool get showLegacyFinanceEntries {
    if (!enableFinanceV2) return true;
    return rolloutStage != FinanceV2RolloutStage.v2Only;
  }

  static bool get showV2AsPrimary {
    return enableFinanceV2 && rolloutStage != FinanceV2RolloutStage.parallel;
  }
}
