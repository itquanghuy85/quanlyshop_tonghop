import 'package:flutter/material.dart';

import '../../../expansion/safe_mode/expansion_feature_flags.dart';
import '../../../expansion/safe_mode/expansion_module_services.dart';
import '../../../expansion/safe_mode/vat_invoice_service.dart';

class CreateInvoiceView extends StatefulWidget {
  final ExpansionFeatureFlags flags;

  const CreateInvoiceView({
    super.key,
    this.flags = const ExpansionFeatureFlags.safeDefaults(),
  });

  @override
  State<CreateInvoiceView> createState() => _CreateInvoiceViewState();
}

class _CreateInvoiceViewState extends State<CreateInvoiceView> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _companyController = TextEditingController();
  final TextEditingController _taxCodeController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  final VatModuleService _vatModuleService = VatModuleService();
  late final VatInvoiceService _invoiceService;

  final List<_InvoiceItemFormData> _items = <_InvoiceItemFormData>[
    _InvoiceItemFormData(),
  ];

  List<VatIssuedInvoice> _invoiceHistory = const <VatIssuedInvoice>[];
  bool _loadingHistory = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _invoiceService = VatInvoiceService(flags: widget.flags);
    _loadInvoices();
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    _companyController.dispose();
    _taxCodeController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _invoiceService.close();
    super.dispose();
  }

  Future<void> _loadInvoices() async {
    if (!widget.flags.enableVAT) {
      if (mounted) {
        setState(() {
          _invoiceHistory = const <VatIssuedInvoice>[];
          _loadingHistory = false;
        });
      }
      return;
    }

    try {
      final invoices = await _invoiceService.loadInvoices(limit: 20);
      if (!mounted) return;
      setState(() {
        _invoiceHistory = invoices;
        _loadingHistory = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingHistory = false);
    }
  }

  double get _subTotal {
    return _buildDraftItems().fold<double>(0, (sum, item) => sum + item.subTotal);
  }

  double get _totalTax {
    return _buildDraftItems().fold<double>(0, (sum, item) => sum + item.taxAmount);
  }

  double get _grandTotal => _subTotal + _totalTax;

  void _addItem() {
    setState(() {
      _items.add(_InvoiceItemFormData());
    });
  }

  void _removeItem(int index) {
    if (_items.length <= 1) return;
    setState(() {
      final removed = _items.removeAt(index);
      removed.dispose();
    });
  }

  List<VatItemDraft> _buildDraftItems() {
    return _items.map((item) {
      final quantity = int.tryParse(item.quantityController.text.trim()) ?? 0;
      final unitPrice = double.tryParse(item.priceController.text.trim()) ?? 0;
      return VatItemDraft(
        productName: item.nameController.text.trim(),
        quantity: quantity,
        unitPrice: unitPrice,
        taxPercent: item.taxPercent,
      );
    }).toList(growable: false);
  }

  Future<void> _submitInvoice({required bool isIssueAction}) async {
    if (!widget.flags.enableVAT) {
      _showMessage('Module VAT đang tắt (enableVAT=false).', isError: true);
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final items = _buildDraftItems();
    if (items.any((item) => item.quantity <= 0 || item.unitPrice <= 0 || item.productName.isEmpty)) {
      _showMessage('Vui lòng nhập đầy đủ thông tin hàng hóa hợp lệ.', isError: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      final invoiceNo = 'INV-${DateTime.now().millisecondsSinceEpoch}';
      await _invoiceService.issueAndSaveInvoice(
        invoiceNo: invoiceNo,
        buyer: VatBuyerInfo(
          companyName: _companyController.text.trim(),
          taxCode: _taxCodeController.text.trim(),
          address: _addressController.text.trim(),
          email: _emailController.text.trim(),
        ),
        items: items,
      );

      await _loadInvoices();
      _showMessage(isIssueAction ? 'Xuất hóa đơn thành công.' : 'Lưu hóa đơn thành công.');

      if (isIssueAction) {
        _clearForm();
      }
    } on ArgumentError catch (e) {
      _showMessage(e.message?.toString() ?? 'Dữ liệu không hợp lệ.', isError: true);
    } catch (_) {
      _showMessage('Không thể lưu hóa đơn VAT. Vui lòng thử lại.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _clearForm() {
    _companyController.clear();
    _taxCodeController.clear();
    _addressController.clear();
    _emailController.clear();

    for (final item in _items) {
      item.dispose();
    }

    setState(() {
      _items
        ..clear()
        ..add(_InvoiceItemFormData());
    });
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  String _money(double value) {
    return value.toStringAsFixed(0);
  }

  Widget _safeSection(String sectionName, Widget Function() builder) {
    try {
      return builder();
    } catch (e) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Text(
          'Lỗi hiển thị phần "$sectionName": $e',
          style: const TextStyle(color: Colors.red),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(title: const Text('Tạo hóa đơn VAT')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE7ECF5)),
              ),
              child: const Text(
                'Nhập thông tin để tạo hóa đơn VAT.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            _safeSection('buyer_info', _buildBuyerInfoSection),
            const SizedBox(height: 16),
            _safeSection('item_list', _buildItemSection),
            const SizedBox(height: 16),
            _safeSection('total', _buildTotalSection),
            const SizedBox(height: 16),
            _safeSection('actions', _buildActionButtons),
            const SizedBox(height: 24),
            _safeSection('history', _buildHistorySection),
          ],
        ),
      ),
    );
  }

  Widget _buildBuyerInfoSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Thông tin người mua', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _companyController,
              decoration: const InputDecoration(labelText: 'Tên công ty'),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Vui lòng nhập tên công ty.' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _taxCodeController,
              decoration: const InputDecoration(labelText: 'Mã số thuế'),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return 'Vui lòng nhập mã số thuế.';
                if (!_vatModuleService.isValidTaxCode(text)) {
                  return 'Mã số thuế không hợp lệ.';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _addressController,
              decoration: const InputDecoration(labelText: 'Địa chỉ'),
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Vui lòng nhập địa chỉ.' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return 'Vui lòng nhập email.';
                if (!text.contains('@') || text.startsWith('@') || text.endsWith('@')) {
                  return 'Email không hợp lệ.';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text('Danh sách hàng', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                OutlinedButton.icon(
                  onPressed: _addItem,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm hàng'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < _items.length; i++) ...<Widget>[
              _buildItemCard(index: i, item: _items[i]),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildItemCard({required int index, required _InvoiceItemFormData item}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: <Widget>[
          TextFormField(
            controller: item.nameController,
            decoration: InputDecoration(
              labelText: 'Tên hàng #${index + 1}',
              suffixIcon: IconButton(
                onPressed: () => _removeItem(index),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
            onChanged: (_) => setState(() {}),
            validator: (value) => (value == null || value.trim().isEmpty) ? 'Nhập tên hàng.' : null,
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextFormField(
                  controller: item.quantityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Số lượng'),
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    final qty = int.tryParse(value?.trim() ?? '');
                    if (qty == null || qty <= 0) return 'SL > 0';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: item.priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Giá'),
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    final price = double.tryParse(value?.trim() ?? '');
                    if (price == null || price <= 0) return 'Giá > 0';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int>(
                    initialValue: item.taxPercent,
                  decoration: const InputDecoration(labelText: 'Thuế suất'),
                  items: const <DropdownMenuItem<int>>[
                    DropdownMenuItem<int>(value: 0, child: Text('0%')),
                    DropdownMenuItem<int>(value: 5, child: Text('5%')),
                    DropdownMenuItem<int>(value: 10, child: Text('10%')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => item.taxPercent = value);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTotalSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Tổng tiền', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _totalLine('Tạm tính', _money(_subTotal)),
            _totalLine('Thuế', _money(_totalTax)),
            const Divider(),
            _totalLine('Tổng', _money(_grandTotal), isBold: true),
          ],
        ),
      ),
    );
  }

  Widget _totalLine(String label, String value, {bool isBold = false}) {
    final style = TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: <Widget>[
        Expanded(
          child: OutlinedButton(
            onPressed: _submitting ? null : () => _submitInvoice(isIssueAction: false),
            child: const Text('Lưu'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton(
            onPressed: _submitting ? null : () => _submitInvoice(isIssueAction: true),
            child: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Xuất hóa đơn'),
          ),
        ),
      ],
    );
  }

  Widget _buildHistorySection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Hóa đơn đã lưu', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_loadingHistory)
              const Center(child: CircularProgressIndicator())
            else if (_invoiceHistory.isEmpty)
              const Text('Chưa có hóa đơn VAT.')
            else
              ..._invoiceHistory.map(
                (invoice) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${invoice.invoiceNo} - ${invoice.buyer.companyName}'),
                  subtitle: Text('MST: ${invoice.buyer.taxCode} | Tổng: ${_money(invoice.grandTotal)}'),
                  trailing: const Icon(Icons.lock, size: 18),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceItemFormData {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController quantityController = TextEditingController(text: '1');
  final TextEditingController priceController = TextEditingController();
  int taxPercent = 10;

  void dispose() {
    nameController.dispose();
    quantityController.dispose();
    priceController.dispose();
  }
}
