import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// Importaciones relativas según la estructura MVC
import '../controllers/db_helper.dart';
import 'audit_history_screen.dart';
import 'add_product_screen.dart';
import 'scanner_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<Map<String, dynamic>> displayedProducts = [];
  final TextEditingController _searchController = TextEditingController();
  bool isLoading = false;
  double totalItems = 0;
  double itemsContados = 0;

  @override
  void initState() {
    super.initState();
    _refreshList();
    _updateCounters();
  }

  void _updateCounters() async {
    final database = await DbHelper.db;
    final total = Sqflite.firstIntValue(await database.rawQuery('SELECT COUNT(*) FROM products')) ?? 0;
    final contados = Sqflite.firstIntValue(await database.rawQuery('SELECT COUNT(*) FROM products WHERE fisica > 0')) ?? 0;
    if (mounted) {
      setState(() {
        totalItems = total.toDouble();
        itemsContados = contados.toDouble();
      });
    }
  }

  void _refreshList() async {
    final data = await DbHelper.search(_searchController.text);
    if (mounted) setState(() => displayedProducts = data);
  }

  void _onScan() async {
    // IMPORTANTE: Se quitó el const de la navegación
    final code = await Navigator.push<String>(
      context, 
      MaterialPageRoute(builder: (_) => const ScannerScreen())
    );
    
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

  void _showNotFoundDialog(String code) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text("No encontrado"),
              content: Text("El código '$code' no existe. ¿Deseas registrarlo?"),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
                ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _goToAddProduct(code);
                    },
                    child: const Text("Registrar"))
              ],
            ));
  }

  void _goToAddProduct([String? initialCode]) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AddProductScreen(initialCode: initialCode)));
    _refreshList();
    _updateCounters();
  }

  void _showConteoDialog(Map<String, dynamic> product) {
    final controller = TextEditingController();
    String zonaSeleccionada = 'Piso de Venta';
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
                      value: zonaSeleccionada,
                      decoration: const InputDecoration(labelText: 'Área de conteo'),
                      items: zonas.map((z) => DropdownMenuItem(value: z, child: Text(z))).toList(),
                      onChanged: (val) => setDialogState(() => zonaSeleccionada = val!),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: controller,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      autofocus: true,
                      decoration: const InputDecoration(labelText: 'Cantidad', border: OutlineInputBorder()),
                    ),
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
                  ElevatedButton(
                      onPressed: () async {
                        double cant = double.tryParse(controller.text) ?? 0.0;
                        await DbHelper.registrarConteo(product['clave'], zonaSeleccionada, cant);
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
    List<List<dynamic>> csvData = [['Clave', 'Código', 'Descripción', 'Unidad', 'Marca', 'Existencia', 'Física', 'Diferencia']];
    for (var p in data) {
      csvData.add([p['clave'], p['codbar'], p['descripcion'], p['unit'], p['marca'], p['existencia'], p['fisica'], p['fisica'] - p['existencia']]);
    }
    String csvString = const ListToCsvConverter().convert(csvData);
    final directory = await getTemporaryDirectory();
    final file = File("${directory.path}/inventario_general.csv");
    await file.writeAsString(csvString);
    await Share.shareXFiles([XFile(file.path)], text: 'Reporte de Inventario');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 80,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Inventario', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            Text('Total SKU: ${totalItems.toInt()} | Contados: ${itemsContados.toInt()}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_edu, size: 28),
            onPressed: () => Navigator.push(
              context, 
              // CORRECCIÓN: Se quitó el 'const' aquí para evitar error de compilación
              MaterialPageRoute(builder: (_) => AuditHistoryScreen()) 
            ).then((_) {
              _refreshList();
              _updateCounters();
            }),
          ),
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
                  hintText: 'Buscar...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  filled: true,
                  fillColor: Colors.grey[100]),
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
                    subtitle: Text("Clave: ${p['clave']} | Stock: ${p['existencia']}"),
                    trailing: Text("${p['fisica']}".replaceAll(RegExp(r'\.0$'), ''),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue)),
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
    _updateCounters();
  }
}
