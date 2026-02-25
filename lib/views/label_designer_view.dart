import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/label_template_model.dart';
import '../services/label_settings_service.dart';
import '../services/notification_service.dart';
import '../theme/app_text_styles.dart';
import 'pty_print_designer_view.dart';

/// Model cho từng element trong tem
class LabelElement {
  final String id;
  String label;
  bool visible;
  double fontSize;
  bool bold;
  String fontType;
  String align;
  int order;
  String prefix;
  int row; // Dòng chứa element (0, 1, 2...)
  int col; // Cột trong dòng (0 = bên trái/full, 1 = bên phải)
  double flex; // Tỷ lệ chiếm chỗ (0.5 = nửa, 1.0 = full)
  double spacing; // Khoảng cách dưới element (0-20)

  LabelElement({
    required this.id,
    required this.label,
    this.visible = true,
    this.fontSize = 1.0,
    this.bold = true,
    this.fontType = 'A',
    this.align = 'center',
    this.order = 0,
    this.prefix = '',
    this.row = 0,
    this.col = 0,
    this.flex = 1.0,
    this.spacing = 4.0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'visible': visible,
    'fontSize': fontSize,
    'bold': bold,
    'fontType': fontType,
    'align': align,
    'order': order,
    'prefix': prefix,
    'row': row,
    'col': col,
    'flex': flex,
    'spacing': spacing,
  };

  factory LabelElement.fromJson(Map<String, dynamic> json) => LabelElement(
    id: json['id'] ?? '',
    label: json['label'] ?? '',
    visible: json['visible'] ?? true,
    fontSize: (json['fontSize'] ?? 1.0).toDouble(),
    bold: json['bold'] ?? true,
    fontType: json['fontType'] ?? 'A',
    align: json['align'] ?? 'center',
    order: json['order'] ?? 0,
    prefix: json['prefix'] ?? '',
    row: json['row'] ?? 0,
    col: json['col'] ?? 0,
    flex: (json['flex'] ?? 1.0).toDouble(),
    spacing: (json['spacing'] ?? 4.0).toDouble(),
  );

  LabelElement copyWith({
    String? label,
    bool? visible,
    double? fontSize,
    bool? bold,
    String? fontType,
    String? align,
    int? order,
    String? prefix,
    int? row,
    int? col,
    double? flex,
    double? spacing,
  }) => LabelElement(
    id: id,
    label: label ?? this.label,
    visible: visible ?? this.visible,
    fontSize: fontSize ?? this.fontSize,
    bold: bold ?? this.bold,
    fontType: fontType ?? this.fontType,
    align: align ?? this.align,
    order: order ?? this.order,
    prefix: prefix ?? this.prefix,
    row: row ?? this.row,
    col: col ?? this.col,
    flex: flex ?? this.flex,
    spacing: spacing ?? this.spacing,
  );
}

class _PaperSpec {
  final double widthMm;
  final double? heightMm;

  const _PaperSpec({required this.widthMm, this.heightMm});
}

/// Trang THIẾT KẾ TEM - Kéo thả trực tiếp trên mẫu
class LabelDesignerView extends StatefulWidget {
  const LabelDesignerView({super.key});

  @override
  State<LabelDesignerView> createState() => _LabelDesignerViewState();
}

class _LabelDesignerViewState extends State<LabelDesignerView>
    with SingleTickerProviderStateMixin {
  static const String _prefsKey = 'label_designer_elements';
  late TabController _tabController;

  List<LabelElement> _elements = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _selectedElementId;

  // Paper Size: '58', '72', '80' (mm) hoặc '2x4', '3x4', '4x6' (inch)
  String _paperSize = '80';
  String _paperMode = 'roll'; // 'roll' (mm) | 'sticker' (cm)
  final TextEditingController _customRollSizeCtrl = TextEditingController();
    final TextEditingController _customStickerWidthCtrl =
      TextEditingController();
    final TextEditingController _customStickerHeightCtrl =
      TextEditingController();

  // Code Type: 'qr', 'barcode' hoặc 'none'
  String _codeType = 'qr';

  double _previewZoom = 1.3;

  // Auto-save debounce timer
  Timer? _autoSaveTimer;

  static const double _referenceWidthMm = 80.0;

  // Prefix controllers for each element
  final Map<String, TextEditingController> _prefixControllers = {};

  // Shop Settings
  final _labelService = LabelSettingsService();
  ShopLabelSettings? _shopSettings;
  final _shopNameCtrl = TextEditingController();
  final _hotlineCtrl = TextEditingController();
  final _sloganCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cpkFormulaCtrl = TextEditingController();
  final _fixedLine1Ctrl = TextEditingController();
  final _fixedLine2Ctrl = TextEditingController();
  final _fixedLine3Ctrl = TextEditingController();

  // Default elements với row layout
  List<LabelElement> get _defaultElements => [
    LabelElement(
      id: 'name',
      label: 'Tên SP',
      fontSize: 1.4,
      bold: true,
      row: 0,
      col: 0,
      flex: 1.0,
      spacing: 2,
    ),
    LabelElement(
      id: 'detail',
      label: 'Chi tiết',
      fontSize: 1.0,
      bold: true,
      row: 1,
      col: 0,
      flex: 1.0,
      spacing: 4,
    ),
    LabelElement(
      id: 'label_info',
      label: 'Thông tin tem',
      fontSize: 0.9,
      bold: false,
      row: 2,
      col: 0,
      flex: 1.0,
      spacing: 3,
    ),
    LabelElement(
      id: 'price_kpk',
      label: 'Giá KPK',
      fontSize: 1.2,
      bold: true,
      row: 3,
      col: 0,
      flex: 1.0,
      prefix: 'KPK: ',
      spacing: 2,
    ),
    LabelElement(
      id: 'price_cpk',
      label: 'Giá CPK',
      fontSize: 1.2,
      bold: true,
      row: 4,
      col: 0,
      flex: 1.0,
      prefix: 'CPK: ',
      spacing: 4,
    ),
    LabelElement(
      id: 'imei',
      label: 'IMEI',
      fontSize: 0.8,
      bold: false,
      row: 5,
      col: 0,
      flex: 0.6,
      prefix: '',
      spacing: 0,
      align: 'left',
    ),
    LabelElement(
      id: 'qr_code',
      label: 'QR',
      fontSize: 1.0,
      bold: false,
      row: 5,
      col: 1,
      flex: 0.4,
      spacing: 4,
    ),
    LabelElement(
      id: 'shop_info',
      label: 'Shop',
      fontSize: 0.7,
      bold: false,
      row: 6,
      col: 0,
      flex: 1.0,
      spacing: 0,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAllData();
  }

  @override
  void dispose() {
    // Cancel auto-save timer and save immediately
    _autoSaveTimer?.cancel();
    _saveSettingsQuiet(); // Save on exit
    
    _tabController.dispose();
    _customRollSizeCtrl.dispose();
    _customStickerWidthCtrl.dispose();
    _customStickerHeightCtrl.dispose();
    _shopNameCtrl.dispose();
    _hotlineCtrl.dispose();
    _sloganCtrl.dispose();
    _addressCtrl.dispose();
    _cpkFormulaCtrl.dispose();
    _fixedLine1Ctrl.dispose();
    _fixedLine2Ctrl.dispose();
    _fixedLine3Ctrl.dispose();
    // Dispose prefix controllers
    for (final ctrl in _prefixControllers.values) {
      ctrl.dispose();
    }
    _prefixControllers.clear();
    super.dispose();
  }

  /// Auto-save with debounce (500ms delay)
  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 500), () {
      _saveSettingsQuiet();
    });
  }

  /// Save settings without showing notification
  Future<void> _saveSettingsQuiet() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(_elements.map((e) => e.toJson()).toList());
      await prefs.setString(_prefsKey, jsonStr);
      await prefs.setString('label_paper_size', _paperSize);
      await prefs.setString('label_code_type', _codeType);

      // Save backward compatible settings
      for (final el in _elements) {
        switch (el.id) {
          case 'name':
            await prefs.setBool('label_show_name', el.visible);
            await prefs.setDouble('label_name_font_size', el.fontSize);
            break;
          case 'detail':
            await prefs.setBool('label_show_detail', el.visible);
            await prefs.setDouble('label_detail_font_size', el.fontSize);
            break;
          case 'price_kpk':
            await prefs.setBool('label_show_price_kpk', el.visible);
            await prefs.setDouble('label_kpk_font_size', el.fontSize);
            break;
          case 'price_cpk':
            await prefs.setBool('label_show_price_cpk', el.visible);
            await prefs.setDouble('label_cpk_font_size', el.fontSize);
            break;
          case 'imei':
            await prefs.setBool('label_show_imei', el.visible);
            await prefs.setDouble('label_imei_font_size', el.fontSize);
            break;
          case 'qr_code':
            await prefs.setBool('label_show_qr', el.visible);
            break;
          case 'shop_info':
            await prefs.setBool('label_show_shop_info', el.visible);
            break;
        }
      }
      debugPrint('Auto-saved label settings');
    } catch (e) {
      debugPrint('Auto-save error: $e');
    }
  }

  Future<void> _loadAllData() async {
    await Future.wait([_loadElements(), _loadShopSettings()]);
  }

  Future<void> _loadElements() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_prefsKey);

    // Load paper size
    _paperSize = prefs.getString('label_paper_size') ?? '80';
    _paperMode = _paperSize.contains('x') ? 'sticker' : 'roll';
    if (_paperMode == 'roll') {
      _customRollSizeCtrl.text = _paperSize;
    } else {
      final parts = _paperSize.split('x');
      _customStickerWidthCtrl.text = parts.first;
      _customStickerHeightCtrl.text =
          parts.length > 1 ? parts.last : '3';
    }

    // Load code type (qr or barcode)
    _codeType = prefs.getString('label_code_type') ?? 'qr';

    if (jsonStr != null) {
      try {
        final List<dynamic> jsonList = jsonDecode(jsonStr);
        _elements = jsonList.map((e) => LabelElement.fromJson(e)).toList();
      } catch (e) {
        _elements = List.from(_defaultElements);
      }
    } else {
      _elements = List.from(_defaultElements);
    }

    // Ensure new default elements are present (backward compatibility)
    final existingIds = _elements.map((e) => e.id).toSet();
    for (final def in _defaultElements) {
      if (!existingIds.contains(def.id)) {
        _elements.add(def);
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadShopSettings() async {
    try {
      final shopSettings = await _labelService.getShopLabelSettings();
      setState(() {
        _shopSettings = shopSettings;
        _shopNameCtrl.text = shopSettings.shopName;
        _hotlineCtrl.text = shopSettings.hotline;
        _sloganCtrl.text = shopSettings.slogan;
        _addressCtrl.text = shopSettings.address;
        _cpkFormulaCtrl.text = shopSettings.cpkFormula;
        if (shopSettings.fixedLines.isNotEmpty) {
          _fixedLine1Ctrl.text =
              shopSettings.fixedLines.elementAtOrNull(0) ?? '';
          _fixedLine2Ctrl.text =
              shopSettings.fixedLines.elementAtOrNull(1) ?? '';
          _fixedLine3Ctrl.text =
              shopSettings.fixedLines.elementAtOrNull(2) ?? '';
        }
      });
    } catch (e) {
      debugPrint('Error loading shop settings: $e');
    }
  }

  Future<void> _saveAll() async {
    setState(() => _isSaving = true);
    try {
      // Save elements
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(_elements.map((e) => e.toJson()).toList());
      await prefs.setString(_prefsKey, jsonStr);

      // Save paper size
      await prefs.setString('label_paper_size', _paperSize);

      // Save code type
      await prefs.setString('label_code_type', _codeType);

      // Save backward compatible settings
      for (final el in _elements) {
        switch (el.id) {
          case 'name':
            await prefs.setBool('label_show_name', el.visible);
            await prefs.setDouble('label_name_font_size', el.fontSize);
            break;
          case 'detail':
            await prefs.setBool('label_show_detail', el.visible);
            await prefs.setDouble('label_detail_font_size', el.fontSize);
            break;
          case 'price_kpk':
            await prefs.setBool('label_show_price_kpk', el.visible);
            await prefs.setDouble('label_kpk_font_size', el.fontSize);
            break;
          case 'price_cpk':
            await prefs.setBool('label_show_price_cpk', el.visible);
            await prefs.setDouble('label_cpk_font_size', el.fontSize);
            break;
          case 'imei':
            await prefs.setBool('label_show_imei', el.visible);
            await prefs.setDouble('label_imei_font_size', el.fontSize);
            break;
          case 'qr_code':
            await prefs.setBool('label_show_qr', el.visible);
            break;
          case 'shop_info':
            await prefs.setBool('label_show_shop_info', el.visible);
            break;
        }
      }

      // Save shop settings
      final fixedLines = <String>[];
      if (_fixedLine1Ctrl.text.trim().isNotEmpty) {
        fixedLines.add(_fixedLine1Ctrl.text.trim());
      }
      if (_fixedLine2Ctrl.text.trim().isNotEmpty) {
        fixedLines.add(_fixedLine2Ctrl.text.trim());
      }
      if (_fixedLine3Ctrl.text.trim().isNotEmpty) {
        fixedLines.add(_fixedLine3Ctrl.text.trim());
      }

      final newSettings = ShopLabelSettings(
        shopName: _shopNameCtrl.text.trim(),
        hotline: _hotlineCtrl.text.trim(),
        slogan: _sloganCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        cpkFormula: _cpkFormulaCtrl.text.trim(),
        fixedLines: fixedLines,
        autoCalculateCPK: _shopSettings?.autoCalculateCPK ?? true,
      );
      await _labelService.saveShopLabelSettings(newSettings);

      NotificationService.showSnackBar(
        '✅ Đã lưu thiết kế tem!',
        color: Colors.green,
      );
    } catch (e) {
      NotificationService.showSnackBar('❌ Lỗi: $e', color: Colors.red);
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _resetToDefault() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đặt lại mặc định?'),
        content: const Text('Bố cục tem sẽ trở về cài đặt gốc.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _elements = List.from(_defaultElements);
                _selectedElementId = null;
              });
            },
            child: const Text('Đặt lại', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0068FF), Color(0xFF0084FF)],
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'THIẾT KẾ TEM',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: AppTextStyles.headline3.fontSize,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.design_services, size: 18), text: 'Bố cục'),
            Tab(icon: Icon(Icons.store, size: 18), text: 'Thông tin Shop'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'PTY 1:1 Designer',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PtyPrintDesignerView(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Đặt lại',
            onPressed: _resetToDefault,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [_buildLayoutTab(), _buildShopSettingsTab()],
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.green,
        onPressed: _isSaving ? null : _saveAll,
        icon: _isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.save, color: Colors.white),
        label: Text(
          _isSaving ? 'Đang lưu...' : 'LƯU',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ===== TAB 1: Visual Layout Designer =====
  Widget _buildLayoutTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Paper Size Selection
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.tune, color: Colors.orange.shade700),
                    const SizedBox(width: 12),
                    const Text(
                      'Loại giấy:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'roll', label: Text('Cuộn (mm)')),
                          ButtonSegment(value: 'sticker', label: Text('Tem dán (cm)')),
                        ],
                        selected: {_paperMode},
                        onSelectionChanged: (s) {
                          setState(() {
                            _paperMode = s.first;
                            _paperSize = _paperMode == 'roll' ? '80' : '2x3';
                            if (_paperMode == 'roll') {
                              _customRollSizeCtrl.text = _paperSize;
                            }
                          });
                          _scheduleAutoSave();
                        },
                        style: ButtonStyle(
                          backgroundColor: WidgetStateProperty.resolveWith((
                            states,
                          ) {
                            if (states.contains(WidgetState.selected)) {
                              return Colors.orange;
                            }
                            return null;
                          }),
                          foregroundColor: WidgetStateProperty.resolveWith((
                            states,
                          ) {
                            if (states.contains(WidgetState.selected)) {
                              return Colors.white;
                            }
                            return null;
                          }),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.receipt_long, color: Colors.orange.shade700),
                    const SizedBox(width: 12),
                    const Text(
                      'Khổ giấy cuộn (mm):',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: '50', label: Text('50mm (PT-50DC)')),
                    ButtonSegment(value: '58', label: Text('58mm')),
                    ButtonSegment(value: '72', label: Text('72mm')),
                    ButtonSegment(value: '80', label: Text('80mm')),
                  ],
                  selected: {
                    _paperMode == 'roll' && !_paperSize.contains('x')
                        ? _paperSize
                        : '80',
                  },
                  onSelectionChanged: _paperMode != 'roll'
                      ? null
                      : (s) {
                          setState(() {
                            _paperSize = s.first;
                            _customRollSizeCtrl.text = _paperSize;
                          });
                          _scheduleAutoSave();
                        },
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected) &&
                          _paperMode == 'roll') {
                        return Colors.orange;
                      }
                      return null;
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected) &&
                          _paperMode == 'roll') {
                        return Colors.white;
                      }
                      return null;
                    }),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _customRollSizeCtrl,
                  enabled: _paperMode == 'roll',
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Tự nhập khổ giấy (mm)',
                    hintText: 'VD: 76',
                    prefixIcon: const Icon(Icons.straighten),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (value) {
                    final normalized = value.trim();
                    final mm = double.tryParse(normalized);
                    if (mm == null) return;
                    setState(() => _paperSize = mm.toStringAsFixed(0));
                    _scheduleAutoSave();
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.label, color: Colors.orange.shade700),
                    const SizedBox(width: 12),
                    const Text(
                      'Tem dán (cm):',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: '2x3', label: Text('2x3')),
                    ButtonSegment(value: '3x4', label: Text('3x4')),
                    ButtonSegment(value: '4x6', label: Text('4x6')),
                  ],
                  selected: {
                    _paperMode == 'sticker' && _paperSize.contains('x')
                        ? _paperSize
                        : '2x3',
                  },
                  onSelectionChanged: _paperMode != 'sticker'
                      ? null
                      : (s) {
                          setState(() {
                            _paperSize = s.first;
                            final parts = _paperSize.split('x');
                            _customStickerWidthCtrl.text = parts.first;
                            _customStickerHeightCtrl.text =
                                parts.length > 1 ? parts.last : '3';
                          });
                          _scheduleAutoSave();
                        },
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected) &&
                          _paperMode == 'sticker') {
                        return Colors.orange;
                      }
                      return null;
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected) &&
                          _paperMode == 'sticker') {
                        return Colors.white;
                      }
                      return null;
                    }),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _customStickerWidthCtrl,
                        enabled: _paperMode == 'sticker',
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Rộng (cm)',
                          hintText: 'VD: 2.5',
                          prefixIcon: const Icon(Icons.straighten),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onChanged: (_) => _updateCustomStickerSize(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _customStickerHeightCtrl,
                        enabled: _paperMode == 'sticker',
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Dài (cm)',
                          hintText: 'VD: 3.5',
                          prefixIcon: const Icon(Icons.straighten),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onChanged: (_) => _updateCustomStickerSize(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Code Type Selection (QR vs Barcode vs None)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.qr_code, color: Colors.blue.shade700),
                const SizedBox(width: 12),
                const Text(
                  'Loại mã:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'none',
                        label: Text('Tắt'),
                        icon: Icon(Icons.block, size: 18),
                      ),
                      ButtonSegment(
                        value: 'qr',
                        label: Text('QR'),
                        icon: Icon(Icons.qr_code_2, size: 18),
                      ),
                      ButtonSegment(
                        value: 'barcode',
                        label: Text('Barcode'),
                        icon: Icon(Icons.view_week, size: 18),
                      ),
                    ],
                    selected: {_codeType},
                    onSelectionChanged: (s) {
                        setState(() => _codeType = s.first);
                        _scheduleAutoSave();
                    },
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith((
                        states,
                      ) {
                        if (states.contains(WidgetState.selected)) {
                          return Colors.blue;
                        }
                        return null;
                      }),
                      foregroundColor: WidgetStateProperty.resolveWith((
                        states,
                      ) {
                        if (states.contains(WidgetState.selected)) {
                          return Colors.white;
                        }
                        return null;
                      }),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Instructions
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.touch_app, color: Colors.blue.shade600),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '👆 Nhấn vào phần tử trên mẫu để chỉnh sửa\n'
                    '🖐️ Nhấn giữ và kéo thả để hoán đổi vị trí\n'
                    '🔀 Gộp/tách dòng ở bảng điều khiển bên dưới',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.zoom_in, size: 18, color: Colors.blue),
              const SizedBox(width: 8),
              const Text('Phóng to mẫu:', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: _previewZoom,
                  min: 0.9,
                  max: 2.2,
                  divisions: 13,
                  label: '${_previewZoom.toStringAsFixed(1)}x',
                  onChanged: (v) => setState(() => _previewZoom = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Visual Preview (Draggable)
          _buildVisualPreview(),

          const SizedBox(height: 16),

          // Element Controls
          if (_selectedElementId != null) _buildElementEditor(),

          // Quick Row Actions
          _buildRowActions(),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildVisualPreview() {
    // Group elements by row
    final rowMap = <int, List<LabelElement>>{};
    for (final el in _elements.where((e) => e.visible)) {
      rowMap.putIfAbsent(el.row, () => []);
      rowMap[el.row]!.add(el);
    }
    final sortedRows = rowMap.keys.toList()..sort();

    return LayoutBuilder(
      builder: (context, constraints) {
        final paperSpec = _getPaperSpec();
        final effectiveWidth =
          max(constraints.maxWidth, _referenceWidthMm * 4);
        final previewScale =
          (effectiveWidth / _referenceWidthMm) * _previewZoom;
        final paperScale = paperSpec.widthMm / _referenceWidthMm;
        final previewWidth = paperSpec.widthMm * previewScale;
        final previewHeight = paperSpec.heightMm == null
            ? null
            : paperSpec.heightMm! * previewScale;
        final sizeLabel = paperSpec.heightMm == null
            ? '${paperSpec.widthMm.toInt()}mm'
            : '${paperSpec.widthMm.toInt()}x${paperSpec.heightMm!.toInt()}mm';

        final content = Column(
          children: sortedRows.map((rowIndex) {
            final rowElements = rowMap[rowIndex]!;
            rowElements.sort((a, b) => a.col.compareTo(b.col));

            final spacing = rowElements.first.spacing * paperScale;

            return Padding(
              padding: EdgeInsets.only(bottom: spacing),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: rowElements.map((el) {
                  return Expanded(
                    flex: (el.flex * 10).round(),
                    child: _buildPreviewElement(el, paperScale),
                  );
                }).toList(),
              ),
            );
          }).toList(),
        );

        return Center(
          child: Container(
            width: previewWidth,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withValues(alpha: 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade100, Colors.blue.shade50],
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.label,
                        color: Colors.blue.shade600,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'MẪU TEM',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        sizeLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue.shade500,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Nhấn để chọn',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue.shade400,
                        ),
                      ),
                    ],
                  ),
                ),

                // Preview Content
                Container(
                  width: previewWidth,
                  padding: EdgeInsets.all(16 * paperScale),
                  child: previewHeight == null
                      ? content
                      : SizedBox(
                          height: previewHeight,
                          child: ClipRect(child: content),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  _PaperSpec _getPaperSpec() {
    if (_paperSize.contains('x')) {
      final parts = _paperSize.split('x');
      final widthCm = double.tryParse(parts.first) ?? 2;
      final heightCm = double.tryParse(parts.last) ?? 3;
      return _PaperSpec(widthMm: widthCm * 10, heightMm: heightCm * 10);
    }
    final width = double.tryParse(_paperSize) ?? 80;
    return _PaperSpec(widthMm: width, heightMm: null);
  }

  void _updateCustomStickerSize() {
    if (_paperMode != 'sticker') return;
    final width = double.tryParse(_customStickerWidthCtrl.text.trim());
    final height = double.tryParse(_customStickerHeightCtrl.text.trim());
    if (width == null || height == null || width <= 0 || height <= 0) return;
    setState(() => _paperSize = '${width}x$height');
    _scheduleAutoSave();
  }

  void _swapElementPositions(String sourceId, String targetId) {
    if (sourceId == targetId) return;
    final sourceIndex = _elements.indexWhere((e) => e.id == sourceId);
    final targetIndex = _elements.indexWhere((e) => e.id == targetId);
    if (sourceIndex == -1 || targetIndex == -1) return;

    final source = _elements[sourceIndex];
    final target = _elements[targetIndex];

    setState(() {
      _elements[sourceIndex] = source.copyWith(
        row: target.row,
        col: target.col,
        order: target.order,
      );
      _elements[targetIndex] = target.copyWith(
        row: source.row,
        col: source.col,
        order: source.order,
      );
      _selectedElementId = targetId;
    });
    _scheduleAutoSave();
  }

  Widget _buildPreviewElement(LabelElement el, double paperScale) {
    final isSelected = _selectedElementId == el.id;
    String text = '';
    Widget? child;

    switch (el.id) {
      case 'name':
        text = '${el.prefix}IPHONE 15 PRO MAX';
        break;
      case 'detail':
        text = '${el.prefix}256GB ĐEN 98%';
        break;
      case 'label_info':
        text = '${el.prefix}BẢO HÀNH 6T / MÁY ĐẸP'.toUpperCase();
        break;
      case 'price_kpk':
        text = '${el.prefix}25,900K';
        break;
      case 'price_cpk':
        text = '${el.prefix}26,400K';
        break;
      case 'imei':
        text = '${el.prefix}3598765...123';
        break;
      case 'qr_code':
        // Ẩn nếu chọn "none" (tắt QR/Barcode)
        if (_codeType == 'none') {
          return const SizedBox.shrink();
        }
        child = Icon(
          _codeType == 'barcode' ? Icons.view_week : Icons.qr_code_2,
          size: 36 * el.fontSize * paperScale,
          color: isSelected ? Colors.blue : Colors.black87,
        );
        break;
      case 'shop_info':
        final shopName = _shopNameCtrl.text.isEmpty
            ? 'SHOP NAME'
            : _shopNameCtrl.text;
        final hotline = _hotlineCtrl.text.isEmpty
            ? '0909.xxx.xxx'
            : _hotlineCtrl.text;
        text = '$shopName • $hotline';
        break;
      default:
        text = el.label;
    }

    final baseFontSize = 13.0 * paperScale;
    final alignment = el.align == 'left'
        ? TextAlign.left
        : el.align == 'right'
        ? TextAlign.right
        : TextAlign.center;
    Widget buildContent({required bool isHover}) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.blue.shade50
              : isHover
              ? Colors.blue.shade100.withValues(alpha: 0.4)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected
                ? Colors.blue
                : isHover
                ? Colors.blue.shade300
                : Colors.transparent,
            width: isSelected || isHover ? 2 : 0,
          ),
        ),
        child:
            child ??
            Text(
              text,
              textAlign: alignment,
              style: TextStyle(
                fontSize: baseFontSize * el.fontSize,
                fontWeight: el.bold ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.blue.shade700 : Colors.black87,
              ),
            ),
      );
    }

    return LongPressDraggable<String>(
      data: el.id,
      feedback: Material(
        color: Colors.transparent,
        child: Transform.scale(
          scale: 1.05,
          child: buildContent(isHover: false),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.4,
        child: buildContent(isHover: false),
      ),
      child: DragTarget<String>(
        onWillAcceptWithDetails: (data) => data.data != el.id,
        onAcceptWithDetails: (data) => _swapElementPositions(data.data, el.id),
        builder: (context, candidates, rejects) {
          final isHover = candidates.isNotEmpty;
          return GestureDetector(
            onTap: () => setState(
              () => _selectedElementId = isSelected ? null : el.id,
            ),
            child: buildContent(isHover: isHover),
          );
        },
      ),
    );
  }

  Widget _buildElementEditor() {
    final el = _elements.firstWhere(
      (e) => e.id == _selectedElementId,
      orElse: () => _elements.first,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade200, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit, color: Colors.blue.shade600, size: 20),
              const SizedBox(width: 8),
              Text(
                'Chỉnh: ${el.label}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => setState(() => _selectedElementId = null),
              ),
            ],
          ),
          const Divider(),

          // Visibility
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hiển thị', style: TextStyle(fontSize: 14)),
            value: el.visible,
            activeThumbColor: Colors.green,
            onChanged: (v) => _updateElement(el.id, visible: v),
          ),

          // Font Size / QR-Barcode Size
          Row(
            children: [
              Text(
                el.id == 'qr_code' ? 'Kích thước QR/Barcode:' : 'Cỡ chữ:',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(width: 8),
              Text(
                '${el.fontSize.toStringAsFixed(1)}x',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              Expanded(
                child: Slider(
                  value: el.fontSize,
                  min: el.id == 'qr_code' ? 0.6 : 0.5,
                  max: el.id == 'qr_code' ? 4.0 : 4.0,
                  divisions: el.id == 'qr_code' ? 34 : 35,
                  onChanged: (v) => _updateElement(el.id, fontSize: v),
                ),
              ),
            ],
          ),

          // Spacing (khoảng cách dưới)
          Row(
            children: [
              const Text('Khoảng cách:', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Text(
                '${el.spacing.round()}px',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
              Expanded(
                child: Slider(
                  value: el.spacing,
                  min: 0,
                  max: 20,
                  divisions: 20,
                  activeColor: Colors.orange,
                  onChanged: (v) => _updateElement(el.id, spacing: v),
                ),
              ),
            ],
          ),

          // Bold + Alignment
          Row(
            children: [
              FilterChip(
                label: const Text('Đậm'),
                selected: el.bold,
                onSelected: (v) => _updateElement(el.id, bold: v),
                selectedColor: Colors.blue.shade100,
              ),
              const SizedBox(width: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'left',
                    icon: Icon(Icons.format_align_left, size: 16),
                  ),
                  ButtonSegment(
                    value: 'center',
                    icon: Icon(Icons.format_align_center, size: 16),
                  ),
                  ButtonSegment(
                    value: 'right',
                    icon: Icon(Icons.format_align_right, size: 16),
                  ),
                ],
                selected: {el.align},
                onSelectionChanged: (s) =>
                    _updateElement(el.id, align: s.first),
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
            ],
          ),

          if (el.id != 'qr_code') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Kiểu chữ:', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'A', label: Text('A')),
                    ButtonSegment(value: 'B', label: Text('B')),
                  ],
                  selected: {el.fontType},
                  onSelectionChanged: (s) =>
                      _updateElement(el.id, fontType: s.first),
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                ),
              ],
            ),
          ],

          // Prefix (tiền tố cho mọi element text)
          if (el.id != 'qr_code' && el.id != 'shop_info') ...[
            const SizedBox(height: 12),
            Builder(
              builder: (context) {
                // Get or create controller for this element
                _prefixControllers.putIfAbsent(
                  el.id,
                  () => TextEditingController(text: el.prefix),
                );
                final ctrl = _prefixControllers[el.id]!;
                // Sync text if element prefix changed externally
                if (ctrl.text != el.prefix) {
                  ctrl.text = el.prefix;
                }
                return TextField(
                  controller: ctrl,
                  decoration: InputDecoration(
                    labelText: 'Tiền tố (ký tự đầu)',
                    hintText: el.id.contains('price') ? 'VD: KPK: hoặc Giá: ' : 'VD: IMEI: ',
                    helperText: 'Nhập ký tự hiện trước nội dung',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (v) => _updateElement(el.id, prefix: v),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRowActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.view_agenda, color: Colors.teal.shade600, size: 20),
              const SizedBox(width: 8),
              Text(
                'Gộp/Tách dòng',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.teal.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Quick presets
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _presetChip('IMEI + QR cùng dòng', () {
                _updateElement(
                  'imei',
                  row: 5,
                  col: 0,
                  flex: 0.6,
                  align: 'left',
                );
                _updateElement('qr_code', row: 5, col: 1, flex: 0.4);
              }, Icons.horizontal_distribute),

              _presetChip('IMEI riêng, QR riêng', () {
                _updateElement(
                  'imei',
                  row: 5,
                  col: 0,
                  flex: 1.0,
                  align: 'center',
                );
                _updateElement('qr_code', row: 6, col: 0, flex: 1.0);
                _updateElement('shop_info', row: 7, col: 0, flex: 1.0);
              }, Icons.view_agenda),

              _presetChip('KPK + CPK cùng dòng', () {
                _updateElement(
                  'price_kpk',
                  row: 3,
                  col: 0,
                  flex: 0.5,
                  align: 'right',
                );
                _updateElement(
                  'price_cpk',
                  row: 3,
                  col: 1,
                  flex: 0.5,
                  align: 'left',
                );
              }, Icons.horizontal_distribute),

              _presetChip('KPK, CPK riêng dòng', () {
                _updateElement(
                  'price_kpk',
                  row: 3,
                  col: 0,
                  flex: 1.0,
                  align: 'center',
                );
                _updateElement(
                  'price_cpk',
                  row: 4,
                  col: 0,
                  flex: 1.0,
                  align: 'center',
                );
              }, Icons.view_agenda),

              _presetChip('Không khoảng cách', () {
                for (final el in _elements) {
                  _updateElement(el.id, spacing: 0);
                }
              }, Icons.compress),

              _presetChip('Thoáng hơn', () {
                for (final el in _elements) {
                  _updateElement(el.id, spacing: 6);
                }
              }, Icons.expand),
            ],
          ),

          const Divider(height: 24),

          // Individual element toggles
          Text(
            'Ẩn/Hiện từng phần:',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _elements
                .map(
                  (el) => FilterChip(
                    label: Text(el.label, style: const TextStyle(fontSize: 12)),
                    selected: el.visible,
                    onSelected: (v) => _updateElement(el.id, visible: v),
                    selectedColor: Colors.blue.shade100,
                    checkmarkColor: Colors.blue,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _presetChip(String label, VoidCallback onTap, IconData icon) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: Colors.teal),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
      backgroundColor: Colors.teal.shade50,
      side: BorderSide(color: Colors.teal.shade200),
    );
  }

  void _updateElement(
    String id, {
    bool? visible,
    double? fontSize,
    bool? bold,
    String? fontType,
    String? align,
    String? prefix,
    int? row,
    int? col,
    double? flex,
    double? spacing,
  }) {
    setState(() {
      final idx = _elements.indexWhere((e) => e.id == id);
      if (idx >= 0) {
        _elements[idx] = _elements[idx].copyWith(
          visible: visible,
          fontSize: fontSize,
          bold: bold,
          fontType: fontType,
          align: align,
          prefix: prefix,
          row: row,
          col: col,
          flex: flex,
          spacing: spacing,
        );
      }
    });
    _scheduleAutoSave();
  }

  // ===== TAB 2: Shop Settings =====
  Widget _buildShopSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Thông tin Shop trên tem', Icons.store),
          const SizedBox(height: 12),
          _buildTextField(
            _shopNameCtrl,
            'Tên Shop',
            'VD: HULUCA MOBILE',
            Icons.store,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            _hotlineCtrl,
            'Hotline',
            'VD: 0909 123 456',
            Icons.phone,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            _sloganCtrl,
            'Slogan',
            'VD: Cam kết giá tốt nhất',
            Icons.format_quote,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            _addressCtrl,
            'Địa chỉ (tùy chọn)',
            'VD: 123 ABC, Q1',
            Icons.location_on,
          ),

          const SizedBox(height: 24),
          _sectionTitle('Công thức tính giá CPK', Icons.calculate),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTextField(
                  _cpkFormulaCtrl,
                  'Công thức',
                  'price + 500000',
                  Icons.functions,
                ),
                const SizedBox(height: 8),
                Text(
                  '• "price + 500000" = Giá bán + 500k\n'
                  '• "price * 1.05" = Giá bán + 5%',
                  style: AppTextStyles.caption.copyWith(
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          _sectionTitle('Dòng cố định trên tem', Icons.text_fields),
          const SizedBox(height: 8),
          Text(
            'Các dòng này luôn hiện trên tem',
            style: AppTextStyles.caption.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          _buildTextField(
            _fixedLine1Ctrl,
            'Dòng 1',
            'VD: Cam kết chính hãng',
            Icons.text_format,
          ),
          const SizedBox(height: 8),
          _buildTextField(
            _fixedLine2Ctrl,
            'Dòng 2',
            'VD: Đổi trả 7 ngày',
            Icons.text_format,
          ),
          const SizedBox(height: 8),
          _buildTextField(
            _fixedLine3Ctrl,
            'Dòng 3',
            'VD: Trả góp 0%',
            Icons.text_format,
          ),

          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.blue),
        const SizedBox(width: 8),
        Text(
          title,
          style: AppTextStyles.subtitle1.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String label,
    String hint,
    IconData icon, {
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }
}
