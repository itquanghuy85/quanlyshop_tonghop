import 'package:flutter/material.dart';
import '../../expansion/safe_mode/expansion_feature_flags.dart';
import '../../expansion/safe_mode/expansion_module_models.dart';

class ExpansionModulesHubView extends StatelessWidget {
  final ExpansionFeatureFlags flags;
  final void Function(ExpansionModuleSpec spec)? onOpenModule;

  const ExpansionModulesHubView({
    super.key,
    this.flags = const ExpansionFeatureFlags.safeDefaults(),
    this.onOpenModule,
  });

  bool _isEnabled(ExpansionModuleKey key) {
    switch (key) {
      case ExpansionModuleKey.vat:
        return flags.enableVAT;
      case ExpansionModuleKey.pricing:
        return flags.enablePricing;
      case ExpansionModuleKey.crm:
        return flags.enableCRM;
      case ExpansionModuleKey.multiBranch:
        return flags.enableMultiBranch;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Expansion Modules (Safe Mode)')),
      body: ListView.builder(
        itemCount: ExpansionModuleCatalog.all.length,
        padding: const EdgeInsets.all(16),
        itemBuilder: (context, index) {
          final spec = ExpansionModuleCatalog.all[index];
          final enabled = _isEnabled(spec.key);
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(spec.displayName, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('Isolated tables: ${spec.isolatedTables.join(', ')}'),
                  Text(spec.note),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Chip(
                        label: Text(enabled ? 'Enabled' : 'Disabled'),
                        backgroundColor: enabled
                            ? Colors.green.withValues(alpha: 0.15)
                            : Colors.orange.withValues(alpha: 0.15),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () => onOpenModule?.call(spec),
                        child: Text(spec.openButtonLabel),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
