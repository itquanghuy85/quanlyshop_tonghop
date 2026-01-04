import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../core/utils/money_utils.dart';
import '../data/db_helper.dart';
import '../models/supplier_model.dart';
import '../models/repair_partner_model.dart';
import '../models/supplier_import_history_model.dart';
import '../models/supplier_product_prices_model.dart';
import '../models/supplier_payment_model.dart';
import '../models/repair_partner_payment_model.dart';
import '../controllers/fast_inventory_input_controller.dart';
import '../services/event_bus.dart';
import '../services/supplier_service.dart';
import '../services/repair_partner_service.dart';
import '../services/supplier_payment_service.dart';
import '../services/repair_partner_payment_service.dart';
import '../services/user_service.dart';
import '../widgets/validated_text_field.dart';

class PartnerManagementView extends StatefulWidget {
  const PartnerManagementView({super.key});

  @override
  State<PartnerManagementView> createState() => _PartnerManagementViewState();
}

class _PartnerManagementViewState extends State<PartnerManagementView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DBHelper _db = DBHelper();

  // Repair Partners
  List<RepairPartner> _repairPartners = [];
  List<SupplierImportHistory> _partnerImportHistory = [];
  List<RepairPartnerPayment> _partnerPayments = [];

  // Suppliers
  List<Supplier> _suppliers = [];
  List<SupplierImportHistory> _supplierImportHistory = [];
  List<SupplierProductPrices> _supplierProductPrices = [];
  List<SupplierPayment> _supplierPayments = [];
  List<Map<String, dynamic>> _supplierDebts = []; // Thêm debts cho suppliers

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      // Load repair partners
      final partnerService = RepairPartnerService();
      _repairPartners = await partnerService.getRepairPartners();

      // Load suppliers
      final supplierService = SupplierService();
      _suppliers = await supplierService.getSuppliers();

      // Load import history for partners (assuming partners can have import history)
      for (var partner in _repairPartners) {
        final history = await supplierService.getSupplierImportHistory(partner.id.toString());
        _partnerImportHistory.addAll(history);
      }

      // Load import history for suppliers
      for (var supplier in _suppliers) {
        final history = await supplierService.getSupplierImportHistory(supplier.id.toString());
        _supplierImportHistory.addAll(history);
        final prices = await supplierService.getSupplierProductPrices(supplier.id.toString());
        _supplierProductPrices.addAll(prices);
      }

      // Load payments
      final partnerPaymentService = RepairPartnerPaymentService();
      final supplierPaymentService = SupplierPaymentService();
      for (var partner in _repairPartners) {
        final payments = await partnerPaymentService.getPartnerPayments(partner.id!);
        _partnerPayments.addAll(payments);
      }
      for (var supplier in _suppliers) {
        final payments = await supplierPaymentService.getSupplierPayments(supplier.id!);
        _supplierPayments.addAll(payments);
      }

      // Load debts for suppliers (SHOP_OWES type)
      _supplierDebts = await _db.getAllDebts();
      _supplierDebts = _supplierDebts.where((debt) => 
        debt['type'] == 'SHOP_OWES' && debt['status'] != 'paid'
      ).toList();

    } catch (e) {
      debugPrint('Error loading data: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QUẢN LÝ ĐỐI TÁC & NHÀ CUNG CẤP'),
        bottom: TabBar(
          controller: _tabController,
          labelStyle: TextStyle(fontSize: 12),
          tabs: const [
            Tab(text: 'ĐỐI TÁC SỬA CHỮA'),
            Tab(text: 'NHÀ CUNG CẤP'),
          ],
        ),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : TabBarView(
            controller: _tabController,
            children: [
              _buildRepairPartnersTab(),
              _buildSuppliersTab(),
            ],
          ),
      floatingActionButton: FloatingActionButton(
        mini: true,
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildRepairPartnersTab() {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const TabBar(
            labelStyle: TextStyle(fontSize: 12),
            tabs: [
              Tab(text: 'DANH SÁCH'),
              Tab(text: 'LỊCH SỬ NHẬP'),
              Tab(text: 'THANH TOÁN'),
              Tab(text: 'THỐNG KÊ'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildPartnersList(),
                _buildPartnerImportHistory(),
                _buildPartnerPayments(),
                _buildPartnerStats(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuppliersTab() {
    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          const TabBar(
            labelStyle: TextStyle(fontSize: 12),
            tabs: [
              Tab(text: 'D/SÁCH'),
              Tab(text: 'L/ SỬ NHẬP'),
              Tab(text: 'GIÁ S/PHẨM'),
              Tab(text: 'T/TOÁN'),
              Tab(text: 'T KÊ'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildSuppliersList(),
                _buildSupplierImportHistory(),
                _buildSupplierProductPrices(),
                _buildSupplierPayments(),
                _buildSupplierStats(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPartnersList() {
    return ListView.builder(
      itemCount: _repairPartners.length,
      itemBuilder: (ctx, i) {
        final partner = _repairPartners[i];
        return Card(
          child: ListTile(
            title: Text(partner.name, style: TextStyle(fontSize: 14)),
            subtitle: Text(partner.phone ?? 'Không có SĐT', style: TextStyle(fontSize: 12)),
            trailing: IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _showEditPartnerDialog(partner),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSuppliersList() {
    return ListView.builder(
      itemCount: _suppliers.length,
      itemBuilder: (ctx, i) {
        final supplier = _suppliers[i];
        return Card(
          child: ListTile(
            title: Text(supplier.name, style: TextStyle(fontSize: 14)),
            subtitle: Text('${supplier.phone ?? ''} - ${supplier.email ?? ''}', style: TextStyle(fontSize: 12)),
            trailing: IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _showEditSupplierDialog(supplier),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPartnerImportHistory() {
    return ListView.builder(
      itemCount: _partnerImportHistory.length,
      itemBuilder: (ctx, i) {
        final history = _partnerImportHistory[i];
        return Card(
          child: ListTile(
            title: Text('Lô ${history.batchId}', style: TextStyle(fontSize: 14)),
            subtitle: Text('Tổng: ${MoneyUtils.formatVND(history.totalCost.toInt())}₫ - ${DateFormat('dd/MM/yyyy').format(DateTime.fromMillisecondsSinceEpoch(history.createdAt))}', style: TextStyle(fontSize: 12)),
          ),
        );
      },
    );
  }

  Widget _buildSupplierImportHistory() {
    return ListView.builder(
      itemCount: _supplierImportHistory.length,
      itemBuilder: (ctx, i) {
        final history = _supplierImportHistory[i];
        return Card(
          child: ListTile(
            title: Text('Lô ${history.batchId}', style: TextStyle(fontSize: 14)),
            subtitle: Text('Tổng: ${MoneyUtils.formatVND(history.totalCost.toInt())}₫ - ${DateFormat('dd/MM/yyyy').format(DateTime.fromMillisecondsSinceEpoch(history.createdAt))}', style: TextStyle(fontSize: 12)),
          ),
        );
      },
    );
  }

  Widget _buildSupplierProductPrices() {
    return ListView.builder(
      itemCount: _supplierProductPrices.length,
      itemBuilder: (ctx, i) {
        final price = _supplierProductPrices[i];
        return Card(
          child: ListTile(
            title: Text(price.productId, style: TextStyle(fontSize: 14)),
            subtitle: Text('Giá nhập: ${MoneyUtils.formatVND(price.costPrice.toInt())}₫ - Giá bán: ${MoneyUtils.formatVND(price.sellingPrice.toInt())}₫', style: TextStyle(fontSize: 12)),
          ),
        );
      },
    );
  }

  Widget _buildPartnerPayments() {
    return ListView.builder(
      itemCount: _partnerPayments.length,
      itemBuilder: (ctx, i) {
        final payment = _partnerPayments[i];
        return Card(
          child: ListTile(
            title: Text('${MoneyUtils.formatVND(payment.amount)}₫ - ${payment.paymentMethod}', style: TextStyle(fontSize: 14)),
            subtitle: Text('${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(payment.paidAt))} - ${payment.note ?? ''}', style: TextStyle(fontSize: 12)),
          ),
        );
      },
    );
  }

  Widget _buildSupplierPayments() {
    return ListView.builder(
      itemCount: _supplierPayments.length,
      itemBuilder: (ctx, i) {
        final payment = _supplierPayments[i];
        return Card(
          child: ListTile(
            title: Text('${MoneyUtils.formatVND(payment.amount)}₫ - ${payment.paymentMethod}', style: TextStyle(fontSize: 14)),
            subtitle: Text('${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(payment.paidAt))} - ${payment.note ?? ''}', style: TextStyle(fontSize: 12)),
          ),
        );
      },
    );
  }

  Widget _buildPartnerStats() {
    final totalPaid = _partnerPayments.fold<int>(0, (sum, p) => sum + p.amount);
    final paymentStats = <String, int>{};
    for (var p in _partnerPayments) {
      paymentStats[p.paymentMethod] = (paymentStats[p.paymentMethod] ?? 0) + p.amount;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text('Tổng thanh toán: ${MoneyUtils.formatVND(totalPaid)}₫', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sections: paymentStats.entries.map((e) => PieChartSectionData(
                  value: e.value.toDouble(),
                  title: '${e.key}\n${MoneyUtils.formatVND(e.value)}₫',
                  color: Colors.primaries[paymentStats.keys.toList().indexOf(e.key) % Colors.primaries.length],
                )).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupplierStats() {
    final totalPaid = _supplierPayments.fold<int>(0, (sum, p) => sum + p.amount);
    
    // Tính tổng công nợ cho suppliers
    final supplierDebtStats = <String, Map<String, dynamic>>{};
    for (var supplier in _suppliers) {
      final supplierDebts = _supplierDebts.where((debt) => 
        debt['personName'] == supplier.name
      ).toList();
      
      int totalOwed = 0;
      for (var debt in supplierDebts) {
        final int total = debt['totalAmount'] ?? 0;
        final int paid = debt['paidAmount'] ?? 0;
        totalOwed += (total - paid);
      }
      
      if (totalOwed > 0 || supplierDebts.isNotEmpty) {
        supplierDebtStats[supplier.name] = {
          'totalOwed': totalOwed,
          'debtCount': supplierDebts.length,
        };
      }
    }
    
    final totalOwedAll = supplierDebtStats.values.fold<int>(0, (sum, stat) => sum + (stat['totalOwed'] as int));
    
    final paymentStats = <String, int>{};
    for (var p in _supplierPayments) {
      paymentStats[p.paymentMethod] = (paymentStats[p.paymentMethod] ?? 0) + p.amount;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tổng quan thanh toán
          Text('💰 TỔNG THANH TOÁN: ${MoneyUtils.formatVND(totalPaid)}₫', 
               style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
          
          const SizedBox(height: 16),
          
          // Tổng quan công nợ
          Text('💸 TỔNG CÔNG NỢ: ${MoneyUtils.formatVND(totalOwedAll)}₫', 
               style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
          
          const SizedBox(height: 20),
          
          // Chi tiết công nợ theo supplier
          if (supplierDebtStats.isNotEmpty) ...[
            Text('📋 CHI TIẾT CÔNG NỢ THEO NCC:', 
                 style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...supplierDebtStats.entries.map((entry) => 
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        entry.key,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    Text(
                      '${MoneyUtils.formatVND(entry.value['totalOwed'])}₫ (${entry.value['debtCount']} khoản)',
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )
            ),
            const SizedBox(height: 20),
          ],
          
          // Biểu đồ thanh toán
          Text('📊 THỐNG KÊ THANH TOÁN:', 
               style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: paymentStats.isEmpty 
              ? const Center(child: Text('Chưa có dữ liệu thanh toán'))
              : PieChart(
                  PieChartData(
                    sections: paymentStats.entries.map((e) => PieChartSectionData(
                      value: e.value.toDouble(),
                      title: '${e.key}\n${MoneyUtils.formatVND(e.value)}₫',
                      color: Colors.primaries[paymentStats.keys.toList().indexOf(e.key) % Colors.primaries.length],
                    )).toList(),
                  ),
                ),
          ),
        ],
      ),
    );
  }

  void _showAddDialog() {
    if (_tabController.index == 0) {
      _showAddPartnerDialog();
    } else {
      _showAddSupplierDialog();
    }
  }

  void _showAddPartnerDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm đối tác sửa chữa'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValidatedTextField(controller: nameCtrl, label: 'Tên đối tác *'),
            ValidatedTextField(controller: phoneCtrl, label: 'Số điện thoại'),
            ValidatedTextField(controller: noteCtrl, label: 'Ghi chú'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.isEmpty) return;
              final service = RepairPartnerService();
              final partner = RepairPartner(
                name: nameCtrl.text.trim().toUpperCase(),
                phone: phoneCtrl.text.trim(),
                note: noteCtrl.text.trim(),
                shopId: (await UserService.getCurrentShopId())!,
              );
              await service.addRepairPartner(partner);
              _loadData();
              Navigator.pop(ctx);
            },
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
  }

  void _showAddSupplierDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final addressCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm nhà cung cấp'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValidatedTextField(controller: nameCtrl, label: 'Tên nhà cung cấp *'),
            ValidatedTextField(controller: phoneCtrl, label: 'Số điện thoại'),
            ValidatedTextField(controller: emailCtrl, label: 'Email'),
            ValidatedTextField(controller: addressCtrl, label: 'Địa chỉ'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Vui lòng nhập tên nhà cung cấp')),
                );
                return;
              }
              
              try {
                final service = SupplierService();
                final supplier = Supplier(
                  name: nameCtrl.text.trim().toUpperCase(),
                  phone: phoneCtrl.text.trim(),
                  email: emailCtrl.text.trim(),
                  address: addressCtrl.text.trim(),
                  shopId: (await UserService.getCurrentShopId())!,
                );
                
                final result = await service.addSupplier(supplier);
                if (result != null) {
                  // Clear supplier cache in other controllers
                  FastInventoryInputController().clearSupplierCache();
                  // Send event to refresh other views
                  EventBus().emit('suppliers_changed');
                  await _loadData();
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Đã thêm nhà cung cấp thành công')),
                  );
                } else {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Lỗi: Không thể thêm nhà cung cấp')),
                  );
                }
              } catch (e) {
                debugPrint('Error adding supplier: $e');
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('Lỗi: $e')),
                );
              }
            },
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
  }

  void _showEditPartnerDialog(RepairPartner partner) {
    // Similar to add, but pre-fill
  }

  void _showEditSupplierDialog(Supplier supplier) {
    // Similar to add, but pre-fill
  }
}