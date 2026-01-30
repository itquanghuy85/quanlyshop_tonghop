import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/db_helper.dart';
import '../models/repair_model.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';
import '../services/sync_orchestrator.dart';
import '../services/firestore_service.dart';
import '../services/unified_printer_service.dart';
import '../services/adjustment_service.dart';
import '../services/first_time_guide_service.dart';
import '../utils/money_utils.dart';
import '../widgets/currency_text_field.dart';
import '../widgets/validated_text_field.dart';
import '../widgets/currency_text_field.dart';
import '../widgets/section_card.dart';
import '../models/repair_partner_model.dart';
import '../models/repair_service_model.dart';
import '../services/repair_partner_service.dart';
import '../services/user_service.dart';
import '../services/payment_intent_service.dart';
import '../models/customer_model.dart';
import '../models/payment_intent_model.dart';
import '../services/customer_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../services/event_bus.dart';
import '../widgets/custom_app_bar.dart';
import '../l10n/app_localizations.dart';

class CreateRepairOrderView extends StatefulWidget {
  final String role;
  const CreateRepairOrderView({super.key, this.role = 'user'});

  @override
  State<CreateRepairOrderView> createState() => _CreateRepairOrderViewState();
}

class _CreateRepairOrderViewState extends State<CreateRepairOrderView> {
  // final NumberFormat currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');
  final db = DBHelper();
  final customerService = CustomerService();
  final List<File> _images = [];
  bool _saving = false;
  String _uploadStatus = "";

  final phoneCtrl = TextEditingController();
  final nameCtrl = TextEditingController();
  final addressCtrl = TextEditingController();
  final modelCtrl = TextEditingController();
  final issueCtrl = TextEditingController();
  final appearanceCtrl = TextEditingController();
  final accCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final priceCtrl = TextEditingController();
  final notesCtrl = TextEditingController(); // Ghi chú đơn sửa

  final phoneF = FocusNode();
  final nameF = FocusNode();
  final modelF = FocusNode();
  final issueF = FocusNode();
  final priceF = FocusNode();
  final passF = FocusNode();
  final appearanceF = FocusNode();
  final accF = FocusNode();

  // Services with partners
  final List<RepairService> _services = [];
  List<RepairPartner> _partners = [];
  bool _isWalkIn = false;

  final List<String> brands = ["IPHONE", "SAMSUNG", "OPPO", "REDMI", "VIVO"];
  final List<String> commonIssues = [
    "THAY PIN",
    "ÉP KÍNH",
    "THAY MÀN",
    "MẤT NGUỒN",
    "LOA/MIC",
    "SẠC",
    "PHẦN MỀM",
  ];

  final List<String> quickAccs = ["SIM", "ỐP LƯNG", "KO PHỤ KIỆN"];
  final Set<String> _selectedAccs = {};

  @override
  void initState() {
    super.initState();
    phoneCtrl.addListener(() {
      if (phoneCtrl.text.length == 10) _smartFill();
      setState(() {}); // Refresh UI for add customer button
    });
    nameCtrl.addListener(
      () => setState(() {}),
    ); // Refresh UI for add customer button
    _loadPartners();
    // Hiển thị hướng dẫn cho người dùng mới
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showFirstTimeGuide();
    });
  }

  /// Hiển thị hướng dẫn lần đầu
  Future<void> _showFirstTimeGuide() async {
    await FirstTimeGuideService.showCarouselGuide(
      context: context,
      screenKey: FirstTimeGuideService.keyCreateRepair,
      title: 'Tạo Đơn Sửa Chữa',
      color: Colors.blue,
      steps: const [
        GuideStep(
          title: '📞 Nhập SĐT khách hàng',
          description: 'Nhập 10 số điện thoại, hệ thống tự động điền tên nếu khách cũ. Hoặc chọn từ danh bạ.',
          icon: Icons.phone,
          iconColor: Colors.green,
        ),
        GuideStep(
          title: '📱 Thông tin máy',
          description: 'Chọn hãng nhanh hoặc nhập model. Mô tả lỗi chi tiết để thợ hiểu rõ vấn đề.',
          icon: Icons.smartphone,
          iconColor: Colors.blue,
        ),
        GuideStep(
          title: '📝 Tình trạng máy',
          description: 'Ghi nhận ngoại quan (xước, móp) và phụ kiện đi kèm (SIM, ốp) để tránh tranh cãi sau này.',
          icon: Icons.checklist,
          iconColor: Colors.orange,
        ),
        GuideStep(
          title: '🔧 Dịch vụ & Đối tác',
          description: 'Thêm dịch vụ sửa chữa, chọn đối tác ngoài nếu cần gửi ra. Hệ thống tự tính công nợ.',
          icon: Icons.build,
          iconColor: Colors.purple,
        ),
        GuideStep(
          title: '💰 Giá dự kiến',
          description: 'Nhập giá báo khách. Có thể điều chỉnh sau khi sửa xong nếu phát sinh thêm.',
          icon: Icons.attach_money,
          iconColor: Colors.amber,
        ),
        GuideStep(
          title: '📸 Chụp ảnh máy',
          description: 'Chụp ảnh trước khi sửa để làm bằng chứng. Tối đa 5 ảnh, lưu trên cloud.',
          icon: Icons.camera_alt,
          iconColor: Colors.teal,
        ),
      ],
    );
  }

  void _loadPartners() async {
    try {
      final service = RepairPartnerService();
      final partners = await service.getRepairPartners();
      setState(() {
        _partners = partners.where((p) => p.active).toList();
      });
    } catch (e) {
      debugPrint('Error loading partners: $e');
    }
  }

  void _smartFill() async {
    final res = await db.getUniqueCustomersAll();
    final find = res.where((c) => c['phone'] == phoneCtrl.text).toList();
    if (find.isNotEmpty) {
      setState(() {
        nameCtrl.text = find.first['customerName'] ?? "";
        addressCtrl.text = (find.first['address'] ?? "").toString();
      });
    }
  }

  Future<void> _selectCustomer() async {
    debugPrint("_selectCustomer: bắt đầu chọn khách hàng");
    // Sync customers from cloud first (ignore errors)
    debugPrint("_selectCustomer: bắt đầu sync từ cloud");
    try {
      await SyncService.syncCustomersFromCloud();
      debugPrint("_selectCustomer: đã sync xong từ cloud");
    } catch (e) {
      debugPrint("_selectCustomer: lỗi sync từ cloud (ignored): $e");
    }

    List<Customer> customers = [];
    try {
      customers = await customerService.getCustomers();
      debugPrint(
        "_selectCustomer: lấy được ${customers.length} customers từ local DB",
      );
    } catch (e) {
      debugPrint("_selectCustomer: lỗi lấy customers: $e");
    }

    // Fallback: lấy danh sách khách độc nhất từ lịch sử nếu chưa có trong bảng customers
    if (customers.isEmpty) {
      try {
        final unique = await db.getUniqueCustomersAll();
        customers = unique
            .map(
              (c) => Customer(
                name: (c['customerName'] ?? '').toString(),
                phone: (c['phone'] ?? '').toString(),
                address: (c['address'] ?? '').toString(),
                createdAt: DateTime.now().millisecondsSinceEpoch,
              ),
            )
            .where((c) => c.phone.isNotEmpty)
            .toList();
        debugPrint(
          "_selectCustomer: fallback ${customers.length} customers từ history",
        );
      } catch (e) {
        debugPrint("_selectCustomer: lỗi fallback: $e");
      }
    }
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => CustomerSelectionDialog(
        customers: customers,
        onSelect: (customer) {
          setState(() {
            nameCtrl.text = customer.name;
            phoneCtrl.text = customer.phone;
            addressCtrl.text = customer.address ?? '';
          });
          Navigator.pop(ctx);
        },
      ),
    );
  }

  Future<void> _addCustomerQuick() async {
    if (_isWalkIn) {
      NotificationService.showSnackBar(
        "Khách vãng lai không lưu danh bạ",
        color: Colors.blue,
      );
      return;
    }
    final name = nameCtrl.text.trim().toUpperCase();
    final phone = phoneCtrl.text.trim();
    final address = addressCtrl.text.trim().toUpperCase();

    if (name.isEmpty || phone.isEmpty) {
      NotificationService.showSnackBar(
        "Vui lòng nhập đủ tên và số điện thoại",
        color: Colors.orange,
      );
      return;
    }

    // Kiểm tra phone format
    final phoneError = UserService.validatePhone(
      phone,
      AppLocalizations.of(context)!,
    );
    if (phoneError != null) {
      NotificationService.showSnackBar(phoneError, color: Colors.red);
      return;
    }

    try {
      // Kiểm tra khách hàng đã tồn tại chưa
      final existingCustomers = await customerService.getCustomers();
      final existing = existingCustomers
          .where((c) => c.phone == phone)
          .toList();

      if (existing.isNotEmpty) {
        NotificationService.showSnackBar(
          "Khách hàng với SĐT này đã tồn tại: ${existing.first.name}",
          color: Colors.orange,
        );
        return;
      }

      final newCustomer = Customer(
        name: name,
        phone: phone,
        address: address,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await customerService.addCustomer(newCustomer);

      NotificationService.showSnackBar(
        "Đã thêm khách hàng: $name",
        color: Colors.green,
      );
      HapticFeedback.lightImpact();
    } catch (e) {
      NotificationService.showSnackBar(
        "Lỗi thêm khách hàng: $e",
        color: Colors.red,
      );
    }
  }

  int _parseFinalPrice(String text) {
    // Parse giá trị và áp dụng rule nhân 1000 nếu < 100000
    // Dùng MoneyUtils.parseMoney để đảm bảo logic đồng nhất
    return MoneyUtils.parseMoney(text);
  }

  Future<Repair?> _saveOrderProcess() async {
    debugPrint('🔧 _saveOrderProcess: Starting...');
    // Finalize currency fields trước khi xử lý
    CurrencyTextField.finalizeAll();

    // Kiểm tra ngày hôm nay đã chốt quỹ chưa
    final today = DateTime.now();
    debugPrint('🔧 _saveOrderProcess: Checking canEditDirectly for today...');
    final canEdit = await AdjustmentService.canEditDirectly(
      today.millisecondsSinceEpoch,
    );
    debugPrint('🔧 _saveOrderProcess: canEdit = $canEdit');
    if (!canEdit && mounted) {
      NotificationService.showSnackBar(
        '❌ Ngày hôm nay đã chốt quỹ! Không thể tạo phiếu sửa mới.',
        color: Colors.red,
      );
      return null;
    }

    final isPhoneMissing = phoneCtrl.text.isEmpty;
    if (modelCtrl.text.isEmpty || (!_isWalkIn && isPhoneMissing)) {
      debugPrint(
        '🔧 _saveOrderProcess: Validation failed - phone or model empty',
      );
      NotificationService.showSnackBar(
        _isWalkIn
            ? "Vui lòng nhập Model máy"
            : "Vui lòng nhập SĐT và Model máy",
        color: Colors.red,
      );
      return null;
    }

    debugPrint('🔧 _saveOrderProcess: Validation passed, starting save...');

    setState(() {
      _saving = true;
      _uploadStatus = "Đang đồng bộ dữ liệu lên server...";
    });
    try {
      String cloudImagePaths = "";
      if (_images.isNotEmpty) {
        List<String> localPaths = _images.map((e) => e.path).toList();
        cloudImagePaths = await StorageService.uploadMultipleAndJoin(
          localPaths.join(','),
          'repairs',
        );
      }

      String finalAccs = _selectedAccs.join(', ');
      if (accCtrl.text.isNotEmpty) {
        finalAccs = finalAccs.isEmpty
            ? accCtrl.text.toUpperCase()
            : "$finalAccs, ${accCtrl.text.toUpperCase()}";
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final totalCost = _services.fold(0, (sum, s) => sum + s.cost);
      final fallbackName = nameCtrl.text.trim().isEmpty
          ? 'KHÁCH VÃNG LAI'
          : nameCtrl.text.trim().toUpperCase();
      final normalizedPhone = phoneCtrl.text.trim();
      final docIdTail = normalizedPhone.isNotEmpty ? normalizedPhone : 'walkin';
      final r = Repair(
        firestoreId: "rep_${now}_${docIdTail}",
        customerName: fallbackName,
        phone: normalizedPhone,
        isWalkIn: _isWalkIn,
        walkInName: _isWalkIn ? fallbackName : null,
        walkInPhone: _isWalkIn && normalizedPhone.isNotEmpty
            ? normalizedPhone
            : null,
        model: modelCtrl.text.trim().toUpperCase(),
        issue: issueCtrl.text.trim().toUpperCase(),
        accessories: "$finalAccs | MK: ${passCtrl.text}".trim().toUpperCase(),
        address: addressCtrl.text.trim().toUpperCase(),
        price: _parseFinalPrice(priceCtrl.text),
        cost: totalCost,
        createdAt: now,
        imagePath: cloudImagePaths,
        createdBy:
            FirebaseAuth.instance.currentUser?.email
                ?.split('@')
                .first
                .toUpperCase() ??
            "NV",
        services: _services,
        notes: notesCtrl.text.trim().isNotEmpty ? notesCtrl.text.trim() : null,
      );

      // Lưu local trước
      await db.upsertRepair(r);

      // Lấy local ID để enqueue
      final savedRepair = await db.getRepairByFirestoreId(r.firestoreId!);
      if (savedRepair == null || savedRepair.id == null) {
        throw Exception('Không thể lưu đơn sửa vào local database');
      }

      // Create customer if not exists
      final existingCustomers = await customerService.getCustomers();
      final existing = existingCustomers
          .where((c) => c.phone == phoneCtrl.text.trim())
          .toList();
      if (existing.isEmpty) {
        final newCustomer = Customer(
          name: nameCtrl.text.trim().toUpperCase(),
          phone: phoneCtrl.text.trim(),
          address: addressCtrl.text.trim().toUpperCase(),
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );
        await customerService.addCustomer(newCustomer);
      }

      // Enqueue sync lên cloud
      await SyncOrchestrator().enqueue(
        entityType: SyncEntityType.repair,
        entityId: savedRepair.id!,
        firestoreId: r.firestoreId,
        operation: SyncOperation.create,
        data: r.toMap(),
      );

      // Trigger sync ngay và chờ kết quả
      debugPrint('🔧 Triggering immediate sync for new repair...');
      final syncResult = await SyncOrchestrator().syncAll();
      debugPrint('🔧 Sync result: success=${syncResult.success}, failed=${syncResult.failed}');
      
      // Nếu sync thất bại, thử upload trực tiếp lên Firestore
      if (syncResult.failed > 0 || syncResult.noNetwork) {
        debugPrint('🔧 Queue sync failed, trying direct Firestore upload...');
        try {
          final firestoreId = await FirestoreService.addRepair(savedRepair);
          if (firestoreId != null) {
            debugPrint('🔧 Direct upload successful: $firestoreId');
          }
        } catch (e) {
          debugPrint('🔧 Direct upload also failed: $e (will retry later)');
          // Don't throw - repair is saved locally and will sync later
        }
      }

      final rWithCloudId = savedRepair;
      await db.logAction(
        userId: FirebaseAuth.instance.currentUser?.uid ?? "0",
        userName: r.createdBy ?? "NV",
        action: "NHẬP ĐƠN SỬA",
        type: "REPAIR",
        targetId: rWithCloudId.firestoreId,
        desc:
            "Đã nhập đơn sửa ${rWithCloudId.model} cho khách ${rWithCloudId.customerName}",
      );

      // Handle partner outsourcing for services that have partners
      final service = RepairPartnerService();
      for (var s in _services.where((s) => s.partnerId != null)) {
        final success = await service.createPartnerHistoryForRepair(
          repairOrderId: rWithCloudId.firestoreId!,
          partnerId: s.partnerId!,
          partnerCost: s.cost,
          customerName: r.customerName,
          deviceModel: r.model,
          issue: s.serviceName,
          repairContent: s.serviceName,
        );
        if (!success) {
          debugPrint(
            'Warning: Partner history creation failed for service ${s.serviceName}',
          );
        }
        
        // === XỬ LÝ PAYMENT METHOD CHO DỊCH VỤ ĐỐI TÁC ===
        if (s.paymentMethod != null) {
          final shopId = await UserService.getCurrentShopId() ?? '';
          final nowTs = DateTime.now().millisecondsSinceEpoch;
          
          if (s.paymentMethod == 'CÔNG NỢ') {
            // CÔNG NỢ → tạo debt record vào bảng debts
            try {
              final debtFId = 'debt_partner_${nowTs}_${s.partnerId}';
              final debtData = {
                'firestoreId': debtFId,
                'type': 'SHOP_OWES', // Shop nợ đối tác
                'debtType': 'SHOP_OWES',
                'personName': s.partnerName ?? 'Đối tác sửa chữa',
                'phone': '',
                'totalAmount': s.cost,
                'paidAmount': 0,
                'note': 'Công nợ đối tác: ${s.serviceName} - Đơn sửa ${r.model} (${r.customerName})',
                'status': 'ACTIVE',
                'createdAt': nowTs,
                'shopId': shopId,
                'linkedId': rWithCloudId.firestoreId ?? '',
                'relatedPartId': s.partnerId?.toString() ?? '',
                'deleted': 0,
                'isSynced': 0,
              };
              final debtId = await db.insertDebt(debtData);
              
              // Sync debt to cloud
              if (debtId > 0) {
                await SyncOrchestrator().enqueue(
                  entityType: SyncEntityType.debt,
                  entityId: debtId,
                  firestoreId: debtFId,
                  operation: SyncOperation.create,
                  data: debtData,
                );
              }
              
              // Tạo PaymentIntent cho việc trả nợ sau này
              final intent = PaymentIntent(
                id: 'pi_partner_debt_${nowTs}_${s.partnerId}',
                type: PaymentIntentType.repairPartnerDebt,
                amount: s.cost,
                description: 'Trả nợ đối tác: ${s.partnerName ?? "N/A"} - ${s.serviceName}',
                referenceId: debtFId,
                referenceType: 'partner_debt',
                personName: s.partnerName,
                createdBy: FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
                createdAt: nowTs,
                metadata: {
                  'repairId': rWithCloudId.id,
                  'repairFirestoreId': rWithCloudId.firestoreId,
                  'partnerId': s.partnerId,
                  'partnerName': s.partnerName,
                  'serviceName': s.serviceName,
                  'debtId': debtId,
                  'debtFirestoreId': debtFId,
                  'debtType': 'SHOP_OWES',
                },
              );
              await PaymentIntentService.createIntent(intent);
              debugPrint('✅ Created partner debt record: $debtFId for ${s.partnerName}');
              
            } catch (e) {
              debugPrint('⚠️ Failed to create partner debt: $e');
            }
          } else {
            // TIỀN MẶT / CHUYỂN KHOẢN → tạo PaymentIntent để xác nhận chi
            try {
              final intent = PaymentIntent(
                id: 'pi_partner_service_${nowTs}_${s.partnerId}',
                type: PaymentIntentType.repairPartnerDebt,
                amount: s.cost,
                description: 'Trả đối tác: ${s.partnerName ?? "N/A"} - ${s.serviceName}',
                referenceId: rWithCloudId.firestoreId,
                referenceType: 'repair_partner_service',
                personName: s.partnerName,
                createdBy: FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
                createdAt: nowTs,
                metadata: {
                  'repairId': rWithCloudId.id,
                  'repairFirestoreId': rWithCloudId.firestoreId,
                  'partnerId': s.partnerId,
                  'partnerName': s.partnerName,
                  'serviceName': s.serviceName,
                  'paymentMethod': s.paymentMethod,
                },
              );
              await PaymentIntentService.createIntent(intent);
              debugPrint('💳 Created PaymentIntent for partner ${s.paymentMethod}: ${intent.id}');
            } catch (e) {
              debugPrint('⚠️ Failed to create partner PaymentIntent: $e');
            }
          }
        }
      }

      // Trigger new order notification
      try {
        await NotificationService.sendNewOrderNotification(
          rWithCloudId.firestoreId!,
          r.customerName,
          r.price,
        );
      } catch (e) {
        debugPrint('Failed to send new order notification: $e');
        // Don't fail the repair creation if notification fails
      }

      // Update customer stats (tổng số lần sửa chữa)
      try {
        await customerService.updateCustomerStatsAfterRepair(
          phoneCtrl.text.trim(),
          r.price,
        );
      } catch (e) {
        debugPrint('Failed to update customer stats: $e');
        // Don't fail the repair creation if stats update fails
      }

      return rWithCloudId;
    } catch (e) {
      NotificationService.showSnackBar("Lỗi: $e", color: Colors.red);
      return null;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onlySave() async {
    debugPrint('🔧 _onlySave: Starting save process...');
    final r = await _saveOrderProcess();
    debugPrint(
      '🔧 _onlySave: _saveOrderProcess returned: ${r != null ? 'success' : 'null'}',
    );
    if (r != null) {
      HapticFeedback.mediumImpact();

      // Notify other views about the new repair
      EventBus().emit('repairs_changed');

      debugPrint('🔧 _onlySave: Calling Navigator.pop...');
      if (mounted) Navigator.pop(context, true);
      NotificationService.showSnackBar(
        "ĐÃ LƯU ĐƠN THÀNH CÔNG",
        color: Colors.green,
      );
    } else {
      debugPrint('🔧 _onlySave: Save failed, r is null');
    }
  }

  Future<void> _saveAndPrint() async {
    final r = await _saveOrderProcess();
    if (r != null) {
      HapticFeedback.mediumImpact();
      NotificationService.showSnackBar(
        "Đang gửi lệnh in phiếu...",
        color: Colors.blue,
      );
      await UnifiedPrinterService.printRepairReceiptFromRepair(r, {
        'shopName': 'QUANG HUY',
        'shopAddr': 'HÀ NỘI',
        'shopPhone': '0964095979',
      });
      if (mounted) Navigator.pop(context, true);
    }
  }

  List<Widget> _buildServicesSection() {
    return [
      if (_services.isNotEmpty) ...[
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: _services
                .map(
                  (service) => ListTile(
                    title: Text(service.serviceName),
                    subtitle: service.partnerName != null
                        ? Text(
                            "Đối tác: ${service.partnerName} - Chi phí: ${MoneyUtils.formatVND(service.cost.toInt())}₫",
                          )
                        : Text(
                            "Chi phí: ${MoneyUtils.formatVND(service.cost.toInt())}₫",
                          ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () =>
                          setState(() => _services.remove(service)),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          "Tổng chi phí: ${MoneyUtils.formatVND(_services.fold(0, (sum, s) => sum + s.cost).toInt())} Vn₫",
          style: AppTextStyles.priceStyle,
        ),
        const SizedBox(height: 10),
      ],
      ElevatedButton.icon(
        onPressed: _showAddServiceDialog,
        icon: const Icon(Icons.add),
        label: const Text("THÊM DỊCH VỤ"),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
      ),
    ];
  }

  void _showAddServiceDialog([RepairService? editService]) {
    final formKey = GlobalKey<FormState>();
    final serviceCtrl = TextEditingController(
      text: editService?.serviceName ?? '',
    );
    final costCtrl = TextEditingController(
      text: editService != null
          ? CurrencyTextField.formatDisplay(editService.cost.toInt())
          : '',
    );
    RepairPartner? selectedPartner = editService != null
        ? _partners.firstWhere(
            (p) => p.id == editService.partnerId,
            orElse: () => _partners.first,
          )
        : null;
    if (editService != null &&
        selectedPartner == _partners.first &&
        editService.partnerId == null) {
      selectedPartner = null;
    }
    
    // Thêm payment method đồng bộ với repair_detail_view
    String? selectedPaymentMethod = editService?.paymentMethod ?? 'TIỀN MẶT';
    final paymentMethods = ['TIỀN MẶT', 'CHUYỂN KHOẢN', 'CÔNG NỢ'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(editService != null ? "Sửa dịch vụ" : "Thêm dịch vụ"),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: serviceCtrl,
                    decoration: const InputDecoration(labelText: "Tên dịch vụ *"),
                    textCapitalization: TextCapitalization.characters,
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? 'Vui lòng nhập tên dịch vụ'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  CurrencyTextField(
                    controller: costCtrl,
                    label: "Chi phí (VNĐ)",
                    validator: (v) => MoneyUtils.validateAmount(
                      v ?? '',
                      min: 1,
                      fieldName: 'Chi phí',
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<RepairPartner>(
                    decoration: const InputDecoration(
                      labelText: "Đối tác (tùy chọn)",
                    ),
                    initialValue: selectedPartner,
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text("Không có đối tác"),
                      ),
                      ..._partners.map(
                        (p) => DropdownMenuItem(value: p, child: Text(p.name)),
                      ),
                    ],
                    onChanged: (p) => setS(() => selectedPartner = p),
                  ),
                  // Phương thức thanh toán (chỉ hiện khi có đối tác) - đồng bộ với repair_detail_view
                  if (selectedPartner != null) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: "Phương thức TT đối tác *",
                        prefixIcon: Icon(Icons.payment, size: 20),
                      ),
                      value: selectedPaymentMethod,
                      items: paymentMethods
                          .map(
                            (m) => DropdownMenuItem(value: m, child: Text(m)),
                          )
                          .toList(),
                      onChanged: (v) => setS(() => selectedPaymentMethod = v),
                      validator: (v) =>
                          selectedPartner != null && (v == null || v.isEmpty)
                          ? 'Vui lòng chọn phương thức TT'
                          : null,
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Hủy"),
            ),
            ElevatedButton(
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) return;
                // Không nhân 1000 - user đã nhập số đầy đủ với formatter
                final cost = MoneyUtils.parseCurrency(costCtrl.text);
                final service = RepairService(
                  serviceName: serviceCtrl.text.trim().toUpperCase(),
                  cost: cost,
                  partnerId: selectedPartner?.id,
                  partnerName: selectedPartner?.name,
                  paymentMethod: selectedPartner != null ? selectedPaymentMethod : null,
                );
                setState(() {
                  if (editService != null) {
                    final index = _services.indexOf(editService);
                    _services[index] = service;
                  } else {
                    _services.add(service);
                  }
                });
                EventBus().emit('repair_services_changed');
                Navigator.pop(ctx);
              },
              child: Text(editService != null ? "Cập nhật" : "Thêm"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: CustomAppBar.build(
        title: 'NHẬP ĐƠN SỬA CHỮA',
        subtitle: 'Điền thông tin khách và máy',
        accentColor: AppBarAccents.repairs,
        actions: [
          IconButton(
            onPressed: _saveAndPrint,
            icon: Icon(Icons.print_rounded, color: AppBarAccents.repairs, size: 22),
            splashRadius: 20,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _saving
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_uploadStatus, style: AppTextStyles.caption),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // === COMPACT: KHÁCH + MÁY + LỖI trong 1 Card ===
                  _buildCompactMainSection(),
                  const SizedBox(height: 8),

                  // === DỊCH VỤ (ExpansionTile nếu chưa có) ===
                  _buildCompactServicesSection(),
                  const SizedBox(height: 8),

                  // === COMPACT: BẢO MẬT + PHỤ KIỆN trong 1 Card ===
                  _buildCompactSecurityAccessoriesSection(),
                  const SizedBox(height: 8),

                  // === GHI CHÚ + HÌNH ẢNH (ExpansionTile) ===
                  _buildCompactNotesImagesSection(),

                  const SizedBox(height: 16),
                  // === NÚT LƯU ===
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _onlySave,
                      icon: const Icon(Icons.save_rounded, size: 20),
                      label: const Text("LƯU ĐƠN", style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
    );
  }

  /// COMPACT: Khách hàng + Máy + Lỗi + Giá trong 1 Card
  Widget _buildCompactMainSection() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header với icon tìm khách
            Row(
              children: [
                Icon(Icons.person_outline, color: Colors.blue, size: 18),
                const SizedBox(width: 6),
                Text("KHÁCH HÀNG & MÁY", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue)),
                const Spacer(),
                IconButton(
                  onPressed: _selectCustomer,
                  icon: const Icon(Icons.search, size: 18),
                  tooltip: 'Chọn khách',
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                  color: Colors.blue,
                ),
                if (!_isWalkIn &&
                    nameCtrl.text.trim().isNotEmpty &&
                    phoneCtrl.text.trim().isNotEmpty)
                  IconButton(
                    onPressed: _addCustomerQuick,
                    icon: const Icon(Icons.person_add, size: 18, color: Colors.green),
                    tooltip: 'Thêm khách',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.only(left: 8),
                  ),
              ],
            ),
            const Divider(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Khách vãng lai (không lưu danh bạ)'),
              subtitle: Text(
                _isWalkIn
                    ? 'Tên/SĐT chỉ lưu trên phiếu, không bắt buộc SĐT'
                    : 'Nhập SĐT để lưu khách vào danh bạ',
                style: const TextStyle(fontSize: 12),
              ),
              value: _isWalkIn,
              onChanged: (v) {
                setState(() {
                  _isWalkIn = v;
                  if (_isWalkIn && nameCtrl.text.trim().isEmpty) {
                    nameCtrl.text = 'KHÁCH VÃNG LAI';
                  }
                });
              },
            ),
            // Row 1: SĐT + Tên
            Row(
              children: [
                Expanded(
                  child: _compactInput(
                    phoneCtrl,
                    _isWalkIn ? "SĐT (không bắt buộc)" : "SĐT *",
                    Icons.phone,
                    type: TextInputType.phone,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _compactInput(
                    nameCtrl,
                    _isWalkIn ? "Tên KH (tùy chọn)" : "Tên KH",
                    Icons.person,
                    caps: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Row 2: Quick brands + Model
            _quick(brands, modelCtrl, issueF),
            _compactInput(modelCtrl, "MODEL MÁY *", Icons.phone_android, caps: true),
            const SizedBox(height: 8),
            // Row 3: Quick issues + Lỗi
            _quick(commonIssues, issueCtrl, priceF),
            _compactInput(issueCtrl, "LỖI MÁY *", Icons.build, caps: true),
            const SizedBox(height: 8),
            // Row 4: Giá
            CurrencyTextField(
              controller: priceCtrl,
              label: "GIÁ DỰ KIẾN",
              icon: Icons.monetization_on,
              onSubmitted: () => FocusScope.of(context).requestFocus(passF),
            ),
          ],
        ),
      ),
    );
  }

  /// COMPACT: Dịch vụ sửa chữa (ExpansionTile nếu chưa có dịch vụ)
  Widget _buildCompactServicesSection() {
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        dense: true,
        leading: Icon(Icons.handyman, color: Colors.teal, size: 20),
        title: Row(
          children: [
            Text("DỊCH VỤ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            if (_services.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.teal, borderRadius: BorderRadius.circular(10)),
                child: Text("${_services.length}", style: const TextStyle(color: Colors.white, fontSize: 11)),
              ),
            ],
          ],
        ),
        initiallyExpanded: _services.isNotEmpty,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(children: _buildServicesSection()),
          ),
        ],
      ),
    );
  }

  /// COMPACT: Bảo mật + Phụ kiện trong ExpansionTile (thu gọn được)
  Widget _buildCompactSecurityAccessoriesSection() {
    final hasContent = passCtrl.text.isNotEmpty || _selectedAccs.isNotEmpty || accCtrl.text.isNotEmpty;
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        dense: true,
        leading: Icon(Icons.lock_outline, color: Colors.red.shade400, size: 20),
        title: Row(
          children: [
            Text("BẢO MẬT & PHỤ KIỆN", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            if (hasContent) ...[
              const SizedBox(width: 8),
              Icon(Icons.check_circle, color: Colors.green, size: 16),
            ],
          ],
        ),
        initiallyExpanded: false, // Mặc định thu gọn để tiết kiệm không gian
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              children: [
                _compactInput(passCtrl, "Mật khẩu màn hình", Icons.lock),
                const SizedBox(height: 8),
                // Quick accs chips
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _compactChip("SIM", _selectedAccs.contains("SIM"), () => _toggleAcc("SIM")),
                    _compactChip("ỐP LƯNG", _selectedAccs.contains("ỐP LƯNG"), () => _toggleAcc("ỐP LƯNG")),
                    _compactChip("KO PHỤ KIỆN", _selectedAccs.contains("KO PHỤ KIỆN"), () => _toggleAcc("KO PHỤ KIỆN")),
                  ],
                ),
                const SizedBox(height: 6),
                _compactInput(accCtrl, "Phụ kiện khác", Icons.add_box_outlined, caps: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _toggleAcc(String acc) {
    setState(() {
      if (_selectedAccs.contains(acc)) {
        _selectedAccs.remove(acc);
      } else {
        _selectedAccs.add(acc);
      }
    });
  }

  Widget _compactChip(String label, bool selected, VoidCallback onTap) {
    return FilterChip(
      label: Text(label, style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: Colors.blue.shade100,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  /// COMPACT: Ghi chú + Hình ảnh (ExpansionTile)
  Widget _buildCompactNotesImagesSection() {
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        dense: true,
        leading: Icon(Icons.note_alt_outlined, color: Colors.blueGrey, size: 20),
        title: Row(
          children: [
            Text("GHI CHÚ & HÌNH ẢNH", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            if (_images.isNotEmpty || notesCtrl.text.isNotEmpty) ...[
              const SizedBox(width: 8),
              Icon(Icons.check_circle, color: Colors.green, size: 16),
            ],
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              children: [
                TextFormField(
                  controller: notesCtrl,
                  maxLines: 2,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: "Ghi chú...",
                    isDense: true,
                    contentPadding: const EdgeInsets.all(10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 8),
                _imageRow(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Compact input field
  Widget _compactInput(TextEditingController c, String label, IconData icon, {bool caps = false, TextInputType type = TextInputType.text}) {
    return TextField(
      controller: c,
      keyboardType: type,
      textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.none,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12),
        prefixIcon: Icon(icon, size: 18),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // OLD BUILD METHOD CONTENT REMOVED - replaced with compact version above
  // Keeping old helper methods below...

  Widget _priorityChip(String label, VoidCallback onTap) {
    return Expanded(
      child: ActionChip(
        label: Text(
          label,
          style: AppTextStyles.caption.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.onSecondary,
          ),
        ),
        backgroundColor: AppColors.secondary,
        padding: const EdgeInsets.all(0),
        onPressed: () {
          HapticFeedback.lightImpact();
          onTap();
        },
      ),
    );
  }

  Widget _buildQuickAccs() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Wrap(
        spacing: 8,
        runSpacing: 0,
        children: quickAccs.map((acc) {
          final isSelected = _selectedAccs.contains(acc);
          return FilterChip(
            label: Text(
              acc,
              style: AppTextStyles.caption.copyWith(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? AppColors.onPrimary : AppColors.onSurface,
              ),
            ),
            selected: isSelected,
            onSelected: (v) {
              HapticFeedback.lightImpact();
              setState(() {
                v ? _selectedAccs.add(acc) : _selectedAccs.remove(acc);
              });
            },
            selectedColor: const Color(0xFF2962FF),
            checkmarkColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _input(
    TextEditingController c,
    String l,
    IconData i, {
    bool caps = false,
    TextInputType type = TextInputType.text,
    FocusNode? f,
    FocusNode? next,
    int? maxLines,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ValidatedTextField(
        controller: c,
        label: l.replaceAll(' *', ''),
        icon: i,
        keyboardType: type,
        uppercase: caps,
        required: l.contains('*'),
        maxLines: maxLines,
        onSubmitted: () {
          if (next != null) FocusScope.of(context).requestFocus(next);
        },
      ),
    );
  }

  Widget _quick(
    List<String> items,
    TextEditingController target,
    FocusNode? nextF,
  ) {
    return Container(
      height: 38,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        itemBuilder: (ctx, i) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ActionChip(
            label: Text(
              items[i],
              style: AppTextStyles.caption.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: () {
              setState(() => target.text = items[i]);
              if (nextF != null) FocusScope.of(context).requestFocus(nextF);
            },
          ),
        ),
      ),
    );
  }

  Widget _imageRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ..._images.map(
            (f) => Container(
              margin: const EdgeInsets.only(right: 10),
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(f, fit: BoxFit.cover),
              ),
            ),
          ),
          GestureDetector(
            onTap: () async {
              final f = await ImagePicker().pickImage(
                source: ImageSource.camera,
                imageQuality: 40,
              );
              if (f != null) setState(() => _images.add(File(f.path)));
            },
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.blue.withAlpha(13),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.add_a_photo, color: Colors.blue),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}

class CustomerSelectionDialog extends StatefulWidget {
  final List<Customer> customers;
  final Function(Customer) onSelect;

  const CustomerSelectionDialog({
    super.key,
    required this.customers,
    required this.onSelect,
  });

  @override
  State<CustomerSelectionDialog> createState() =>
      _CustomerSelectionDialogState();
}

class _CustomerSelectionDialogState extends State<CustomerSelectionDialog> {
  late List<Customer> _filteredCustomers;

  @override
  void initState() {
    super.initState();
    _filteredCustomers = widget.customers;
  }

  void _filterCustomers(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredCustomers = widget.customers;
      } else {
        _filteredCustomers = widget.customers.where((customer) {
          return customer.name.toLowerCase().contains(query.toLowerCase()) ||
              customer.phone.contains(query);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('CHỌN KHÁCH HÀNG'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: 'Tìm theo tên hoặc số điện thoại...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _filterCustomers,
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _filteredCustomers.isEmpty
                  ? const Center(child: Text('Không tìm thấy khách hàng'))
                  : ListView.builder(
                      itemCount: _filteredCustomers.length,
                      itemBuilder: (context, index) {
                        final customer = _filteredCustomers[index];
                        return ListTile(
                          title: Text(customer.name),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(customer.phone),
                              if (customer.address != null &&
                                  customer.address!.isNotEmpty)
                                Text(
                                  'Địa chỉ: ${customer.address}',
                                  style: AppTextStyles.caption.copyWith(
                                    color: Colors.grey,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (customer.notes != null &&
                                  customer.notes!.isNotEmpty)
                                Text(
                                  'Ghi chú: ${customer.notes}',
                                  style: AppTextStyles.caption.copyWith(
                                    color: Colors.blue,
                                    fontStyle: FontStyle.italic,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                          isThreeLine:
                              (customer.address != null &&
                                  customer.address!.isNotEmpty) ||
                              (customer.notes != null &&
                                  customer.notes!.isNotEmpty),
                          onTap: () => widget.onSelect(customer),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('HỦY'),
        ),
      ],
    );
  }
}
