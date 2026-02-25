import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/shop_deduction_settings.dart';
import '../../services/salary_calculation_service.dart';
import '../../services/user_service.dart';
import 'add_custom_adjustment_dialog.dart';

/// Màn hình cài đặt Khấu trừ, Thuế, Bảo hiểm của shop
class ShopDeductionSettingsView extends StatefulWidget {
  const ShopDeductionSettingsView({super.key});

  @override
  State<ShopDeductionSettingsView> createState() =>
      _ShopDeductionSettingsViewState();
}

class _ShopDeductionSettingsViewState extends State<ShopDeductionSettingsView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  ShopDeductionSettings _settings = ShopDeductionSettings();
  bool _isLoading = true;
  bool _isSaving = false;

  // Custom adjustments tab state
  List<CustomSalaryAdjustment> _adjustments = [];
  bool _loadingAdjustments = false;
  int _adjMonth = DateTime.now().month;
  int _adjYear = DateTime.now().year;

  final _currencyFormat = NumberFormat('#,###', 'vi_VN');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final settings =
          await SalaryCalculationService.getShopDeductionSettings();
      setState(() {
        _settings = settings;
      });
    } catch (e) {
      debugPrint('Error loading deduction settings: $e');
    } finally {
      setState(() => _isLoading = false);
    }
    _loadAdjustments();
  }

  Future<void> _loadAdjustments() async {
    setState(() => _loadingAdjustments = true);
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return;
      final data = await SalaryCalculationService.getAllShopAdjustments(
        shopId: shopId,
        month: _adjMonth,
        year: _adjYear,
      );
      if (mounted) setState(() => _adjustments = data);
    } catch (e) {
      debugPrint('Error loading adjustments: $e');
    } finally {
      if (mounted) setState(() => _loadingAdjustments = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      final success = await SalaryCalculationService.saveShopDeductionSettings(
        _settings,
      );
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Đã lưu cài đặt thành công'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Lỗi khi lưu cài đặt'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Exception saving deduction settings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Lỗi: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _formatCurrency(double value) {
    return '${_currencyFormat.format(value)}đ';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 44,
        title: const Text('Cài đặt Khấu trừ & Thuế', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        bottom: TabBar(
          controller: _tabController,
          labelColor: colorScheme.onPrimaryContainer,
          unselectedLabelColor: colorScheme.onPrimaryContainer.withOpacity(0.5),
          indicatorColor: colorScheme.onPrimaryContainer,
          indicatorWeight: 2,
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
          tabs: const [
            Tab(icon: Icon(Icons.warning_amber_rounded, size: 18), text: 'Khấu trừ'),
            Tab(icon: Icon(Icons.health_and_safety_rounded, size: 18), text: 'Bảo hiểm'),
            Tab(icon: Icon(Icons.receipt_long_rounded, size: 18), text: 'Thuế TNCN'),
            Tab(icon: Icon(Icons.card_giftcard_rounded, size: 18), text: 'Thưởng/Trừ'),
          ],
        ),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              onPressed: _saveSettings,
              icon: const Icon(Icons.save),
              tooltip: 'Lưu cài đặt',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildDeductionTab(),
                _buildInsuranceTab(),
                _buildTaxTab(),
                _buildCustomAdjustmentsTab(),
              ],
            ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 1: KHẤU TRỪ (Đi muộn, Về sớm, Nghỉ quá phép)
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildDeductionTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // === ĐI MUỘN ===
        _buildSectionCard(
          title: 'Trừ đi muộn',
          icon: Icons.schedule,
          iconColor: Colors.orange,
          enabled: _settings.enableLateDeduction,
          onEnabledChanged: (v) {
            setState(() {
              _settings = _settings.copyWith(enableLateDeduction: v);
            });
          },
          children: [
            _CurrencyField(
              label: 'Số tiền trừ mỗi lần đi muộn',
              value: _settings.lateDeductionPerTime,
              onChanged: (v) {
                setState(() {
                  _settings = _settings.copyWith(lateDeductionPerTime: v);
                });
              },
            ),
            const SizedBox(height: 12),
            _NumberField(
              label: 'Số lần được miễn (không trừ)',
              value: _settings.lateGraceTimes,
              suffix: 'lần/tháng',
              onChanged: (v) {
                setState(() {
                  _settings = _settings.copyWith(lateGraceTimes: v);
                });
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Ví dụ: Miễn 2 lần → Đi muộn 5 lần → Trừ 3 lần',
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // === VỀ SỚM ===
        _buildSectionCard(
          title: 'Trừ về sớm',
          icon: Icons.exit_to_app,
          iconColor: Colors.blue,
          enabled: _settings.enableEarlyLeaveDeduction,
          onEnabledChanged: (v) {
            setState(() {
              _settings = _settings.copyWith(enableEarlyLeaveDeduction: v);
            });
          },
          children: [
            _CurrencyField(
              label: 'Số tiền trừ mỗi lần về sớm',
              value: _settings.earlyLeaveDeductionPerTime,
              onChanged: (v) {
                setState(() {
                  _settings = _settings.copyWith(earlyLeaveDeductionPerTime: v);
                });
              },
            ),
            const SizedBox(height: 12),
            _NumberField(
              label: 'Số lần được miễn (không trừ)',
              value: _settings.earlyLeaveGraceTimes,
              suffix: 'lần/tháng',
              onChanged: (v) {
                setState(() {
                  _settings = _settings.copyWith(earlyLeaveGraceTimes: v);
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 10),

        // === NGHỈ QUÁ PHÉP ===
        _buildSectionCard(
          title: 'Trừ nghỉ quá phép',
          icon: Icons.event_busy,
          iconColor: Colors.red,
          enabled: _settings.enableAbsenceDeduction,
          onEnabledChanged: (v) {
            setState(() {
              _settings = _settings.copyWith(enableAbsenceDeduction: v);
            });
          },
          children: [
            _NumberField(
              label: 'Số ngày nghỉ phép cho phép',
              value: _settings.allowedAbsenceDays,
              suffix: 'ngày/tháng',
              onChanged: (v) {
                setState(() {
                  _settings = _settings.copyWith(allowedAbsenceDays: v);
                });
              },
            ),
            const SizedBox(height: 12),
            _CurrencyField(
              label: 'Số tiền trừ mỗi ngày nghỉ quá phép',
              value: _settings.absenceDeductionPerDay,
              onChanged: (v) {
                setState(() {
                  _settings = _settings.copyWith(absenceDeductionPerDay: v);
                });
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Ví dụ: Phép 2 ngày → Nghỉ 5 ngày → Trừ 3 ngày',
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 2: BẢO HIỂM (BHXH, BHYT, BHTN)
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildInsuranceTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Info card
        Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info, color: Colors.blue.shade700, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'Tỷ lệ đóng BH người lao động theo luật:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade900,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '• BHXH: 8% lương đóng BH\n'
                  '• BHYT: 1.5% lương đóng BH\n'
                  '• BHTN: 1% lương đóng BH\n'
                  '• Tổng: 10.5% lương đóng BH',
                  style: TextStyle(color: Colors.blue.shade800, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Mức lương đóng BH
        _buildSectionCard(
          title: 'Mức lương đóng BH',
          icon: Icons.account_balance_wallet,
          iconColor: Colors.teal,
          enabled: true,
          showSwitch: false,
          children: [
            _CurrencyField(
              label: 'Mức lương đóng BH (để 0 = dùng lương cơ bản)',
              value: _settings.insuranceBaseSalary,
              onChanged: (v) {
                setState(() {
                  _settings = _settings.copyWith(insuranceBaseSalary: v);
                });
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Nếu để 0, hệ thống sẽ dùng lương cơ bản làm mức đóng BH',
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // === BHXH ===
        _buildSectionCard(
          title: 'BHXH (Bảo hiểm xã hội)',
          icon: Icons.security,
          iconColor: Colors.green,
          enabled: _settings.enableSocialInsurance,
          onEnabledChanged: (v) {
            setState(() {
              _settings = _settings.copyWith(enableSocialInsurance: v);
            });
          },
          children: [
            _PercentField(
              label: 'Tỷ lệ BHXH',
              value: _settings.socialInsuranceRate,
              onChanged: (v) {
                setState(() {
                  _settings = _settings.copyWith(socialInsuranceRate: v);
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 10),

        // === BHYT ===
        _buildSectionCard(
          title: 'BHYT (Bảo hiểm y tế)',
          icon: Icons.local_hospital,
          iconColor: Colors.red,
          enabled: _settings.enableHealthInsurance,
          onEnabledChanged: (v) {
            setState(() {
              _settings = _settings.copyWith(enableHealthInsurance: v);
            });
          },
          children: [
            _PercentField(
              label: 'Tỷ lệ BHYT',
              value: _settings.healthInsuranceRate,
              onChanged: (v) {
                setState(() {
                  _settings = _settings.copyWith(healthInsuranceRate: v);
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 10),

        // === BHTN ===
        _buildSectionCard(
          title: 'BHTN (Bảo hiểm thất nghiệp)',
          icon: Icons.work_off,
          iconColor: Colors.orange,
          enabled: _settings.enableUnemploymentInsurance,
          onEnabledChanged: (v) {
            setState(() {
              _settings = _settings.copyWith(enableUnemploymentInsurance: v);
            });
          },
          children: [
            _PercentField(
              label: 'Tỷ lệ BHTN',
              value: _settings.unemploymentInsuranceRate,
              onChanged: (v) {
                setState(() {
                  _settings = _settings.copyWith(unemploymentInsuranceRate: v);
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Summary
        Card(
          color: Colors.green.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tổng % BH người lao động đóng:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade900,
                    fontSize: 12,
                  ),
                ),
                Text(
                  '${_settings.totalInsuranceRate.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 3: THUẾ TNCN
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildTaxTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Info card
        Card(
          color: Colors.amber.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info, color: Colors.amber.shade700, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'Biểu thuế TNCN lũy tiến:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade900,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '• Đến 5 triệu: 5%\n'
                  '• 5-10 triệu: 10%\n'
                  '• 10-18 triệu: 15%\n'
                  '• 18-32 triệu: 20%\n'
                  '• 32-52 triệu: 25%\n'
                  '• 52-80 triệu: 30%\n'
                  '• Trên 80 triệu: 35%',
                  style: TextStyle(color: Colors.amber.shade800, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // === THUẾ TNCN ===
        _buildSectionCard(
          title: 'Tính thuế TNCN',
          icon: Icons.receipt_long,
          iconColor: Colors.indigo,
          enabled: _settings.enablePIT,
          onEnabledChanged: (v) {
            setState(() {
              _settings = _settings.copyWith(enablePIT: v);
            });
          },
          children: [
            _CurrencyField(
              label: 'Giảm trừ bản thân (11 triệu theo luật)',
              value: _settings.pitDeductionSelf,
              onChanged: (v) {
                setState(() {
                  _settings = _settings.copyWith(pitDeductionSelf: v);
                });
              },
            ),
            const SizedBox(height: 12),
            _CurrencyField(
              label: 'Giảm trừ người phụ thuộc (4.4 triệu/người)',
              value: _settings.pitDeductionDependent,
              onChanged: (v) {
                setState(() {
                  _settings = _settings.copyWith(pitDeductionDependent: v);
                });
              },
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Công thức tính:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Thu nhập chịu thuế = GROSS - BH - Giảm trừ bản thân - Giảm trừ người phụ thuộc',
                    style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Thuế TNCN = Áp dụng biểu thuế lũy tiến',
                    style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Demo calculator
        if (_settings.enablePIT) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📊 Ví dụ tính thuế:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const Divider(),
                  _buildDemoRow('Thu nhập GROSS', 20000000),
                  _buildDemoRow('- BHXH, BHYT, BHTN (10.5%)', -2100000),
                  _buildDemoRow(
                    '- Giảm trừ bản thân',
                    -_settings.pitDeductionSelf,
                  ),
                  _buildDemoRow(
                    '- Giảm trừ 1 người phụ thuộc',
                    -_settings.pitDeductionDependent,
                  ),
                  const Divider(),
                  _buildDemoRow(
                    '= Thu nhập chịu thuế',
                    20000000 -
                        2100000 -
                        _settings.pitDeductionSelf -
                        _settings.pitDeductionDependent,
                    isBold: true,
                  ),
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final taxable =
                          20000000 -
                          2100000 -
                          _settings.pitDeductionSelf -
                          _settings.pitDeductionDependent;
                      final tax = PITCalculator.calculatePIT(taxable);
                      return _buildDemoRow(
                        'Thuế TNCN phải đóng',
                        tax,
                        isBold: true,
                        isRed: true,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDemoRow(
    String label,
    double value, {
    bool isBold = false,
    bool isRed = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            _formatCurrency(value),
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
              color: isRed ? Colors.red : (value < 0 ? Colors.grey[600] : null),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAB 4: THƯỞNG / KHẤU TRỪ KHÁC
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildCustomAdjustmentsTab() {
    final bonuses = _adjustments.where((a) => a.isBonus).toList();
    final deductions = _adjustments.where((a) => a.isDeduction).toList();
    final totalBonus = bonuses.fold<double>(0, (s, a) => s + a.amount);
    final totalDeduction = deductions.fold<double>(0, (s, a) => s + a.amount);

    return Column(
      children: [
        // Month/Year picker row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.grey[50],
          child: Row(
            children: [
              const Icon(Icons.date_range, size: 18, color: Colors.grey),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _adjMonth,
                underline: const SizedBox(),
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                items: List.generate(12, (i) => DropdownMenuItem(
                  value: i + 1,
                  child: Text('Tháng ${i + 1}'),
                )),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _adjMonth = v);
                    _loadAdjustments();
                  }
                },
              ),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _adjYear,
                underline: const SizedBox(),
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                items: List.generate(5, (i) {
                  final y = DateTime.now().year - 2 + i;
                  return DropdownMenuItem(value: y, child: Text('$y'));
                }),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _adjYear = v);
                    _loadAdjustments();
                  }
                },
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _addNewAdjustment,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Thêm', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                ),
              ),
            ],
          ),
        ),

        // Summary bar
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    const Text('Thưởng', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 2),
                    Text(
                      '+${_currencyFormat.format(totalBonus)}đ',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                    Text('${bonuses.length} khoản', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ),
              Container(width: 1, height: 36, color: Colors.grey[300]),
              Expanded(
                child: Column(
                  children: [
                    const Text('Khấu trừ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 2),
                    Text(
                      '-${_currencyFormat.format(totalDeduction)}đ',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red),
                    ),
                    Text('${deductions.length} khoản', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
        ),

        // List
        Expanded(
          child: _loadingAdjustments
              ? const Center(child: CircularProgressIndicator())
              : _adjustments.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[300]),
                          const SizedBox(height: 8),
                          Text(
                            'Chưa có khoản thưởng/trừ nào\ntháng $_adjMonth/$_adjYear',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey[500], fontSize: 13),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _addNewAdjustment,
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Thêm mới', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      itemCount: _adjustments.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final adj = _adjustments[index];
                        final isBonus = adj.isBonus;
                        return Dismissible(
                          key: Key(adj.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 16),
                            decoration: BoxDecoration(
                              color: Colors.red[400],
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          confirmDismiss: (_) async {
                            return await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Xác nhận xóa'),
                                content: Text('Xóa "${adj.name}" - ${_currencyFormat.format(adj.amount)}đ?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('HỦY')),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                    child: const Text('XÓA'),
                                  ),
                                ],
                              ),
                            );
                          },
                          onDismissed: (_) => _deleteAdjustment(adj),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isBonus ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3),
                              ),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2))],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: (isBonus ? Colors.green : Colors.red).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    isBonus ? Icons.trending_up : Icons.trending_down,
                                    color: isBonus ? Colors.green : Colors.red,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        adj.name,
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${adj.staffName}${adj.note != null && adj.note!.isNotEmpty ? ' • ${adj.note}' : ''}',
                                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${isBonus ? '+' : '-'}${_currencyFormat.format(adj.amount)}đ',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isBonus ? Colors.green : Colors.red,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Future<void> _addNewAdjustment() async {
    // Use same dialog pattern as payroll_view
    final result = await showAddCustomAdjustmentDialog(
      context,
      staffId: '', // empty = user picks from the dialog
      staffName: '',
      month: _adjMonth,
      year: _adjYear,
    );
    if (result == true && mounted) {
      _loadAdjustments();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Đã thêm khoản thưởng/trừ'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _deleteAdjustment(CustomSalaryAdjustment adj) async {
    final ok = await SalaryCalculationService.deleteCustomAdjustment(adj.id);
    if (mounted) {
      if (ok) {
        setState(() => _adjustments.removeWhere((a) => a.id == adj.id));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xóa'), backgroundColor: Colors.orange),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Lỗi khi xóa'), backgroundColor: Colors.red),
        );
        _loadAdjustments(); // Reload to restore
      }
    }
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required bool enabled,
    bool showSwitch = true,
    ValueChanged<bool>? onEnabledChanged,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: iconColor.withAlpha(50),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: iconColor.withAlpha(220), size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (showSwitch)
                  Transform.scale(
                    scale: 0.85,
                    child: Switch(value: enabled, onChanged: onEnabledChanged),
                  ),
              ],
            ),
            if (enabled && children.isNotEmpty) ...[
              const Divider(height: 16),
              ...children,
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CUSTOM TEXT FIELDS (tách riêng để giữ focus)
// ═══════════════════════════════════════════════════════════════════════════

class _CurrencyField extends StatefulWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _CurrencyField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_CurrencyField> createState() => _CurrencyFieldState();
}

class _CurrencyFieldState extends State<_CurrencyField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  final _format = NumberFormat('#,###', 'vi_VN');

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format.format(widget.value));
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_CurrencyField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && widget.value != oldWidget.value) {
      _controller.text = _format.format(widget.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: TextInputType.number,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: const TextStyle(fontSize: 12),
        suffixText: 'đ',
        suffixStyle: const TextStyle(fontSize: 12, color: Colors.grey),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: const OutlineInputBorder(),
      ),
      onChanged: (value) {
        final cleaned = value.replaceAll(RegExp(r'[^0-9]'), '');
        final parsed = double.tryParse(cleaned) ?? 0;
        widget.onChanged(parsed);
      },
    );
  }
}

class _PercentField extends StatefulWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _PercentField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_PercentField> createState() => _PercentFieldState();
}

class _PercentFieldState extends State<_PercentField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_PercentField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && widget.value != oldWidget.value) {
      _controller.text = widget.value.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: const TextStyle(fontSize: 12),
        suffixText: '%',
        suffixStyle: const TextStyle(fontSize: 12, color: Colors.grey),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: const OutlineInputBorder(),
      ),
      onChanged: (value) {
        final parsed = double.tryParse(value.replaceAll(',', '.')) ?? 0;
        widget.onChanged(parsed);
      },
    );
  }
}

class _NumberField extends StatefulWidget {
  final String label;
  final int value;
  final String? suffix;
  final ValueChanged<int> onChanged;

  const _NumberField({
    required this.label,
    required this.value,
    this.suffix,
    required this.onChanged,
  });

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && widget.value != oldWidget.value) {
      _controller.text = widget.value.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: TextInputType.number,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: const TextStyle(fontSize: 12),
        suffixText: widget.suffix,
        suffixStyle: const TextStyle(fontSize: 12, color: Colors.grey),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: const OutlineInputBorder(),
      ),
      onChanged: (value) {
        final parsed = int.tryParse(value) ?? 0;
        widget.onChanged(parsed);
      },
    );
  }
}
