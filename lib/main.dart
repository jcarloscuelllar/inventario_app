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
    String path = p.join(await getDatabasesPath(), 'inventory_final.db');
    return await openDatabase(path, version: 1, 
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
      await db.execute('CREATE TABLE audit (id INTEGER PRIMARY KEY AUTOINCREMENT, clave TEXT, zona TEXT, cantidad REAL, fecha TEXT)');
    });
  }

  static Future<void> registrarConteo(String clave, String zona, double cantidad) async {
    final database = await db;
    await database.insert('audit', {'clave': clave, 'zona': zona, 'cantidad': cantidad, 'fecha': DateTime.now().toString().substring(0, 19)});
    await database.rawUpdate('UPDATE products SET fisica = fisica + ? WHERE clave = ?', [cantidad, clave]);
  }

  static Future<List<Map<String, dynamic>>> search(String query) async {
    final database = await db;
    if (query.isEmpty) return await database.query('products', limit: 100);
    return await database.query('products', where: 'descripcion LIKE ? OR clave LIKE ?', whereArgs: ['%$query%', '%$query%'], limit: 100);
  }

  static Future<void> updateVinculo(String clave, String nomenclature) async {
    final database = await db;
    await database.update('products', {'ajuste_vinculo': nomenclature}, where: 'clave = ?', whereArgs: [clave]);
  }
}

/* =======================
   PANTALLA PRINCIPAL
======================= */
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<Map<String, dynamic>> displayedProducts = [];
  Set<String> selectedClaves = {};
  bool isSelectionMode = false;
  int ajusteCounter = 0;

  @override
  void initState() { super.initState(); _refresh(); }

  void _refresh() async {
    final data = await DbHelper.search("");
    setState(() => displayedProducts = data);
  }

  void _vincular(double cantAjuste) async {
    String letra = String.fromCharCode((ajusteCounter % 26) + 65);
    for (String clave in selectedClaves) {
      final p = displayedProducts.firstWhere((e) => e['clave'] == clave);
      double diff = p['fisica'] - p['existencia'];
      String nom = "";
      if (diff > 0) {
        double res = diff - cantAjuste;
        nom = (res > 0) ? "+${res.toInt()}S +${cantAjuste.toInt()}$letra" : "+${cantAjuste.toInt()}$letra";
      } else {
        double res = diff.abs() - cantAjuste;
        nom = (res > 0) ? "-${res.toInt()}F -${cantAjuste.toInt()}$letra" : "-${cantAjuste.toInt()}$letra";
      }
      await DbHelper.updateVinculo(clave, nom);
    }
    setState(() { ajusteCounter++; selectedClaves.clear(); isSelectionMode = false; });
    _refresh();
  }

  // --- GENERACIÓN DEL PDF CON 4 TABLAS ---
  Future<void> _exportPDF() async {
    final data = await (await DbHelper.db).query('products');
    final pdf = pw.Document();

    // Filtros para las tablas
    final sobrantes = data.where((p) => p['ajuste_vinculo'].toString().contains('S')).toList();
    final faltantes = data.where((p) => p['ajuste_vinculo'].toString().contains('F')).toList();
    final ajustes = data.where((p) => p['ajuste_vinculo'].toString().contains(RegExp(r'[A-Z]'))).toList();

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (ctx) => [
        pw.Text("REPORTE DE AUDITORÍA E INVENTARIO", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 10),

        // TABLA 1: GENERAL
        pw.Text("1. Tabla General", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        _buildPdfTable(['Clave', 'Sist.', 'Fis.', 'Sobr.', 'Falt.', 'Ajuste'], data.map((p) {
          double d = p['fisica'] - p['existencia'];
          return [p['clave'], p['existencia'], p['fisica'], d > 0 ? d.toInt() : '', d < 0 ? d.abs().toInt() : '', p['ajuste_vinculo']];
        }).toList()),

        // TABLA 2: SOBRANTES
        pw.SizedBox(height: 20),
        pw.Text("2. Solo Sobrantes Netos", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        _buildPdfTable(['Clave', 'Descripción', 'Sobrante S'], sobrantes.map((p) => [p['clave'], p['descripcion'], p['ajuste_vinculo']]).toList()),

        // TABLA 3: FALTANTES
        pw.SizedBox(height: 20),
        pw.Text("3. Solo Faltantes Netos", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        _buildPdfTable(['Clave', 'Descripción', 'Faltante F'], faltantes.map((p) => [p['clave'], p['descripcion'], p['ajuste_vinculo']]).toList()),

        // TABLA 4: AJUSTES VINCULADOS
        pw.SizedBox(height: 20),
        pw.Text("4. Cruces de Ajuste (Uno a Uno)", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        _buildPdfTable(['Clave', 'Descripción', 'Vínculo'], ajustes.map((p) => [p['clave'], p['descripcion'], p['ajuste_vinculo']]).toList()),
      ],
    ));

    final dir = await getTemporaryDirectory();
    final file = File("${dir.path}/reporte_4_tablas.pdf");
    await file.writeAsBytes(await pdf.save());
    await Share.shareXFiles([XFile(file.path)]);
  }

  pw.Widget _buildPdfTable(List<String> headers, List<List<dynamic>> data) {
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
      cellStyle: const pw.TextStyle(fontSize: 9),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Inventario"),
        actions: [
          if (isSelectionMode) IconButton(icon: const Icon(Icons.balance), onPressed: () => _vincularDialog()),
          IconButton(icon: const Icon(Icons.picture_as_pdf), onPressed: _exportPDF),
        ],
      ),
      body: ListView.builder(
        itemCount: displayedProducts.length,
        itemBuilder: (ctx, i) {
          final p = displayedProducts[i];
          return ListTile(
            onLongPress: () => setState(() { isSelectionMode = true; selectedClaves.add(p['clave']); }),
            title: Text(p['descripcion']),
            subtitle: Text("${p['ajuste_vinculo']}"),
            trailing: Text("${p['fisica']}"),
          );
        },
      ),
    );
  }

  void _vincularDialog() {
    final c = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("Cantidad Ajuste"),
      content: TextField(controller: c, keyboardType: TextInputType.number),
      actions: [ElevatedButton(onPressed: () => _vincular(double.parse(c.text)), child: const Text("OK"))],
    ));
  }

  void _onScan() {} // Implementar igual al anterior
  void _importCSV() {} // Implementar igual al anterior
  void _exportCSV() {} // Implementar igual al anterior
}

// (Las clases AuditHistoryScreen y ScannerScreen permanecen igual al código anterior)
