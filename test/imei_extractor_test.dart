import 'package:flutter_test/flutter_test.dart';
import 'package:quanlyshop/utils/imei_extractor.dart';

void main() {
  group('IMEIExtractor', () {
    // Valid IMEI for testing (passes Luhn check): 490154203237518
    // Another valid: 354712093476189
    
    group('extract', () {
      test('should extract single IMEI from simple string', () {
        // Using valid IMEI that passes Luhn check
        const qrData = '490154203237518';
        final result = IMEIExtractor.extract(qrData);
        
        expect(result.hasIMEI, isTrue);
        expect(result.candidates.length, 1);
        expect(result.candidates.first, '490154203237518');
        expect(result.isMultiLine, isFalse);
      });

      test('should extract IMEI with label', () {
        const qrData = 'IMEI: 490154203237518';
        final result = IMEIExtractor.extract(qrData);
        
        expect(result.hasIMEI, isTrue);
        expect(result.imei, '490154203237518');
      });

      test('should extract multiple IMEIs from multi-line QR (Apple style)', () {
        // Both IMEIs must pass Luhn check
        // 490154203237518 - valid
        // 352099001761481 - valid (generated with Luhn)
        const qrData = '''IMEI:490154203237518
IMEI2:352099001761481
S/N:ABC123DEF456
Model:iPhone 15 Pro''';
        
        final result = IMEIExtractor.extract(qrData);
        
        expect(result.hasIMEI, isTrue);
        expect(result.hasMultipleCandidates, isTrue);
        expect(result.candidates.length, 2);
        expect(result.candidates, contains('490154203237518'));
        expect(result.candidates, contains('352099001761481'));
        expect(result.serial, 'ABC123DEF456');
        expect(result.isMultiLine, isTrue);
      });

      test('should extract IMEI from Samsung QR format', () {
        const qrData = 'IMEI:490154203237518|SN:R9ABC123DEF|PN:SM-G998B';
        final result = IMEIExtractor.extract(qrData);
        
        expect(result.hasIMEI, isTrue);
        expect(result.imei, '490154203237518');
      });

      test('should handle QR with semicolon delimiter', () {
        const qrData = '490154203237518;ABC123DEF456;iPhone15Pro';
        final result = IMEIExtractor.extract(qrData);
        
        expect(result.hasIMEI, isTrue);
        expect(result.imei, '490154203237518');
      });

      test('should return empty result for non-IMEI data', () {
        const qrData = 'Hello World';
        final result = IMEIExtractor.extract(qrData);
        
        expect(result.hasIMEI, isFalse);
        expect(result.candidates, isEmpty);
      });

      test('should extract IMEI from messy manufacturer QR', () {
        const qrData = '''
Product: iPhone 15 Pro Max
IMEI: 490154203237518
Serial: ABC123DEF456
Color: Natural Titanium
Capacity: 256GB
''';
        final result = IMEIExtractor.extract(qrData);
        
        expect(result.hasIMEI, isTrue);
        expect(result.imei, '490154203237518');
        expect(result.serial, 'ABC123DEF456');
        expect(result.isMultiLine, isTrue);
      });
    });

    group('getLast5Digits', () {
      test('should get last 5 digits from IMEI', () {
        expect(IMEIExtractor.getLast5Digits('490154203237518'), '37518');
      });

      test('should handle short strings', () {
        expect(IMEIExtractor.getLast5Digits('1234'), '1234');
      });

      test('should remove non-digit characters', () {
        expect(IMEIExtractor.getLast5Digits('IMEI:490154203237518'), '37518');
      });
    });

    group('formatIMEI', () {
      test('should format 15-digit IMEI correctly', () {
        final formatted = IMEIExtractor.formatIMEI('490154203237518');
        expect(formatted, '49015420 323751 8');
      });

      test('should return original for non-15 digit strings', () {
        expect(IMEIExtractor.formatIMEI('12345'), '12345');
      });
    });

    group('looksLikeIMEI', () {
      test('should return true for 15-digit number', () {
        expect(IMEIExtractor.looksLikeIMEI('490154203237518'), isTrue);
      });

      test('should return true for IMEI with prefix', () {
        expect(IMEIExtractor.looksLikeIMEI('IMEI:490154203237518'), isTrue);
      });

      test('should return false for short number', () {
        expect(IMEIExtractor.looksLikeIMEI('12345'), isFalse);
      });

      test('should return false for text', () {
        expect(IMEIExtractor.looksLikeIMEI('Hello World'), isFalse);
      });
    });
  });
}
