import 'package:flutter/material.dart';
import '../data/db_helper.dart';
import '../models/product_model.dart';
import '../models/shop_settings_model.dart';
import '../services/notification_service.dart';
import '../services/unified_printer_service.dart';
import '../services/category_service.dart';
import '../services/business_type_helper.dart';
import '../theme/app_text_styles.dart';
import '../widgets/printer_selection_dialog.dart';
import '../models/printer_types.dart';
import 'label_designer_view.dart';

class ImeiQrPrinterView extends StatefulWidget {
  const ImeiQrPrinterView({super.key});

  @override
  State<ImeiQrPrinterView> createState() => _ImeiQrPrinterViewState();
}

class _ImeiQrPrinterViewState extends State<ImeiQrPrinterView> {
  final db = DBHelper();
  final TextEditingController _searchCtrl = TextEditingController();

  ShopSettings? _shopSettings;
  BusinessTerminology get _terms => BusinessTypeHelper.instance.getTerminology(_shopSettings);

  bool _isLoading = true;
  bool _isPrinting = false;
  bool _showName = true;
  bool _showDetail = true;
  bool _showImei = true;
  bool _bluetoothCompat = true;
  int _paddingLines = 1;
  String _qrSize = 'medium';
  final int _columns = 1;
  String _codeType = 'qr';
  List<Product> _allItems = [];
  List<Product> _filteredItems = [];
  final Set<String> _selectedImeis = {};

  @override
  void initState() {
    super.initState();
    _loadShopSettings();
    _loadData();
  }

  Future<void> _loadShopSettings() async {
    try {
      final settings = await CategoryService().getShopSettings();
      if (mounted) {
        setState(() => _shopSettings = settings);
      }
    } catch (e) {
      debugPrint('Error loading shop settings: $e');
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final products = await db.getProductsByType('DIEN_THOAI');
      final imeiItems = products
          .where((p) => (p.imei ?? '').trim().isNotEmpty)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() {
        _allItems = imeiItems;
        _filteredItems = List<Product>.from(imeiItems);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      NotificationService.showSnackBar(
        'Lỗi tải danh sách ${_terms.specialField1Label}: $e',
        color: Colors.red,
      );
    }
  }

  void _applySearch(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      _filteredItems = _allItems.where((p) {
        final imei = p.imei?.toLowerCase() ?? '';
        final name = p.name.toLowerCase();
        final model = p.model?.toLowerCase() ?? '';
        return imei.contains(q) || name.contains(q) || model.contains(q);
      }).toList();
    });
  }

  void _toggleAll(bool selectAll) {
    setState(() {
      _selectedImeis.clear();
      if (selectAll) {
        _selectedImeis.addAll(
          _filteredItems
              .map((p) => p.imei ?? '')
              .where((v) => v.trim().isNotEmpty),
        );
      }
    });
  }

  Future<void> _printItems(List<Product> items) async {
    if (items.isEmpty) {
      NotificationService.showSnackBar(
        'Không có ${_terms.specialField1Label} để in',
        color: Colors.orange,
      );
      return;
    }

    setState(() => _isPrinting = true);

    try {
      final printerConfig = await showPrinterSelectionDialog(context);
      if (printerConfig == null) return;

      final printerType = printerConfig['type'] as PrinterType?;
      final bluetoothPrinter = printerConfig['bluetoothPrinter'];
      final wifiIp = printerConfig['wifiIp'] as String?;

      final ok = await UnifiedPrinterService.printImeiQrBatch(
        items,
        printerType: printerType,
        bluetoothPrinter: bluetoothPrinter,
        wifiIp: wifiIp,
        showName: _showName,
        showDetail: _showDetail,
        showImei: _showImei,
        paddingLines: _paddingLines,
        qrSize: _qrSize,
        columns: _columns,
        codeType: _codeType,
        defaultProductName: _terms.productPlural.toUpperCase(),
        imeiPrefix: '${_terms.specialField1Label}: ',
        imeiLabel: _terms.specialField1Label,
        preferRasterForBluetooth: _bluetoothCompat,
      );
      if (!mounted) return;

      NotificationService.showSnackBar(
        ok ? 'In QR ${_terms.specialField1Label} thành công' : 'In QR ${_terms.specialField1Label} thất bại',
        color: ok ? Colors.green : Colors.red,
      );
    } catch (e) {
      if (!mounted) return;
      NotificationService.showSnackBar(
        'Lỗi in QR ${_terms.specialField1Label}: $e',
        color: Colors.red,
      );
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selectedImeis.length;
    return Scaffold(
      appBar: AppBar(
        title: Text('In QR ${_terms.specialField1Label} - ${_terms.inventoryLabel}'),
        actions: [
          IconButton(
            tooltip: 'Thiết kế tem',
            icon: const Icon(Icons.design_services),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LabelDesignerView()),
              );
            },
          ),
          IconButton(
            tooltip: 'Làm mới',
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _applySearch,
                    decoration: InputDecoration(
                      hintText: 'Tìm ${_terms.specialField1Label} / Tên / Model',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Tổng ${_terms.specialField1Label}: ${_filteredItems.length}',
                          style: AppTextStyles.body2,
                        ),
                      ),
                      TextButton(
                        onPressed: () => _toggleAll(true),
                        child: const Text('Chọn hết'),
                      ),
                      TextButton(
                        onPressed: () => _toggleAll(false),
                        child: const Text('Bỏ chọn'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tùy chỉnh tem',
                            style: AppTextStyles.subtitle1.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text('Loại mã'),
                              const SizedBox(width: 12),
                              DropdownButton<String>(
                                value: _codeType,
                                items: const [
                                  DropdownMenuItem(
                                    value: 'qr',
                                    child: Text('QR'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'barcode',
                                    child: Text('Barcode'),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() => _codeType = v);
                                },
                              ),
                              const SizedBox(width: 12),
                              if (_codeType == 'qr') ...[
                                const Text('Cỡ QR'),
                                const SizedBox(width: 8),
                                DropdownButton<String>(
                                  value: _qrSize,
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'xsmall',
                                      child: Text('Rất nhỏ'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'small',
                                      child: Text('Nhỏ'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'medium',
                                      child: Text('Vừa'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'large',
                                      child: Text('Lớn'),
                                    ),
                                  ],
                                  onChanged: (v) {
                                    if (v == null) return;
                                    setState(() => _qrSize = v);
                                  },
                                ),
                              ],
                              const Spacer(),
                              Text('Đệm: $_paddingLines'),
                            ],
                          ),
                          Slider(
                            value: _paddingLines.toDouble(),
                            min: 0,
                            max: 4,
                            divisions: 4,
                            label: '$_paddingLines',
                            onChanged: (v) =>
                                setState(() => _paddingLines = v.round()),
                          ),
                          Wrap(
                            spacing: 12,
                            children: [
                              FilterChip(
                                label: Text('Tên ${_terms.productLabel.toLowerCase()}'),
                                selected: _showName,
                                onSelected: (v) =>
                                    setState(() => _showName = v),
                              ),
                              FilterChip(
                                label: const Text('Chi tiết'),
                                selected: _showDetail,
                                onSelected: (v) =>
                                    setState(() => _showDetail = v),
                              ),
                              FilterChip(
                                label: Text(_terms.specialField1Label),
                                selected: _showImei,
                                onSelected: (v) =>
                                    setState(() => _showImei = v),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Ưu tiên tương thích Bluetooth'),
                            subtitle: const Text(
                              'In QR dạng ảnh để tăng khả năng in trên Bluetooth',
                            ),
                            value: _bluetoothCompat,
                            onChanged: (v) =>
                                setState(() => _bluetoothCompat = v),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _filteredItems.length,
                    itemBuilder: (ctx, i) {
                      final p = _filteredItems[i];
                      final imei = p.imei ?? '';
                      final isSelected = _selectedImeis.contains(imei);
                      return Card(
                        child: CheckboxListTile(
                          value: isSelected,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selectedImeis.add(imei);
                              } else {
                                _selectedImeis.remove(imei);
                              }
                            });
                          },
                          title: Text(p.name),
                          subtitle: Text('${_terms.specialField1Label}: $imei'),
                          secondary: const Icon(Icons.qr_code_2),
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isPrinting
                                ? null
                                : () => _printItems(_filteredItems),
                            icon: const Icon(Icons.print),
                            label: const Text('In tất cả'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isPrinting
                                ? null
                                : () {
                                    final selected = _filteredItems
                                        .where((p) =>
                                            _selectedImeis
                                                .contains(p.imei ?? ''))
                                        .toList();
                                    _printItems(selected);
                                  },
                            icon: const Icon(Icons.check_circle),
                            label: Text(
                              'In đã chọn ($selectedCount)',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
