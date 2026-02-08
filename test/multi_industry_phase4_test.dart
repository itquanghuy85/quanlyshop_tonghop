// Phase 4: General Shop - Unit Tests
// Tests for DynamicFormBuilder, BusinessTypeWizard, and related models

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quanlyshop/widgets/dynamic_form_builder.dart';
import 'package:quanlyshop/views/onboarding/business_type_wizard.dart';
import 'package:quanlyshop/models/shop_settings_model.dart';

void main() {
  group('DynamicField Model Tests', () {
    test('creates text field correctly', () {
      final field = DynamicField(
        key: 'name',
        label: 'Tên sản phẩm',
        type: FieldType.text,
        required: true,
      );

      expect(field.key, equals('name'));
      expect(field.label, equals('Tên sản phẩm'));
      expect(field.type, equals(FieldType.text));
      expect(field.required, isTrue);
      expect(field.options, isEmpty);
    });

    test('creates select field with options', () {
      final field = DynamicField(
        key: 'category',
        label: 'Danh mục',
        type: FieldType.select,
        options: ['Điện thoại', 'Laptop', 'Phụ kiện'],
      );

      expect(field.key, equals('category'));
      expect(field.type, equals(FieldType.select));
      expect(field.options, hasLength(3));
      expect(field.options.first, equals('Điện thoại'));
    });

    test('creates multiSelect field', () {
      final field = DynamicField(
        key: 'tags',
        label: 'Nhãn',
        type: FieldType.multiSelect,
        options: ['Sale', 'New', 'Hot'],
      );

      expect(field.type, equals(FieldType.multiSelect));
      expect(field.options, hasLength(3));
    });

    test('creates number field', () {
      final field = DynamicField(
        key: 'quantity',
        label: 'Số lượng',
        type: FieldType.number,
        suffix: 'cái',
      );

      expect(field.type, equals(FieldType.number));
      expect(field.suffix, equals('cái'));
    });

    test('creates date field', () {
      final field = DynamicField(
        key: 'expiry',
        label: 'Hạn sử dụng',
        type: FieldType.date,
      );

      expect(field.type, equals(FieldType.date));
    });

    test('creates checkbox field with default value', () {
      final field = DynamicField(
        key: 'isActive',
        label: 'Đang hoạt động',
        type: FieldType.checkbox,
        defaultValue: true,
      );

      expect(field.type, equals(FieldType.checkbox));
      expect(field.defaultValue, isTrue);
    });

    test('creates textarea field', () {
      final field = DynamicField(
        key: 'description',
        label: 'Mô tả',
        type: FieldType.textarea,
        description: 'Nhập mô tả chi tiết sản phẩm',
        maxLines: 5,
      );

      expect(field.type, equals(FieldType.textarea));
      expect(field.description, equals('Nhập mô tả chi tiết sản phẩm'));
      expect(field.maxLines, equals(5));
    });

    test('creates color field', () {
      final field = DynamicField(
        key: 'productColor',
        label: 'Màu sản phẩm',
        type: FieldType.color,
      );

      expect(field.type, equals(FieldType.color));
    });

    test('creates field with hint', () {
      final field = DynamicField(
        key: 'phone',
        label: 'Số điện thoại',
        type: FieldType.text,
        hint: 'Nhập số điện thoại',
        icon: Icons.phone,
      );

      expect(field.hint, equals('Nhập số điện thoại'));
      expect(field.icon, equals(Icons.phone));
    });
  });

  group('DynamicField.fromJson Tests', () {
    test('parses text field from JSON', () {
      final json = {
        'key': 'name',
        'label': 'Tên',
        'type': 'text',
        'required': true,
        'hint': 'Nhập tên'
      };

      final field = DynamicField.fromJson(json);

      expect(field.key, equals('name'));
      expect(field.label, equals('Tên'));
      expect(field.type, equals(FieldType.text));
      expect(field.required, isTrue);
      expect(field.hint, equals('Nhập tên'));
    });

    test('parses select field with options', () {
      final json = {
        'key': 'size',
        'label': 'Kích thước',
        'type': 'select',
        'options': ['S', 'M', 'L', 'XL']
      };

      final field = DynamicField.fromJson(json);

      expect(field.type, equals(FieldType.select));
      expect(field.options, equals(['S', 'M', 'L', 'XL']));
    });

    test('parses number field with suffix', () {
      final json = {
        'key': 'price',
        'label': 'Giá',
        'type': 'number',
        'suffix': 'VND'
      };

      final field = DynamicField.fromJson(json);

      expect(field.type, equals(FieldType.number));
      expect(field.suffix, equals('VND'));
    });

    test('parses checkbox with default value', () {
      final json = {
        'key': 'featured',
        'label': 'Nổi bật',
        'type': 'checkbox',
        'defaultValue': false
      };

      final field = DynamicField.fromJson(json);

      expect(field.type, equals(FieldType.checkbox));
      expect(field.defaultValue, isFalse);
    });

    test('handles unknown type gracefully', () {
      final json = {
        'key': 'unknown',
        'label': 'Unknown',
        'type': 'fancy_field'
      };

      final field = DynamicField.fromJson(json);

      expect(field.type, equals(FieldType.text)); // fallback to text
    });

    test('parses dropdown as select', () {
      final json = {
        'key': 'status',
        'label': 'Trạng thái',
        'type': 'dropdown',
        'options': ['A', 'B']
      };

      final field = DynamicField.fromJson(json);
      expect(field.type, equals(FieldType.select));
    });

    test('parses int as number', () {
      final json = {
        'key': 'count',
        'label': 'Số lượng',
        'type': 'int'
      };

      final field = DynamicField.fromJson(json);
      expect(field.type, equals(FieldType.number));
    });

    test('parses bool as checkbox', () {
      final json = {
        'key': 'active',
        'label': 'Hoạt động',
        'type': 'bool'
      };

      final field = DynamicField.fromJson(json);
      expect(field.type, equals(FieldType.checkbox));
    });

    test('parses multiline as textarea', () {
      final json = {
        'key': 'note',
        'label': 'Ghi chú',
        'type': 'multiline',
        'maxLines': 4
      };

      final field = DynamicField.fromJson(json);
      expect(field.type, equals(FieldType.textarea));
      expect(field.maxLines, equals(4));
    });
  });

  group('DynamicField.toJson Tests', () {
    test('converts field to JSON correctly', () {
      final field = DynamicField(
        key: 'brand',
        label: 'Thương hiệu',
        type: FieldType.select,
        options: ['Apple', 'Samsung', 'Xiaomi'],
        required: true,
      );

      final json = field.toJson();

      expect(json['key'], equals('brand'));
      expect(json['label'], equals('Thương hiệu'));
      expect(json['type'], equals('select'));
      expect(json['options'], equals(['Apple', 'Samsung', 'Xiaomi']));
      expect(json['required'], isTrue);
    });

    test('round-trip JSON conversion', () {
      final original = DynamicField(
        key: 'weight',
        label: 'Trọng lượng',
        type: FieldType.number,
        defaultValue: 1.0,
        description: 'Đơn vị: kg',
        suffix: 'kg',
      );

      final json = original.toJson();
      final restored = DynamicField.fromJson(json);

      expect(restored.key, equals(original.key));
      expect(restored.label, equals(original.label));
      expect(restored.type, equals(original.type));
      expect(restored.description, equals(original.description));
      expect(restored.suffix, equals(original.suffix));
    });
  });

  group('FieldType Parsing Tests', () {
    test('has all 8 field types', () {
      expect(FieldType.values.length, equals(8));
    });

    test('all types have correct names', () {
      expect(FieldType.text.name, equals('text'));
      expect(FieldType.number.name, equals('number'));
      expect(FieldType.select.name, equals('select'));
      expect(FieldType.multiSelect.name, equals('multiSelect'));
      expect(FieldType.date.name, equals('date'));
      expect(FieldType.checkbox.name, equals('checkbox'));
      expect(FieldType.textarea.name, equals('textarea'));
      expect(FieldType.color.name, equals('color'));
    });
  });

  group('parseFieldsFromJson Tests', () {
    test('parses JSON array string to list of fields', () {
      final jsonString = '''[
        {"key": "name", "label": "Tên", "type": "text", "required": true},
        {"key": "price", "label": "Giá", "type": "number"}
      ]''';

      final fields = parseFieldsFromJson(jsonString);

      expect(fields, hasLength(2));
      expect(fields[0].key, equals('name'));
      expect(fields[1].key, equals('price'));
    });

    test('returns empty list for null input', () {
      final fields = parseFieldsFromJson(null);
      expect(fields, isEmpty);
    });

    test('returns empty list for empty string', () {
      final fields = parseFieldsFromJson('');
      expect(fields, isEmpty);
    });

    test('returns empty list for invalid JSON', () {
      final fields = parseFieldsFromJson('not valid json');
      expect(fields, isEmpty);
    });
  });

  group('fieldsToJsonString Tests', () {
    test('converts list of fields to JSON string', () {
      final fields = [
        DynamicField(key: 'a', label: 'A', type: FieldType.text),
        DynamicField(key: 'b', label: 'B', type: FieldType.number),
      ];

      final jsonString = fieldsToJsonString(fields);
      
      expect(jsonString, isNotNull);
      expect(jsonString, contains('"key":"a"'));
      expect(jsonString, contains('"key":"b"'));
    });

    test('round-trip conversion', () {
      final original = [
        DynamicField(
          key: 'test',
          label: 'Test',
          type: FieldType.select,
          options: ['A', 'B', 'C'],
        ),
      ];

      final jsonString = fieldsToJsonString(original);
      final restored = parseFieldsFromJson(jsonString);

      expect(restored, hasLength(1));
      expect(restored[0].key, equals('test'));
      expect(restored[0].options, equals(['A', 'B', 'C']));
    });
  });

  group('BusinessTypePresets Tests', () {
    test('gets electronics preset', () {
      final preset = BusinessTypePresets.getPreset('electronics');

      expect(preset['businessType'], equals('electronics'));
      expect(preset['enableRepair'], isTrue);
      expect(preset['enableSerial'], isTrue);
      expect(preset['enableWarranty'], isTrue);
      expect(preset['enableExpiry'], isFalse);
      expect(preset['enableVariants'], isFalse);
      expect(preset['defaultUnit'], equals('cái'));
      expect(preset['defaultCategories'], isNotEmpty);
    });

    test('gets food preset', () {
      final preset = BusinessTypePresets.getPreset('food');

      expect(preset['businessType'], equals('food'));
      expect(preset['enableRepair'], isFalse);
      expect(preset['enableExpiry'], isTrue);
      expect(preset['enableBatch'], isTrue);
      expect(preset['defaultUnit'], equals('kg'));
      expect(preset['expiryWarningDays'], equals(7));
    });

    test('gets fashion preset', () {
      final preset = BusinessTypePresets.getPreset('fashion');

      expect(preset['businessType'], equals('fashion'));
      expect(preset['enableVariants'], isTrue);
      expect(preset['enableExpiry'], isFalse);
      expect(preset['enableRepair'], isFalse);
    });

    test('gets general preset', () {
      final preset = BusinessTypePresets.getPreset('general');

      expect(preset['businessType'], equals('general'));
      expect(preset['enableRepair'], isFalse);
      expect(preset['enableSerial'], isFalse);
      expect(preset['enableWarranty'], isFalse);
      expect(preset['enableExpiry'], isFalse);
      expect(preset['enableVariants'], isFalse);
      expect(preset['enableBatch'], isFalse);
    });

    test('defaults to general for unknown type', () {
      final preset = BusinessTypePresets.getPreset('unknown');

      expect(preset['businessType'], equals('general'));
    });

    test('availableTypes has all 4 types', () {
      expect(BusinessTypePresets.availableTypes, hasLength(4));
      expect(BusinessTypePresets.availableTypes, contains('electronics'));
      expect(BusinessTypePresets.availableTypes, contains('food'));
      expect(BusinessTypePresets.availableTypes, contains('fashion'));
      expect(BusinessTypePresets.availableTypes, contains('general'));
    });

    test('getTypeName returns Vietnamese names', () {
      expect(BusinessTypePresets.getTypeName('electronics'), contains('Điện'));
      expect(BusinessTypePresets.getTypeName('food'), contains('Thực phẩm'));
      expect(BusinessTypePresets.getTypeName('fashion'), contains('Thời trang'));
      expect(BusinessTypePresets.getTypeName('general'), contains('Tổng hợp'));
    });

    test('getTypeIcon returns emoji icons', () {
      expect(BusinessTypePresets.getTypeIcon('electronics'), equals('📱'));
      expect(BusinessTypePresets.getTypeIcon('food'), equals('🍎'));
      expect(BusinessTypePresets.getTypeIcon('fashion'), equals('👕'));
      expect(BusinessTypePresets.getTypeIcon('general'), equals('📦'));
    });
  });

  group('Electronics Preset Categories Tests', () {
    test('electronics has correct categories', () {
      final preset = BusinessTypePresets.getPreset('electronics');
      final categories = preset['defaultCategories'] as List<Map<String, dynamic>>;

      expect(categories, hasLength(5));
      
      // Check phone category
      final phone = categories.firstWhere((c) => c['name'] == 'Điện thoại');
      expect(phone['trackSerial'], isTrue);
      expect(phone['hasWarranty'], isTrue);
      
      // Check accessory category
      final accessory = categories.firstWhere((c) => c['name'] == 'Phụ kiện');
      expect(accessory['trackSerial'], isFalse);
    });
  });

  group('Food Preset Categories Tests', () {
    test('food has correct categories', () {
      final preset = BusinessTypePresets.getPreset('food');
      final categories = preset['defaultCategories'] as List<Map<String, dynamic>>;

      expect(categories, hasLength(7));
      
      // Check vegetable category
      final veggie = categories.firstWhere((c) => c['name'] == 'Rau củ');
      expect(veggie['trackExpiry'], isTrue);
      expect(veggie['unit'], equals('kg'));
    });
  });

  group('Fashion Preset Categories Tests', () {
    test('fashion has correct categories', () {
      final preset = BusinessTypePresets.getPreset('fashion');
      final categories = preset['defaultCategories'] as List<Map<String, dynamic>>;

      expect(categories, hasLength(6));
      
      // Check shirt category
      final shirt = categories.firstWhere((c) => c['name'] == 'Áo');
      expect(shirt['hasVariants'], isTrue);
      
      // Check bag category - no variants
      final bag = categories.firstWhere((c) => c['name'] == 'Túi xách');
      expect(bag['hasVariants'], isFalse);
    });
  });

  group('ShopSettings with BusinessType Tests', () {
    test('creates ShopSettings for electronics', () {
      final preset = BusinessTypePresets.getPreset('electronics');
      final settings = ShopSettings(
        shopId: 'shop1',
        businessType: preset['businessType'],
        businessTypeName: preset['businessTypeName'],
        enableRepair: preset['enableRepair'],
        enableSerial: preset['enableSerial'],
        enableWarranty: preset['enableWarranty'],
        defaultUnit: preset['defaultUnit'],
      );

      expect(settings.businessType, equals('electronics'));
      expect(settings.enableRepair, isTrue);
      expect(settings.enableSerial, isTrue);
    });

    test('creates ShopSettings for food', () {
      final preset = BusinessTypePresets.getPreset('food');
      final settings = ShopSettings(
        shopId: 'shop2',
        businessType: preset['businessType'],
        businessTypeName: preset['businessTypeName'],
        enableExpiry: preset['enableExpiry'],
        enableBatch: preset['enableBatch'],
        defaultUnit: preset['defaultUnit'],
        expiryWarningDays: preset['expiryWarningDays'],
      );

      expect(settings.businessType, equals('food'));
      expect(settings.enableExpiry, isTrue);
      expect(settings.enableBatch, isTrue);
      expect(settings.expiryWarningDays, equals(7));
    });

    test('creates ShopSettings for fashion', () {
      final preset = BusinessTypePresets.getPreset('fashion');
      final settings = ShopSettings(
        shopId: 'shop3',
        businessType: preset['businessType'],
        businessTypeName: preset['businessTypeName'],
        enableVariants: preset['enableVariants'],
        defaultUnit: preset['defaultUnit'],
      );

      expect(settings.businessType, equals('fashion'));
      expect(settings.enableVariants, isTrue);
    });
  });

  group('Field Validation Logic Tests', () {
    test('required field validation', () {
      final field = DynamicField(
        key: 'name',
        label: 'Tên',
        type: FieldType.text,
        required: true,
      );

      // Logic test - empty value should fail for required
      expect(field.required, isTrue);
      final isEmpty = ''.isEmpty;
      expect(isEmpty && field.required, isTrue); // Would fail validation
    });

    test('select field options validation logic', () {
      final field = DynamicField(
        key: 'size',
        label: 'Size',
        type: FieldType.select,
        options: ['S', 'M', 'L'],
      );

      // Test valid option
      expect(field.options.contains('M'), isTrue);

      // Test invalid option
      expect(field.options.contains('XXL'), isFalse);
    });
  });

  group('Complex Field Configurations Tests', () {
    test('field with all properties', () {
      final field = DynamicField(
        key: 'fullField',
        label: 'Full Field',
        type: FieldType.number,
        required: true,
        hint: 'Enter value',
        description: 'This is description text',
        suffix: 'VND',
        defaultValue: 10,
      );

      expect(field.key, equals('fullField'));
      expect(field.required, isTrue);
      expect(field.hint, equals('Enter value'));
      expect(field.description, equals('This is description text'));
      expect(field.suffix, equals('VND'));
      expect(field.defaultValue, equals(10));
    });

    test('multiSelect field with multiple selected', () {
      final field = DynamicField(
        key: 'features',
        label: 'Tính năng',
        type: FieldType.multiSelect,
        options: ['WiFi', 'Bluetooth', 'NFC', '5G', 'Fast Charging'],
        defaultValue: ['WiFi', 'Bluetooth'],
      );

      expect(field.type, equals(FieldType.multiSelect));
      expect(field.options, hasLength(5));
      expect(field.defaultValue, isA<List>());
      expect((field.defaultValue as List).length, equals(2));
    });
  });

  group('Edge Cases Tests', () {
    test('empty key field', () {
      final field = DynamicField(
        key: '',
        label: 'No Key',
        type: FieldType.text,
      );

      expect(field.key, isEmpty);
    });

    test('unicode in labels and options', () {
      final field = DynamicField(
        key: 'vn',
        label: 'Màu sắc đặc biệt',
        type: FieldType.select,
        options: ['Đỏ', 'Vàng', 'Xanh lá', 'Xanh dương'],
      );

      expect(field.label, contains('đặc biệt'));
      expect(field.options.first, equals('Đỏ'));
    });

    test('empty options list', () {
      final field = DynamicField(
        key: 'empty',
        label: 'Empty select',
        type: FieldType.select,
      );

      expect(field.options, isEmpty);
    });
  });

  group('JSON Array Fields List Tests', () {
    test('parses complex nested structure', () {
      final jsonString = '''[
        {
          "key": "productName",
          "label": "Tên sản phẩm",
          "type": "text",
          "required": true,
          "hint": "Nhập tên sản phẩm"
        },
        {
          "key": "category",
          "label": "Danh mục",
          "type": "select",
          "options": ["Điện tử", "Thời trang", "Thực phẩm"]
        },
        {
          "key": "attributes",
          "label": "Thuộc tính",
          "type": "multiSelect",
          "options": ["Hot", "Sale", "New", "Limited"]
        },
        {
          "key": "price",
          "label": "Giá bán",
          "type": "number",
          "suffix": "VND"
        },
        {
          "key": "expiryDate",
          "label": "Hạn sử dụng",
          "type": "date"
        },
        {
          "key": "isActive",
          "label": "Đang bán",
          "type": "checkbox",
          "defaultValue": true
        },
        {
          "key": "description",
          "label": "Mô tả",
          "type": "textarea"
        },
        {
          "key": "color",
          "label": "Màu sắc",
          "type": "color"
        }
      ]''';

      final fields = parseFieldsFromJson(jsonString);

      expect(fields, hasLength(8));
      expect(fields[0].type, equals(FieldType.text));
      expect(fields[1].type, equals(FieldType.select));
      expect(fields[2].type, equals(FieldType.multiSelect));
      expect(fields[3].type, equals(FieldType.number));
      expect(fields[4].type, equals(FieldType.date));
      expect(fields[5].type, equals(FieldType.checkbox));
      expect(fields[6].type, equals(FieldType.textarea));
      expect(fields[7].type, equals(FieldType.color));
    });
  });

  group('Default Values Tests', () {
    test('field without options has empty list', () {
      final field = DynamicField(
        key: 'text',
        label: 'Text',
        type: FieldType.text,
      );

      expect(field.options, isA<List>());
      expect(field.options, isEmpty);
    });

    test('field defaults required to false', () {
      final field = DynamicField(
        key: 'opt',
        label: 'Optional',
        type: FieldType.text,
      );

      expect(field.required, isFalse);
    });

    test('field defaults type to text', () {
      final field = DynamicField(
        key: 't',
        label: 'T',
      );

      expect(field.type, equals(FieldType.text));
    });
  });
}
