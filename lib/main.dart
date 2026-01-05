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
    return await openDatabase(path, version: 3, 
        onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE products (
          clave TEXT PRIMARY KEY,
          codbar TEXT,
          descripcion TEXT,
          marca TEXT,
          unit TEXT,
          existencia REAL, 
          fisica REAL DEFAULT 0,
          ajuste_vinculo TEXT DEFAULT ''
        )''');
      await _createAuditTable(db);
    }, onUpgrade: (db, oldV, newV) async {
      if (oldV < 3) {
        await db.execute('ALTER TABLE products ADD COLUMN ajuste_vinculo TEXT DEFAULT ""');
      }
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
        'fisica': 0.0,
        'ajuste_vinculo': ''
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
      'fecha': DateTime.now().toString().substring(0, 19),
    });
    await database.rawUpdate(
        'UPDATE products SET fisica = fisica + ? WHERE clave = ?',
        [cantidad, clave]);
  }

  static Future<void> vincularAjuste(String clave, String nomenclatura) async {
    final database = await db;
    await database.rawUpdate(
      'UPDATE products SET ajuste_vinculo = ajuste_vinculo || ? WHERE clave = ?',
      [" $nomenclatura", clave]
    );
  }

  static Future<List<Map<String, dynamic>>> getFullAudit() async {
    final database = await db;
    return await database.rawQuery('''
      SELECT audit.id, audit.fecha, audit.zona, products.descripcion, products.clave, audit.cantidad
      FROM audit
      JOIN products ON audit.clave = products.clave
      ORDER BY audit.fecha DESC
    ''');
  }

  static Future<void> eliminarRegistroAuditoria(int id, String clave, double cantidad) async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE products SET fisica = fisica - ? WHERE clave = ?',
        [cantidad, clave]
      );
      await txn.delete('audit', where: 'id = ?', whereArgs: [id]);
    });
  }

  static Future<List<Map<String, dynamic>>> search(String query) async {
    final database = await db;
    // Solo mostramos productos con diferencias o pendientes (fisica 0)
    String baseWhere = '(fisica != existencia OR fisica = 0)';
    if (query.isEmpty) return await database.query('products', where: baseWhere, limit: 100);
    return await database.query('products',
        where: '($baseWhere) AND (descripcion LIKE ? OR clave LIKE ? OR codbar LIKE ? OR marca LIKE ?)',
        whereArgs: ['%$query%', '%$query%', '%$query%', '%$query%'],
        limit: 100);
  }

  static Future<List<Map<String, dynamic>>> getAllForExport() async {
    final database = await db;
    return await database.query('products');
  }
}

/* =======================
   PANTALLA PRINCIPAL
======================= */
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
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
  Set<String> selectedClaves = {};
  bool isSelectionMode = false;
  bool isLoading = false;
  double totalItems = 0;
  double itemsContados = 0;
  int ajusteGlobalCount = 0;

  @override
  void initState() {
    super.initState();
    _refreshList();
    _updateCounters();
  }

  String _generateAjusteLetter(int index) {
    String letter = "";
    while (index >= 0) {
      letter = String.fromCharCode((index % 26) + 65) + letter;
      index = (index ~/ 26) - 1;
    }
    return letter;
  }

  void _updateCounters() async {
    final database = await DbHelper.db;
    final total = Sqflite.firstIntValue(await database.rawQuery('SELECT COUNT(*) FROM products')) ?? 0;
    final contados = Sqflite.firstIntValue(await database.rawQuery('SELECT COUNT(*) FROM products WHERE fisica > 0')) ?? 0;
    if (mounted) setState(() {
      totalItems = total.toDouble();
      itemsContados = contados.toDouble();
    });
  }

  void _refreshList() async {
    final data = await DbHelper.search(_searchController.text);
    if (mounted) setState(() => displayedProducts = data);
  }

  void _onScan() async {
    final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScannerScreen()));
    if (code != null && mounted) {
      await Future.delayed(const Duration(milliseconds: 400));
      final database = await DbHelper.db;
      final res = await database.query('products', where: 'codbar = ? OR clave = ?', whereArgs: [code, code]);
      if (res.isNotEmpty) {
        _showConteoDialog(res.first);
      } else {
        _showNotFoundDialog(code);
      }
    }
  }

  void _processVincularAjuste() async {
    if (selectedClaves.length < 2) return;

    List<Map<String, dynamic>> seleccionados = displayedProducts
        .where((p) => selectedClaves.contains(p['clave']))
        .toList();

    double totalPos = 0;
    double totalNeg = 0;

    for (var p in seleccionados) {
      double d = p['fisica'] - p['existencia'];
      if (d > 0) totalPos += d; else totalNeg += d.abs();
    }

    double maxSaldable = totalPos < totalNeg ? totalPos : totalNeg;

    if (maxSaldable <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Seleccione sobrantes y faltantes")));
      return;
    }

    String letra = _generateAjusteLetter(ajusteGlobalCount);
    for (var p in seleccionados) {
      double d = p['fisica'] - p['existencia'];
      String mark = (d > 0) ? "+${maxSaldable.toInt()}$letra" : "-${maxSaldable.toInt()}$letra";
      await DbHelper.vincularAjuste(p['clave'], mark);
    }

    setState(() {
      ajusteGlobalCount++;
      selectedClaves.clear();
      isSelectionMode = false;
    });
    _refreshList();
  }

  void _showConteoDialog(Map<String, dynamic> product) {
    final controller = TextEditingController();
    String zona = 'Piso de Venta';
    final zonas = ['Piso de Venta', 'Marbete', 'Bodega', 'Vitrina', 'Exhibición', 'Entregas', 'Cajas', 'Remate'];

    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
                title: Text(product['descripcion']),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: zona,
                      items: zonas.map((z) => DropdownMenuItem(value: z, child: Text(z))).toList(),
                      onChanged: (val) => setDialogState(() => zona = val!),
                    ),
                    TextField(
                      controller: controller,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      autofocus: true,
                      decoration: const InputDecoration(labelText: 'Cantidad'),
                    ),
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
                  ElevatedButton(
                      onPressed: () async {
                        double cant = double.tryParse(controller.text) ?? 0.0;
                        await DbHelper.registrarConteo(product['clave'], zona, cant);
                        if (mounted) Navigator.pop(context);
                        _refreshList();
                        _updateCounters();
                      },
                      child: const Text('Sumar')),
                ],
              ),
        ));
  }

  Future<void> _exportCSV() async {
    final data = await DbHelper.getAllForExport();
    List<List<dynamic>> csvData = [
      ['Clave', 'Ajuste', 'Código', 'Descripción', 'Unidad', 'Marca', 'Existencia', 'Física', 'Sobrantes', 'Faltantes']
    ];
    for (var p in data) {
      double diff = p['fisica'] - p['existencia'];
      csvData.add([
        p['clave'],
        p['ajuste_vinculo'],
        p['codbar'],
        p['descripcion'],
        p['unit'],
        p['marca'],
        p['existencia'],
        diff == 0 ? '-' : p['fisica'],
        diff > 0 ? "+${diff.toStringAsFixed(2)}S" : "",
        diff < 0 ? "-${diff.abs().toStringAsFixed(2)}F" : ""
      ]);
    }
    String csvString = const ListToCsvConverter().convert(csvData);
    final directory = await getTemporaryDirectory();
    final file = File("${directory.path}/reporte_inventario.csv");
    await file.writeAsString(csvString);
    await Share.shareXFiles([XFile(file.path)], text: 'Reporte CSV');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isSelectionMode ? "${selectedClaves.length} seleccionados" : 'Inventario'),
        actions: [
          if (isSelectionMode)
            IconButton(icon: const Icon(Icons.balance, color: Colors.blue, size: 30), onPressed: _processVincularAjuste),
          IconButton(icon: const Icon(Icons.history_edu), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuditHistoryScreen()))),
          IconButton(icon: const Icon(Icons.upload_file), onPressed: _importCSV),
          IconButton(icon: const Icon(Icons.download), onPressed: _exportCSV),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => _refreshList(),
              decoration: InputDecoration(hintText: 'Buscar diferencias...', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: displayedProducts.length,
              itemBuilder: (context, i) {
                final p = displayedProducts[i];
                bool isSelected = selectedClaves.contains(p['clave']);
                double diff = p['fisica'] - p['existencia'];
                return Card(
                  color: isSelected ? Colors.yellow[200] : null,
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    onLongPress: () => setState(() { isSelectionMode = true; selectedClaves.add(p['clave']); }),
                    onTap: () {
                      if (isSelectionMode) {
                        setState(() { isSelected ? selectedClaves.remove(p['clave']) : selectedClaves.add(p['clave']); if (selectedClaves.isEmpty) isSelectionMode = false; });
                      } else {
                        _showConteoDialog(p);
                      }
                    },
                    title: Text(p['descripcion'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("Clave: ${p['clave']} | Ajustes:${p['ajuste_vinculo']}"),
                    trailing: Text(diff == 0 ? "-" : diff.toStringAsFixed(1), style: TextStyle(fontSize: 18, color: diff > 0 ? Colors.green : (diff < 0 ? Colors.red : Colors.grey))),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: _onScan, label: const Text("Escanear"), icon: const Icon(Icons.qr_code_scanner)),
    );
  }

  Future<void> _importCSV() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv']);
    if (result == null) return;
    setState(() => isLoading = true);
    try {
      final file = File(result.files.single.path!);
      final rows = const CsvToListConverter().convert(await file.readAsString());
      await DbHelper.insertBatch(rows);
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"))); }
    setState(() => isLoading = false);
    _refreshList();
    _updateCounters();
  }

  void _showNotFoundDialog(String code) {
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("No encontrado"), actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
      ElevatedButton(onPressed: () { Navigator.pop(ctx); _goToAddProduct(code); }, child: const Text("Registrar"))
    ]));
  }

  void _goToAddProduct([String? initialCode]) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AddProductScreen(initialCode: initialCode)));
    _refreshList();
    _updateCounters();
  }
}

/* =======================
   REPORTE DE AUDITORÍA
======================= */
class AuditHistoryScreen extends StatefulWidget {
  const AuditHistoryScreen({super.key});
  @override
  State<AuditHistoryScreen> createState() => _AuditHistoryScreenState();
}

class _AuditHistoryScreenState extends State<AuditHistoryScreen> {
  List<Map<String, dynamic>> _logs = [];
  @override
  void initState() { super.initState(); _load(); }
  void _load() async { final d = await DbHelper.getFullAudit(); setState(() => _logs = d); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Historial")),
      body: ListView.builder(
        itemCount: _logs.length,
        itemBuilder: (ctx, i) {
          final l = _logs[i];
          return ListTile(
            title: Text("${l['descripcion']} (${l['clave']})"),
            subtitle: Text("${l['zona']} - ${l['fecha']}"),
            trailing: Text("${l['cantidad']}", style: const TextStyle(fontWeight: FontWeight.bold)),
            onLongPress: () async {
               await DbHelper.eliminarRegistroAuditoria(l['id'], l['clave'], l['cantidad']);
               _load();
            },
          );
        },
      ),
    );
  }
}

/* =======================
   FORMULARIO Y SCANNER
======================= */
class AddProductScreen extends StatefulWidget {
  final String? initialCode;
  const AddProductScreen({super.key, this.initialCode});
  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _claveCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _stockCtrl = TextEditingController(text: "0");

  @override
  void initState() { super.initState(); if (widget.initialCode != null) _claveCtrl.text = widget.initialCode!; }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Nuevo")),
      body: Form(
        key: _formKey,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TextFormField(controller: _claveCtrl, decoration: const InputDecoration(labelText: "Clave")),
              TextFormField(controller: _descCtrl, decoration: const InputDecoration(labelText: "Descripción")),
              TextFormField(controller: _stockCtrl, decoration: const InputDecoration(labelText: "Stock"), keyboardType: TextInputType.number),
              ElevatedButton(onPressed: () async {
                await DbHelper.insertProduct({'clave': _claveCtrl.text, 'descripcion': _descCtrl.text, 'existencia': double.parse(_stockCtrl.text), 'fisica': 0, 'ajuste_vinculo': ''});
                Navigator.pop(context);
              }, child: const Text("Guardar"))
            ],
          ),
        ),
      ),
    );
  }
}

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
      body: MobileScanner(controller: controller, onDetect: (cap) {
        final code = cap.barcodes.first.rawValue;
        if (code != null) Navigator.pop(context, code);
      }),
    );
  }
}
