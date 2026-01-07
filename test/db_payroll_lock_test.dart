import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:quanlyshop/data/db_helper.dart';

void main() {
  // Initialize sqflite for ffi (tests)
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('payroll locking set and unset', () async {
    final db = DBHelper();
    const month = '2099-12'; // use a far future month to avoid collisions

    // Ensure lock is unset to start
    await db.setPayrollMonthLock(month, locked: false, lockedBy: 'test_init', note: 'init');
    expect(await db.isPayrollMonthLocked(month), false);

    await db.setPayrollMonthLock(month, locked: true, lockedBy: 'tester', note: 'unit test');
    expect(await db.isPayrollMonthLocked(month), true);

    await db.setPayrollMonthLock(month, locked: false, lockedBy: 'tester', note: 'unit test unset');
    expect(await db.isPayrollMonthLocked(month), false);
  });
}
