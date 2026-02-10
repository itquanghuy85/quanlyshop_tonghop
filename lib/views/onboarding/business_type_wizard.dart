import 'package:flutter/material.dart';
import '../../models/shop_settings_model.dart';
import '../../services/category_service.dart';

/// Wizard chọn ngành kinh doanh cho shop mới
/// Phase 4: General Shop - Onboarding
class BusinessTypeWizard extends StatefulWidget {
  final String shopId;
  final String shopName;
  final Function(ShopSettings) onComplete;

  const BusinessTypeWizard({
    super.key,
    required this.shopId,
    required this.shopName,
    required this.onComplete,
  });

  @override
  State<BusinessTypeWizard> createState() => _BusinessTypeWizardState();
}

class _BusinessTypeWizardState extends State<BusinessTypeWizard> {
  int _currentStep = 0;
  String _selectedType = 'electronics';
  final Map<String, bool> _selectedModules = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _updateModulesForType(_selectedType);
  }

  void _updateModulesForType(String type) {
    setState(() {
      _selectedModules.clear();
      switch (type) {
        case 'electronics':
          _selectedModules['enableRepair'] = true;
          _selectedModules['enableSerial'] = true;
          _selectedModules['enableWarranty'] = true;
          _selectedModules['enableExpiry'] = false;
          _selectedModules['enableVariants'] = false;
          _selectedModules['enableBatch'] = false;
          break;
        case 'food':
          _selectedModules['enableRepair'] = false;
          _selectedModules['enableSerial'] = false;
          _selectedModules['enableWarranty'] = false;
          _selectedModules['enableExpiry'] = true;
          _selectedModules['enableVariants'] = false;
          _selectedModules['enableBatch'] = true;
          break;
        case 'fashion':
          _selectedModules['enableRepair'] = false;
          _selectedModules['enableSerial'] = false;
          _selectedModules['enableWarranty'] = false;
          _selectedModules['enableExpiry'] = false;
          _selectedModules['enableVariants'] = true;
          _selectedModules['enableBatch'] = false;
          break;
        case 'general':
          // All off, user will customize
          _selectedModules['enableRepair'] = false;
          _selectedModules['enableSerial'] = false;
          _selectedModules['enableWarranty'] = false;
          _selectedModules['enableExpiry'] = false;
          _selectedModules['enableVariants'] = false;
          _selectedModules['enableBatch'] = false;
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thiết lập cửa hàng'),
        centerTitle: true,
      ),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: _onStepContinue,
        onStepCancel: _onStepCancel,
        controlsBuilder: (context, details) {
          return Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Row(
              children: [
                FilledButton(
                  onPressed: _isLoading ? null : details.onStepContinue,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_currentStep == 2 ? 'Hoàn tất' : 'Tiếp tục'),
                ),
                const SizedBox(width: 12),
                if (_currentStep > 0)
                  TextButton(
                    onPressed: details.onStepCancel,
                    child: const Text('Quay lại'),
                  ),
              ],
            ),
          );
        },
        steps: [
          Step(
            title: const Text('Chọn ngành'),
            subtitle: const Text('Chọn loại hình kinh doanh'),
            content: _buildBusinessTypeSelector(),
            isActive: _currentStep >= 0,
            state: _currentStep > 0 ? StepState.complete : StepState.indexed,
          ),
          Step(
            title: const Text('Tính năng'),
            subtitle: const Text('Tùy chỉnh tính năng'),
            content: _buildModuleSelector(),
            isActive: _currentStep >= 1,
            state: _currentStep > 1 ? StepState.complete : StepState.indexed,
          ),
          Step(
            title: const Text('Xác nhận'),
            subtitle: const Text('Kiểm tra và hoàn tất'),
            content: _buildSummary(),
            isActive: _currentStep >= 2,
            state: StepState.indexed,
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessTypeSelector() {
    return Column(
      children: [
        _buildTypeCard(
          'electronics',
          '📱 Điện thoại & Điện tử',
          'Shop điện thoại, laptop, phụ kiện...\nHỗ trợ: Quản lý IMEI, sửa chữa, bảo hành',
          Icons.phone_android,
          Colors.blue,
        ),
        // Food và General tạm ẩn - chỉ hỗ trợ Electronics và Fashion
        // _buildTypeCard(
        //   'food',
        //   '🍎 Thực phẩm & Đồ tươi sống',
        //   'Cửa hàng thực phẩm, nông sản...\nHỗ trợ: Hạn sử dụng, theo lô, đơn vị tính',
        //   Icons.restaurant,
        //   Colors.green,
        // ),
        _buildTypeCard(
          'fashion',
          '👕 Thời trang & May mặc',
          'Shop quần áo, giày dép, túi xách...\nHỗ trợ: Size, màu sắc, biến thể',
          Icons.checkroom,
          Colors.purple,
        ),
        // _buildTypeCard(
        //   'general',
        //   '📦 Tổng hợp / Tùy chỉnh',
        //   'Các loại hình khác hoặc tự tạo\nTự do bật/tắt từng tính năng',
        //   Icons.store,
        //   Colors.orange,
        // ),
      ],
    );
  }

  Widget _buildTypeCard(
    String type,
    String title,
    String description,
    IconData icon,
    Color color,
  ) {
    final isSelected = _selectedType == type;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? color : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: () {
          setState(() => _selectedType = type);
          _updateModulesForType(type);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isSelected ? color : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Radio<String>(
                value: type,
                groupValue: _selectedType,
                onChanged: (v) {
                  setState(() => _selectedType = v!);
                  _updateModulesForType(v!);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModuleSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tùy chỉnh tính năng cho "${_getTypeName(_selectedType)}"',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Text(
          'Bạn có thể bật/tắt các tính năng theo nhu cầu',
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
        const SizedBox(height: 16),
        _buildModuleSwitch(
          'enableRepair',
          'Module sửa chữa',
          'Nhận máy, quản lý tiến độ sửa, bàn giao',
          Icons.build,
        ),
        _buildModuleSwitch(
          'enableSerial',
          'Quản lý IMEI/Serial',
          'Theo dõi số IMEI hoặc Serial sản phẩm',
          Icons.numbers,
        ),
        _buildModuleSwitch(
          'enableWarranty',
          'Quản lý bảo hành',
          'Theo dõi tình trạng bảo hành sản phẩm',
          Icons.verified_user,
        ),
        _buildModuleSwitch(
          'enableExpiry',
          'Quản lý hạn sử dụng',
          'Cảnh báo sản phẩm sắp hết hạn',
          Icons.timer,
        ),
        _buildModuleSwitch(
          'enableBatch',
          'Quản lý theo lô',
          'Nhập hàng theo lô, theo dõi từng lô',
          Icons.inventory,
        ),
        _buildModuleSwitch(
          'enableVariants',
          'Biến thể (size/màu)',
          'Quản lý sản phẩm theo size, màu sắc',
          Icons.style,
        ),
      ],
    );
  }

  Widget _buildModuleSwitch(
    String key,
    String title,
    String description,
    IconData icon,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: SwitchListTile(
        secondary: Icon(icon),
        title: Text(title),
        subtitle: Text(description, style: const TextStyle(fontSize: 12)),
        value: _selectedModules[key] ?? false,
        onChanged: (v) => setState(() => _selectedModules[key] = v),
      ),
    );
  }

  Widget _buildSummary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.store, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      widget.shopName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                const Divider(),
                _buildSummaryRow(
                  'Loại hình',
                  _getTypeName(_selectedType),
                  _getTypeIcon(_selectedType),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tính năng đã bật:',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: _selectedModules.entries
                      .where((e) => e.value)
                      .map((e) => Chip(
                            label: Text(
                              _getModuleName(e.key),
                              style: const TextStyle(fontSize: 11),
                            ),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ))
                      .toList(),
                ),
                if (!_selectedModules.values.any((v) => v))
                  const Text(
                    'Chưa bật tính năng nào',
                    style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.blue),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Bạn có thể thay đổi cài đặt bất cứ lúc nào trong phần Cài đặt cửa hàng',
                  style: TextStyle(color: Colors.blue[700], fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text('$label: ', style: TextStyle(color: Colors.grey[600])),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    );
  }

  String _getTypeName(String type) {
    switch (type) {
      case 'electronics':
        return 'Điện thoại & Điện tử';
      case 'food':
        return 'Thực phẩm & Đồ tươi sống';
      case 'fashion':
        return 'Thời trang & May mặc';
      case 'general':
        return 'Tổng hợp / Tùy chỉnh';
      default:
        return type;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'electronics':
        return Icons.phone_android;
      case 'food':
        return Icons.restaurant;
      case 'fashion':
        return Icons.checkroom;
      case 'general':
        return Icons.store;
      default:
        return Icons.store;
    }
  }

  String _getModuleName(String key) {
    switch (key) {
      case 'enableRepair':
        return 'Sửa chữa';
      case 'enableSerial':
        return 'IMEI/Serial';
      case 'enableWarranty':
        return 'Bảo hành';
      case 'enableExpiry':
        return 'Hạn sử dụng';
      case 'enableBatch':
        return 'Theo lô';
      case 'enableVariants':
        return 'Biến thể';
      default:
        return key;
    }
  }

  void _onStepContinue() async {
    if (_currentStep < 2) {
      setState(() => _currentStep++);
    } else {
      // Save settings
      await _saveSettings();
    }
  }

  void _onStepCancel() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);

    try {
      final settings = ShopSettings(
        shopId: widget.shopId,
        firestoreId: 'shop_settings',
        businessType: _selectedType,
        businessTypeName: _getTypeName(_selectedType),
        enableRepair: _selectedModules['enableRepair'] ?? false,
        enableSerial: _selectedModules['enableSerial'] ?? false,
        enableWarranty: _selectedModules['enableWarranty'] ?? false,
        enableExpiry: _selectedModules['enableExpiry'] ?? false,
        enableBatch: _selectedModules['enableBatch'] ?? false,
        enableVariants: _selectedModules['enableVariants'] ?? false,
        defaultUnit: _selectedType == 'food' ? 'kg' : 'cái',
      );

      // Save to Firestore through service
      await CategoryService().saveShopSettings(settings);

      // Default categories will be created by CategoryService when needed

      widget.onComplete(settings);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}

/// Dialog chọn nhanh loại hình cho shop đã có
class BusinessTypeQuickSelector extends StatelessWidget {
  final Function(String) onSelected;

  const BusinessTypeQuickSelector({super.key, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Chọn loại hình kinh doanh'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildOption(context, 'electronics', '📱 Điện thoại & Điện tử', Icons.phone_android, Colors.blue),
          // Food và General tạm ẩn - chỉ hỗ trợ Electronics và Fashion
          // _buildOption(context, 'food', '🍎 Thực phẩm', Icons.restaurant, Colors.green),
          _buildOption(context, 'fashion', '👕 Thời trang', Icons.checkroom, Colors.purple),
          // _buildOption(context, 'general', '📦 Tổng hợp', Icons.store, Colors.orange),
        ],
      ),
    );
  }

  Widget _buildOption(
    BuildContext context,
    String type,
    String label,
    IconData icon,
    Color color,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(label),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.pop(context);
          onSelected(type);
        },
      ),
    );
  }
}

/// Preset configurations for each business type
class BusinessTypePresets {
  static Map<String, dynamic> getPreset(String type) {
    switch (type) {
      case 'electronics':
        return {
          'businessType': 'electronics',
          'businessTypeName': 'Điện thoại & Điện tử',
          'enableRepair': true,
          'enableSerial': true,
          'enableWarranty': true,
          'enableExpiry': false,
          'enableBatch': false,
          'enableVariants': false,
          'defaultUnit': 'cái',
          'defaultCategories': [
            {'name': 'Điện thoại', 'icon': '📱', 'trackSerial': true, 'hasWarranty': true},
            {'name': 'Máy tính bảng', 'icon': '📱', 'trackSerial': true, 'hasWarranty': true},
            {'name': 'Laptop', 'icon': '💻', 'trackSerial': true, 'hasWarranty': true},
            {'name': 'Phụ kiện', 'icon': '🎧', 'trackSerial': false, 'hasWarranty': false},
            {'name': 'Linh kiện', 'icon': '🔧', 'trackSerial': false, 'hasWarranty': false},
          ],
        };
      case 'food':
        return {
          'businessType': 'food',
          'businessTypeName': 'Thực phẩm & Đồ tươi sống',
          'enableRepair': false,
          'enableSerial': false,
          'enableWarranty': false,
          'enableExpiry': true,
          'enableBatch': true,
          'enableVariants': false,
          'defaultUnit': 'kg',
          'expiryWarningDays': 7,
          'defaultCategories': [
            {'name': 'Rau củ', 'icon': '🥬', 'trackExpiry': true, 'unit': 'kg'},
            {'name': 'Trái cây', 'icon': '🍎', 'trackExpiry': true, 'unit': 'kg'},
            {'name': 'Thịt cá', 'icon': '🍖', 'trackExpiry': true, 'unit': 'kg'},
            {'name': 'Đồ khô', 'icon': '🍚', 'trackExpiry': true, 'unit': 'gói'},
            {'name': 'Đồ hộp', 'icon': '🥫', 'trackExpiry': true, 'unit': 'hộp'},
            {'name': 'Đồ uống', 'icon': '🧃', 'trackExpiry': true, 'unit': 'chai'},
            {'name': 'Đông lạnh', 'icon': '🧊', 'trackExpiry': true, 'unit': 'kg'},
          ],
        };
      case 'fashion':
        return {
          'businessType': 'fashion',
          'businessTypeName': 'Thời trang & May mặc',
          'enableRepair': false,
          'enableSerial': false,
          'enableWarranty': false,
          'enableExpiry': false,
          'enableBatch': false,
          'enableVariants': true,
          'defaultUnit': 'cái',
          'defaultCategories': [
            {'name': 'Áo', 'icon': '👕', 'hasVariants': true},
            {'name': 'Quần', 'icon': '👖', 'hasVariants': true},
            {'name': 'Váy/Đầm', 'icon': '👗', 'hasVariants': true},
            {'name': 'Giày dép', 'icon': '👟', 'hasVariants': true},
            {'name': 'Túi xách', 'icon': '👜', 'hasVariants': false},
            {'name': 'Phụ kiện', 'icon': '🧣', 'hasVariants': false},
          ],
        };
      case 'general':
      default:
        return {
          'businessType': 'general',
          'businessTypeName': 'Tổng hợp',
          'enableRepair': false,
          'enableSerial': false,
          'enableWarranty': false,
          'enableExpiry': false,
          'enableBatch': false,
          'enableVariants': false,
          'defaultUnit': 'cái',
          'defaultCategories': [
            {'name': 'Hàng hóa', 'icon': '📦'},
            {'name': 'Khác', 'icon': '📋'},
          ],
        };
    }
  }

  static List<String> get availableTypes => ['electronics', 'food', 'fashion', 'general'];

  static String getTypeName(String type) {
    final preset = getPreset(type);
    return preset['businessTypeName'] ?? type;
  }

  static String getTypeIcon(String type) {
    switch (type) {
      case 'electronics':
        return '📱';
      case 'food':
        return '🍎';
      case 'fashion':
        return '👕';
      case 'general':
        return '📦';
      default:
        return '📦';
    }
  }
}
