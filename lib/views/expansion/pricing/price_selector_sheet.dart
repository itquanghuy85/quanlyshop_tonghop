import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../expansion/safe_mode/expansion_feature_flags.dart';
import '../../../expansion/safe_mode/expansion_module_services.dart'
    show ModuleDisabledException;
import '../../../expansion/safe_mode/pricing_models.dart';
import '../../../expansion/safe_mode/pricing_repository.dart';

/// Widget chọn giá linh hoạt cho 1 sản phẩm.
///
/// Dùng như bottom sheet:
/// ```dart
/// PriceSelectorSheet.show(
///   context,
///   productId: p.firestoreId ?? p.id.toString(),
///   productName: p.name,
///   basePrice: p.price.toDouble(),
///   quantity: qty,
///   customerId: currentCustomerId,
///   flags: const ExpansionFeatureFlags(enablePricing: true),
///   onPriceSelected: (price) {
///     setState(() => item['sellPrice'] = price.toInt());
///   },
/// );
/// ```
class PriceSelectorSheet extends StatefulWidget {
  final String productId;
  final String productName;
  final double basePrice;
  final int quantity;
  final String? customerId;
  final ExpansionFeatureFlags flags;
  final void Function(double price, PricingRuleType type) onPriceSelected;

  const PriceSelectorSheet({
    super.key,
    required this.productId,
    required this.productName,
    required this.basePrice,
    required this.quantity,
    required this.flags,
    required this.onPriceSelected,
    this.customerId,
  });

  /// Hiển thị dưới dạng bottom sheet. Trả về giá đã chọn hoặc null nếu huỷ.
  static Future<double?> show(
    BuildContext context, {
    required String productId,
    required String productName,
    required double basePrice,
    required int quantity,
    required ExpansionFeatureFlags flags,
    required void Function(double price, PricingRuleType type) onPriceSelected,
    String? customerId,
  }) {
    return showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => PriceSelectorSheet(
        productId: productId,
        productName: productName,
        basePrice: basePrice,
        quantity: quantity,
        customerId: customerId,
        flags: flags,
        onPriceSelected: onPriceSelected,
      ),
    );
  }

  @override
  State<PriceSelectorSheet> createState() => _PriceSelectorSheetState();
}

class _PriceSelectorSheetState extends State<PriceSelectorSheet> {
  final PricingRepository _repo = PricingRepository();
  final NumberFormat _fmt = NumberFormat('#,###', 'vi_VN');
  static const String _vipPercentKey = 'pricing_fallback_vip_percent';
  static const String _wholesalePercentKey =
      'pricing_fallback_wholesale_percent';

  final TextEditingController _vipPercentCtrl = TextEditingController();
  final TextEditingController _wholesalePercentCtrl = TextEditingController();

  List<_PriceOption> _options = [];
  int _selectedIndex = 0;
  bool _loading = true;
  String? _error;
  double _vipPercent = 5;
  double _wholesalePercent = 10;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _vipPercentCtrl.dispose();
    _wholesalePercentCtrl.dispose();
    _repo.close();
    super.dispose();
  }

  Future<void> _loadFallbackPercents() async {
    final prefs = await SharedPreferences.getInstance();
    final vip = prefs.getDouble(_vipPercentKey) ?? 5;
    final wholesale = prefs.getDouble(_wholesalePercentKey) ?? 10;

    _vipPercent = vip.clamp(0, 100).toDouble();
    _wholesalePercent = wholesale.clamp(0, 100).toDouble();
    _vipPercentCtrl.text = _vipPercent.toStringAsFixed(0);
    _wholesalePercentCtrl.text = _wholesalePercent.toStringAsFixed(0);
  }

  Future<void> _saveFallbackPercents() async {
    final vipParsed = double.tryParse(_vipPercentCtrl.text.trim());
    final wholesaleParsed = double.tryParse(_wholesalePercentCtrl.text.trim());
    final vip = (vipParsed ?? _vipPercent).clamp(0, 100).toDouble();
    final wholesale = (wholesaleParsed ?? _wholesalePercent).clamp(0, 100)
        .toDouble();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_vipPercentKey, vip);
    await prefs.setDouble(_wholesalePercentKey, wholesale);

    if (!mounted) return;
    setState(() {
      _vipPercent = vip;
      _wholesalePercent = wholesale;
      _vipPercentCtrl.text = vip.toStringAsFixed(0);
      _wholesalePercentCtrl.text = wholesale.toStringAsFixed(0);
    });
  }

  Future<void> _load() async {
    await _loadFallbackPercents();

    if (!widget.flags.enablePricing) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      // Lấy loại giá của khách (nếu có)
      PricingRuleType customerType = PricingRuleType.normal;
      if (widget.customerId != null) {
        final cp = await _repo.getCustomerPricing(widget.customerId!);
        if (cp != null) customerType = cp.pricingType;
      }

      // Lấy rules của sản phẩm
      final rules = await _repo.getRulesForProduct(widget.productId);

      // Xây danh sách options
      final List<_PriceOption> options = [];
        final double effectiveBasePrice =
          widget.basePrice > 0 ? widget.basePrice : 0.0;

      // Luôn thêm giá thường (basePrice)
      options.add(_PriceOption(
        label: 'Giá thường',
        price: effectiveBasePrice,
        type: PricingRuleType.normal,
        isRecommended: customerType == PricingRuleType.normal,
        reason: effectiveBasePrice > 0 ? 'Giá gốc' : 'Giá gốc chưa nhập',
      ));

      // Tìm giá VIP
      final vipQtyRule = _bestQtyRule(rules, PricingRuleType.vip, widget.quantity);
      final vipTypeRule = _bestTypeRule(rules, PricingRuleType.vip);
      final vipRule = vipQtyRule ?? vipTypeRule;
      options.add(_PriceOption(
        label: 'Giá VIP',
        price: vipRule?.price ??
          (effectiveBasePrice > 0
            ? (effectiveBasePrice * (1 - _vipPercent / 100))
              .roundToDouble()
            : 0.0),
        type: PricingRuleType.vip,
        isRecommended: customerType == PricingRuleType.vip,
        reason: vipRule != null
            ? (vipQtyRule != null ? 'Rule SL ≥${vipQtyRule.minQty}' : 'Giá khách VIP')
          : (effectiveBasePrice > 0
            ? 'Mặc định: giảm ${_vipPercent.toStringAsFixed(0)}%'
            : 'Chưa có rule VIP'),
      ));

      // Tìm giá sỉ
      final wsQtyRule = _bestQtyRule(rules, PricingRuleType.wholesale, widget.quantity);
      final wsTypeRule = _bestTypeRule(rules, PricingRuleType.wholesale);
      final wsRule = wsQtyRule ?? wsTypeRule;
      options.add(_PriceOption(
        label: 'Giá sỉ',
        price: wsRule?.price ??
          (effectiveBasePrice > 0
            ? (effectiveBasePrice * (1 - _wholesalePercent / 100))
              .roundToDouble()
            : 0.0),
        type: PricingRuleType.wholesale,
        isRecommended: customerType == PricingRuleType.wholesale,
        reason: wsRule != null
            ? (wsQtyRule != null ? 'Rule SL ≥${wsQtyRule.minQty}' : 'Giá khách sỉ')
          : (effectiveBasePrice > 0
            ? 'Mặc định: giảm ${_wholesalePercent.toStringAsFixed(0)}%'
            : 'Chưa có rule sỉ'),
      ));

      // Xác định option được chọn sẵn
      int recommended = options.indexWhere((o) => o.isRecommended);
      if (recommended < 0) recommended = 0;

      if (mounted) {
        setState(() {
          _options = options;
          _selectedIndex = recommended;
          _loading = false;
        });
      }
    } on ModuleDisabledException {
      if (mounted) setState(() { _loading = false; _error = 'Module Pricing chưa bật.'; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  /// Rule theo số lượng: qty >= minQty, cùng type, lấy minQty cao nhất
  PriceRule? _bestQtyRule(List<PriceRule> rules, PricingRuleType type, int qty) {
    return rules
        .where((r) => r.type == type && r.minQty > 0 && qty >= r.minQty)
        .fold<PriceRule?>(null, (best, r) {
      if (best == null || r.minQty > best.minQty) return r;
      return best;
    });
  }

  /// Rule theo loại khách: minQty = 0
  PriceRule? _bestTypeRule(List<PriceRule> rules, PricingRuleType type) {
    final matches = rules.where((r) => r.type == type && r.minQty == 0).toList();
    return matches.isEmpty ? null : matches.first;
  }

  void _confirm() {
    if (_options.isEmpty) return;
    final selected = _options[_selectedIndex];
    final price = selected.price;
    widget.onPriceSelected(price, selected.type);
    Navigator.pop(context, price);
  }

  String _fmt2(double price) => '${_fmt.format(price.toInt())}đ';

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    return SafeArea(
      child: SizedBox(
        height: maxHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            // Handle bar
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Header
            Text(
              widget.productName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'SL: ${widget.quantity}',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const Divider(height: 20),

              Expanded(
                child: ListView(
                  children: [
                    // Body
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_error != null)
                      _buildError()
                    else if (!widget.flags.enablePricing)
                      _buildDisabled()
                    else if (_options.isEmpty)
                      _buildNoRules()
                    else
                      _buildOptions(),

                    if (!_loading && _error == null && widget.flags.enablePricing)
                      _buildFallbackConfig(),

                    // Actions
                    if (!_loading &&
                        _error == null &&
                        widget.flags.enablePricing &&
                        _options.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildSummaryRow(),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _confirm,
                          child: Text(
                            'Áp dụng ${_options.isNotEmpty ? _fmt2(_options[_selectedIndex].price) : ''}',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptions() {
    return Column(
      children: List.generate(_options.length, (i) {
        final opt = _options[i];
        final isSelected = _selectedIndex == i;
        final savedPct = opt.price < widget.basePrice
            ? ((widget.basePrice - opt.price) / widget.basePrice * 100).round()
            : 0;

        return GestureDetector(
          onTap: () => setState(() => _selectedIndex = i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
                  : Colors.transparent,
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey.shade300,
                width: isSelected ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                // IgnorePointer: để InkWell cha xử lý tap, tránh Radio cướp gesture
                IgnorePointer(
                  child: Radio<int>(
                    value: i,
                    groupValue: _selectedIndex,
                    onChanged: (_) {},
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(opt.label,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              )),
                          if (opt.isRecommended) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('Phù hợp',
                                  style: TextStyle(
                                      fontSize: 10, color: Colors.green)),
                            ),
                          ],
                          if (savedPct > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('-$savedPct%',
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.red)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(opt.reason,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ),
                Text(
                  _fmt2(opt.price),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: opt.price < widget.basePrice
                        ? Colors.green.shade700
                        : null,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildSummaryRow() {
    if (_options.isEmpty) return const SizedBox.shrink();
    final selected = _options[_selectedIndex];
    final saved = (widget.basePrice - selected.price) * widget.quantity;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('SL ${widget.quantity} × ${_fmt2(selected.price)}',
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _fmt2(selected.price * widget.quantity),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              if (saved > 0)
                Text('Tiết kiệm ${_fmt2(saved)}',
                    style: const TextStyle(color: Colors.green, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNoRules() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          const Icon(Icons.price_change_outlined, size: 40, color: Colors.grey),
          const SizedBox(height: 8),
          const Text('Chưa có rule giá nào cho sản phẩm này.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 4),
          Text('Giá gốc: ${_fmt2(widget.basePrice)}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () {
              widget.onPriceSelected(widget.basePrice, PricingRuleType.normal);
              Navigator.pop(context, widget.basePrice);
            },
            child: const Text('Dùng giá gốc'),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackConfig() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tùy chỉnh % giảm mặc định (khi chưa có rule)',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _vipPercentCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'VIP %',
                    suffixText: '%',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _wholesalePercentCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Sỉ %',
                    suffixText: '%',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: () async {
                  await _saveFallbackPercents();
                  await _load();
                },
                child: const Text('Lưu'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDisabled() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(Icons.lock_outline, size: 40, color: Colors.orange),
          SizedBox(height: 8),
          Text('Module Pricing chưa được bật.',
              style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 40, color: Colors.red),
          const SizedBox(height: 8),
          Text(_error ?? 'Lỗi không xác định',
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// Option nội bộ — lưu thông tin 1 lựa chọn giá
class _PriceOption {
  final String label;
  final double price;
  final PricingRuleType type;
  final bool isRecommended;
  final String reason;

  const _PriceOption({
    required this.label,
    required this.price,
    required this.type,
    required this.isRecommended,
    required this.reason,
  });
}
