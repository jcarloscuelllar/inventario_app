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
import 'manual_adjustments_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  // --- VARIABLES DE ESTADO ---
  // Almacenan los productos cargados, el texto de búsqueda y el estado de la UI
  List<Map<String, dynamic>> displayedProducts = [];
  final TextEditingController _searchController = TextEditingController();
  bool isLoading = false;
  double totalItems = 0;
  double itemsContados = 0;
  bool filterPending = false;

  @override
  void initState() {
    super.initState();
    _refreshList(); // Carga inicial de datos
    _updateCounters(); // Inicializa los contadores de la parte superior
  }

  // --- LÓGICA DE CONTADORES ---
  // Consulta la base de datos para obtener el total de SKUs y cuántos llevan conteo físico
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

  // --- REFRESCAR LISTADO ---
  // Llama al controlador para obtener los productos basados en el buscador y el filtro de pendientes
  void _refreshList() async {
    final data = await DbHelper.search(_searchController.text, onlyPending: filterPending);
    if (mounted) setState(() => displayedProducts = data);
  }

  // --- LÓGICA DE ESCANEO ---
  // Abre la cámara y procesa el código obtenido buscando en la DB
  void _onScan() async {
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

  // Diálogo informativo cuando un producto escaneado no existe
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

  // Navegación a la pantalla de agregar producto nuevo
  void _goToAddProduct([String? initialCode]) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AddProductScreen(initialCode: initialCode)));
    _refreshList();
    _updateCounters();
  }

  // --- DIÁLOGO DE CONTEO (MODIFICADO) ---
  // Se adaptó para incluir información detallada del producto antes del formulario
  void _showConteoDialog(Map<String, dynamic> product) {
    final controller = TextEditingController();
    String zonaSeleccionada = 'Piso de Venta';
    final zonas = ['Piso de Venta', 'Marbete', 'Bodega', 'Vitrina', 'Exhibición', 'Entregas', 'Cajas', 'Remate'];

    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
                title: Text(product['descripcion']),
                content: SingleChildScrollView( // MODIFICACIÓN: Scroll de seguridad
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start, // MODIFICACIÓN: Alineación izquierda
                    children: [
                      // MODIFICACIÓN: Bloque de detalles del producto
                      Text("UPC: ${product['codbar']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Text("Clave: ${product['clave']}", style: const TextStyle(fontSize: 13)),
                      Text("Unidad: ${product['unit'] ?? product['unidad']}", style: const TextStyle(fontSize: 13)),
                      Text("Marca: ${product['marca']}", style: const TextStyle(fontSize: 13)),
                      
                      const Divider(), // MODIFICACIÓN: Línea divisoria decorativa
                      const SizedBox(height: 10),

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
                        decoration: const InputDecoration(
                          labelText: 'Cantidad', 
                          border: OutlineInputBorder()
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  // Lógica de guardado del conteo
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

  // --- EXPORTAR CSV ---
  // Genera un archivo con los resultados finales, incluyendo cálculos de sobrantes y faltantes
  Future<void> _exportCSV() async {
    final data = await DbHelper.getAllForExport();
    List<List<dynamic>> csvData = [
      ['CLAVE', 'CODIGO', 'DESCRIPCION', 'UNIDAD', 'MARCA', 'SISTEMA', 'FISICA', 'SOBRANTE', 'FALTANTE']
    ];

    for (var p in data) {
      double stockSistema = p['existencia'] ?? 0.0;
      double stockFisico = p['fisica'] ?? 0.0;
      double diferencia = stockFisico - stockSistema;

      double sobrante = 0.0;
      double faltante = 0.0;

      if (diferencia > 0) {
        sobrante = diferencia;
      } else if (diferencia < 0) {
        faltante = diferencia.abs();
      }

      csvData.add([
        p['clave'], p['codbar'], p['descripcion'], p['unit'], p['marca'],
        stockSistema, stockFisico,
        sobrante == 0 ? "" : sobrante,
        faltante == 0 ? "" : faltante,
      ]);
    }

    String csvString = const ListToCsvConverter().convert(csvData);
    final directory = await getTemporaryDirectory();
    final file = File("${directory.path}/inventario_general.csv");
    await file.writeAsString(csvString);
    await Share.shareXFiles([XFile(file.path)], text: 'Reporte de Inventario Final');
  }

  // --- INTERFAZ DE USUARIO ---
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
          // Botón para filtrar productos pendientes
          IconButton(
            icon: Icon(
              filterPending ? Icons.pending_actions : Icons.list_alt,
              color: filterPending ? Colors.orangeAccent : null,
            ),
            tooltip: filterPending ? 'Viendo pendientes' : 'Viendo todos',
            onPressed: () {
              setState(() => filterPending = !filterPending);
              _refreshList();
            },
          ),
          // Botón de Ajustes Manuales
          IconButton(
            icon: const Icon(Icons.balance, size: 28, color: Colors.orange),
            onPressed: () async {
              final data = await DbHelper.getAllForExport(); 
              final itemsConDiferencia = data.where((p) {
                double diff = (p['fisica'] ?? 0.0) - (p['existencia'] ?? 0.0);
                return diff != 0;
              }).toList();

              if (itemsConDiferencia.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("No hay diferencias para ajustar"))
                );
                return;
              }
              Navigator.push(context, MaterialPageRoute(builder: (_) => ManualAdjustmentsScreen(initialData: itemsConDiferencia)));
            },
          ),
          // Historial, Importación y Exportación
          IconButton(
            icon: const Icon(Icons.history_edu, size: 28),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AuditHistoryScreen())).then((_) {
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
          // Buscador de productos
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
          // Listado principal
          Expanded(
            child: ListView.builder(
              itemCount: displayedProducts.length,
              itemBuilder: (context, i) {
                final p = displayedProducts[i];
                return Card(
                   color: p['fisica'] > 0 ? Colors.green[50] : Colors.white,
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

  // --- IMPORTAR CSV ---
  // Permite seleccionar un archivo CSV de la memoria y cargarlo en la base de datos
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
