enum ExpansionModuleKey {
  vat,
  pricing,
  crm,
  multiBranch,
}

class ExpansionModuleSpec {
  final ExpansionModuleKey key;
  final String displayName;
  final String openButtonLabel;
  final String routeName;
  final List<String> isolatedTables;
  final String note;

  const ExpansionModuleSpec({
    required this.key,
    required this.displayName,
    required this.openButtonLabel,
    required this.routeName,
    required this.isolatedTables,
    required this.note,
  });
}

class ExpansionModuleCatalog {
  static const vat = ExpansionModuleSpec(
    key: ExpansionModuleKey.vat,
    displayName: 'VAT / E-Invoice',
    openButtonLabel: 'Open VAT Module',
    routeName: '/expansion/vat',
    isolatedTables: ['invoices', 'invoice_items'],
    note: 'No changes to sale or payment flow.',
  );

  static const pricing = ExpansionModuleSpec(
    key: ExpansionModuleKey.pricing,
    displayName: 'Pricing Engine',
    openButtonLabel: 'Open Pricing Module',
    routeName: '/expansion/pricing',
    isolatedTables: ['price_rules', 'customer_pricing'],
    note: 'No overwrite of legacy salePrice.',
  );

  static const crm = ExpansionModuleSpec(
    key: ExpansionModuleKey.crm,
    displayName: 'CRM & Loyalty',
    openButtonLabel: 'Open CRM Module',
    routeName: '/expansion/crm',
    isolatedTables: ['loyalty_points', 'customer_level'],
    note: 'No changes to legacy customer schema.',
  );

  static const multiBranch = ExpansionModuleSpec(
    key: ExpansionModuleKey.multiBranch,
    displayName: 'Multi-Branch',
    openButtonLabel: 'Open Multi-Branch Module',
    routeName: '/expansion/multi-branch',
    isolatedTables: ['branches', 'branch_inventory'],
    note: 'Legacy shopId isolation remains unchanged.',
  );

  static const List<ExpansionModuleSpec> all = [
    vat,
    pricing,
    crm,
    multiBranch,
  ];
}
