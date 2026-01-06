import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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
    String path = p.join(await getDatabasesPath(), 'inventory_v7.db');
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
        try { await db.execute('ALTER TABLE products ADD COLUMN ajuste_vinculo TEXT DEFAULT ""'); } catch(e){}
      }
    });
  }

  static Future<void> _createAuditTable(Database db) async {
    await db.execute('''CREATE TABLE audit (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          clave TEXT, zona TEXT, cantidad REAL, fecha TEXT
        )''');
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
      });
    }
    await batch.commit(noResult: true);
  }

  static Future<void> registrarConteo(String clave, String zona, double cantidad) async {
    final database = await db;
    await database.insert('audit', {
      'clave': clave, 'zona': zona, 'cantidad': cantidad, 
      'fecha': DateTime.now().toString().substring(0, 19),
    });
    await database.rawUpdate('UPDATE products SET fisica = fisica + ? WHERE clave = ?', [cantidad, clave]);
  }

  static Future<List<Map<String, dynamic>>> search(String query) async {
    final database = await db;
    if (query.isEmpty) return await database.query('products');
    return await database.query('products',
        where: 'descripcion LIKE ? OR clave LIKE ? OR codbar LIKE ?',
        whereArgs: ['%$query%', '%$query%', '%$query%']);
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
  Set<String> selectedClaves = {};
  bool isSelectionMode = false;
  int ajusteCounter = 0;
  double totalItems = 0; double itemsContados = 0;

  @override
  void initState() { super.initState(); _refresh(); }

  void _refresh() async {
    final data = await DbHelper.search(_searchController.text);
    final database = await DbHelper.db;
    final total = Sqflite.firstIntValue(await database.rawQuery('SELECT COUNT(*) FROM products')) ?? 0;
    final contados = Sqflite.firstIntValue(await database.rawQuery('SELECT COUNT(*) FROM products WHERE fisica > 0')) ?? 0;
    setState(() {
      displayedProducts = data;
      totalItems = total.toDouble();
      itemsContados = contados.toDouble();
    });
  }

  // --- LÓGICA DE VINCULACIÓN ALGEBRAICA ---
  void _vincular(double cantAjuste) async {
    if (cantAjuste <= 0) return;
    String letra = String.fromCharCode((ajusteCounter % 26) + 65);
    final database = await DbHelper.db;

    for (String clave in selectedClaves) {
      final p = displayedProducts.firstWhere((e) => e['clave'] == clave);
      double diff = p['fisica'] - p['existencia'];
      String nom = "";

      if (diff > 0) { // Sobrante
        double res = diff - cantAjuste;
        nom = (res > 0) ? "+${res.toInt()}S +${cantAjuste.toInt()}$letra" : "+${cantAjuste.toInt()}$letra";
      } else { // Faltante
        double res = diff.abs() - cantAjuste;
        nom = (res > 0) ? "-${res.toInt()}F -${cantAjuste.toInt()}$letra" : "-${cantAjuste.toInt()}$letra";
      }
      await database.update('products', {'ajuste_vinculo': nom}, where: 'clave = ?', whereArgs: [clave]);
    }
    setState(() { ajusteCounter++; selectedClaves.clear(); isSelectionMode = false; });
    _refresh();
  }

  void _revertirAjuste() async {
    final database = await DbHelper.db;
    for (String clave in selectedClaves) {
      await database.update('products', {'ajuste_vinculo': ''}, where: 'clave = ?', whereArgs: [clave]);
    }
    setState(() { selectedClaves.clear(); isSelectionMode = false; });
    _refresh();
  }

  // --- EXPORTAR PDF (4 TABLAS) ---
  Future<void> _exportPDF() async {
    final data = await (await DbHelper.db).query('products');
    final pdf = pw.Document();

    final sobrantes = data.where((p) => p['ajuste_vinculo'].toString().contains('S')).toList();
    final faltantes = data.where((p) => p['ajuste_vinculo'].toString().contains('F')).toList();
    final ajustes = data.where((p) => p['ajuste_vinculo'].toString().contains(RegExp(r'[A-Z]'))).toList();

    pdf.addPage(pw.MultiPage(
      build: (ctx) => [
        pw.Header(level: 0, child: pw.Text("REPORTE DE AUDITORIA E INVENTARIO")),
        
        pw.Bullet(text: "1. Tabla General"),
        _buildPdfTable(['Clave', 'Sist.', 'Fis.', 'Sob.', 'Fal.', 'Ajuste'], data.map((p) {
          double d = p['fisica'] - p['existencia'];
          return [p['clave'].toString(), p['existencia'].toString(), p['fisica'].toString(), d > 0 ? d.toInt().toString() : '', d < 0 ? d.abs().toInt().toString() : '', p['ajuste_vinculo'].toString()];
        }).toList()),

        pw.SizedBox(height: 20),
        pw.Bullet(text: "2. Solo Sobrantes Netos"),
        _buildPdfTable(['Clave', 'Descripcion', 'Sobrante S'], sobrantes.map((p) => [p['clave'].toString(), p['descripcion'].toString(), p['ajuste_vinculo'].toString()]).toList()),

        pw.SizedBox(height: 20),
        pw.Bullet(text: "3. Solo Faltantes Netos"),
        _buildPdfTable(['Clave', 'Descripcion', 'Faltante F'], faltantes.map((p) => [p['clave'].toString(), p['descripcion'].toString(), p['ajuste_vinculo'].toString()]).toList()),

        pw.SizedBox(height: 20),
        pw.Bullet(text: "4. Cruces Realizados"),
        _buildPdfTable(['Clave', 'Descripcion', 'Vinculo'], ajustes.map((p) => [p['clave'].toString(), p['descripcion'].toString(), p['ajuste_vinculo'].toString()]).toList()),
      ],
    ));

    final dir = await getTemporaryDirectory();
    final file = File("${dir.path}/reporte_ajustes.pdf");
    await file.writeAsBytes(await pdf.save());
    await Share.shareXFiles([XFile(file.path)]);
  }

  pw.Widget _buildPdfTable(List<String> headers, List<List<String>> rows) {
    return pw.Table.fromTextArray(
      headers: headers,
      data: rows,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
      cellStyle: const pw.TextStyle(fontSize: 8),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
    );
  }

  // --- DIÁLOGOS Y NAVEGACIÓN ---
  void _onScan() async {
    final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScannerScreen()));
    if (code != null) {
      final res = await (await DbHelper.db).query('products', where: 'codbar = ? OR clave = ?', whereArgs: [code, code]);
      if (res.isNotEmpty) _showConteoDialog(res.first);
    }
  }

  void _showConteoDialog(Map<String, dynamic> product) {
    final controller = TextEditingController();
    String zona = 'Piso de Venta';
    final zonas = ['Piso de Venta', 'Bodega', 'Exhibición', 'Cajas'];

    showDialog(context: context, builder: (ctx) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(product['descripcion']),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            value: zona,
            items: zonas.map((z) => DropdownMenuItem(value: z, child: Text(z))).toList(),
            onChanged: (val) => setDialogState(() => zona = val!),
          ),
          TextField(controller: controller, keyboardType: TextInputType.number, autofocus: true, decoration: const InputDecoration(labelText: "Cantidad")),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(onPressed: () async {
            await DbHelper.registrarConteo(product['clave'], zona, double.tryParse(controller.text) ?? 0);
            Navigator.pop(ctx); _refresh();
          }, child: const Text("Sumar")),
        ],
      ),
    ));
  }

  void _vincularDialog() {
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("Ajuste Uno por Uno"),
      content: TextField(controller: ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: "Cantidad a saldar")),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
        ElevatedButton(onPressed: () { _vincular(double.tryParse(ctrl.text) ?? 0); Navigator.pop(ctx); }, child: const Text("Aplicar")),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 80,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isSelectionMode ? "${selectedClaves.length} Seleccionados" : 'Inventario', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('Total: ${totalItems.toInt()} | Contados: ${itemsContados.toInt()}', style: const TextStyle(fontSize: 14)),
        ]),
        actions: [
          if (isSelectionMode) ...[
            IconButton(icon: const Icon(Icons.balance, color: Colors.blue), onPressed: _vincularDialog),
            IconButton(icon: const Icon(Icons.refresh, color: Colors.orange), onPressed: _revertirAjuste),
          ],
          IconButton(icon: const Icon(Icons.history), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuditHistoryScreen())).then((_) => _refresh())),
          IconButton(icon: const Icon(Icons.picture_as_pdf), onPressed: _exportPDF),
          IconButton(icon: const Icon(Icons.upload_file), onPressed: _importCSV),
        ],
      ),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(8.0), child: TextField(controller: _searchController, onChanged: (_) => _refresh(), decoration: const InputDecoration(hintText: 'Buscar...', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()))),
        Expanded(child: ListView.builder(
          itemCount: displayedProducts.length,
          itemBuilder: (context, i) {
            final p = displayedProducts[i];
            bool isSel = selectedClaves.contains(p['clave']);
            return ListTile(
              tileColor: isSel ? Colors.blue[50] : null,
              onLongPress: () => setState(() { isSelectionMode = true; selectedClaves.add(p['clave']); }),
              onTap: () {
                if (isSelectionMode) {
                  setState(() { isSel ? selectedClaves.remove(p['clave']) : selectedClaves.add(p['clave']); if (selectedClaves.isEmpty) isSelectionMode = false; });
                } else { _showConteoDialog(p); }
              },
              title: Text(p['descripcion'], style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("Clave: ${p['clave']} | ${p['ajuste_vinculo']}"),
              trailing: Text("${p['fisica']}".replaceAll(RegExp(r'\.0$'), ''), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
            );
          },
        )),
      ]),
      floatingActionButton: FloatingActionButton(onPressed: _onScan, child: const Icon(Icons.qr_code_scanner)),
    );
  }

  void _importCSV() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv']);
    if (result != null) {
      final content = await File(result.files.single.path!).readAsString();
      final rows = const CsvToListConverter().convert(content);
      await DbHelper.insertBatch(rows); _refresh();
    }
  }
}

/* =======================
   VISTAS DE APOYO
======================= */
class AuditHistoryScreen extends StatefulWidget {
  const AuditHistoryScreen({super.key});
  @override
  State<AuditHistoryScreen> createState() => _AuditHistoryScreenState();
}

class _AuditHistoryScreenState extends State<AuditHistoryScreen> {
  List<Map<String, dynamic>> logs = [];
  @override
  void initState() { super.initState(); _load(); }
  void _load() async {
    final db = await DbHelper.db;
    final res = await db.rawQuery('SELECT audit.*, products.descripcion FROM audit JOIN products ON audit.clave = products.clave ORDER BY audit.fecha DESC');
    setState(() => logs = res);
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Historial de Auditoría")),
      body: ListView.builder(
        itemCount: logs.length,
        itemBuilder: (ctx, i) => ListTile(
          title: Text(logs[i]['descripcion']),
          subtitle: Text("${logs[i]['zona']} | ${logs[i]['fecha']}"),
          trailing: Text("+${logs[i]['cantidad']}", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}

class ScannerScreen extends StatelessWidget {
  const ScannerScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MobileScanner(onDetect: (cap) {
        final code = cap.barcodes.first.rawValue;
        if (code != null) Navigator.pop(context, code);
      }),
    );
  }
}
