import 'package:flutter/material.dart';
import '../models/product_variant_model.dart';
import '../services/variant_service.dart';

/// Widget chọn biến thể sản phẩm (size/color) khi bán hàng
/// Dùng trong create_sale_view.dart cho shop thời trang
class VariantSelector extends StatefulWidget {
  final String productId;
  final String productName;
  final Function(ProductVariant?) onVariantSelected;
  final ProductVariant? initialVariant;
  final bool showStock;

  const VariantSelector({
    super.key,
    required this.productId,
    required this.productName,
    required this.onVariantSelected,
    this.initialVariant,
    this.showStock = true,
  });

  @override
  State<VariantSelector> createState() => _VariantSelectorState();
}

class _VariantSelectorState extends State<VariantSelector> {
  final VariantService _variantService = VariantService();
  List<ProductVariant> _variants = [];
  ProductVariant? _selectedVariant;
  bool _isLoading = true;

  // Grouped data
  List<String> _sizes = [];
  List<String> _colors = [];
  String? _selectedSize;
  String? _selectedColor;

  @override
  void initState() {
    super.initState();
    _selectedVariant = widget.initialVariant;
    _loadVariants();
  }

  Future<void> _loadVariants() async {
    setState(() => _isLoading = true);

    final variants = await _variantService.getVariantsByProduct(widget.productId);

    // Extract unique sizes and colors
    final sizes = <String>{};
    final colors = <String>{};
    for (final v in variants) {
      if (v.size != null && v.size!.isNotEmpty) sizes.add(v.size!);
      if (v.color != null && v.color!.isNotEmpty) colors.add(v.color!);
    }

    setState(() {
      _variants = variants;
      _sizes = sizes.toList()..sort(_sortSizes);
      _colors = colors.toList();
      _isLoading = false;

      // Pre-select if initial variant provided
      if (_selectedVariant != null) {
        _selectedSize = _selectedVariant!.size;
        _selectedColor = _selectedVariant!.color;
      }
    });
  }

  int _sortSizes(String a, String b) {
    // Sort sizes in logical order
    final sizeOrder = {
      'XS': 1, 'S': 2, 'M': 3, 'L': 4, 'XL': 5, 'XXL': 6, '3XL': 7,
    };
    
    final aOrder = sizeOrder[a] ?? int.tryParse(a) ?? 999;
    final bOrder = sizeOrder[b] ?? int.tryParse(b) ?? 999;
    
    if (aOrder is int && bOrder is int) {
      return aOrder.compareTo(bOrder);
    }
    return a.compareTo(b);
  }

  void _updateSelection() {
    // Find variant matching selected size and color
    ProductVariant? match;
    
    for (final v in _variants) {
      final sizeMatch = _selectedSize == null || v.size == _selectedSize;
      final colorMatch = _selectedColor == null || v.color == _selectedColor;
      
      if (sizeMatch && colorMatch) {
        match = v;
        break;
      }
    }

    setState(() => _selectedVariant = match);
    widget.onVariantSelected(match);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_variants.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Sản phẩm này không có biến thể',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Size selection
        if (_sizes.isNotEmpty) ...[
          const Text(
            'Kích cỡ:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _buildSizeSelector(),
          const SizedBox(height: 16),
        ],

        // Color selection
        if (_colors.isNotEmpty) ...[
          const Text(
            'Màu sắc:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _buildColorSelector(),
          const SizedBox(height: 16),
        ],

        // Selected variant info
        if (_selectedVariant != null) _buildSelectedInfo(),
      ],
    );
  }

  Widget _buildSizeSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _sizes.map((size) {
        final isSelected = _selectedSize == size;
        final variantsWithSize = _variants.where((v) => v.size == size).toList();
        final hasStock = variantsWithSize.any((v) => v.quantity > 0);

        return ChoiceChip(
          label: Text(size),
          selected: isSelected,
          onSelected: hasStock || isSelected
              ? (selected) {
                  setState(() {
                    _selectedSize = selected ? size : null;
                  });
                  _updateSelection();
                }
              : null,
          backgroundColor: hasStock ? null : Colors.grey[200],
          selectedColor: Theme.of(context).primaryColor.withOpacity(0.2),
          labelStyle: TextStyle(
            color: !hasStock
                ? Colors.grey
                : isSelected
                    ? Theme.of(context).primaryColor
                    : null,
            decoration: !hasStock ? TextDecoration.lineThrough : null,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildColorSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _colors.map((color) {
        final isSelected = _selectedColor == color;
        final variantsWithColor = _variants.where((v) => v.color == color);
        final hasStock = variantsWithColor.any((v) => v.quantity > 0);

        // Also filter by selected size if any
        final validVariants = _selectedSize != null
            ? variantsWithColor.where((v) => v.size == _selectedSize)
            : variantsWithColor;
        final validHasStock = validVariants.any((v) => v.quantity > 0);

        return ChoiceChip(
          avatar: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: _getColorFromName(color),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey),
            ),
          ),
          label: Text(color),
          selected: isSelected,
          onSelected: validHasStock || isSelected
              ? (selected) {
                  setState(() {
                    _selectedColor = selected ? color : null;
                  });
                  _updateSelection();
                }
              : null,
          backgroundColor: validHasStock ? null : Colors.grey[200],
          selectedColor: Theme.of(context).primaryColor.withOpacity(0.2),
          labelStyle: TextStyle(
            color: !validHasStock
                ? Colors.grey
                : isSelected
                    ? Theme.of(context).primaryColor
                    : null,
            decoration: !validHasStock ? TextDecoration.lineThrough : null,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSelectedInfo() {
    final variant = _selectedVariant!;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: variant.isOutOfStock
            ? Colors.red.withOpacity(0.1)
            : Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: variant.isOutOfStock ? Colors.red : Colors.green,
        ),
      ),
      child: Row(
        children: [
          Icon(
            variant.isOutOfStock ? Icons.error : Icons.check_circle,
            color: variant.isOutOfStock ? Colors.red : Colors.green,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  variant.displayName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (widget.showStock)
                  Text(
                    variant.isOutOfStock
                        ? 'Hết hàng'
                        : 'Còn ${variant.quantity} sản phẩm',
                    style: TextStyle(
                      color: variant.isOutOfStock ? Colors.red : Colors.green,
                      fontSize: 12,
                    ),
                  ),
                if (variant.sku != null)
                  Text(
                    'SKU: ${variant.sku}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 11),
                  ),
              ],
            ),
          ),
          if (variant.salePrice > 0)
            Text(
              '${(variant.salePrice / 1000).toStringAsFixed(0)}K',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
        ],
      ),
    );
  }

  Color _getColorFromName(String colorName) {
    return CommonColors.hexCodes[colorName] != null
        ? _hexToColor(CommonColors.hexCodes[colorName]!)
        : Colors.grey;
  }

  Color _hexToColor(String hex) {
    hex = hex.replaceAll('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }
}

/// Widget hiển thị badge biến thể trên sản phẩm
class VariantBadge extends StatelessWidget {
  final VariantSummary summary;
  final bool compact;

  const VariantBadge({
    super.key,
    required this.summary,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (summary.totalVariants == 0) return const SizedBox.shrink();

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.purple.withOpacity(0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '${summary.totalVariants} biến thể',
          style: const TextStyle(
            fontSize: 10,
            color: Colors.purple,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.style, size: 16, color: Colors.purple),
              const SizedBox(width: 4),
              Text(
                '${summary.totalVariants} biến thể',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (summary.availableSizes.isNotEmpty)
            Text(
              'Size: ${summary.availableSizes.join(", ")}',
              style: const TextStyle(fontSize: 12),
            ),
          if (summary.availableColors.isNotEmpty)
            Text(
              'Màu: ${summary.availableColors.join(", ")}',
              style: const TextStyle(fontSize: 12),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.inventory_2, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text(
                'Tổng tồn: ${summary.totalStock}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
          Text(
            summary.priceRange,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget chọn biến thể dạng grid (cho danh sách sản phẩm)
class VariantQuickSelect extends StatelessWidget {
  final List<ProductVariant> variants;
  final Function(ProductVariant) onSelect;

  const VariantQuickSelect({
    super.key,
    required this.variants,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    // Group by size then color
    final grouped = <String, List<ProductVariant>>{};
    for (final v in variants) {
      final key = v.size ?? 'default';
      grouped.putIfAbsent(key, () => []).add(v);
    }

    return Column(
      children: grouped.entries.map((entry) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                width: 40,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  entry.key,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: entry.value.map((v) {
                    final hasStock = v.quantity > 0;
                    return InkWell(
                      onTap: hasStock ? () => onSelect(v) : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: hasStock
                              ? _getColorFromName(v.color ?? '').withOpacity(0.2)
                              : Colors.grey[200],
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: hasStock
                                ? _getColorFromName(v.color ?? '')
                                : Colors.grey,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              v.color ?? '?',
                              style: TextStyle(
                                fontSize: 10,
                                color: hasStock ? null : Colors.grey,
                                decoration: hasStock
                                    ? null
                                    : TextDecoration.lineThrough,
                              ),
                            ),
                            Text(
                              '${v.quantity}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: hasStock ? Colors.green : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Color _getColorFromName(String colorName) {
    return CommonColors.hexCodes[colorName] != null
        ? _hexToColor(CommonColors.hexCodes[colorName]!)
        : Colors.grey;
  }

  Color _hexToColor(String hex) {
    hex = hex.replaceAll('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }
}

/// Dialog chọn biến thể khi bán hàng
class VariantSelectionDialog extends StatefulWidget {
  final String productId;
  final String productName;
  final int productPrice;
  final ProductVariant? currentVariant;

  const VariantSelectionDialog({
    super.key,
    required this.productId,
    required this.productName,
    required this.productPrice,
    this.currentVariant,
  });

  @override
  State<VariantSelectionDialog> createState() => _VariantSelectionDialogState();
}

class _VariantSelectionDialogState extends State<VariantSelectionDialog> {
  ProductVariant? _selectedVariant;

  @override
  void initState() {
    super.initState();
    _selectedVariant = widget.currentVariant;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.productName),
      content: SizedBox(
        width: double.maxFinite,
        child: VariantSelector(
          productId: widget.productId,
          productName: widget.productName,
          initialVariant: widget.currentVariant,
          onVariantSelected: (v) => setState(() => _selectedVariant = v),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _selectedVariant != null && !_selectedVariant!.isOutOfStock
              ? () => Navigator.pop(context, _selectedVariant)
              : null,
          child: const Text('Chọn'),
        ),
      ],
    );
  }
}

/// Widget thống kê biến thể trên trang inventory
class VariantStockWidget extends StatelessWidget {
  final String productId;
  final VariantService variantService;

  const VariantStockWidget({
    super.key,
    required this.productId,
    required this.variantService,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<VariantSummary>(
      future: variantService.getVariantSummary(productId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final summary = snapshot.data!;
        if (summary.totalVariants == 0) {
          return const SizedBox.shrink();
        }

        return VariantBadge(summary: summary);
      },
    );
  }
}
