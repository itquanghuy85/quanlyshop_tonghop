import 'package:flutter/material.dart';
import 'dart:convert';

/// Widget builder cho dynamic form fields
/// Hỗ trợ tạo form động dựa trên cấu hình JSON
/// Dùng cho ngành "General" - tùy chỉnh thuộc tính sản phẩm
class DynamicFormBuilder extends StatelessWidget {
  final List<DynamicField> fields;
  final Map<String, dynamic> values;
  final Function(String key, dynamic value) onFieldChanged;
  final bool readOnly;

  const DynamicFormBuilder({
    super.key,
    required this.fields,
    required this.values,
    required this.onFieldChanged,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: fields.map((field) => _buildField(context, field)).toList(),
    );
  }

  Widget _buildField(BuildContext context, DynamicField field) {
    switch (field.type) {
      case FieldType.text:
        return _buildTextField(field);
      case FieldType.number:
        return _buildNumberField(field);
      case FieldType.select:
        return _buildSelectField(context, field);
      case FieldType.multiSelect:
        return _buildMultiSelectField(context, field);
      case FieldType.date:
        return _buildDateField(context, field);
      case FieldType.checkbox:
        return _buildCheckboxField(field);
      case FieldType.textarea:
        return _buildTextareaField(field);
      case FieldType.color:
        return _buildColorField(context, field);
      default:
        return _buildTextField(field);
    }
  }

  Widget _buildTextField(DynamicField field) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        initialValue: values[field.key]?.toString() ?? '',
        decoration: InputDecoration(
          labelText: field.label,
          hintText: field.hint,
          helperText: field.description,
          border: const OutlineInputBorder(),
          prefixIcon: field.icon != null ? Icon(field.icon) : null,
        ),
        readOnly: readOnly,
        enabled: !readOnly,
        onChanged: (value) => onFieldChanged(field.key, value),
        validator: field.required
            ? (v) => v == null || v.isEmpty ? 'Vui lòng nhập ${field.label}' : null
            : null,
      ),
    );
  }

  Widget _buildNumberField(DynamicField field) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        initialValue: values[field.key]?.toString() ?? '',
        decoration: InputDecoration(
          labelText: field.label,
          hintText: field.hint,
          helperText: field.description,
          border: const OutlineInputBorder(),
          prefixIcon: field.icon != null ? Icon(field.icon) : null,
          suffixText: field.suffix,
        ),
        keyboardType: TextInputType.number,
        readOnly: readOnly,
        enabled: !readOnly,
        onChanged: (value) => onFieldChanged(field.key, int.tryParse(value) ?? 0),
        validator: field.required
            ? (v) => v == null || v.isEmpty ? 'Vui lòng nhập ${field.label}' : null
            : null,
      ),
    );
  }

  Widget _buildSelectField(BuildContext context, DynamicField field) {
    final currentValue = values[field.key]?.toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        value: field.options.contains(currentValue) ? currentValue : null,
        decoration: InputDecoration(
          labelText: field.label,
          helperText: field.description,
          border: const OutlineInputBorder(),
          prefixIcon: field.icon != null ? Icon(field.icon) : null,
        ),
        items: field.options.map((option) => DropdownMenuItem(
          value: option,
          child: Text(option),
        )).toList(),
        onChanged: readOnly ? null : (value) => onFieldChanged(field.key, value),
        validator: field.required
            ? (v) => v == null ? 'Vui lòng chọn ${field.label}' : null
            : null,
      ),
    );
  }

  Widget _buildMultiSelectField(BuildContext context, DynamicField field) {
    final currentValues = List<String>.from(values[field.key] ?? []);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(field.label, style: const TextStyle(fontWeight: FontWeight.w500)),
          if (field.description != null)
            Text(field.description!, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: field.options.map((option) {
              final isSelected = currentValues.contains(option);
              return FilterChip(
                label: Text(option),
                selected: isSelected,
                onSelected: readOnly
                    ? null
                    : (selected) {
                        final newValues = List<String>.from(currentValues);
                        if (selected) {
                          newValues.add(option);
                        } else {
                          newValues.remove(option);
                        }
                        onFieldChanged(field.key, newValues);
                      },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDateField(BuildContext context, DynamicField field) {
    final currentValue = values[field.key];
    DateTime? date;
    if (currentValue is int) {
      date = DateTime.fromMillisecondsSinceEpoch(currentValue);
    } else if (currentValue is String && currentValue.isNotEmpty) {
      date = DateTime.tryParse(currentValue);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: readOnly
            ? null
            : () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  onFieldChanged(field.key, picked.millisecondsSinceEpoch);
                }
              },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: field.label,
            helperText: field.description,
            border: const OutlineInputBorder(),
            prefixIcon: field.icon != null ? Icon(field.icon) : const Icon(Icons.calendar_today),
            suffixIcon: date != null && !readOnly
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => onFieldChanged(field.key, null),
                  )
                : null,
          ),
          child: Text(
            date != null
                ? '${date.day}/${date.month}/${date.year}'
                : field.hint ?? 'Chọn ngày...',
            style: TextStyle(
              color: date != null ? null : Colors.grey[600],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCheckboxField(DynamicField field) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: CheckboxListTile(
        title: Text(field.label),
        subtitle: field.description != null ? Text(field.description!) : null,
        value: values[field.key] == true,
        onChanged: readOnly ? null : (value) => onFieldChanged(field.key, value),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildTextareaField(DynamicField field) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        initialValue: values[field.key]?.toString() ?? '',
        decoration: InputDecoration(
          labelText: field.label,
          hintText: field.hint,
          helperText: field.description,
          border: const OutlineInputBorder(),
          alignLabelWithHint: true,
        ),
        maxLines: field.maxLines ?? 3,
        readOnly: readOnly,
        enabled: !readOnly,
        onChanged: (value) => onFieldChanged(field.key, value),
      ),
    );
  }

  Widget _buildColorField(BuildContext context, DynamicField field) {
    final currentValue = values[field.key]?.toString();
    final commonColors = ['Đen', 'Trắng', 'Đỏ', 'Xanh', 'Vàng', 'Hồng', 'Xám', 'Nâu'];

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(field.label, style: const TextStyle(fontWeight: FontWeight.w500)),
          if (field.description != null)
            Text(field.description!, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: commonColors.map((color) {
              final isSelected = currentValue == color;
              return ChoiceChip(
                label: Text(color),
                selected: isSelected,
                onSelected: readOnly
                    ? null
                    : (selected) => onFieldChanged(field.key, selected ? color : null),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

/// Enum cho loại field
enum FieldType {
  text,
  number,
  select,
  multiSelect,
  date,
  checkbox,
  textarea,
  color,
}

/// Model cho dynamic field
class DynamicField {
  final String key;
  final String label;
  final FieldType type;
  final String? hint;
  final String? description;
  final String? suffix;
  final bool required;
  final List<String> options;
  final IconData? icon;
  final int? maxLines;
  final dynamic defaultValue;

  DynamicField({
    required this.key,
    required this.label,
    this.type = FieldType.text,
    this.hint,
    this.description,
    this.suffix,
    this.required = false,
    this.options = const [],
    this.icon,
    this.maxLines,
    this.defaultValue,
  });

  /// Create from JSON config
  factory DynamicField.fromJson(Map<String, dynamic> json) {
    return DynamicField(
      key: json['key'] ?? json['name'] ?? '',
      label: json['label'] ?? json['key'] ?? '',
      type: _parseFieldType(json['type']),
      hint: json['hint'],
      description: json['description'],
      suffix: json['suffix'],
      required: json['required'] == true,
      options: List<String>.from(json['options'] ?? []),
      icon: _parseIcon(json['icon']),
      maxLines: json['maxLines'],
      defaultValue: json['defaultValue'],
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'label': label,
      'type': type.name,
      'hint': hint,
      'description': description,
      'suffix': suffix,
      'required': required,
      'options': options,
      'maxLines': maxLines,
      'defaultValue': defaultValue,
    };
  }

  static FieldType _parseFieldType(String? type) {
    switch (type?.toLowerCase()) {
      case 'number':
      case 'int':
      case 'integer':
        return FieldType.number;
      case 'select':
      case 'dropdown':
        return FieldType.select;
      case 'multiselect':
      case 'multi_select':
        return FieldType.multiSelect;
      case 'date':
      case 'datetime':
        return FieldType.date;
      case 'checkbox':
      case 'bool':
      case 'boolean':
        return FieldType.checkbox;
      case 'textarea':
      case 'multiline':
        return FieldType.textarea;
      case 'color':
        return FieldType.color;
      default:
        return FieldType.text;
    }
  }

  static IconData? _parseIcon(String? iconName) {
    final iconMap = {
      'phone': Icons.phone,
      'email': Icons.email,
      'calendar': Icons.calendar_today,
      'money': Icons.attach_money,
      'barcode': Icons.qr_code,
      'location': Icons.location_on,
      'person': Icons.person,
      'inventory': Icons.inventory,
      'weight': Icons.scale,
      'timer': Icons.timer,
      'color': Icons.color_lens,
      'size': Icons.straighten,
    };
    return iconMap[iconName];
  }
}

/// Widget để quản lý custom fields cho category
class CustomFieldsEditor extends StatefulWidget {
  final List<DynamicField> fields;
  final Function(List<DynamicField>) onFieldsChanged;

  const CustomFieldsEditor({
    super.key,
    required this.fields,
    required this.onFieldsChanged,
  });

  @override
  State<CustomFieldsEditor> createState() => _CustomFieldsEditorState();
}

class _CustomFieldsEditorState extends State<CustomFieldsEditor> {
  late List<DynamicField> _fields;

  @override
  void initState() {
    super.initState();
    _fields = List.from(widget.fields);
  }

  void _addField() async {
    final newField = await showDialog<DynamicField>(
      context: context,
      builder: (context) => const _AddFieldDialog(),
    );

    if (newField != null) {
      setState(() => _fields.add(newField));
      widget.onFieldsChanged(_fields);
    }
  }

  void _removeField(int index) {
    setState(() => _fields.removeAt(index));
    widget.onFieldsChanged(_fields);
  }

  void _reorderFields(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    setState(() {
      final item = _fields.removeAt(oldIndex);
      _fields.insert(newIndex, item);
    });
    widget.onFieldsChanged(_fields);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Thuộc tính tùy chỉnh',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            TextButton.icon(
              onPressed: _addField,
              icon: const Icon(Icons.add),
              label: const Text('Thêm thuộc tính'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_fields.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.add_box_outlined, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 8),
                    Text(
                      'Chưa có thuộc tính tùy chỉnh',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    const Text(
                      'Thêm thuộc tính để thu thập thông tin sản phẩm',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _fields.length,
            onReorder: _reorderFields,
            itemBuilder: (context, index) {
              final field = _fields[index];
              return Card(
                key: ValueKey(field.key),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.drag_handle),
                  title: Text(field.label),
                  subtitle: Text(
                    '${field.type.name}${field.required ? ' *' : ''}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _removeField(index),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Dialog thêm field mới
class _AddFieldDialog extends StatefulWidget {
  const _AddFieldDialog();

  @override
  State<_AddFieldDialog> createState() => _AddFieldDialogState();
}

class _AddFieldDialogState extends State<_AddFieldDialog> {
  final _keyController = TextEditingController();
  final _labelController = TextEditingController();
  final _optionsController = TextEditingController();
  FieldType _type = FieldType.text;
  bool _required = false;

  @override
  void dispose() {
    _keyController.dispose();
    _labelController.dispose();
    _optionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Thêm thuộc tính'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _labelController,
              decoration: const InputDecoration(
                labelText: 'Tên hiển thị',
                hintText: 'VD: Xuất xứ, Chất liệu...',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                // Auto-generate key from label
                _keyController.text = v
                    .toLowerCase()
                    .replaceAll(' ', '_')
                    .replaceAll(RegExp(r'[^\w]'), '');
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _keyController,
              decoration: const InputDecoration(
                labelText: 'Mã (key)',
                helperText: 'Tự động tạo từ tên',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<FieldType>(
              value: _type,
              decoration: const InputDecoration(
                labelText: 'Loại',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: FieldType.text, child: Text('Văn bản')),
                DropdownMenuItem(value: FieldType.number, child: Text('Số')),
                DropdownMenuItem(value: FieldType.select, child: Text('Chọn 1')),
                DropdownMenuItem(value: FieldType.multiSelect, child: Text('Chọn nhiều')),
                DropdownMenuItem(value: FieldType.date, child: Text('Ngày')),
                DropdownMenuItem(value: FieldType.checkbox, child: Text('Có/Không')),
                DropdownMenuItem(value: FieldType.textarea, child: Text('Đoạn văn')),
                DropdownMenuItem(value: FieldType.color, child: Text('Màu sắc')),
              ],
              onChanged: (v) => setState(() => _type = v ?? FieldType.text),
            ),
            if (_type == FieldType.select || _type == FieldType.multiSelect) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _optionsController,
                decoration: const InputDecoration(
                  labelText: 'Các lựa chọn',
                  hintText: 'VN, TQ, Mỹ, ...',
                  helperText: 'Phân cách bằng dấu phẩy',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            CheckboxListTile(
              title: const Text('Bắt buộc'),
              value: _required,
              onChanged: (v) => setState(() => _required = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () {
            if (_labelController.text.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Vui lòng nhập tên')),
              );
              return;
            }

            final options = _optionsController.text
                .split(',')
                .map((o) => o.trim())
                .where((o) => o.isNotEmpty)
                .toList();

            Navigator.pop(
              context,
              DynamicField(
                key: _keyController.text.isEmpty
                    ? 'field_${DateTime.now().millisecondsSinceEpoch}'
                    : _keyController.text,
                label: _labelController.text,
                type: _type,
                required: _required,
                options: options,
              ),
            );
          },
          child: const Text('Thêm'),
        ),
      ],
    );
  }
}

/// Helper để parse JSON string thành list of fields
List<DynamicField> parseFieldsFromJson(String? jsonString) {
  if (jsonString == null || jsonString.isEmpty) return [];
  try {
    final list = json.decode(jsonString) as List;
    return list.map((e) => DynamicField.fromJson(e)).toList();
  } catch (e) {
    return [];
  }
}

/// Helper để convert list of fields thành JSON string
String fieldsToJsonString(List<DynamicField> fields) {
  return json.encode(fields.map((f) => f.toJson()).toList());
}
