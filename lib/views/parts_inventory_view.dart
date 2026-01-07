import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/db_helper.dart';
import '../services/user_service.dart';
import '../widgets/validated_text_field.dart';
import '../widgets/currency_text_field.dart';

class PartsInventoryView extends StatefulWidget {
  const PartsInventoryView({super.key});

  @override
  State<PartsInventoryView> createState() => _PartsInventoryViewState();
}

class _PartsInventoryViewState extends State<PartsInventoryView> {
  final db = DBHelper();
  List<Map<String, dynamic>> _parts = [];
  bool _isLoading = true;
  final searchCtrl = TextEditingController();
  bool _isAdmin = false;

  // Theme colors cho màn hình phụ tùng
  final Color _primaryColor = Colors.purple; // Màu chính cho phụ tùng
  final Color _backgroundColor = const Color(0xFFF8FAFF);

  @override
  void initState() {
    super.initState();
    _loadPermissions();
    _refreshParts();
  }

  Future<void> _loadPermissions() async {
    final perms = await UserService.getCurrentUserPermissions();
    if (!mounted) return;
    setState(() {
      _isAdmin = perms['allowViewParts'] ?? false;
    });
  }

  Future<void> _refreshParts() async {
    setState(() => _isLoading = true);
    final data = await db.getAllParts();
    setState(() {
      _parts = data;
      _isLoading = false;
    });
  }

  void _showAddPartDialog({Map<String, dynamic>? part}) {
    final nameC = TextEditingController(text: part?['partName']);
    final modelC = TextEditingController(text: part?['compatibleModels']);
    final costC = TextEditingController(
      text: part != null ? CurrencyTextField.formatDisplay(part['cost']) : "",
    );
    final priceC = TextEditingController(
      text: part != null ? CurrencyTextField.formatDisplay(part['price']) : "",
    );
    final qtyC = TextEditingController(
      text: part != null ? part['quantity'].toString() : "1",
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          nameC.addListener(() => setS(() {}));
          return AlertDialog(
            title: Text(part == null ? "NHẬP LINH KIỆN MỚI" : "SỬA LINH KIỆN"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValidatedTextField(
                    controller: nameC,
                    label: "Tên linh kiện (VD: PIN IPHONE 11)",
                    icon: Icons.inventory,
                    uppercase: true,
                    required: true,
                  ),
                  ValidatedTextField(
                    controller: modelC,
                    label: "Dòng máy tương thích",
                    icon: Icons.phone_android,
                    uppercase: true,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: CurrencyTextField(
                          controller: costC,
                          label: "Giá vốn",
                          icon: Icons.attach_money,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: CurrencyTextField(
                          controller: priceC,
                          label: "Giá bán",
                          icon: Icons.sell,
                        ),
                      ),
                    ],
                  ),
                  ValidatedTextField(
                    controller: qtyC,
                    label: "Số lượng nhập",
                    icon: Icons.numbers,
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("HỦY"),
              ),
              ElevatedButton(
                onPressed: nameC.text.isNotEmpty
                    ? () async {
                        if (nameC.text.isEmpty) return;
                        try {
                          final data = {
                            'partName': nameC.text.toUpperCase(),
                            'compatibleModels': modelC.text.toUpperCase(),
                            'cost': CurrencyTextField.parseValueWithMultiply(
                              costC.text,
                            ),
                            'price': CurrencyTextField.parseValueWithMultiply(
                              priceC.text,
                            ),
                            'quantity': int.tryParse(qtyC.text) ?? 0,
                            'updatedAt': DateTime.now().millisecondsSinceEpoch,
                          };
                          if (part == null) {
                            await db.insertPart(data);
                          } else {
                            await (await db.database).update(
                              'repair_parts',
                              data,
                              where: 'id = ?',
                              whereArgs: [part['id']],
                            );
                          }
                          if (!mounted) return;
                          Navigator.of(context).pop();
                          _refreshParts();
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Lỗi: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    : null,
                child: const Text("XÁC NHẬN"),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: const Text(
          "KHO LINH KIỆN SỬA CHỮA",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 2,
        automaticallyImplyLeading: true,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _primaryColor))
          : ListView.builder(
              padding: const EdgeInsets.all(15),
              itemCount: _parts.length,
              itemBuilder: (ctx, i) {
                final p = _parts[i];
                final bool isLow = p['quantity'] < 3;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isLow
                          ? Colors.red.withAlpha(25)
                          : _primaryColor.withAlpha(25),
                      child: Icon(
                        Icons.settings_input_component,
                        color: isLow ? Colors.red : _primaryColor,
                      ),
                    ),
                    title: Text(
                      p['partName'],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      "Dùng cho: ${p['compatibleModels']}\nSố lượng: ${p['quantity']}",
                    ),
                    trailing: Text(
                      "${NumberFormat('#,###').format(p['price'])} đ",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    onTap: _isAdmin ? () => _showAddPartDialog(part: p) : null,
                  ),
                );
              },
            ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _showAddPartDialog(),
              label: const Text("NHẬP LINH KIỆN"),
              icon: const Icon(Icons.add),
              backgroundColor: _primaryColor,
            )
          : null,
    );
  }
}
