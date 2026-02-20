import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:barcode/barcode.dart' as bc;
import 'package:barcode_image/barcode_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/money_utils.dart';
import '../data/db_helper.dart';
import '../models/printer_types.dart';
import '../models/product_model.dart';
import '../services/unified_printer_service.dart';
import '../services/label_settings_service.dart';
import '../widgets/printer_selection_dialog.dart';

// ══════════════════════════════════════════════════════════════════════════════
// LABEL ELEMENT MODEL
// ══════════════════════════════════════════════════════════════════════════════

enum LabelElementType { text, qr, barcode }

class LabelElement {
  LabelElement({
    required this.id,
    required this.type,
    required this.xMm,
    required this.yMm,
    required this.widthMm,
    required this.heightMm,
    this.rotationDeg = 0,
    this.text = 'TEXT',
    this.fontSizeMm = 3.5,
    this.bold = true,
    this.visible = true,
    this.prefix = '',
  });

  final String id;
  final LabelElementType type;
  double xMm;
  double yMm;
  double widthMm;
  double heightMm;
  int rotationDeg;
  String text;
  double fontSizeMm;
  bool bold;
  bool visible;
  String prefix;

  LabelElement copyWith({
    double? xMm,
    double? yMm,
    double? widthMm,
    double? heightMm,
    int? rotationDeg,
    String? text,
    double? fontSizeMm,
    bool? bold,
    bool? visible,
    String? prefix,
  }) {
    return LabelElement(
      id: id,
      type: type,
      xMm: xMm ?? this.xMm,
      yMm: yMm ?? this.yMm,
      widthMm: widthMm ?? this.widthMm,
      heightMm: heightMm ?? this.heightMm,
      rotationDeg: rotationDeg ?? this.rotationDeg,
      text: text ?? this.text,
      fontSizeMm: fontSizeMm ?? this.fontSizeMm,
      bold: bold ?? this.bold,
      visible: visible ?? this.visible,
      prefix: prefix ?? this.prefix,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'xMm': xMm,
    'yMm': yMm,
    'widthMm': widthMm,
    'heightMm': heightMm,
    'rotationDeg': rotationDeg,
    'text': text,
    'fontSizeMm': fontSizeMm,
    'bold': bold,
    'visible': visible,
    'prefix': prefix,
  };

  static LabelElement fromJson(Map<String, dynamic> json) {
    return LabelElement(
      id: json['id'] as String,
      type: LabelElementType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => LabelElementType.text,
      ),
      xMm: (json['xMm'] as num).toDouble(),
      yMm: (json['yMm'] as num).toDouble(),
      widthMm: (json['widthMm'] as num).toDouble(),
      heightMm: (json['heightMm'] as num).toDouble(),
      rotationDeg: json['rotationDeg'] as int? ?? 0,
      text: json['text'] as String? ?? 'TEXT',
      fontSizeMm: (json['fontSizeMm'] as num?)?.toDouble() ?? 3.5,
      bold: json['bold'] as bool? ?? true,
      visible: json['visible'] as bool? ?? true,
      prefix: json['prefix'] as String? ?? '',
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MAIN VIEW
// ══════════════════════════════════════════════════════════════════════════════

class PtyPrintDesignerView extends StatefulWidget {
  const PtyPrintDesignerView({super.key});

  @override
  State<PtyPrintDesignerView> createState() => _PtyPrintDesignerViewState();
}

class _PtyPrintDesignerViewState extends State<PtyPrintDesignerView>
    with SingleTickerProviderStateMixin {
  // ─────────────────────────────────────────────────────────────────────────────
  // STATE
  // ─────────────────────────────────────────────────────────────────────────────

  late TabController _tabController;
  final _db = DBHelper();

  // Inventory
  final TextEditingController _inventorySearchCtrl = TextEditingController();
  bool _inventoryLoading = false;
  List<Product> _inventoryItems = [];
  List<Product> _filteredInventory = [];
  final Set<String> _selectedKeys = {};

  // Print settings
  bool _isPrinting = false;
  bool _showPriceCPK = true;
  bool _useCustomCPK = false;
  bool _autoCut = false; // Tắt cắt tự động mặc định
  int _feedLines = 1; // Số dòng đẩy giấy sau in
  final TextEditingController _priceCPKCtrl = TextEditingController();
  ShopLabelSettings? _shopSettings;

  // Label config - editable
  double _labelWidthMm = 50;
  double _labelHeightMm = 30;
  double _dpi = 203;
  final TextEditingController _widthCtrl = TextEditingController(text: '50');
  final TextEditingController _heightCtrl = TextEditingController(text: '30');
  final TextEditingController _dpiCtrl = TextEditingController(text: '203');

  double _marginLeftMm = 2;
  double _marginTopMm = 2;
  double _marginRightMm = 2;
  double _marginBottomMm = 2;

  // Grid settings
  bool _showGrid = true;
  double _gridSpacingMm = 5.0; // 5mm grid spacing

  // Overflow area - vùng giấy thừa cho phép kéo ra ngoài
  double _overflowMm = 10.0; // 10mm mỗi bên

  // Zoom settings - tùy chỉnh phóng to/thu nhỏ
  double _zoomScale = 1.0;
  static const double _minZoom = 0.5;
  static const double _maxZoom = 3.0;
  final TransformationController _transformController = TransformationController();

  // Auto-save
  Timer? _saveTimer;
  static const String _settingsKey = 'pty_designer_settings_v2';

  // Elements & selection
  LabelElement? _selectedElement;
  bool _isDragging = false;

  final Product _sampleProduct = Product(
    id: 0,
    firestoreId: 'sample_0001',
    name: 'IPHONE 15 PRO MAX',
    brand: 'APPLE',
    model: 'A3108',
    imei: '359876543210123',
    cost: 18000000,
    price: 25900000,
    condition: '98%',
    description: '',
    createdAt: DateTime.now().millisecondsSinceEpoch,
    quantity: 1,
    color: 'ĐEN',
    capacity: '256GB',
    labelInfo: 'Bảo hành 6T',
  );

  final List<LabelElement> _elements = [
    LabelElement(
      id: 'title',
      type: LabelElementType.text,
      xMm: 2,
      yMm: 2,
      widthMm: 46,
      heightMm: 5,
      text: '{{name}}',
      fontSizeMm: 3.5,
      bold: true,
    ),
    LabelElement(
      id: 'detail',
      type: LabelElementType.text,
      xMm: 2,
      yMm: 7,
      widthMm: 30,
      heightMm: 3,
      text: '{{capacity}} {{color}} {{condition}}',
      fontSizeMm: 2.5,
      bold: false,
    ),
    LabelElement(
      id: 'price',
      type: LabelElementType.text,
      xMm: 2,
      yMm: 11,
      widthMm: 18,
      heightMm: 4,
      text: '{{price}}',
      fontSizeMm: 3.0,
      bold: true,
    ),
    LabelElement(
      id: 'priceCPK',
      type: LabelElementType.text,
      xMm: 21,
      yMm: 11,
      widthMm: 18,
      heightMm: 4,
      text: '{{priceCPK}}',
      fontSizeMm: 3.0,
      bold: true,
      visible: false,
    ),
    LabelElement(
      id: 'labelInfo',
      type: LabelElementType.text,
      xMm: 2,
      yMm: 16,
      widthMm: 28,
      heightMm: 4,
      text: '{{labelInfo}}',
      fontSizeMm: 2.5,
      bold: false,
    ),
    LabelElement(
      id: 'imei',
      type: LabelElementType.text,
      xMm: 2,
      yMm: 20,
      widthMm: 28,
      heightMm: 3,
      text: '{{imei}}',
      fontSizeMm: 2.0,
      bold: false,
      visible: false,
    ),
    LabelElement(
      id: 'shopInfo',
      type: LabelElementType.text,
      xMm: 2,
      yMm: 27,
      widthMm: 46,
      heightMm: 3,
      text: 'HULUCA - 0909.xxx.xxx',
      fontSizeMm: 2.0,
      bold: false,
      visible: false,
    ),
    LabelElement(
      id: 'qr',
      type: LabelElementType.qr,
      xMm: 34,
      yMm: 7,
      widthMm: 13,
      heightMm: 13,
    ),
    LabelElement(
      id: 'barcode',
      type: LabelElementType.barcode,
      xMm: 2,
      yMm: 22,
      widthMm: 28,
      heightMm: 6,
      visible: false,
    ),
  ];

  // ─────────────────────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadInventory();
    _loadLabelSettings();
    _loadDesignerSettings();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _tabController.dispose();
    _inventorySearchCtrl.dispose();
    _priceCPKCtrl.dispose();
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    _dpiCtrl.dispose();
    _transformController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // SETTINGS PERSISTENCE
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> _loadDesignerSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_settingsKey);
      if (jsonStr == null) return;

      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (!mounted) return;

      setState(() {
        _labelWidthMm = (data['labelWidthMm'] as num?)?.toDouble() ?? 50;
        _labelHeightMm = (data['labelHeightMm'] as num?)?.toDouble() ?? 30;
        _dpi = (data['dpi'] as num?)?.toDouble() ?? 203;

        // Guard against corrupted settings (0 or negative values)
        if (_labelWidthMm <= 0) _labelWidthMm = 50;
        if (_labelHeightMm <= 0) _labelHeightMm = 30;
        if (_dpi <= 0) _dpi = 203;
        _marginLeftMm = (data['marginLeftMm'] as num?)?.toDouble() ?? 2;
        _marginTopMm = (data['marginTopMm'] as num?)?.toDouble() ?? 2;
        _marginRightMm = (data['marginRightMm'] as num?)?.toDouble() ?? 2;
        _marginBottomMm = (data['marginBottomMm'] as num?)?.toDouble() ?? 2;
        _autoCut = data['autoCut'] as bool? ?? false;
        _feedLines = data['feedLines'] as int? ?? 1;
        _showGrid = data['showGrid'] as bool? ?? true;
        _gridSpacingMm = (data['gridSpacingMm'] as num?)?.toDouble() ?? 5.0;
        _overflowMm = (data['overflowMm'] as num?)?.toDouble() ?? 10.0;

        // Load elements - merge với default để đảm bảo có đủ phần tử mới
        final elementsJson = data['elements'] as List<dynamic>?;
        if (elementsJson != null && elementsJson.isNotEmpty) {
          // Load saved elements
          final savedElements = <String, LabelElement>{};
          for (final ej in elementsJson) {
            final el = LabelElement.fromJson(ej as Map<String, dynamic>);
            savedElements[el.id] = el;
          }

          // Merge với default - giữ vị trí và settings của saved, thêm mới nếu chưa có
          for (int i = 0; i < _elements.length; i++) {
            final defaultEl = _elements[i];
            if (savedElements.containsKey(defaultEl.id)) {
              _elements[i] = savedElements[defaultEl.id]!;
            }
            // Nếu không có trong saved thì giữ nguyên default
          }
        }

        // Update text controllers
        _widthCtrl.text = _labelWidthMm.toStringAsFixed(0);
        _heightCtrl.text = _labelHeightMm.toStringAsFixed(0);
        _dpiCtrl.text = _dpi.toStringAsFixed(0);
      });
    } catch (e) {
      debugPrint('Error loading PTY designer settings: $e');
    }
  }

  Future<void> _saveDesignerSettings({bool showNotification = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'labelWidthMm': _labelWidthMm,
        'labelHeightMm': _labelHeightMm,
        'dpi': _dpi,
        'marginLeftMm': _marginLeftMm,
        'marginTopMm': _marginTopMm,
        'marginRightMm': _marginRightMm,
        'marginBottomMm': _marginBottomMm,
        'autoCut': _autoCut,
        'feedLines': _feedLines,
        'showGrid': _showGrid,
        'gridSpacingMm': _gridSpacingMm,
        'overflowMm': _overflowMm,
        'elements': _elements.map((e) => e.toJson()).toList(),
      };
      await prefs.setString(_settingsKey, jsonEncode(data));

      if (showNotification && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã lưu cài đặt'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving PTY designer settings: $e');
    }
  }

  void _scheduleAutoSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      _saveDesignerSettings();
    });
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // DATA LOADING
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> _loadLabelSettings() async {
    final service = LabelSettingsService();
    final settings = await service.getShopLabelSettings();
    if (!mounted) return;
    setState(() => _shopSettings = settings);
  }

  Future<void> _loadInventory() async {
    setState(() => _inventoryLoading = true);
    try {
      final items = await _db.getInStockProducts();
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() {
        _inventoryItems = items;
        _filteredInventory = List<Product>.from(items);
        _inventoryLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _inventoryLoading = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────────

  String _keyForProduct(Product p) =>
      p.firestoreId ?? (p.id != null ? 'id_${p.id}' : p.name);

  List<Product> get _selectedProducts => _inventoryItems
      .where((p) => _selectedKeys.contains(_keyForProduct(p)))
      .toList();

  Product get _previewProduct =>
      _selectedProducts.isNotEmpty ? _selectedProducts.first : _sampleProduct;

  double _mmToPx(double mm) => mm * _dpi / 25.4;
  Size get _labelPxSize =>
      Size(_mmToPx(_labelWidthMm), _mmToPx(_labelHeightMm));

  Widget _sizeStepButton(IconData icon, VoidCallback onPressed) {
    return SizedBox(
      height: 22,
      width: 28,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          side: BorderSide(color: Colors.grey.shade300),
        ),
        onPressed: onPressed,
        child: Icon(icon, size: 16),
      ),
    );
  }

  Future<double> _computePxPerMmForPrint(double labelWidthMm) async {
    // Trả về px/mm khớp khổ giấy để tránh bị resize sau khi render
    final basePxPerMm = _mmToPx(1);
    try {
      final prefs = await SharedPreferences.getInstance();
      final paperSizeStr = prefs.getString('label_paper_size') ?? '80';
      int? maxDots;
      switch (paperSizeStr) {
        case '50':
        case '58':
          maxDots = 384;
          break;
        case '72':
          maxDots = 512;
          break;
        default:
          maxDots = 576;
      }
      if (labelWidthMm > 0 && maxDots != null && maxDots > 0) {
        final fitPxPerMm = maxDots / labelWidthMm;
        // Không phóng to quá DPI gốc; chỉ thu nhỏ để khớp khổ giấy
        return fitPxPerMm < basePxPerMm ? fitPxPerMm : basePxPerMm;
      }
    } catch (e) {
      debugPrint('PTY_PRINT: _computePxPerMmForPrint error: $e');
    }
    return basePxPerMm; // fallback dùng DPI hiện tại
  }

  void _selectElement(LabelElement? el) {
    if (_selectedElement?.id != el?.id) {
      HapticFeedback.selectionClick();
      setState(() => _selectedElement = el);
    }
  }

  void _updateElement(LabelElement el, void Function(LabelElement e) update) {
    setState(() => update(el));
    _scheduleAutoSave();
  }

  int _calculateCPK(Product product) {
    if (_useCustomCPK) {
      final parsed =
          int.tryParse(_priceCPKCtrl.text.replaceAll(RegExp(r'[.,]'), '')) ?? 0;
      return parsed;
    }
    final price = product.price;
    final settings = _shopSettings;
    if (settings != null) {
      return settings.calculateCPK(price);
    }
    return price + 500000;
  }

  String _resolveText(String template, Product product, {String prefix = ''}) {
    final priceCPK = _calculateCPK(product);
    final map = <String, String>{
      '{{name}}': product.name.toUpperCase(),
      '{{brand}}': product.brand.toUpperCase(),
      '{{model}}': (product.model ?? '').toUpperCase(),
      '{{imei}}': product.imei ?? '',
      '{{price}}': MoneyUtils.formatVND(product.price),
      '{{priceCPK}}': _showPriceCPK ? MoneyUtils.formatVND(priceCPK) : '',
      '{{capacity}}': (product.capacity ?? '').toUpperCase(),
      '{{color}}': (product.color ?? '').toUpperCase(),
      '{{condition}}': product.condition.toUpperCase(),
      '{{labelInfo}}': (product.labelInfo ?? '').toUpperCase(),
      '{{warranty}}': (product.warranty ?? '').toUpperCase(),
      '{{qty}}': product.quantity.toString(),
    };
    var result = template;
    map.forEach((key, value) {
      result = result.replaceAll(key, value);
    });
    // Thêm prefix vào đầu nếu có
    if (prefix.isNotEmpty && result.isNotEmpty) {
      return '$prefix$result';
    }
    return result;
  }

  String _resolveQrData(Product product) {
    final imei = product.imei?.trim();
    if (imei != null && imei.isNotEmpty) return 'IMEI:$imei';
    final fallback = product.firestoreId ?? (product.id?.toString() ?? 'NA');
    return 'check_inv:$fallback';
  }

  String _resolveBarcodeData(Product product) {
    final imei = product.imei?.trim();
    if (imei != null && imei.isNotEmpty) return imei;
    return product.id?.toString() ?? '0000';
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: _buildAppBar(colorScheme),
      // Dùng resizeToAvoidBottomInset để tránh overflow khi keyboard mở
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false, // Bottom được xử lý bởi bottomNavigationBar
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Tính toán flex dựa trên chiều cao màn hình
            final availableHeight = constraints.maxHeight;
            final isSmallScreen = availableHeight < 500;

            return Column(
              children: [
                // Canvas area - co giãn linh hoạt
                Expanded(
                  flex: isSmallScreen ? 1 : 2,
                  child: _buildCanvasArea(colorScheme),
                ),
                // Control panel - giới hạn chiều cao tối đa
                Expanded(
                  flex: isSmallScreen ? 2 : 3,
                  child: _buildControlPanel(colorScheme),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: _buildBottomActions(colorScheme),
    );
  }

  PreferredSizeWidget _buildAppBar(ColorScheme colorScheme) {
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 1,
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.onPrimary,
      title: const Text(
        'PTY Label Designer',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      actions: [
        IconButton(
          icon: Badge(
            label: Text('${_selectedKeys.length}'),
            isLabelVisible: _selectedKeys.isNotEmpty,
            child: const Icon(Icons.inventory_2_outlined),
          ),
          tooltip: 'Chọn sản phẩm từ kho',
          onPressed: _openInventorySelector,
        ),
        const SizedBox(width: 8),
      ],
      bottom: TabBar(
        controller: _tabController,
        labelColor: colorScheme.onPrimary,
        unselectedLabelColor: colorScheme.onPrimary.withOpacity(0.6),
        indicatorColor: colorScheme.onPrimary,
        tabs: const [
          Tab(icon: Icon(Icons.edit_outlined), text: 'Thiết kế'),
          Tab(icon: Icon(Icons.preview_outlined), text: 'Xem trước'),
        ],
      ),
    );
  }

  Widget _buildCanvasArea(ColorScheme colorScheme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Padding cho margin xung quanh
        const margin = 16.0;
        final availableHeight = constraints.maxHeight - (margin * 2);
        final availableWidth = constraints.maxWidth - (margin * 2);

        return Container(
          margin: const EdgeInsets.all(margin),
          child: TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildDesignCanvas(colorScheme, availableWidth, availableHeight),
              _buildPreviewCanvas(colorScheme, availableWidth, availableHeight),
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // DESIGN CANVAS
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildDesignCanvas(
    ColorScheme colorScheme, [
    double? maxWidth,
    double? maxHeight,
  ]) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = (maxWidth ?? constraints.maxWidth) - 32;
        final maxH = (maxHeight ?? constraints.maxHeight) - 32;
        // Đảm bảo scale không âm khi space quá nhỏ
        final rawScale = min(
          maxW / _labelPxSize.width,
          maxH / _labelPxSize.height,
        );
        final scale =
            (rawScale > 0 ? rawScale : 0.1) * 0.90; // Giảm còn 90% để có buffer
        final scaledSize = Size(
          _labelPxSize.width * scale,
          _labelPxSize.height * scale,
        );
        final pxPerMm = _mmToPx(1) * scale;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Label info header với zoom controls
            _buildLabelInfoHeader(colorScheme),
            const SizedBox(height: 8),
            // Canvas với InteractiveViewer để zoom/pan
            Expanded(
              child: InteractiveViewer(
                transformationController: _transformController,
                minScale: _minZoom,
                maxScale: _maxZoom,
                boundaryMargin: const EdgeInsets.all(100),
                onInteractionUpdate: (details) {
                  // Sync zoom scale với slider
                  final scale = _transformController.value.getMaxScaleOnAxis();
                  if (scale != _zoomScale) {
                    setState(() => _zoomScale = scale.clamp(_minZoom, _maxZoom));
                  }
                },
                child: Center(
                  child: Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.shadow.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(8),
                    child: GestureDetector(
                      onTapDown: (_) => _selectElement(null),
                      // Vùng bao gồm cả overflow (giấy thừa)
                      child: Container(
                        width: scaledSize.width + (_overflowMm * 2 * pxPerMm),
                        height: scaledSize.height + (_overflowMm * 2 * pxPerMm),
                        decoration: BoxDecoration(
                          // Vùng giấy thừa - màu xám nhạt
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                          // Vùng in chính (label) - nằm giữa
                          Positioned(
                            left: _overflowMm * pxPerMm,
                            top: _overflowMm * pxPerMm,
                            child: Container(
                              width: scaledSize.width,
                              height: scaledSize.height,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(
                                  color: colorScheme.primary,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(2),
                                boxShadow: [
                                  BoxShadow(
                                    color: colorScheme.primary.withOpacity(0.1),
                                    blurRadius: 4,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  // Grid lines (if enabled)
                                  if (_showGrid)
                                    CustomPaint(
                                      size: scaledSize,
                                      painter: _GridPainter(
                                        gridSpacingPx: _gridSpacingMm * pxPerMm,
                                        color: Colors.grey.withOpacity(0.3),
                                      ),
                                    ),
                                  // Margin guides
                                  CustomPaint(
                                    size: scaledSize,
                                    painter: _MarginGuidePainter(
                                      margins: EdgeInsets.fromLTRB(
                                        _marginLeftMm * pxPerMm,
                                        _marginTopMm * pxPerMm,
                                        _marginRightMm * pxPerMm,
                                        _marginBottomMm * pxPerMm,
                                      ),
                                      color: colorScheme.primary.withOpacity(
                                        0.2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Elements (only visible ones) - có thể kéo ra ngoài vùng in
                          ..._elements
                              .where((el) => el.visible)
                              .map(
                                (el) => _buildDraggableElement(
                                  el,
                                  pxPerMm,
                                  colorScheme,
                                  _overflowMm *
                                      pxPerMm, // offset for overflow area
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLabelInfoHeader(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Label size info
          Icon(Icons.straighten, size: 16, color: colorScheme.primary),
          const SizedBox(width: 4),
          Text(
            '${_labelWidthMm.toInt()}×${_labelHeightMm.toInt()}mm',
            style: TextStyle(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          Container(
            height: 20,
            width: 1,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: colorScheme.primary.withOpacity(0.3),
          ),
          // Zoom controls
          Icon(Icons.zoom_out, size: 16, color: colorScheme.primary),
          SizedBox(
            width: 100,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: colorScheme.primary,
                inactiveTrackColor: colorScheme.primary.withOpacity(0.3),
                thumbColor: colorScheme.primary,
              ),
              child: Slider(
                value: _zoomScale,
                min: _minZoom,
                max: _maxZoom,
                onChanged: (value) {
                  setState(() {
                    _zoomScale = value;
                    _updateTransformController();
                  });
                },
              ),
            ),
          ),
          Icon(Icons.zoom_in, size: 16, color: colorScheme.primary),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${(_zoomScale * 100).toInt()}%',
              style: TextStyle(
                color: colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Reset zoom button
          InkWell(
            onTap: () {
              setState(() {
                _zoomScale = 1.0;
                _updateTransformController();
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.fit_screen,
                size: 16,
                color: colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _updateTransformController() {
    // Cập nhật TransformationController khi zoom thay đổi
    _transformController.value = Matrix4.identity()..scale(_zoomScale);
  }

  Widget _buildDraggableElement(
    LabelElement el,
    double pxPerMm,
    ColorScheme colorScheme, [
    double overflowOffset = 0,
  ]) {
    // Tính vị trí có tính overflow offset
    final left = (el.xMm * pxPerMm) + overflowOffset;
    final top = (el.yMm * pxPerMm) + overflowOffset;
    final width = el.widthMm * pxPerMm;
    final height = el.heightMm * pxPerMm;
    final isSelected = _selectedElement?.id == el.id;

    // Kiểm tra element có nằm ngoài vùng in không
    final isOutsidePrintArea =
        el.xMm < 0 ||
        el.yMm < 0 ||
        el.xMm + el.widthMm > _labelWidthMm ||
        el.yMm + el.heightMm > _labelHeightMm;

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _selectElement(el),
        onPanStart: (_) {
          _selectElement(el);
          setState(() => _isDragging = true);
        },
        onPanUpdate: (details) {
          final deltaX = details.delta.dx / pxPerMm;
          final deltaY = details.delta.dy / pxPerMm;
          // Cho phép kéo ra ngoài vùng in, giới hạn bởi vùng overflow
          final minX = -_overflowMm;
          final minY = -_overflowMm;
          final maxX = _labelWidthMm + _overflowMm - el.widthMm;
          final maxY = _labelHeightMm + _overflowMm - el.heightMm;
          _updateElement(el, (e) {
            e.xMm = (e.xMm + deltaX).clamp(minX, maxX);
            e.yMm = (e.yMm + deltaY).clamp(minY, maxY);
          });
        },
        onPanEnd: (_) => setState(() => _isDragging = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: width,
          height: height,
          transform: Matrix4.rotationZ((el.rotationDeg * pi) / 180),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            // Màu nền khác khi nằm ngoài vùng in
            color: isOutsidePrintArea ? Colors.orange.shade50 : Colors.white,
            border: Border.all(
              color: isOutsidePrintArea
                  ? Colors.orange
                  : isSelected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
              width: isSelected ? 2 : 1,
              strokeAlign: BorderSide.strokeAlignOutside,
            ),
            borderRadius: BorderRadius.circular(2),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color:
                          (isOutsidePrintArea
                                  ? Colors.orange
                                  : colorScheme.primary)
                              .withOpacity(0.3),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Stack(
            children: [
              _buildElementContent(el, pxPerMm, colorScheme),
              // Icon cảnh báo nếu nằm ngoài vùng in
              if (isOutsidePrintArea)
                Positioned(
                  right: 2,
                  top: 2,
                  child: Icon(
                    Icons.warning_amber_rounded,
                    size: 12,
                    color: Colors.orange.shade700,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildElementContent(
    LabelElement el,
    double pxPerMm,
    ColorScheme colorScheme,
  ) {
    switch (el.type) {
      case LabelElementType.text:
        final resolvedText = _resolveText(
          el.text,
          _previewProduct,
          prefix: el.prefix,
        );
        return Container(
          padding: const EdgeInsets.all(2),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              resolvedText.isEmpty ? el.id.toUpperCase() : resolvedText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: el.fontSizeMm * pxPerMm * 0.3,
                fontWeight: el.bold ? FontWeight.bold : FontWeight.normal,
                color: Colors.black87,
              ),
            ),
          ),
        );

      case LabelElementType.qr:
        return Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(2),
          ),
          child: const Center(
            child: Icon(Icons.qr_code_2, color: Colors.black54),
          ),
        );

      case LabelElementType.barcode:
        return Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(2),
          ),
          child: CustomPaint(painter: _BarcodePlaceholderPainter()),
        );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // PREVIEW CANVAS
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildPreviewCanvas(
    ColorScheme colorScheme, [
    double? maxWidth,
    double? maxHeight,
  ]) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = (maxWidth ?? constraints.maxWidth) - 32;
        final maxH = (maxHeight ?? constraints.maxHeight) - 32;
        // Đảm bảo scale không âm
        final rawScale = min(
          maxW / _labelPxSize.width,
          maxH / _labelPxSize.height,
        );
        final scale = (rawScale > 0 ? rawScale : 0.1) * 0.90;
        final scaledSize = Size(
          _labelPxSize.width * scale,
          _labelPxSize.height * scale,
        );
        final pxPerMm = _mmToPx(1) * scale;

        return SingleChildScrollView(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildProductInfoChip(colorScheme),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.shadow.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Container(
                    width: scaledSize.width,
                    height: scaledSize.height,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: colorScheme.outline),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: CustomPaint(
                        size: scaledSize,
                        painter: _PreviewPainter(
                          elements: _elements.where((e) => e.visible).toList(),
                          product: _previewProduct,
                          pxPerMm: pxPerMm,
                          resolveText: _resolveText,
                          resolveQrData: _resolveQrData,
                          resolveBarcodeData: _resolveBarcodeData,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProductInfoChip(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.smartphone, size: 16, color: colorScheme.secondary),
          const SizedBox(width: 8),
          Text(
            _previewProduct.name,
            style: TextStyle(
              color: colorScheme.secondary,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // CONTROL PANEL
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildControlPanel(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _selectedElement != null
                  ? _buildElementEditor(colorScheme)
                  : _buildQuickSettings(colorScheme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickSettings(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Cài đặt nhanh',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            // Save button
            FilledButton.icon(
              onPressed: () => _saveDesignerSettings(showNotification: true),
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Lưu'),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Grid settings
        _buildGridSettings(colorScheme),
        const SizedBox(height: 16),
        // Paper size controls
        _buildPaperSizeSection(colorScheme),
        const SizedBox(height: 16),
        // Margin controls
        _buildMarginSection(colorScheme),
        const SizedBox(height: 16),
        // Elements visibility toggle
        _buildElementsVisibilitySection(colorScheme),
        const SizedBox(height: 16),
        // CPK settings
        _buildCPKSection(colorScheme),
        const SizedBox(height: 16),
        // Elements quick select
        _buildElementsQuickSelect(colorScheme),
      ],
    );
  }

  Widget _buildGridSettings(ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Grid toggle
            Row(
              children: [
                Icon(Icons.grid_4x4, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Lưới căn chỉnh',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                Switch(
                  value: _showGrid,
                  onChanged: (v) {
                    setState(() => _showGrid = v);
                    _scheduleAutoSave();
                  },
                ),
              ],
            ),
            if (_showGrid) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Khoảng cách:'),
                  Expanded(
                    child: Slider(
                      value: _gridSpacingMm,
                      min: 1,
                      max: 10,
                      divisions: 9,
                      label: '${_gridSpacingMm.toInt()}mm',
                      onChanged: (v) {
                        setState(() => _gridSpacingMm = v);
                        _scheduleAutoSave();
                      },
                    ),
                  ),
                  Text('${_gridSpacingMm.toInt()}mm'),
                ],
              ),
            ],
            const Divider(height: 16),
            // Overflow area - vùng giấy thừa
            Row(
              children: [
                Icon(Icons.crop_free, size: 18, color: colorScheme.tertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Vùng giấy thừa',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Cho phép kéo phần tử ra ngoài vùng in ${_overflowMm.toInt()}mm',
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              children: [
                const SizedBox(width: 70, child: Text('Kích thước:')),
                Expanded(
                  child: Slider(
                    value: _overflowMm,
                    min: 0,
                    max: 20,
                    divisions: 20,
                    label: '${_overflowMm.toInt()}mm',
                    onChanged: (v) {
                      setState(() => _overflowMm = v);
                      _scheduleAutoSave();
                    },
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${_overflowMm.toInt()}mm',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildElementsVisibilitySection(ColorScheme colorScheme) {
    final qrElement = _elements.firstWhere(
      (e) => e.type == LabelElementType.qr,
      orElse: () => _elements.first,
    );
    final barcodeElement = _elements.firstWhere(
      (e) => e.type == LabelElementType.barcode,
      orElse: () => _elements.first,
    );
    final hasQr = _elements.any((e) => e.type == LabelElementType.qr);
    final hasBarcode = _elements.any((e) => e.type == LabelElementType.barcode);

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.visibility, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Bật/tắt phần tử',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Text elements visibility FIRST
            ..._elements.where((e) => e.type == LabelElementType.text).map((
              el,
            ) {
              String label = el.id;
              IconData icon = Icons.text_fields;
              switch (el.id) {
                case 'title':
                  label = 'Tên SP';
                  icon = Icons.title;
                  break;
                case 'detail':
                  label = 'Chi tiết (GB/Màu/TT)';
                  icon = Icons.info_outline;
                  break;
                case 'price':
                  label = 'Giá bán';
                  icon = Icons.attach_money;
                  break;
                case 'priceCPK':
                  label = 'Giá CPK';
                  icon = Icons.price_change;
                  break;
                case 'labelInfo':
                  label = 'Thông tin tem';
                  icon = Icons.label;
                  break;
                case 'imei':
                  label = 'IMEI/Serial';
                  icon = Icons.qr_code;
                  break;
                case 'shopInfo':
                  label = 'Thông tin Shop';
                  icon = Icons.store;
                  break;
              }
              return SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Row(
                  children: [
                    Icon(icon, size: 20),
                    const SizedBox(width: 8),
                    Text(label),
                  ],
                ),
                value: el.visible,
                onChanged: (v) {
                  setState(() => el.visible = v);
                  _scheduleAutoSave();
                },
              );
            }),
            const Divider(),
            if (hasQr)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Row(
                  children: [
                    Icon(Icons.qr_code_2, size: 20),
                    SizedBox(width: 8),
                    Text('QR Code'),
                  ],
                ),
                value: qrElement.visible,
                onChanged: (v) {
                  setState(() => qrElement.visible = v);
                  _scheduleAutoSave();
                },
              ),
            if (hasBarcode)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Row(
                  children: [
                    Icon(Icons.view_week, size: 20),
                    SizedBox(width: 8),
                    Text('Barcode'),
                  ],
                ),
                value: barcodeElement.visible,
                onChanged: (v) {
                  setState(() => barcodeElement.visible = v);
                  _scheduleAutoSave();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaperSizeSection(ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.primaryContainer.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.straighten, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Kích thước giấy',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _widthCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: 'Rộng (mm)',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          onChanged: (v) {
                            final val = double.tryParse(v);
                            if (val != null && val > 0 && val <= 100) {
                              setState(() => _labelWidthMm = val);
                              _scheduleAutoSave();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _sizeStepButton(Icons.keyboard_arrow_up, () {
                            final next = (_labelWidthMm + 1).clamp(10, 100);
                            setState(() {
                              _labelWidthMm = next.toDouble();
                              _widthCtrl.text = next.toStringAsFixed(0);
                            });
                            _scheduleAutoSave();
                          }),
                          _sizeStepButton(Icons.keyboard_arrow_down, () {
                            final next = (_labelWidthMm - 1).clamp(10, 100);
                            setState(() {
                              _labelWidthMm = next.toDouble();
                              _widthCtrl.text = next.toStringAsFixed(0);
                            });
                            _scheduleAutoSave();
                          }),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Text('×'),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _heightCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: 'Cao (mm)',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          onChanged: (v) {
                            final val = double.tryParse(v);
                            if (val != null && val > 0 && val <= 100) {
                              setState(() => _labelHeightMm = val);
                              _scheduleAutoSave();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _sizeStepButton(Icons.keyboard_arrow_up, () {
                            final next = (_labelHeightMm + 1).clamp(10, 100);
                            setState(() {
                              _labelHeightMm = next.toDouble();
                              _heightCtrl.text = next.toStringAsFixed(0);
                            });
                            _scheduleAutoSave();
                          }),
                          _sizeStepButton(Icons.keyboard_arrow_down, () {
                            final next = (_labelHeightMm - 1).clamp(10, 100);
                            setState(() {
                              _labelHeightMm = next.toDouble();
                              _heightCtrl.text = next.toStringAsFixed(0);
                            });
                            _scheduleAutoSave();
                          }),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dpiCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'DPI',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    onChanged: (v) {
                      final val = double.tryParse(v);
                      if (val != null && val >= 150 && val <= 600) {
                        setState(() => _dpi = val);
                        _scheduleAutoSave();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                // Quick presets
                PopupMenuButton<List<double>>(
                  tooltip: 'Mẫu có sẵn',
                  icon: Icon(
                    Icons.dashboard_customize,
                    color: colorScheme.primary,
                  ),
                  onSelected: (preset) {
                    setState(() {
                      _labelWidthMm = preset[0];
                      _labelHeightMm = preset[1];
                      _dpi = preset[2];
                      _widthCtrl.text = preset[0].toStringAsFixed(0);
                      _heightCtrl.text = preset[1].toStringAsFixed(0);
                      _dpiCtrl.text = preset[2].toStringAsFixed(0);
                    });
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: [50.0, 30.0, 203.0],
                      child: Text('50×30 mm (203 DPI)'),
                    ),
                    const PopupMenuItem(
                      value: [40.0, 30.0, 203.0],
                      child: Text('40×30 mm (203 DPI)'),
                    ),
                    const PopupMenuItem(
                      value: [60.0, 40.0, 203.0],
                      child: Text('60×40 mm (203 DPI)'),
                    ),
                    const PopupMenuItem(
                      value: [80.0, 50.0, 203.0],
                      child: Text('80×50 mm (203 DPI)'),
                    ),
                    const PopupMenuItem(
                      value: [50.0, 30.0, 300.0],
                      child: Text('50×30 mm (300 DPI)'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarginSection(ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.crop_free, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Lề (mm)',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildCompactStepper('L', _marginLeftMm, (v) {
                    setState(() => _marginLeftMm = v);
                    _scheduleAutoSave();
                  }, colorScheme),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildCompactStepper('T', _marginTopMm, (v) {
                    setState(() => _marginTopMm = v);
                    _scheduleAutoSave();
                  }, colorScheme),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildCompactStepper('R', _marginRightMm, (v) {
                    setState(() => _marginRightMm = v);
                    _scheduleAutoSave();
                  }, colorScheme),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildCompactStepper('B', _marginBottomMm, (v) {
                    setState(() => _marginBottomMm = v);
                    _scheduleAutoSave();
                  }, colorScheme),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactStepper(
    String label,
    double value,
    ValueChanged<double> onChanged,
    ColorScheme colorScheme,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              InkWell(
                onTap: () => onChanged(max(0, value - 0.5)),
                child: Icon(Icons.remove, size: 16, color: colorScheme.primary),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  value.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              InkWell(
                onTap: () => onChanged(value + 0.5),
                child: Icon(Icons.add, size: 16, color: colorScheme.primary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCPKSection(ColorScheme colorScheme) {
    final cpk = _calculateCPK(_previewProduct);
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.attach_money, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Giá CPK',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    MoneyUtils.formatVND(cpk),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Hiện giá CPK trên tem'),
              value: _showPriceCPK,
              onChanged: (v) => setState(() => _showPriceCPK = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Nhập giá CPK thủ công'),
              value: _useCustomCPK,
              onChanged: (v) => setState(() => _useCustomCPK = v),
            ),
            if (_useCustomCPK)
              TextField(
                controller: _priceCPKCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Giá CPK',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            const Divider(height: 16),
            // Print paper settings
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Cắt giấy tự động'),
              subtitle: Text(
                _autoCut ? 'Máy in sẽ cắt sau mỗi tem' : 'Không cắt giấy',
                style: const TextStyle(fontSize: 11),
              ),
              value: _autoCut,
              onChanged: (v) {
                setState(() => _autoCut = v);
                _scheduleAutoSave();
              },
            ),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Đẩy giấy sau in:',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
                Text(
                  '$_feedLines dòng',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  onPressed: _feedLines > 0
                      ? () {
                          setState(() => _feedLines--);
                          _scheduleAutoSave();
                        }
                      : null,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  onPressed: _feedLines < 10
                      ? () {
                          setState(() => _feedLines++);
                          _scheduleAutoSave();
                        }
                      : null,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildElementsQuickSelect(ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.layers, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Phần tử',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _elements.map((el) {
                final isSelected = _selectedElement?.id == el.id;
                return ChoiceChip(
                  selected: isSelected,
                  label: Text(_elementLabel(el)),
                  avatar: Icon(
                    _elementIcon(el),
                    size: 18,
                    color: isSelected
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                  onSelected: (_) => _selectElement(el),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  String _elementLabel(LabelElement el) {
    switch (el.type) {
      case LabelElementType.text:
        return el.id;
      case LabelElementType.qr:
        return 'QR Code';
      case LabelElementType.barcode:
        return 'Barcode';
    }
  }

  IconData _elementIcon(LabelElement el) {
    switch (el.type) {
      case LabelElementType.text:
        return Icons.text_fields;
      case LabelElementType.qr:
        return Icons.qr_code_2;
      case LabelElementType.barcode:
        return Icons.view_week;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // ELEMENT EDITOR
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildElementEditor(ColorScheme colorScheme) {
    final el = _selectedElement!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => _selectElement(null),
              visualDensity: VisualDensity.compact,
            ),
            Icon(_elementIcon(el), color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'Chỉnh sửa: ${_elementLabel(el)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Size controls
        _buildSizeControls(el, colorScheme),
        const SizedBox(height: 12),
        
        // Position navigation buttons - di chuyển nhanh
        _buildPositionNavButtons(el, colorScheme),
        const SizedBox(height: 12),

        // Rotation
        _buildRotationControls(el, colorScheme),
        const SizedBox(height: 12),

        // Text specific controls
        if (el.type == LabelElementType.text) ...[
          _buildTextControls(el, colorScheme),
        ],
      ],
    );
  }

  Widget _buildSizeControls(LabelElement el, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kích thước',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(
                  width: 20,
                  child: Text(
                    'W',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: TextEditingController(
                      text: el.widthMm.toStringAsFixed(1),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      suffixText: 'mm',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    style: const TextStyle(fontSize: 14),
                    onSubmitted: (v) {
                      final val = double.tryParse(v) ?? el.widthMm;
                      _updateElement(
                        el,
                        (e) => e.widthMm = val.clamp(4, _labelWidthMm - 4),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                const SizedBox(
                  width: 20,
                  child: Text(
                    'H',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: TextEditingController(
                      text: el.heightMm.toStringAsFixed(1),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      suffixText: 'mm',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    style: const TextStyle(fontSize: 14),
                    onSubmitted: (v) {
                      final val = double.tryParse(v) ?? el.heightMm;
                      _updateElement(
                        el,
                        (e) => e.heightMm = val.clamp(4, _labelHeightMm - 4),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Nút điều hướng vị trí nhanh - di chuyển lên/xuống/trái/phải
  Widget _buildPositionNavButtons(LabelElement el, ColorScheme colorScheme) {
    const double step = 0.5; // Di chuyển 0.5mm mỗi lần bấm
    const double bigStep = 2.0; // Di chuyển 2mm khi giữ
    
    Widget navButton({
      required IconData icon,
      required VoidCallback onPressed,
      required String tooltip,
    }) {
      return Material(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onPressed();
          },
          onLongPress: () {
            // Di chuyển nhanh khi giữ
            HapticFeedback.mediumImpact();
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 20,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
        ),
      );
    }
    
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Di chuyển vị trí',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Control pad layout
                Column(
                  children: [
                    // Lên
                    navButton(
                      icon: Icons.keyboard_arrow_up,
                      tooltip: 'Lên',
                      onPressed: () => _updateElement(
                        el,
                        (e) => e.yMm = (e.yMm - step).clamp(0, _labelHeightMm - e.heightMm),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Trái
                        navButton(
                          icon: Icons.keyboard_arrow_left,
                          tooltip: 'Trái',
                          onPressed: () => _updateElement(
                            el,
                            (e) => e.xMm = (e.xMm - step).clamp(0, _labelWidthMm - e.widthMm),
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Nút căn giữa
                        Material(
                          color: colorScheme.secondary,
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              // Căn giữa theo chiều ngang
                              _updateElement(
                                el,
                                (e) => e.xMm = (_labelWidthMm - e.widthMm) / 2,
                              );
                            },
                            onLongPress: () {
                              HapticFeedback.heavyImpact();
                              // Căn giữa cả hai chiều
                              _updateElement(
                                el,
                                (e) {
                                  e.xMm = (_labelWidthMm - e.widthMm) / 2;
                                  e.yMm = (_labelHeightMm - e.heightMm) / 2;
                                },
                              );
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 36,
                              height: 36,
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.center_focus_strong,
                                size: 18,
                                color: colorScheme.onSecondary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Phải
                        navButton(
                          icon: Icons.keyboard_arrow_right,
                          tooltip: 'Phải',
                          onPressed: () => _updateElement(
                            el,
                            (e) => e.xMm = (e.xMm + step).clamp(0, _labelWidthMm - e.widthMm),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Xuống
                    navButton(
                      icon: Icons.keyboard_arrow_down,
                      tooltip: 'Xuống',
                      onPressed: () => _updateElement(
                        el,
                        (e) => e.yMm = (e.yMm + step).clamp(0, _labelHeightMm - e.heightMm),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 24),
                // Các nút căn lề nhanh
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Căn lề:',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // Căn trái
                        _alignButton(
                          icon: Icons.align_horizontal_left,
                          tooltip: 'Căn trái',
                          colorScheme: colorScheme,
                          onPressed: () => _updateElement(el, (e) => e.xMm = 1),
                        ),
                        const SizedBox(width: 4),
                        // Căn phải
                        _alignButton(
                          icon: Icons.align_horizontal_right,
                          tooltip: 'Căn phải',
                          colorScheme: colorScheme,
                          onPressed: () => _updateElement(
                            el,
                            (e) => e.xMm = _labelWidthMm - e.widthMm - 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // Căn trên
                        _alignButton(
                          icon: Icons.align_vertical_top,
                          tooltip: 'Căn trên',
                          colorScheme: colorScheme,
                          onPressed: () => _updateElement(el, (e) => e.yMm = 1),
                        ),
                        const SizedBox(width: 4),
                        // Căn dưới
                        _alignButton(
                          icon: Icons.align_vertical_bottom,
                          tooltip: 'Căn dưới',
                          colorScheme: colorScheme,
                          onPressed: () => _updateElement(
                            el,
                            (e) => e.yMm = _labelHeightMm - e.heightMm - 1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _alignButton({
    required IconData icon,
    required String tooltip,
    required ColorScheme colorScheme,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onPressed();
          },
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 18,
              color: colorScheme.onTertiaryContainer,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRotationControls(LabelElement el, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Text(
              'Xoay: ${el.rotationDeg}°',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            IconButton.filled(
              onPressed: () => _updateElement(
                el,
                (e) => e.rotationDeg = (e.rotationDeg - 90) % 360,
              ),
              icon: const Icon(Icons.rotate_left),
              style: IconButton.styleFrom(
                backgroundColor: colorScheme.primaryContainer,
                foregroundColor: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: () => _updateElement(
                el,
                (e) => e.rotationDeg = (e.rotationDeg + 90) % 360,
              ),
              icon: const Icon(Icons.rotate_right),
              style: IconButton.styleFrom(
                backgroundColor: colorScheme.primaryContainer,
                foregroundColor: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => _updateElement(el, (e) => e.rotationDeg = 0),
              child: const Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextControls(LabelElement el, ColorScheme colorScheme) {
    return Column(
      children: [
        Card(
          elevation: 0,
          color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nội dung',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: ValueKey('text_${el.id}'),
                  initialValue: el.text,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Nhập nội dung hoặc chọn token',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (v) => _updateElement(el, (e) => e.text = v),
                ),
                if (el.id == 'price' || el.id == 'priceCPK') ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    key: ValueKey('prefix_${el.id}'),
                    initialValue: el.prefix,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'Tiền tố (prefix) trước giá',
                      hintText: 'VD: Giá KM: ',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onChanged: (v) => _updateElement(el, (e) => e.prefix = v),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _tokenChip('{{name}}', 'Tên', el),
                    _tokenChip('{{price}}', 'Giá', el),
                    _tokenChip('{{priceCPK}}', 'CPK', el),
                    _tokenChip('{{imei}}', 'IMEI', el),
                    _tokenChip('{{model}}', 'Model', el),
                    _tokenChip('{{capacity}}', 'GB', el),
                    _tokenChip('{{color}}', 'Màu', el),
                    _tokenChip('{{condition}}', 'TT', el),
                    _tokenChip('{{labelInfo}}', 'Tem', el),
                    _tokenChip('{{warranty}}', 'BH', el),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Font',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Size'),
                    Expanded(
                      child: Slider(
                        value: el.fontSizeMm.clamp(2, 15),
                        min: 2,
                        max: 15,
                        divisions: 26,
                        onChanged: (v) =>
                            _updateElement(el, (e) => e.fontSizeMm = v),
                      ),
                    ),
                    Text('${el.fontSizeMm.toStringAsFixed(1)}mm'),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('In đậm (Bold)'),
                  value: el.bold,
                  onChanged: (v) => _updateElement(el, (e) => e.bold = v),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _tokenChip(String token, String label, LabelElement el) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      visualDensity: VisualDensity.compact,
      onPressed: () => _updateElement(el, (e) => e.text = token),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // BOTTOM ACTIONS
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildBottomActions(ColorScheme colorScheme) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Product count
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sản phẩm đã chọn',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '${_selectedKeys.length} sản phẩm',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            // Print button
            FilledButton.icon(
              onPressed: _isPrinting ? null : _printSelectedItems,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              icon: _isPrinting
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.onPrimary,
                      ),
                    )
                  : const Icon(Icons.print),
              label: Text(_isPrinting ? 'Đang in...' : 'IN TEM'),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // INVENTORY SELECTOR
  // ─────────────────────────────────────────────────────────────────────────────

  void _applyInventorySearch(String q) {
    final query = q.trim().toLowerCase();
    setState(() {
      _filteredInventory = _inventoryItems.where((p) {
        final imei = p.imei?.toLowerCase() ?? '';
        final name = p.name.toLowerCase();
        final model = p.model?.toLowerCase() ?? '';
        final color = p.color?.toLowerCase() ?? '';
        return imei.contains(query) ||
            name.contains(query) ||
            model.contains(query) ||
            color.contains(query);
      }).toList();
    });
  }

  void _toggleAllInventory(bool selectAll) {
    setState(() {
      _selectedKeys.clear();
      if (selectAll) {
        _selectedKeys.addAll(_filteredInventory.map(_keyForProduct));
      }
    });
  }

  void _toggleOne(Product p, bool selected) {
    final key = _keyForProduct(p);
    setState(() {
      if (selected) {
        _selectedKeys.add(key);
      } else {
        _selectedKeys.remove(key);
      }
    });
  }

  Future<void> _openInventorySelector() async {
    final colorScheme = Theme.of(context).colorScheme;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.85,
              maxChildSize: 0.95,
              minChildSize: 0.5,
              builder: (_, controller) {
                return Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Handle
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // Header
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Chọn sản phẩm',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: () {
                                    _toggleAllInventory(true);
                                    setSheetState(() {});
                                  },
                                  child: const Text('Chọn hết'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    _toggleAllInventory(false);
                                    setSheetState(() {});
                                  },
                                  child: const Text('Bỏ chọn'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _inventorySearchCtrl,
                              onChanged: (q) {
                                _applyInventorySearch(q);
                                setSheetState(() {});
                              },
                              decoration: InputDecoration(
                                hintText: 'Tìm tên / IMEI / model / màu',
                                prefixIcon: const Icon(Icons.search),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: colorScheme.surfaceContainerHighest,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // List
                      Expanded(
                        child: _inventoryLoading
                            ? const Center(child: CircularProgressIndicator())
                            : _filteredInventory.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.inventory_2_outlined,
                                      size: 64,
                                      color: colorScheme.outlineVariant,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Không tìm thấy sản phẩm',
                                      style: TextStyle(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                controller: controller,
                                itemCount: _filteredInventory.length,
                                itemBuilder: (_, i) {
                                  final p = _filteredInventory[i];
                                  final key = _keyForProduct(p);
                                  final checked = _selectedKeys.contains(key);
                                  return CheckboxListTile(
                                    value: checked,
                                    onChanged: (v) {
                                      _toggleOne(p, v ?? false);
                                      setSheetState(() {});
                                    },
                                    title: Text(
                                      p.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${p.imei ?? '-'} • ${p.capacity ?? ''} ${p.color ?? ''}',
                                    ),
                                    secondary: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primaryContainer
                                            .withOpacity(0.5),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        Icons.smartphone,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      // Footer
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: FilledButton(
                            onPressed: () => Navigator.pop(context),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                            child: Text(
                              'Xác nhận (${_selectedKeys.length} sản phẩm)',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
    setState(() {}); // Refresh main view
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // PRINTING
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> _printSelectedItems() async {
    final items = _selectedProducts;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Vui lòng chọn sản phẩm từ kho'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Chọn ngay',
            onPressed: _openInventorySelector,
          ),
        ),
      );
      return;
    }

    final printerConfig = await showPrinterSelectionDialog(context);
    if (printerConfig == null) {
      print('PTY_PRINT: User cancelled printer selection');
      return;
    }

    final printerType = printerConfig['type'] as PrinterType?;
    final bluetoothPrinter = printerConfig['bluetoothPrinter'];
    final wifiIp = printerConfig['wifiIp'] as String?;

    print('=== PTY_PRINT START ===');
    print('PTY_PRINT: printerConfig = $printerConfig');
    print('PTY_PRINT: printerType = $printerType');
    print('PTY_PRINT: bluetoothPrinter = $bluetoothPrinter');
    print(
      'PTY_PRINT: bluetoothPrinter type = ${bluetoothPrinter?.runtimeType}',
    );
    if (bluetoothPrinter != null) {
      print(
        'PTY_PRINT: bluetoothPrinter.macAddress = ${bluetoothPrinter.macAddress}',
      );
    }
    print('PTY_PRINT: wifiIp = $wifiIp');
    print('PTY_PRINT: Items to print: ${items.length}');

    setState(() => _isPrinting = true);

    int success = 0;
    int failed = 0;
    String? lastError;

    // Tính px/mm dựa trên khổ giấy máy in để tránh bị co giãn sau khi render
    final pxPerMm = await _computePxPerMmForPrint(_labelWidthMm);

    for (int i = 0; i < items.length; i++) {
      final product = items[i];
      try {
        print(
          'PTY_PRINT: [$i/${items.length}] Exporting bitmap for: ${product.name}',
        );
        final png = await _exportBitmap(
          product,
          includeCodes: true,
          pxPerMm: pxPerMm,
        );
        print('PTY_PRINT: [$i] Bitmap exported, size: ${png.length} bytes');

        if (png.isEmpty) {
          print('PTY_PRINT: [$i] ERROR: Empty bitmap!');
          failed++;
          lastError = 'Bitmap trống';
          continue;
        }

        print(
          'PTY_PRINT: [$i] Calling printLabelBitmap (cut=$_autoCut, feedLines=$_feedLines)...',
        );
        final ok = await UnifiedPrinterService.printLabelBitmap(
          png,
          printerType: printerType,
          bluetoothPrinter: bluetoothPrinter,
          wifiIp: wifiIp,
          feedLines: _feedLines,
          cut: _autoCut,
        );
        print('PTY_PRINT: [$i] printLabelBitmap result: $ok');

        if (ok) {
          success++;
          // Đợi giữa các lần in để máy in xử lý
          if (i < items.length - 1) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
        } else {
          failed++;
          lastError = 'Không thể gửi dữ liệu đến máy in';
        }
      } catch (e, stackTrace) {
        print('PTY_PRINT: [$i] Exception: $e');
        print('PTY_PRINT: [$i] Stack: $stackTrace');
        failed++;
        lastError = e.toString();
      }
    }

    print('=== PTY_PRINT END: success=$success, failed=$failed ===');

    if (!mounted) return;
    setState(() => _isPrinting = false);

    String message;
    Color bgColor;
    if (failed == 0 && success > 0) {
      message = 'In thành công $success tem';
      bgColor = Colors.green;
    } else if (success == 0 && failed > 0) {
      message = 'In thất bại! ${lastError ?? "Kiểm tra kết nối máy in"}';
      bgColor = Colors.red;
    } else {
      message = 'Thành công: $success, Thất bại: $failed';
      bgColor = Colors.orange;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: bgColor,
        duration: const Duration(seconds: 4),
        action: failed > 0
            ? SnackBarAction(
                label: 'Cài đặt',
                textColor: Colors.white,
                onPressed: () {
                  Navigator.pushNamed(context, '/printer_settings');
                },
              )
            : null,
      ),
    );
  }

  Future<Uint8List> _exportBitmap(
    Product product, {
    bool includeCodes = true,
    double? pxPerMm,
  }) async {
    final safeWidthMm = (_labelWidthMm <= 0 ? 50 : _labelWidthMm).toDouble();
    final safeHeightMm = (_labelHeightMm <= 0 ? 30 : _labelHeightMm).toDouble();

    // Ưu tiên vẽ đúng độ rộng tối đa của khổ giấy để không bị resize mờ nét
    final effectivePxPerMm =
        pxPerMm ?? await _computePxPerMmForPrint(safeWidthMm);
    final labelPxSize = Size(
      effectivePxPerMm * safeWidthMm,
      effectivePxPerMm * safeHeightMm,
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // White background
    canvas.drawRect(Offset.zero & labelPxSize, Paint()..color = Colors.white);

    // Draw only visible elements
    for (final el in _elements.where((e) => e.visible)) {
      if (!includeCodes &&
          (el.type == LabelElementType.qr ||
              el.type == LabelElementType.barcode)) {
        continue;
      }
      await _drawElementToCanvas(canvas, el, product, effectivePxPerMm);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      labelPxSize.width.toInt(),
      labelPxSize.height.toInt(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _drawElementToCanvas(
    Canvas canvas,
    LabelElement el,
    Product product,
    double pxPerMm,
  ) async {
    final rect = Rect.fromLTWH(
      pxPerMm * el.xMm,
      pxPerMm * el.yMm,
      pxPerMm * el.widthMm,
      pxPerMm * el.heightMm,
    );

    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.rotate((el.rotationDeg * pi) / 180);
    canvas.translate(-rect.center.dx, -rect.center.dy);

    switch (el.type) {
      case LabelElementType.text:
        final textPainter = TextPainter(
          text: TextSpan(
            text: _resolveText(el.text, product, prefix: el.prefix),
            style: TextStyle(
              color: Colors.black,
              fontSize: pxPerMm * el.fontSizeMm * 0.28,
              fontWeight: el.bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout(maxWidth: rect.width);
        final offset = Offset(
          rect.left + (rect.width - textPainter.width) / 2,
          rect.top + (rect.height - textPainter.height) / 2,
        );
        textPainter.paint(canvas, offset);
        break;

      case LabelElementType.qr:
        final qrImage = _buildQrImage(
          _resolveQrData(product),
          rect.width.toInt(),
        );
        final qrUi = await _toUiImage(qrImage);
        canvas.drawImageRect(
          qrUi,
          Rect.fromLTWH(0, 0, qrUi.width.toDouble(), qrUi.height.toDouble()),
          rect,
          Paint()
            ..filterQuality = FilterQuality.none
            ..isAntiAlias = false,
        );
        break;

      case LabelElementType.barcode:
        final bar = bc.Barcode.code128();
        final imgBar = img.Image(
          width: rect.width.toInt(),
          height: rect.height.toInt(),
        );
        img.fill(imgBar, color: img.ColorRgb8(255, 255, 255));
        drawBarcode(
          imgBar,
          bar,
          _resolveBarcodeData(product),
          x: 0,
          y: 0,
          width: rect.width.toInt(),
          height: rect.height.toInt(),
        );
        final barUi = await _toUiImage(imgBar);
        canvas.drawImageRect(
          barUi,
          Rect.fromLTWH(0, 0, barUi.width.toDouble(), barUi.height.toDouble()),
          rect,
          Paint()
            ..filterQuality = FilterQuality.none
            ..isAntiAlias = false,
        );
        break;
    }

    canvas.restore();
  }

  img.Image _buildQrImage(String data, int sizePx) {
    final qr = bc.Barcode.qrCode(
      errorCorrectLevel: bc.BarcodeQRCorrectionLevel.high,
    );
    final image = img.Image(width: sizePx, height: sizePx);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    final pad = max(4, (sizePx * 0.1).round());
    final inner = max(1, sizePx - pad * 2);
    drawBarcode(image, qr, data, x: pad, y: pad, width: inner, height: inner);
    return image;
  }

  Future<ui.Image> _toUiImage(img.Image image) async {
    final png = img.encodePng(image);
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(png));
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTERS
// ══════════════════════════════════════════════════════════════════════════════

class _GridPainter extends CustomPainter {
  _GridPainter({required this.gridSpacingPx, required this.color});

  final double gridSpacingPx;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // Draw vertical lines
    for (double x = gridSpacingPx; x < size.width; x += gridSpacingPx) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Draw horizontal lines
    for (double y = gridSpacingPx; y < size.height; y += gridSpacingPx) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      gridSpacingPx != oldDelegate.gridSpacingPx || color != oldDelegate.color;
}

class _MarginGuidePainter extends CustomPainter {
  _MarginGuidePainter({required this.margins, required this.color});

  final EdgeInsets margins;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Draw dashed lines for margins
    final contentRect = Rect.fromLTRB(
      margins.left,
      margins.top,
      size.width - margins.right,
      size.height - margins.bottom,
    );

    canvas.drawRect(contentRect, paint);
  }

  @override
  bool shouldRepaint(covariant _MarginGuidePainter oldDelegate) =>
      margins != oldDelegate.margins || color != oldDelegate.color;
}

class _BarcodePlaceholderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black54;
    const barCount = 12;
    final barWidth = size.width / (barCount * 2);

    for (int i = 0; i < barCount; i++) {
      final x = i * barWidth * 2;
      canvas.drawRect(
        Rect.fromLTWH(x, size.height * 0.1, barWidth, size.height * 0.8),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter({
    required this.elements,
    required this.product,
    required this.pxPerMm,
    required this.resolveText,
    required this.resolveQrData,
    required this.resolveBarcodeData,
  });

  final List<LabelElement> elements;
  final Product product;
  final double pxPerMm;
  final String Function(String, Product) resolveText;
  final String Function(Product) resolveQrData;
  final String Function(Product) resolveBarcodeData;

  @override
  void paint(Canvas canvas, Size size) {
    for (final el in elements) {
      final rect = Rect.fromLTWH(
        el.xMm * pxPerMm,
        el.yMm * pxPerMm,
        el.widthMm * pxPerMm,
        el.heightMm * pxPerMm,
      );

      canvas.save();
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.rotate((el.rotationDeg * pi) / 180);
      canvas.translate(-rect.center.dx, -rect.center.dy);

      switch (el.type) {
        case LabelElementType.text:
          final textPainter = TextPainter(
            text: TextSpan(
              text: resolveText(el.text, product),
              style: TextStyle(
                color: Colors.black,
                fontSize: el.fontSizeMm * pxPerMm * 0.3,
                fontWeight: el.bold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
          );
          textPainter.layout(maxWidth: rect.width);
          textPainter.paint(
            canvas,
            Offset(
              rect.left + (rect.width - textPainter.width) / 2,
              rect.top + (rect.height - textPainter.height) / 2,
            ),
          );
          break;

        case LabelElementType.qr:
          final iconPainter = TextPainter(
            text: TextSpan(
              text: String.fromCharCode(Icons.qr_code_2.codePoint),
              style: TextStyle(
                fontSize: rect.height * 0.8,
                fontFamily: Icons.qr_code_2.fontFamily,
                color: Colors.black87,
              ),
            ),
            textDirection: TextDirection.ltr,
          );
          iconPainter.layout();
          iconPainter.paint(
            canvas,
            Offset(
              rect.left + (rect.width - iconPainter.width) / 2,
              rect.top + (rect.height - iconPainter.height) / 2,
            ),
          );
          break;

        case LabelElementType.barcode:
          final paint = Paint()..color = Colors.black;
          const barCount = 16;
          final barWidth = rect.width / (barCount * 1.5);
          for (int i = 0; i < barCount; i++) {
            final x = rect.left + i * barWidth * 1.5;
            canvas.drawRect(
              Rect.fromLTWH(x, rect.top, barWidth, rect.height),
              paint,
            );
          }
          break;
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
