import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  runApp(const MyApp());
}

/* =======================
   MODELO DE PRODUCTO
======================= */
class Product {
  final String clave;
  final String codbar;
  final String descripcion;
  final String marca;
  final String unidad;

  int existencia;         // sistema
  int existenciaFisica;   // conteo
  int sobrante;
  int faltante;

  Product({
    required this.clave,
    required this.codbar,
    required this.descripcion,
    required this.marca,
    required this.unidad,
    required this.existencia,
    this.existenciaFisica = 0,
    this.sobrante = 0,
    this.faltante = 0,
  });

  void recalcular() {
    final diff = existenciaFisica - existencia;
    sobrante = diff > 0 ? diff : 0;
    faltante = diff < 0 ? diff.abs() : 0;
  }
}

/* =======================
   APP
======================= */
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Inventario',
      home: const InventoryScreen(),
    );
  }
}

/* =======================
   INVENTARIO
======================= */
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<Product> products = [];
  bool isScanning = false;
  int totalArticulos = 0;
  String message = '';

  /* =======================
     IMPORTAR CSV
  ======================= */
  Future<void> importCSV() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null) return;

    final file = File(result.files.single.path!);
    final content = await file.readAsString();
    final rows = const CsvToListConverter().convert(content);

    final List<Product> loaded = [];

    for (int i = 1; i < rows.length; i++) {
      loaded.add(
        Product(
          clave: rows[i][0].toString(),
          codbar: rows[i][1].toString(),
          descripcion: rows[i][2].toString(),
          marca: rows[i][3].toString(),
          unidad: rows[i][4].toString(),
          existencia: int.tryParse(rows[i][5].toString()) ?? 0,
        ),
      );
    }

    setState(() {
      products = loaded;
      totalArticulos = loaded.length;
      message = '';
    });
  }

  /* =======================
     ESCANEO
  ======================= */
  void onBarcodeDetected(String code) {
    if (isScanning) return;
    isScanning = true;

    final product = products.firstWhere(
      (p) => p.codbar == code,
      orElse: () => Product(
        clave: '',
        codbar: '',
        descripcion: '',
        marca: '',
        unidad: '',
        existencia: 0,
      ),
    );

    if (product.clave.isEmpty) {
      setState(() {
        message = 'Producto no encontrado';
        isScanning = false;
      });
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ConteoDialog(
        product: product,
        onSave: (cantidad) {
          setState(() {
            product.existenciaFisica += cantidad;
            product.recalcular();
            isScanning = false;
          });
        },
      ),
    );
  }

  /* =======================
     UI
  ======================= */
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inventario')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: importCSV,
              child: const Text('Importar Inventario'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Escanear código'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ScannerScreen(
                      onDetect: onBarcodeDetected,
                    ),
                  ),
                );
              },
            ),
            if (totalArticulos > 0)
              Text(
                'Artículos a inventariar: $totalArticulos',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 8),
            if (message.isNotEmpty)
              Text(message, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),

            /* =======================
               TABLA
            ======================= */
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Clave')),
                    DataColumn(label: Text('Código')),
                    DataColumn(label: Text('Descripción')),
                    DataColumn(label: Text('Marca')),
                    DataColumn(label: Text('Unidad')),
                    DataColumn(label: Text('Existencia')),
                    DataColumn(label: Text('Exist. Física')),
                    DataColumn(label: Text('Sobrante')),
                    DataColumn(label: Text('Faltante')),
                  ],
                  rows: products.map((p) {
                    return DataRow(cells: [
                      DataCell(Text(p.clave)),
                      DataCell(Text(p.codbar)),
                      DataCell(Text(p.descripcion)),
                      DataCell(Text(p.marca)),
                      DataCell(Text(p.unidad)),
                      DataCell(Text(p.existencia.toString())),
                      DataCell(Text(p.existenciaFisica.toString())),
                      DataCell(Text(p.sobrante.toString())),
                      DataCell(Text(p.faltante.toString())),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* =======================
   SCANNER
======================= */
class ScannerScreen extends StatelessWidget {
  final Function(String) onDetect;

  const ScannerScreen({super.key, required this.onDetect});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear')),
      body: MobileScanner(
        onDetect: (barcode, args) {
          final code = barcode.rawValue;
          if (code != null) {
            onDetect(code);
            Navigator.pop(context);
          }
        },
      ),
    );
  }
}

/* =======================
   DIALOGO DE CONTEO
======================= */
class ConteoDialog extends StatefulWidget {
  final Product product;
  final Function(int) onSave;

  const ConteoDialog({
    super.key,
    required this.product,
    required this.onSave,
  });

  @override
  State<ConteoDialog> createState() => _ConteoDialogState();
}

class _ConteoDialogState extends State<ConteoDialog> {
  final TextEditingController controller = TextEditingController();
  String area = 'Bodega';

  final areas = [
    'Bodega',
    'Piso de venta',
    'Marbete',
    'Vitrina',
    'Exhibición',
    'Entregas',
    'Remate',
    'Cajas',
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Conteo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.product.descripcion),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: area,
            items: areas
                .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                .toList(),
            onChanged: (v) => area = v!,
            decoration: const InputDecoration(labelText: 'Área'),
          ),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Cantidad'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            final qty = int.tryParse(controller.text) ?? 0;
            widget.onSave(qty);
            Navigator.pop(context);
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}