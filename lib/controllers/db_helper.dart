import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class DbHelper {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    String path = p.join(await getDatabasesPath(), 'inventory.db');
    return await openDatabase(path, version: 2,
        onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE products (
          clave TEXT PRIMARY KEY,
          codbar TEXT,
          descripcion TEXT,
          marca TEXT,
          unit TEXT,
          existencia REAL, 
          fisica REAL DEFAULT 0
        )''');
      await _createAuditTable(db);
    }, onUpgrade: (db, oldV, newV) async {
      if (oldV < 2) await _createAuditTable(db);
    });
  }

  static Future<void> _createAuditTable(Database db) async {
    await db.execute('''
        CREATE TABLE audit (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          clave TEXT,
          zona TEXT,
          cantidad REAL,
          fecha TEXT
        )''');
  }

  static Future<void> insertProduct(Map<String, dynamic> product) async {
    final database = await db;
    await database.insert('products', product, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> insertBatch(List<List<dynamic>> rows) async {
    final database = await db;
    Batch batch = database.batch();
    batch.delete('products');
    batch.delete('audit');

    for (var i = 1; i < rows.length; i++) {
      if (rows[i].length < 6) continue;
      batch.insert('products', {
        'clave': rows[i][0].toString(),
        'codbar': rows[i][1].toString(),
        'descripcion': rows[i][2].toString(),
        'unit': rows[i][3].toString(),
        'marca': rows[i][4].toString(),
        'existencia': double.tryParse(rows[i][5].toString()) ?? 0.0,
        'fisica': 0.0
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  static Future<void> registrarConteo(String clave, String zona, double cantidad) async {
    final database = await db;
    await database.insert('audit', {
      'clave': clave,
      'zona': zona,
      'cantidad': cantidad,
      'fecha': DateTime.now().toString(),
    });
    await database.rawUpdate(
        'UPDATE products SET fisica = fisica + ? WHERE clave = ?',
        [cantidad, clave]);
  }

  static Future<List<Map<String, dynamic>>> search(String query) async {
    final database = await db;
    if (query.isEmpty) return await database.query('products', limit: 100);
    return await database.query('products',
        where: 'descripcion LIKE ? OR clave LIKE ? OR codbar LIKE ? OR marca LIKE ?',
        whereArgs: ['%$query%', '%$query%', '%$query%', '%$query%'],
        limit: 100);
  }

  static Future<List<Map<String, dynamic>>> getAllForExport() async {
    final database = await db;
    return await database.query('products');
  }
}
