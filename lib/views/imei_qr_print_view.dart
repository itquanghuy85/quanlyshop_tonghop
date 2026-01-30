import 'package:flutter/material.dart';
import '../data/db_helper.dart';
import '../models/product_model.dart';
import '../services/notification_service.dart';
import '../services/unified_printer_service.dart';
import '../theme/app_text_styles.dart';
import '../l10n/app_localizations.dart';
import '../widgets/printer_selection_dialog.dart';
import '../models/printer_types.dart';
import 'label_designer_view.dart';

class ImeiQrPrintView extends StatefulWidget {
  const ImeiQrPrintView({super.key});

  @override
  State<ImeiQrPrintView> createState() => _ImeiQrPrintViewState();
}

class _ImeiQrPrintViewState extends State<ImeiQrPrintView> {
  final db = DBHelper();
  final TextEditingController _searchCtrl = TextEditingController();

  bool _isLoading = true;
  bool _isPrinting = false;
  bool _showName = true;
  bool _showDetail = true;
  bool _showImei = true;
  int _paddingLines = 1;
  String _qrSize = 'medium'; // small | medium | large
  int _columns = 1;
  List<Product> _allItems = [];
  List<Product> _filteredItems = [];
  final Set<String> _selectedImeis = {};

  @override
  void initState() {
    super.initState();
    _loadData();
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
      final loc = AppLocalizations.of(context)!;
      NotificationService.showSnackBar(
        loc.imeiListLoadError(e.toString()),
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
      final loc = AppLocalizations.of(context)!;
      NotificationService.showSnackBar(
        loc.noImeiToPrint,
        color: Colors.orange,
      );
      return;
    }

    final printerConfig = await showPrinterSelectionDialog(context);
    if (printerConfig == null) return;

    final printerType = printerConfig['type'] as PrinterType?;
    final bluetoothPrinter = printerConfig['bluetoothPrinter'];
    final wifiIp = printerConfig['wifiIp'] as String?;
    final loc = AppLocalizations.of(context)!;

    setState(() => _isPrinting = true);
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
      defaultProductName: loc.defaultProductName,
      imeiPrefix: loc.imeiPrefix,
      imeiLabel: loc.imei,
    );
    if (!mounted) return;
    setState(() => _isPrinting = false);

    NotificationService.showSnackBar(
      ok
          ? AppLocalizations.of(context)!.printQrImeiSuccess
          : AppLocalizations.of(context)!.printQrImeiFail,
      color: ok ? Colors.green : Colors.red,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selectedImeis.length;
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.printQrImeiInventory),
        actions: [
          IconButton(
            tooltip: loc.designQrLabel,
            icon: const Icon(Icons.design_services),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LabelDesignerView()),
              );
            },
          ),
          IconButton(
            tooltip: loc.refresh,
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
                      hintText: loc.searchImeiNameModel,
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
                          loc.imeiTotalCount(_filteredItems.length),
                          style: AppTextStyles.body2,
                        ),
                      ),
                      TextButton(
                        onPressed: () => _toggleAll(true),
                        child: Text(loc.selectAll),
                      ),
                      TextButton(
                        onPressed: () => _toggleAll(false),
                        child: Text(loc.clearSelection),
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
                            loc.labelCustomization,
                            style: AppTextStyles.subtitle1.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(loc.qrSize),
                              const SizedBox(width: 12),
                              DropdownButton<String>(
                                value: _qrSize,
                                items: [
                                  DropdownMenuItem(
                                    value: 'xsmall',
                                    child: Text(loc.qrSizeXSmall),
                                  ),
                                  DropdownMenuItem(
                                    value: 'small',
                                    child: Text(loc.qrSizeSmall),
                                  ),
                                  DropdownMenuItem(
                                    value: 'medium',
                                    child: Text(loc.qrSizeMedium),
                                  ),
                                  DropdownMenuItem(
                                    value: 'large',
                                    child: Text(loc.qrSizeLarge),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() => _qrSize = v);
                                },
                              ),
                              const SizedBox(width: 12),
                              Text(loc.columns),
                              const SizedBox(width: 8),
                              DropdownButton<int>(
                                value: _columns,
                                items: const [
                                  DropdownMenuItem(
                                    value: 1,
                                    child: Text('1'),
                                  ),
                                  DropdownMenuItem(
                                    value: 2,
                                    child: Text('2'),
                                  ),
                                  DropdownMenuItem(
                                    value: 3,
                                    child: Text('3'),
                                  ),
                                  DropdownMenuItem(
                                    value: 4,
                                    child: Text('4'),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() => _columns = v);
                                },
                              ),
                              const Spacer(),
                              Text('${loc.padding}: $_paddingLines'),
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
                                label: Text(loc.productName),
                                selected: _showName,
                                onSelected: (v) =>
                                    setState(() => _showName = v),
                              ),
                              FilterChip(
                                label: Text(loc.modelDetail),
                                selected: _showDetail,
                                onSelected: (v) =>
                                    setState(() => _showDetail = v),
                              ),
                              FilterChip(
                                label: Text(loc.imei),
                                selected: _showImei,
                                onSelected: (v) =>
                                    setState(() => _showImei = v),
                              ),
                            ],
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
                          subtitle: Text(loc.imeiWithValue(imei)),
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
                            label: Text(loc.printAll),
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
                              '${loc.printSelected} (${selectedCount})',
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
