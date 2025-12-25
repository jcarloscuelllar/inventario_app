import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  runApp(const MyApp());
}

/* =========================
   MODELO PRODUCTO
========================= */
class Product {
  final String clave;
  final String codbar;
  final String descripcion;
  final String marca;
  final String unidad;
  String existencia;

  Product({
    required this.clave,
    required this.codbar,
    required this.descripcion,
    required this.marca,
    required this.unidad,
    required this.existencia,
  });

  String get claveNormalizada {
    return clave.replaceFirst(RegExp(r'^0+'), '');
  }

  List<String> toCsvRow() {
    return [clave, codbar, descripcion, marca, unidad, existencia];
  }
}

/* =========================
   APP
========================= */
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

/* =========================
   INVENTARIO
========================= */
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<Product> allProducts = [];
  File? csvFile;

  int totalArticulos = 0;

  /* ---------- IMPORTAR CSV ---------- */
  Future<void> importCSV() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (result == null) return;

    csvFile = File(result.files.single.path!);
    final content = await csvFile!.readAsString();
    final rows = const CsvToListConverter().convert(content);

    List<Product> products = [];

    for (int i = 1; i < rows.length; i++) {
      products.add(
        Product(
          clave: rows[i][0].toString(),
          codbar: rows[i][1].toString(), // 👈 SEGUNDA COLUMNA
          descripcion: rows[i][2].toString(),
          marca: rows[i][3].toString(),
          unidad: rows[i][4].toString(),
          existencia: rows[i][5].toString(),
        ),
      );
    }

    setState(() {
      allProducts = products;
      totalArticulos = products.length;
    });
  }

  /* ---------- BUSCAR POR CODBAR ---------- */
  Product? buscarPorCodbar(String code) {
    try {
      return allProducts.firstWhere((p) => p.codbar == code);
    } catch (_) {
      return null;
    }
  }

  /* ---------- GUARDAR CSV ---------- */
  Future<void> guardarCSV() async {
    if (csvFile == null) return;

    List<List<String>> rows = [
      ['clave', 'codbar', 'descripcion', 'marca', 'unidad', 'existencia'],
      ...allProducts.map((p) => p.toCsvRow()),
    ];

    final csv = const ListToCsvConverter().convert(rows);
    await csvFile!.writeAsString(csv);
  }

  /* ---------- ABRIR SCANNER ---------- */
  void abrirScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerPage(
          onDetect: (code) async {
            final producto = buscarPorCodbar(code);

            if (producto != null) {
              final cantidad = await Navigator.push<int>(
                context,
                MaterialPageRoute(
                  builder: (_) => ConteoPage(product: producto),
                ),
              );

              if (cantidad != null) {
                setState(() {
                  producto.existencia = cantidad.toString();
                });
                await guardarCSV();
              }
            } else {
              final agregar = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('No encontrado'),
                  content: Text('¿Deseas agregar el código $code?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('No'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Sí'),
                    ),
                  ],
                ),
              );

              if (agregar == true) {
                setState(() {
                  allProducts.add(
                    Product(
                      clave: '',
                      codbar: code,
                      descripcion: 'NUEVO PRODUCTO',
                      marca: '',
                      unidad: '',
                      existencia: '0',
                    ),
                  );
                  totalArticulos = allProducts.length;
                });
                await guardarCSV();
              }
            }
          },
        ),
      ),
    );
  }

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

            if (totalArticulos > 0)
              Text(
                'Artículos a inventariar: $totalArticulos',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),

            const SizedBox(height: 20),

            ElevatedButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Escanear código'),
              onPressed: abrirScanner,
            ),
          ],
        ),
      ),
    );
  }
}

/* =========================
   SCANNER (CON BLOQUEO)
========================= */
class ScannerPage extends StatefulWidget {
  final Function(String) onDetect;
  const ScannerPage({super.key, required this.onDetect});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  bool _procesando = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear')),
      body: MobileScanner(
        onDetect: (capture) {
          if (_procesando) return;

          final code = capture.barcodes.first.rawValue;
          if (code == null) return;

          _procesando = true;

          widget.onDetect(code);

          Navigator.pop(context);
        },
      ),
    );
  }
}

/* =========================
   CONTEO
========================= */
class ConteoPage extends StatefulWidget {
  final Product product;
  const ConteoPage({super.key, required this.product});

  @override
  State<ConteoPage> createState() => _ConteoPageState();
}

class _ConteoPageState extends State<ConteoPage> {
  late TextEditingController _controller;
  int cantidad = 0;

  @override
  void initState() {
    super.initState();
    cantidad = int.tryParse(widget.product.existencia) ?? 0;
    _controller = TextEditingController(text: cantidad.toString());
  }

  void sync() {
    cantidad = int.tryParse(_controller.text) ?? cantidad;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.product.descripcion)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              onChanged: (_) => sync(),
              decoration: const InputDecoration(
                labelText: 'Cantidad',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove, size: 40),
                  onPressed: () {
                    if (cantidad > 0) {
                      setState(() {
                        cantidad--;
                        _controller.text = cantidad.toString();
                      });
                    }
                  },
                ),
                const SizedBox(width: 30),
                IconButton(
                  icon: const Icon(Icons.add, size: 40),
                  onPressed: () {
                    setState(() {
                      cantidad++;
                      _controller.text = cantidad.toString();
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, cantidad);
              },
              child: const Text('Guardar conteo'),
            ),
          ],
        ),
      ),
    );
  }
}