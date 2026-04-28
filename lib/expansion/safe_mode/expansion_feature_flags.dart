class ExpansionFeatureFlags {
  final bool enableVAT;
  final bool enablePricing;
  final bool enableCRM;
  final bool enableMultiBranch;

  const ExpansionFeatureFlags({
    this.enableVAT = false,
    this.enablePricing = false,
    this.enableCRM = false,
    this.enableMultiBranch = false,
  });

  const ExpansionFeatureFlags.safeDefaults()
      : enableVAT = false,
        enablePricing = false,
        enableCRM = false,
        enableMultiBranch = false;

  ExpansionFeatureFlags copyWith({
    bool? enableVAT,
    bool? enablePricing,
    bool? enableCRM,
    bool? enableMultiBranch,
  }) {
    return ExpansionFeatureFlags(
      enableVAT: enableVAT ?? this.enableVAT,
      enablePricing: enablePricing ?? this.enablePricing,
      enableCRM: enableCRM ?? this.enableCRM,
      enableMultiBranch: enableMultiBranch ?? this.enableMultiBranch,
    );
  }
}
