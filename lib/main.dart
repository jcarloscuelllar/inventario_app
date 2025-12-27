import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() => runApp(const MyApp());

/* =======================
   BASE DE DATOS (HELPER)
======================= */
class DbHelper {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    String path = p.join(await getDatabasesPath(), 'inventory.db');
    return await openDatabase(path, version: 1, onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE products (
          clave TEXT PRIMARY KEY,
          codbar TEXT,
          descripcion TEXT,
          marca TEXT,
          unidad TEXT,
          existencia INTEGER,
          fisica INTEGER DEFAULT 0
        )''');
    });
  }

  static Future<void> insertBatch(List<List<dynamic>> rows) async {
    final database = await db;
    Batch batch = database.batch();
    // Limpiar tabla previa si se desea una importación limpia
    batch.delete('products');
    
    for (var i = 1; i < rows.length; i++) {
      if (rows[i].length < 6) continue;
      batch.insert('products', {
        'clave': rows[i][0].toString(),
        'codbar': rows[i][1].toString(),
        'descripcion': rows[i][2].toString(),
        'marca': rows[i][3].toString(),
        'unidad': rows[i][4].toString(),
        'existencia': int.tryParse(rows[i][5].toString()) ?? 0,
        'fisica': 0
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  static Future<void> updateFisica(String clave, int nuevaCantidad) async {
    final database = await db;
    await database.rawUpdate(
      'UPDATE products SET fisica = fisica + ? WHERE clave = ?',
      [nuevaCantidad, clave]
    );
  }

  static Future<List<Map<String, dynamic>>> search(String query, bool byClave) async {
    final database = await db;
    if (query.isEmpty) return await database.query('products', limit: 100);
    
    if (byClave) {
      // Normalización simple: buscar coincidencias que contengan la clave
      return await database.query('products', 
        where: 'clave LIKE ?', whereArgs: ['%$query%'], limit: 100);
    } else {
      return await database.query('products', 
        where: 'descripcion LIKE ?', whereArgs: ['%$query%'], limit: 100);
    }
  }

  static Future<List<Map<String, dynamic>>> getAllForExport() async {
    final database = await db;
    return await database.query('products');
  }
}

/* =======================
   APP & UI
======================= */
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green),
      home: const InventoryScreen(),
    );
  }
}

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<Map<String, dynamic>> displayedProducts = [];
  final TextEditingController _searchController = TextEditingController();
  bool searchByClave = false;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _refreshList();
  }

  void _refreshList() async {
    final data = await DbHelper.search(_searchController.text, searchByClave);
    setState(() => displayedProducts = data);
  }

  /* ACCIONES */
  Future<void> _importCSV() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv']);
    if (result == null) return;

    setState(() => isLoading = true);
    final file = File(result.files.single.path!);
    final content = await file.readAsString();
    final rows = const CsvToListConverter().convert(content);
    
    await DbHelper.insertBatch(rows);
    setState(() => isLoading = false);
    _refreshList();
  }

  Future<void> _exportCSV() async {
    final data = await DbHelper.getAllForExport();
    List<List<dynamic>> csvData = [
      ['Clave', 'Código', 'Descripción', 'Existencia', 'Física', 'Sobrante', 'Faltante']
    ];

    for (var p in data) {
      int ext = p['existencia'];
      int fis = p['fisica'];
      int diff = fis - ext;
      csvData.add([
        p['clave'], p['codbar'], p['descripcion'], ext, fis,
        diff > 0 ? diff : 0, diff < 0 ? diff.abs() : 0
      ]);
    }

    String csvString = const ListToCsvConverter().convert(csvData);
    final directory = await getTemporaryDirectory();
    final path = "${directory.path}/inventario_final.csv";
    final file = File(path);
    await file.writeAsString(csvString);

    await Share.shareXFiles([XFile(path)], text: 'Reporte de Inventario');
  }

  void _onScan() async {
    final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScannerScreen()));
    if (code != null) {
      final database = await DbHelper.db;
      final res = await database.query('products', where: 'codbar = ?', whereArgs: [code]);
      if (res.isNotEmpty) {
        _showConteoDialog(res.first);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Código no registrado')));
      }
    }
  }

  void _showConteoDialog(Map<String, dynamic> product) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(product['descripcion']),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Cantidad física encontrada'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
          ElevatedButton(
            onPressed: () async {
              await DbHelper.updateFisica(product['clave'], int.tryParse(controller.text) ?? 0);
              Navigator.pop(context);
              _refreshList();
            }, 
            child: const Text('Sumar')
          ),
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventario SQLite (80k)'),
        actions: [
          IconButton(icon: const Icon(Icons.download), onPressed: _exportCSV),
          IconButton(icon: const Icon(Icons.upload_file), onPressed: _importCSV),
        ],
      ),
      body: Column(
        children: [
          if (isLoading) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => _refreshList(),
              decoration: InputDecoration(
                hintText: 'Buscar por ${searchByClave ? "clave" : "descripción"}...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: Icon(searchByClave ? Icons.vpn_key : Icons.abc),
                  onPressed: () => setState(() {
                    searchByClave = !searchByClave;
                    _refreshList();
                  }),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: displayedProducts.length,
              itemBuilder: (context, i) {
                final p = displayedProducts[i];
                return ListTile(
                  title: Text(p['descripcion']),
                  subtitle: Text("Clave: ${p['clave']} | Sistema: ${p['existencia']}"),
                  trailing: Text("${p['fisica']}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
                  onTap: () => _showConteoDialog(p),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _onScan,
        child: const Icon(Icons.qr_code_scanner),
      ),
    );
  }
}

/* =======================
   SCANNER SCREEN (Igual a la anterior con dispose)
======================= */
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final controller = MobileScannerController();
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MobileScanner(
        controller: controller,
        onDetect: (cap) {
          final code = cap.barcodes.first.rawValue;
          if (code != null) Navigator.pop(context, code);
        },
      ),
    );
  }
}
