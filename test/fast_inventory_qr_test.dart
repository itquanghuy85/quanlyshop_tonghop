import 'package:flutter_test/flutter_test.dart';
import 'package:quanlyshop/utils/qr_parser.dart';

void main() {
  group('Fast Inventory Check QR Parsing Tests', () {
    test('Parse DIEN_THOAI QR correctly', () {
      const qrData = 'type=DIEN_THOAI&code=IPH15PM&imei=12345';
      final result = QRParser.parse(qrData);

      expect(result['type'], 'DIEN_THOAI');
      expect(result['code'], 'IPH15PM');
      expect(result['imei'], '12345');
    });

    test('Parse PHỤ KIỆN QR correctly', () {
      const qrData = 'type=PHỤ KIỆN&code=CASE001';
      final result = QRParser.parse(qrData);

      expect(result['type'], 'PHỤ KIỆN');
      expect(result['code'], 'CASE001');
      expect(result['imei'], isNull);
    });

    test('Handle URL encoded values', () {
      const qrData = 'type=DIEN_THOAI&code=iPhone%2015%20Pro&imei=67890';
      final result = QRParser.parse(qrData);

      expect(result['type'], 'DIEN_THOAI');
      expect(result['code'], 'iPhone 15 Pro');
      expect(result['imei'], '67890');
    });

    test('Ignore unknown QR types', () {
      const qrData = 'type=ORDER&id=123';
      final result = QRParser.parse(qrData);

      expect(result['type'], 'ORDER');
      // Should still parse but our inventory check will ignore it
    });

    test('Handle malformed QR gracefully', () {
      const qrData = 'invalid=data=here';
      final result = QRParser.parse(qrData);

      expect(result, isNotNull);
      expect(result['invalid'], 'data=here');
    });
  });
}
