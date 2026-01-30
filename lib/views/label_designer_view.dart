import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/label_template_model.dart';
import '../services/label_settings_service.dart';
import '../services/notification_service.dart';
import '../theme/app_text_styles.dart';
import '../l10n/app_localizations.dart';

/// Model cho từng element trong tem
class LabelElement {
  final String id;
  String label;
  bool visible;
  double fontSize;
  bool bold;
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
    align: align ?? this.align,
    order: order ?? this.order,
    prefix: prefix ?? this.prefix,
    row: row ?? this.row,
    col: col ?? this.col,
    flex: flex ?? this.flex,
    spacing: spacing ?? this.spacing,
  );
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
  bool _didLoad = false;

  List<LabelElement> _elements = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _selectedElementId;

  // Paper Size: '58', '72', '80' (mm) hoặc '2x4', '3x4', '4x6' (inch)
  String _paperSize = '80';

  // Code Type: 'qr' hoặc 'barcode'
  String _codeType = 'qr';

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

  List<LabelElement> _buildDefaultElements(AppLocalizations loc) => [
        LabelElement(
          id: 'name',
          label: loc.labelElementName,
          fontSize: 1.4,
          bold: true,
          row: 0,
          col: 0,
          flex: 1.0,
          spacing: 2,
        ),
        LabelElement(
          id: 'detail',
          label: loc.labelElementDetail,
          fontSize: 1.0,
          bold: true,
          row: 1,
          col: 0,
          flex: 1.0,
          spacing: 4,
        ),
        LabelElement(
          id: 'price_kpk',
          label: loc.labelElementPriceKpk,
          fontSize: 1.2,
          bold: true,
          row: 2,
          col: 0,
          flex: 1.0,
          prefix: loc.priceKpkPrefix,
          spacing: 2,
        ),
        LabelElement(
          id: 'price_cpk',
          label: loc.labelElementPriceCpk,
          fontSize: 1.2,
          bold: true,
          row: 3,
          col: 0,
          flex: 1.0,
          prefix: loc.priceCpkPrefix,
          spacing: 4,
        ),
        LabelElement(
          id: 'label_note',
          label: loc.labelElementLabelNote,
          fontSize: 0.9,
          bold: false,
          row: 4,
          col: 0,
          flex: 1.0,
          spacing: 2,
        ),
        LabelElement(
          id: 'imei',
          label: loc.labelElementImei,
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
          label: loc.labelElementQr,
          fontSize: 1.0,
          bold: false,
          row: 5,
          col: 1,
          flex: 0.4,
          spacing: 4,
        ),
        LabelElement(
          id: 'shop_info',
          label: loc.labelElementShop,
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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoad) return;
    _didLoad = true;
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
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

  Future<void> _loadAllData() async {
    await Future.wait([_loadElements(), _loadShopSettings()]);
  }

  Future<void> _loadElements() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_prefsKey);
    final loc = AppLocalizations.of(context)!;
    final defaults = _buildDefaultElements(loc);

    // Load paper size
    _paperSize = prefs.getString('label_paper_size') ?? '80';

    // Load code type (qr or barcode)
    _codeType = prefs.getString('label_code_type') ?? 'qr';

    if (jsonStr != null) {
      try {
        final List<dynamic> jsonList = jsonDecode(jsonStr);
        final loaded = jsonList.map((e) => LabelElement.fromJson(e)).toList();
        final loadedMap = {for (final el in loaded) el.id: el};
        _elements = [
          for (final def in defaults)
            if (loadedMap.containsKey(def.id))
              loadedMap[def.id]!.copyWith(label: def.label)
            else
              def,
          ...loaded.where((el) => !defaults.any((d) => d.id == el.id)),
        ];
      } catch (e) {
        _elements = defaults;
      }
    } else {
      _elements = defaults;
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
      if (_fixedLine1Ctrl.text.trim().isNotEmpty)
        fixedLines.add(_fixedLine1Ctrl.text.trim());
      if (_fixedLine2Ctrl.text.trim().isNotEmpty)
        fixedLines.add(_fixedLine2Ctrl.text.trim());
      if (_fixedLine3Ctrl.text.trim().isNotEmpty)
        fixedLines.add(_fixedLine3Ctrl.text.trim());

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
                    final loc = AppLocalizations.of(context)!;
                    _elements = _buildDefaultElements(loc);
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
              colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
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
                    ButtonSegment(value: '58', label: Text('58mm')),
                    ButtonSegment(value: '72', label: Text('72mm')),
                    ButtonSegment(value: '80', label: Text('80mm')),
                  ],
                  selected: {_paperSize.contains('x') ? '80' : _paperSize},
                  onSelectionChanged: (s) =>
                      setState(() => _paperSize = s.first),
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected) &&
                          !_paperSize.contains('x'))
                        return Colors.orange;
                      return null;
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected) &&
                          !_paperSize.contains('x'))
                        return Colors.white;
                      return null;
                    }),
                  ),
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
                  selected: {_paperSize.contains('x') ? _paperSize : '2x3'},
                  onSelectionChanged: (s) =>
                      setState(() => _paperSize = s.first),
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected) &&
                          _paperSize.contains('x'))
                        return Colors.orange;
                      return null;
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected) &&
                          _paperSize.contains('x'))
                        return Colors.white;
                      return null;
                    }),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Code Type Selection (QR vs Barcode)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.purple.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.purple.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.qr_code, color: Colors.purple.shade700),
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
                        value: 'qr',
                        label: Text('QR Code'),
                        icon: Icon(Icons.qr_code_2, size: 18),
                      ),
                      ButtonSegment(
                        value: 'barcode',
                        label: Text('Barcode'),
                        icon: Icon(Icons.view_week, size: 18),
                      ),
                    ],
                    selected: {_codeType},
                    onSelectionChanged: (s) =>
                        setState(() => _codeType = s.first),
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith((
                        states,
                      ) {
                        if (states.contains(WidgetState.selected))
                          return Colors.purple;
                        return null;
                      }),
                      foregroundColor: WidgetStateProperty.resolveWith((
                        states,
                      ) {
                        if (states.contains(WidgetState.selected))
                          return Colors.white;
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
                    '🤏 Nhấn giữ rồi kéo thả để đổi vị trí\n'
                    '🔀 Gộp/tách dòng ở bảng điều khiển bên dưới',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                  ),
                ),
              ],
            ),
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

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withValues(alpha: 0.2),
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
                colors: [Colors.purple.shade100, Colors.purple.shade50],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.label, color: Colors.purple.shade600, size: 20),
                const SizedBox(width: 8),
                Text(
                  'MẪU TEM',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.purple.shade700,
                  ),
                ),
                const Spacer(),
                Text(
                  'Nhấn để chọn',
                  style: TextStyle(fontSize: 11, color: Colors.purple.shade400),
                ),
              ],
            ),
          ),

          // Preview Content
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: sortedRows.map((rowIndex) {
                final rowElements = rowMap[rowIndex]!;
                rowElements.sort((a, b) => a.col.compareTo(b.col));

                // Calculate spacing from first element in row
                final spacing = rowElements.first.spacing;

                return Padding(
                  padding: EdgeInsets.only(bottom: spacing),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: rowElements.map((el) {
                      return Expanded(
                        flex: (el.flex * 10).round(),
                        child: _buildDraggablePreviewElement(el),
                      );
                    }).toList(),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraggablePreviewElement(LabelElement el) {
    return DragTarget<String>(
      onWillAccept: (data) => data != null && data != el.id,
      onAccept: (data) => _swapElementPosition(data, el.id),
      builder: (context, candidateData, rejectedData) {
        final highlight = candidateData.isNotEmpty;
        return LongPressDraggable<String>(
          data: el.id,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.9,
              child: _buildPreviewElement(el),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: _buildPreviewElement(el),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: highlight ? Colors.teal : Colors.transparent,
                width: 1.2,
              ),
              color:
                  highlight ? Colors.teal.withValues(alpha: 0.08) : Colors.transparent,
            ),
            child: _buildPreviewElement(el),
          ),
        );
      },
    );
  }

  void _swapElementPosition(String draggedId, String targetId) {
    final draggedIndex = _elements.indexWhere((e) => e.id == draggedId);
    final targetIndex = _elements.indexWhere((e) => e.id == targetId);
    if (draggedIndex < 0 || targetIndex < 0) return;

    final dragged = _elements[draggedIndex];
    final target = _elements[targetIndex];

    setState(() {
      _elements[draggedIndex] = dragged.copyWith(
        row: target.row,
        col: target.col,
      );
      _elements[targetIndex] = target.copyWith(
        row: dragged.row,
        col: dragged.col,
      );
      _selectedElementId = draggedId;
    });
  }

  Widget _buildPreviewElement(LabelElement el) {
    final isSelected = _selectedElementId == el.id;
    String text = '';
    Widget? child;

    switch (el.id) {
      case 'name':
        text = 'IPHONE 15 PRO MAX';
        break;
      case 'detail':
        text = '256GB ĐEN 98%';
        break;
      case 'price_kpk':
        text = '${el.prefix}25,900K';
        break;
      case 'price_cpk':
        text = '${el.prefix}26,400K';
        break;
      case 'label_note':
        text = 'BẢO HÀNH 6 THÁNG';
        break;
      case 'imei':
        text = '${el.prefix}3598765...123';
        break;
      case 'qr_code':
        child = Icon(
          Icons.qr_code_2,
          size: 36 * el.fontSize,
          color: isSelected ? Colors.purple : Colors.black87,
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

    const baseFontSize = 13.0;
    final alignment = el.align == 'left'
        ? TextAlign.left
        : el.align == 'right'
        ? TextAlign.right
        : TextAlign.center;

    return GestureDetector(
      onTap: () =>
          setState(() => _selectedElementId = isSelected ? null : el.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? Colors.purple.shade50 : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? Colors.purple : Colors.transparent,
            width: isSelected ? 2 : 0,
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
                color: isSelected ? Colors.purple.shade700 : Colors.black87,
              ),
            ),
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
        border: Border.all(color: Colors.purple.shade200, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit, color: Colors.purple.shade600, size: 20),
              const SizedBox(width: 8),
              Text(
                'Chỉnh: ${el.label}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.purple.shade700,
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
            activeColor: Colors.green,
            onChanged: (v) => _updateElement(el.id, visible: v),
          ),

          // Font Size
          Row(
            children: [
              const Text('Cỡ chữ:', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Text(
                '${el.fontSize.toStringAsFixed(1)}x',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.purple,
                ),
              ),
              Expanded(
                child: Slider(
                  value: el.fontSize,
                  min: 0.5,
                  max: 2.0,
                  divisions: 15,
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
                style: TextStyle(
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
                selectedColor: Colors.purple.shade100,
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

          // Prefix (for price/imei)
          if (el.id.contains('price') || el.id == 'imei') ...[
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
                    labelText: 'Tiền tố',
                    hintText: 'VD: Giá: ',
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
                  row: 4,
                  col: 0,
                  flex: 0.6,
                  align: 'left',
                );
                _updateElement('qr_code', row: 4, col: 1, flex: 0.4);
              }, Icons.horizontal_distribute),

              _presetChip('IMEI riêng, QR riêng', () {
                _updateElement(
                  'imei',
                  row: 4,
                  col: 0,
                  flex: 1.0,
                  align: 'center',
                );
                _updateElement('qr_code', row: 5, col: 0, flex: 1.0);
                _updateElement('shop_info', row: 6, col: 0, flex: 1.0);
              }, Icons.view_agenda),

              _presetChip('KPK + CPK cùng dòng', () {
                _updateElement(
                  'price_kpk',
                  row: 2,
                  col: 0,
                  flex: 0.5,
                  align: 'right',
                );
                _updateElement(
                  'price_cpk',
                  row: 2,
                  col: 1,
                  flex: 0.5,
                  align: 'left',
                );
              }, Icons.horizontal_distribute),

              _presetChip('KPK, CPK riêng dòng', () {
                _updateElement(
                  'price_kpk',
                  row: 2,
                  col: 0,
                  flex: 1.0,
                  align: 'center',
                );
                _updateElement(
                  'price_cpk',
                  row: 3,
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
                    selectedColor: Colors.purple.shade100,
                    checkmarkColor: Colors.purple,
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
          align: align,
          prefix: prefix,
          row: row,
          col: col,
          flex: flex,
          spacing: spacing,
        );
      }
    });
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
        Icon(icon, size: 20, color: Colors.purple),
        const SizedBox(width: 8),
        Text(
          title,
          style: AppTextStyles.subtitle1.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.purple,
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
