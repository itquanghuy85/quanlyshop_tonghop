import 'package:flutter_test/flutter_test.dart';
import '../lib/utils/qr_parser.dart';

void main() {
  group('QR Parser Tests', () {
    test('Parse ORDER QR correctly', () {
      const qrData = 'type=ORDER&id=ABC123';
      final result = QRParser.parse(qrData);

      expect(result['type'], 'ORDER');
      expect(result['id'], 'ABC123');
      expect(QRParser.isValidQR(result), true);
      expect(QRParser.getType(result), 'ORDER');
    });

    test('Parse REPAIR QR correctly', () {
      const qrData = 'type=REPAIR&id=DEF456';
      final result = QRParser.parse(qrData);

      expect(result['type'], 'REPAIR');
      expect(result['id'], 'DEF456');
      expect(QRParser.isValidQR(result), true);
      expect(QRParser.getType(result), 'REPAIR');
    });

    test('Parse PHONE QR correctly', () {
      const qrData = 'type=PHONE&imei=12345&code=IPH15PM';
      final result = QRParser.parse(qrData);

      expect(result['type'], 'PHONE');
      expect(result['imei'], '12345');
      expect(result['code'], 'IPH15PM');
      expect(QRParser.isValidQR(result), true);
      expect(QRParser.getType(result), 'PHONE');
    });

    test('Parse ACCESSORY QR correctly', () {
      const qrData = 'type=ACCESSORY&code=CASE001';
      final result = QRParser.parse(qrData);

      expect(result['type'], 'ACCESSORY');
      expect(result['code'], 'CASE001');
      expect(QRParser.isValidQR(result), true);
      expect(QRParser.getType(result), 'ACCESSORY');
    });

    test('Handle invalid QR (missing type)', () {
      const qrData = 'id=ABC123';
      final result = QRParser.parse(qrData);

      expect(QRParser.isValidQR(result), false);
      expect(QRParser.getType(result), null);
    });

    test('Handle URL encoded values', () {
      const qrData = 'type=ORDER&id=iPhone%2015%20Pro%20Max';
      final result = QRParser.parse(qrData);

      expect(result['id'], 'iPhone 15 Pro Max');
    });

    test('Handle malformed QR gracefully', () {
      const qrData = 'invalid=data=here';
      final result = QRParser.parse(qrData);

      expect(result.length, 1);
      expect(result['invalid'], 'data=here');
    });

    test('Handle empty QR', () {
      const qrData = '';
      final result = QRParser.parse(qrData);

      expect(result.isEmpty, true);
      expect(QRParser.isValidQR(result), false);
    });
  });
}
