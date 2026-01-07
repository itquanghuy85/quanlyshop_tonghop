import 'package:flutter_test/flutter_test.dart';
import '../lib/utils/qr_parser.dart';

void main() {
  group('Fast Inventory Check QR Parsing Tests', () {
    test('Parse PHONE QR correctly', () {
      const qrData = 'type=PHONE&code=IPH15PM&imei=12345';
      final result = QRParser.parse(qrData);

      expect(result['type'], 'PHONE');
      expect(result['code'], 'IPH15PM');
      expect(result['imei'], '12345');
    });

    test('Parse ACCESSORY QR correctly', () {
      const qrData = 'type=ACCESSORY&code=CASE001';
      final result = QRParser.parse(qrData);

      expect(result['type'], 'ACCESSORY');
      expect(result['code'], 'CASE001');
      expect(result['imei'], isNull);
    });

    test('Handle URL encoded values', () {
      const qrData = 'type=PHONE&code=iPhone%2015%20Pro&imei=67890';
      final result = QRParser.parse(qrData);

      expect(result['type'], 'PHONE');
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
