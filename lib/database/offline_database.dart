import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class BillXLocalDatabase {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();

    final path = join(databasePath, 'billx.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE products (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            productId TEXT,
            barcode TEXT UNIQUE,
            name TEXT NOT NULL,
            price REAL NOT NULL,
            stock REAL DEFAULT 0,
            synced INTEGER DEFAULT 0,
            createdAt TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE bills (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            firebaseId TEXT,
            userId TEXT NOT NULL,
            invoiceNumber TEXT,
            total REAL NOT NULL,
            cash REAL DEFAULT 0,
            balance REAL DEFAULT 0,
            createdAt TEXT,
            synced INTEGER DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE bill_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            billLocalId INTEGER NOT NULL,
            productId TEXT,
            barcode TEXT,
            name TEXT NOT NULL,
            price REAL NOT NULL,
            quantity REAL NOT NULL,
            total REAL NOT NULL
          )
        ''');
      },
    );
  }

  // ------------------------------------------------------------
  // PRODUCTS
  // ------------------------------------------------------------

  static Future<int> saveProduct({
    String? productId,
    required String barcode,
    required String name,
    required double price,
    double stock = 0,
    bool synced = false,
  }) async {
    final db = await database;

    return await db.insert('products', {
      'productId': productId,
      'barcode': barcode,
      'name': name,
      'price': price,
      'stock': stock,
      'synced': synced ? 1 : 0,
      'createdAt': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<Map<String, dynamic>?> getProduct(String barcode) async {
    final db = await database;

    final result = await db.query(
      'products',
      where: 'barcode = ?',
      whereArgs: [barcode],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return result.first;
  }

  static Future<List<Map<String, dynamic>>> getProducts() async {
    final db = await database;

    return await db.query('products', orderBy: 'name ASC');
  }

  static Future<List<Map<String, dynamic>>> getUnsyncedProducts() async {
    final db = await database;

    return await db.query(
      'products',
      where: 'synced = ?',
      whereArgs: [0],
      orderBy: 'id ASC',
    );
  }

  static Future<void> markProductSynced(int id) async {
    final db = await database;

    await db.update(
      'products',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ------------------------------------------------------------
  // BILLS
  // ------------------------------------------------------------

  static Future<int> saveBill({
    required String userId,
    String? firebaseId,
    String? invoiceNumber,
    required double total,
    double cash = 0,
    double balance = 0,
    required List<Map<String, dynamic>> items,
    bool synced = false,
  }) async {
    final db = await database;

    final billLocalId = await db.insert('bills', {
      'firebaseId': firebaseId,
      'userId': userId,
      'invoiceNumber': invoiceNumber,
      'total': total,
      'cash': cash,
      'balance': balance,
      'createdAt': DateTime.now().toIso8601String(),
      'synced': synced ? 1 : 0,
    });

    for (final item in items) {
      await db.insert('bill_items', {
        'billLocalId': billLocalId,
        'productId': item['productId'],
        'barcode': item['barcode'],
        'name': item['name'] ?? '',
        'price': (item['price'] as num?)?.toDouble() ?? 0,
        'quantity': (item['quantity'] as num?)?.toDouble() ?? 0,
        'total': (item['total'] as num?)?.toDouble() ?? 0,
      });
    }

    return billLocalId;
  }

  static Future<List<Map<String, dynamic>>> getBills(String userId) async {
    final db = await database;

    return await db.query(
      'bills',
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'createdAt DESC',
    );
  }

  static Future<List<Map<String, dynamic>>> getBillItems(
    int billLocalId,
  ) async {
    final db = await database;

    return await db.query(
      'bill_items',
      where: 'billLocalId = ?',
      whereArgs: [billLocalId],
      orderBy: 'id ASC',
    );
  }

  static Future<List<Map<String, dynamic>>> getUnsyncedBills() async {
    final db = await database;

    return await db.query(
      'bills',
      where: 'synced = ?',
      whereArgs: [0],
      orderBy: 'id ASC',
    );
  }

  static Future<void> markBillSynced(int localId, {String? firebaseId}) async {
    final db = await database;

    final values = <String, dynamic>{'synced': 1};

    if (firebaseId != null && firebaseId.isNotEmpty) {
      values['firebaseId'] = firebaseId;
    }

    await db.update('bills', values, where: 'id = ?', whereArgs: [localId]);
  }

  // ------------------------------------------------------------
  // DELETE BILL
  // ------------------------------------------------------------

  static Future<void> deleteBill(int localId) async {
    final db = await database;

    await db.delete(
      'bill_items',
      where: 'billLocalId = ?',
      whereArgs: [localId],
    );

    await db.delete('bills', where: 'id = ?', whereArgs: [localId]);
  }

  // ------------------------------------------------------------
  // CLOSE DATABASE
  // ------------------------------------------------------------

  static Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
