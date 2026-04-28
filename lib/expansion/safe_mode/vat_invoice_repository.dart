import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'expansion_module_services.dart';
import 'vat_invoice_persistence_models.dart';

class VatInvoiceRepository {
  static const String _dbName = 'vat_module_safe_mode.db';
  static const int _dbVersion = 1;

  static const String invoicesTable = 'invoices';
  static const String invoiceItemsTable = 'invoice_items';

  static bool _factoryInitialized = false;
  Database? _database;

  static void _ensureDatabaseFactoryInitialized() {
    if (_factoryInitialized) return;
    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
    }
    _factoryInitialized = true;
  }

  Future<Database> _openDb() async {
    if (_database != null) return _database!;

    _ensureDatabaseFactoryInitialized();
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    _database = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS $invoicesTable(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            invoiceNo TEXT NOT NULL UNIQUE,
            companyName TEXT NOT NULL,
            taxCode TEXT NOT NULL,
            address TEXT NOT NULL,
            email TEXT NOT NULL,
            subTotal REAL NOT NULL,
            totalTax REAL NOT NULL,
            grandTotal REAL NOT NULL,
            issuedAt INTEGER NOT NULL,
            locked INTEGER NOT NULL DEFAULT 1
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS $invoiceItemsTable(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            invoiceNo TEXT NOT NULL,
            productName TEXT NOT NULL,
            quantity INTEGER NOT NULL,
            unitPrice REAL NOT NULL,
            taxPercent INTEGER NOT NULL,
            subTotal REAL NOT NULL,
            taxAmount REAL NOT NULL,
            FOREIGN KEY (invoiceNo) REFERENCES $invoicesTable(invoiceNo)
          )
        ''');

        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_invoice_items_invoice_no ON $invoiceItemsTable(invoiceNo)',
        );
      },
    );

    return _database!;
  }

  Future<void> saveInvoice(VatIssuedInvoice invoice) async {
    final db = await _openDb();
    final invoiceRow = VatInvoiceRow.fromIssued(invoice);
    final itemRows = invoice.items
        .map((item) => VatInvoiceItemRow.fromDraft(invoice.invoiceNo, item))
        .toList();

    await db.transaction((txn) async {
      await txn.insert(
        invoicesTable,
        invoiceRow.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      for (final item in itemRows) {
        await txn.insert(invoiceItemsTable, item.toMap());
      }
    });
  }

  Future<List<VatIssuedInvoice>> getInvoices({int limit = 100}) async {
    final db = await _openDb();

    final invoiceRows = await db.query(
      invoicesTable,
      orderBy: 'issuedAt DESC',
      limit: limit,
    );

    if (invoiceRows.isEmpty) return const [];

    final invoices = <VatIssuedInvoice>[];

    for (final row in invoiceRows) {
      final invoice = VatInvoiceRow.fromMap(row);
      final itemRows = await db.query(
        invoiceItemsTable,
        where: 'invoiceNo = ?',
        whereArgs: [invoice.invoiceNo],
        orderBy: 'id ASC',
      );

      final items = itemRows
          .map((itemMap) => VatInvoiceItemRow.fromMap(itemMap).toDraft())
          .toList(growable: false);

      invoices.add(
        VatIssuedInvoice(
          invoiceNo: invoice.invoiceNo,
          buyer: invoice.toBuyerInfo(),
          items: List<VatItemDraft>.unmodifiable(items),
          subTotal: invoice.subTotal,
          totalTax: invoice.totalTax,
          grandTotal: invoice.grandTotal,
          issuedAt: invoice.issuedAt,
          locked: invoice.locked,
        ),
      );
    }

    return invoices;
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
