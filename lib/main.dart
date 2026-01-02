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

  static Future<void> insertProduct(Map<String, dynamic> product) async {
    final database = await db;
    await database.insert('products', product, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> insertBatch(List<List<dynamic>> rows) async {
    final database = await db;
    Batch batch = database.batch();
    batch.delete('products');
    
    for (var i = 1; i < rows.length; i++) {
      if (rows[i].length < 6) continue;
      batch.insert('products', {
        'clave': rows[i][0].toString(),
        'codbar': rows[i][1].toString(),
        'descripcion': rows[i][2].toString(),
        'unidad': rows[i][3].toString(),
        'marca': rows[i][4].toString(),
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

  static Future<List<Map<String, dynamic>>> search(String query) async {
    final database = await db;
    if (query.isEmpty) return await database.query('products', limit: 100);
    
    return await database.query(
      'products',
      where: 'descripcion LIKE ? OR clave LIKE ? OR codbar LIKE ? OR marca LIKE ?',
      whereArgs: ['%$query%', '%$query%', '%$query%', '%$query%'],
      limit: 100
    );
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
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _refreshList();
  }

  void _refreshList() async {
    final data = await DbHelper.search(_searchController.text);
    if (mounted) setState(() => displayedProducts = data);
  }

  void _onScan() async {
    final code = await Navigator.push<String>(
      context, 
      MaterialPageRoute(builder: (_) => const ScannerScreen())
    );

    if (code != null && mounted) {
      await Future.delayed(const Duration(milliseconds: 400));
      
      final database = await DbHelper.db;
      final res = await database.query('products', 
        where: 'codbar = ? OR clave = ?', 
        whereArgs: [code, code]
      );

      if (res.isNotEmpty) {
        _showConteoDialog(res.first);
      } else {
        _showNotFoundDialog(code);
      }
    }
  }

  void _showNotFoundDialog(String code) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("No encontrado"),
        content: Text("El código '$code' no existe en la base de datos. ¿Deseas registrarlo?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _goToAddProduct(code);
            }, 
            child: const Text("Registrar")
          )
        ],
      )
    );
  }

  void _goToAddProduct([String? initialCode]) async {
    await Navigator.push(
      context, 
      MaterialPageRoute(builder: (_) => AddProductScreen(initialCode: initialCode))
    );
    _refreshList();
  }

  // CORRECCIÓN AQUÍ: Se eliminó 'subtitle' y se usó 'content' con Column
  void _showConteoDialog(Map<String, dynamic> product) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(product['descripcion']),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Marca: ${product['marca']} | Clave: ${product['clave']}",
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Cantidad física encontrada',
                border: OutlineInputBorder()
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
          ElevatedButton(
            onPressed: () async {
              int cant = int.tryParse(controller.text) ?? 0;
              await DbHelper.updateFisica(product['clave'], cant);
              if (mounted) Navigator.pop(context);
              _refreshList();
            }, 
            child: const Text('Sumar')
          ),
        ],
      )
    );
  }

  Future<void> _importCSV() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv']);
    if (result == null) return;
    setState(() => isLoading = true);
    try {
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      final rows = const CsvToListConverter().convert(content);
      await DbHelper.insertBatch(rows);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
    setState(() => isLoading = false);
    _refreshList();
  }

  Future<void> _exportCSV() async {
    final data = await DbHelper.getAllForExport();
    List<List<dynamic>> csvData = [['Clave', 'Código', 'Descripción','Unidad', 'Marca', 'Existencia', 'Física', 'Diferencia']];
    for (var p in data) {
      csvData.add([p['clave'], p['codbar'], p['descripcion'],p['unidad'], p['marca'], p['existencia'], p['fisica'], p['fisica'] - p['existencia']]);
    }
    String csvString = const ListToCsvConverter().convert(csvData);
    final directory = await getTemporaryDirectory();
    final path = "${directory.path}/inventario_export.csv";
    final file = File(path);
    await file.writeAsString(csvString);
    await Share.shareXFiles([XFile(path)], text: 'Reporte de Inventario');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventario'),
        actions: [
          IconButton(icon: const Icon(Icons.add_box), onPressed: () => _goToAddProduct()),
          IconButton(icon: const Icon(Icons.upload_file), onPressed: _importCSV),
          IconButton(icon: const Icon(Icons.download), onPressed: _exportCSV),
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
                hintText: 'Buscar (Clave, Barra, Marca o Descr)...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: Colors.grey[100]
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: displayedProducts.length,
              itemBuilder: (context, i) {
                final p = displayedProducts[i];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    title: Text(p['descripcion'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("Clave: ${p['clave']} | Unidad: ${p['unidad']} | Marca: ${p['marca']} | Stock: ${p['existencia']}"),
                    trailing: Text("${p['fisica']}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue)),
                    onTap: () => _showConteoDialog(p),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _onScan,
        label: const Text("Escanear"),
        icon: const Icon(Icons.qr_code_scanner),
      ),
    );
  }
}

/* =======================
   CRUD: AGREGAR PRODUCTO
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
  final _barCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _marcaCtrl = TextEditingController();
  final _stockCtrl = TextEditingController(text: "0");

  @override
  void initState() {
    super.initState();
    if (widget.initialCode != null) {
      _barCtrl.text = widget.initialCode!;
      _claveCtrl.text = widget.initialCode!;
    }
  }

  void _save() async {
    if (_formKey.currentState!.validate()) {
      await DbHelper.insertProduct({
        'clave': _claveCtrl.text,
        'codbar': _barCtrl.text,
        'descripcion': _descCtrl.text,
        'marca': _marcaCtrl.text,
        'unidad': 'PZ',
        'existencia': int.tryParse(_stockCtrl.text) ?? 0,
        'fisica': 0
      });
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Nuevo Producto"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(controller: _claveCtrl, decoration: const InputDecoration(labelText: "Clave *"), validator: (v) => v!.isEmpty ? "Requerido" : null),
              const SizedBox(height: 10),
              TextFormField(controller: _barCtrl, decoration: const InputDecoration(labelText: "Código de Barras")),
              const SizedBox(height: 10),
              TextFormField(controller: _descCtrl, decoration: const InputDecoration(labelText: "Descripción *"), validator: (v) => v!.isEmpty ? "Requerido" : null),
              const SizedBox(height: 10),
              TextFormField(controller: _marcaCtrl, decoration: const InputDecoration(labelText: "Marca")),
              const SizedBox(height: 10),
              TextFormField(controller: _stockCtrl, decoration: const InputDecoration(labelText: "Stock en Sistema"), keyboardType: TextInputType.number),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                child: const Text("GUARDAR E IR ATRÁS"),
              )
            ],
          ),
        ),
      ),
    );
  }
}

/* =======================
   SCANNER SCREEN
======================= */
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final controller = MobileScannerController();
  bool isDetected = false;

  @override
  void dispose() { 
    controller.dispose(); 
    super.dispose(); 
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Escaneando Código")),
      body: MobileScanner(
        controller: controller,
        onDetect: (cap) {
          if (isDetected) return;
          final code = cap.barcodes.first.rawValue;
          if (code != null) {
            isDetected = true;
            Navigator.pop(context, code);
          }
        },
      ),
    );
  }
}
