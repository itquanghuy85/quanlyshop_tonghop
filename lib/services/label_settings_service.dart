import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/label_template_model.dart';
import 'user_service.dart';

/// Service quản lý cài đặt tem sản phẩm cho từng shop
class LabelSettingsService {
  static final LabelSettingsService _instance = LabelSettingsService._internal();
  factory LabelSettingsService() => _instance;
  LabelSettingsService._internal();

  static const String _templatesKey = 'label_templates';
  static const String _defaultTemplateKey = 'default_label_template';
  static const String _shopLabelSettingsKey = 'shop_label_settings';

  List<LabelTemplate>? _cachedTemplates;
  ShopLabelSettings? _cachedShopSettings;

  /// Lấy danh sách tất cả templates (mặc định + tùy chỉnh)
  Future<List<LabelTemplate>> getTemplates() async {
    if (_cachedTemplates != null) return _cachedTemplates!;

    final prefs = await SharedPreferences.getInstance();
    final shopId = UserService().getCurrentShopId();
    final key = '${_templatesKey}_$shopId';

    final jsonStr = prefs.getString(key);
    if (jsonStr != null) {
      try {
        final List<dynamic> jsonList = json.decode(jsonStr);
        _cachedTemplates = jsonList.map((e) => LabelTemplate.fromMap(e)).toList();
        return _cachedTemplates!;
      } catch (e) {
        print('Error loading templates: $e');
      }
    }

    // Trả về templates mặc định nếu chưa có
    _cachedTemplates = LabelTemplate.getDefaultTemplates();
    await _saveTemplates(_cachedTemplates!);
    return _cachedTemplates!;
  }

  /// Lưu templates
  Future<void> _saveTemplates(List<LabelTemplate> templates) async {
    final prefs = await SharedPreferences.getInstance();
    final shopId = UserService().getCurrentShopId();
    final key = '${_templatesKey}_$shopId';

    final jsonList = templates.map((e) => e.toMap()).toList();
    await prefs.setString(key, json.encode(jsonList));
    _cachedTemplates = templates;
  }

  /// Lấy template theo ID
  Future<LabelTemplate?> getTemplateById(String id) async {
    final templates = await getTemplates();
    try {
      return templates.firstWhere((t) => t.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Lấy template theo loại
  Future<LabelTemplate?> getTemplateByType(LabelType type) async {
    final templates = await getTemplates();
    try {
      return templates.firstWhere((t) => t.type == type && t.isDefault);
    } catch (e) {
      try {
        return templates.firstWhere((t) => t.type == type);
      } catch (e) {
        return null;
      }
    }
  }

  /// Lấy template mặc định đang được chọn
  Future<LabelTemplate> getDefaultTemplate() async {
    final prefs = await SharedPreferences.getInstance();
    final shopId = UserService().getCurrentShopId();
    final key = '${_defaultTemplateKey}_$shopId';

    final defaultId = prefs.getString(key) ?? 'sales';
    final template = await getTemplateById(defaultId);

    if (template != null) return template;

    // Fallback to sales template
    final templates = await getTemplates();
    return templates.firstWhere(
      (t) => t.type == LabelType.sales,
      orElse: () => templates.first,
    );
  }

  /// Đặt template mặc định
  Future<void> setDefaultTemplate(String templateId) async {
    final prefs = await SharedPreferences.getInstance();
    final shopId = UserService().getCurrentShopId();
    final key = '${_defaultTemplateKey}_$shopId';
    await prefs.setString(key, templateId);
  }

  /// Thêm template tùy chỉnh
  Future<void> addCustomTemplate(LabelTemplate template) async {
    final templates = await getTemplates();

    // Đảm bảo ID duy nhất
    final newTemplate = template.copyWith(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      type: LabelType.custom,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    templates.add(newTemplate);
    await _saveTemplates(templates);
  }

  /// Cập nhật template
  Future<void> updateTemplate(LabelTemplate template) async {
    final templates = await getTemplates();
    final index = templates.indexWhere((t) => t.id == template.id);

    if (index >= 0) {
      templates[index] = template.copyWith(updatedAt: DateTime.now());
      await _saveTemplates(templates);
    }
  }

  /// Xóa template tùy chỉnh
  Future<void> deleteTemplate(String templateId) async {
    final templates = await getTemplates();

    // Không cho xóa template mặc định
    final template = templates.firstWhere(
      (t) => t.id == templateId,
      orElse: () => templates.first,
    );
    if (template.type != LabelType.custom) return;

    templates.removeWhere((t) => t.id == templateId);
    await _saveTemplates(templates);
  }

  /// Lấy cài đặt tem của shop
  Future<ShopLabelSettings> getShopLabelSettings() async {
    if (_cachedShopSettings != null) return _cachedShopSettings!;

    final prefs = await SharedPreferences.getInstance();
    final shopId = UserService().getCurrentShopId();
    final key = '${_shopLabelSettingsKey}_$shopId';

    final jsonStr = prefs.getString(key);
    if (jsonStr != null) {
      try {
        _cachedShopSettings = ShopLabelSettings.fromMap(json.decode(jsonStr));
        return _cachedShopSettings!;
      } catch (e) {
        print('Error loading shop label settings: $e');
      }
    }

    // Trả về cài đặt mặc định
    _cachedShopSettings = ShopLabelSettings();
    return _cachedShopSettings!;
  }

  /// Lưu cài đặt tem của shop
  Future<void> saveShopLabelSettings(ShopLabelSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    final shopId = UserService().getCurrentShopId();
    final key = '${_shopLabelSettingsKey}_$shopId';

    await prefs.setString(key, json.encode(settings.toMap()));
    _cachedShopSettings = settings;
  }

  /// Reset về mặc định
  Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    final shopId = UserService().getCurrentShopId();

    await prefs.remove('${_templatesKey}_$shopId');
    await prefs.remove('${_defaultTemplateKey}_$shopId');
    await prefs.remove('${_shopLabelSettingsKey}_$shopId');

    _cachedTemplates = null;
    _cachedShopSettings = null;
  }

  /// Clear cache
  void clearCache() {
    _cachedTemplates = null;
    _cachedShopSettings = null;
  }
}

/// Cài đặt tem chung cho shop
class ShopLabelSettings {
  final String shopName;
  final String hotline;
  final String slogan;
  final String address;
  final String cpkFormula; // Công thức tính CPK mặc định
  final List<String> fixedLines; // Các dòng text cố định
  final bool autoCalculateCPK; // Tự động tính CPK

  ShopLabelSettings({
    this.shopName = '',
    this.hotline = '',
    this.slogan = 'Cam kết giá tốt nhất',
    this.address = '',
    this.cpkFormula = 'price + 500000',
    this.fixedLines = const [],
    this.autoCalculateCPK = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'shopName': shopName,
      'hotline': hotline,
      'slogan': slogan,
      'address': address,
      'cpkFormula': cpkFormula,
      'fixedLines': fixedLines,
      'autoCalculateCPK': autoCalculateCPK,
    };
  }

  factory ShopLabelSettings.fromMap(Map<String, dynamic> map) {
    return ShopLabelSettings(
      shopName: map['shopName'] ?? '',
      hotline: map['hotline'] ?? '',
      slogan: map['slogan'] ?? 'Cam kết giá tốt nhất',
      address: map['address'] ?? '',
      cpkFormula: map['cpkFormula'] ?? 'price + 500000',
      fixedLines: List<String>.from(map['fixedLines'] ?? []),
      autoCalculateCPK: map['autoCalculateCPK'] ?? true,
    );
  }

  ShopLabelSettings copyWith({
    String? shopName,
    String? hotline,
    String? slogan,
    String? address,
    String? cpkFormula,
    List<String>? fixedLines,
    bool? autoCalculateCPK,
  }) {
    return ShopLabelSettings(
      shopName: shopName ?? this.shopName,
      hotline: hotline ?? this.hotline,
      slogan: slogan ?? this.slogan,
      address: address ?? this.address,
      cpkFormula: cpkFormula ?? this.cpkFormula,
      fixedLines: fixedLines ?? this.fixedLines,
      autoCalculateCPK: autoCalculateCPK ?? this.autoCalculateCPK,
    );
  }

  /// Tính CPK từ giá
  int calculateCPK(int price) {
    if (cpkFormula.contains('*')) {
      final multiplier =
          double.tryParse(cpkFormula.replaceAll('price', '').replaceAll('*', '').trim()) ?? 1.05;
      return (price * multiplier).round();
    } else {
      final addition =
          int.tryParse(cpkFormula.replaceAll('price', '').replaceAll('+', '').trim()) ?? 500000;
      return price + addition;
    }
  }
}
