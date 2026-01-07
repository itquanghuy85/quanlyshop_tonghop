import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:quanlyshop/data/db_helper.dart';
import 'package:quanlyshop/models/quick_input_code_model.dart';

void main() {
  // Initialize sqflite for ffi (tests)
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Quick Input Code Sync Tests', () {
    test('Check unsynced quick input codes', () async {
      final db = DBHelper();
      final unsyncedCodes = await db.getUnsyncedQuickInputCodes();

      print('Found ${unsyncedCodes.length} unsynced quick input codes:');
      for (final code in unsyncedCodes) {
        print('- ${code.name} (ID: ${code.id}, firestoreId: ${code.firestoreId})');
      }

      if (unsyncedCodes.isEmpty) {
        print('✅ All quick input codes are synchronized!');
      } else {
        print('⚠️  ${unsyncedCodes.length} quick input codes need synchronization');
      }
    });

    test('Check total quick input codes', () async {
      final db = DBHelper();
      final allCodes = await db.getQuickInputCodes();

      print('Total quick input codes: ${allCodes.length}');
      for (final code in allCodes) {
        final syncStatus = code.isSynced ? '✅ Synced' : '❌ Not synced';
        print('- ${code.name}: $syncStatus');
      }
    });
  });
}
