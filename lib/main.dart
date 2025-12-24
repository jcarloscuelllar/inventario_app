import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';

void main() {
  runApp(const MyApp());
}

class Product {
  final String clave;
  final String codbar;
  final String descripcion;
  final String marca;
  final String unidad;
  final String existencia;

  Product({
    required this.clave,
    required this.codbar,
    required this.descripcion,
    required this.marca,
    required this.unidad,
    required this.existencia,
  });

  /// Quita ceros a la izquierda: 001234 → 1234
  String get claveNormalizada {
    return clave.replaceFirst(RegExp(r'^0+'), '');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Inventario',
      theme: ThemeData(primarySwatch: Colors.blue),
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
  List<Product> allProducts = [];
  List<Product> filteredProducts = [];
  Set<int> selectedRows = {};

  String searchText = '';
  bool searchByClave = false;
  String message = '';

  int totalArticulos = 0; // 👈 TOTAL A INVENTARIAR

  Future<void> importCSV() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (result == null) return;

    final file = File(result.files.single.path!);
    final content = await file.readAsString();
    final rows = const CsvToListConverter().convert(content);

    List<Product> products = [];

    // 👇 Se salta el encabezado
    for (int i = 1; i < rows.length; i++) {
      products.add(
        Product(
          clave: rows[i][0].toString(),
          codbar: rows[i][1].toString(),
          descripcion: rows[i][2].toString(),
          marca: rows[i][3].toString(),
          unidad: rows[i][4].toString(),
          existencia: rows[i][5].toString(),
        ),
      );
    }

    setState(() {
      allProducts = products;
      filteredProducts = products;
      selectedRows.clear();
      totalArticulos = products.length; // 👈 CONTEO REAL
      message = '';
    });
  }

  void search() {
    if (searchText.isEmpty) {
      setState(() {
        filteredProducts = allProducts;
        message = '';
      });
      return;
    }

    if (searchByClave) {
      final claveBuscada = searchText.replaceFirst(RegExp(r'^0+'), '');

      final results = allProducts.where((p) {
        return p.claveNormalizada == claveBuscada;
      }).toList();

      setState(() {
        filteredProducts = results;
        message = results.isEmpty ? 'No se encontró el producto' : '';
      });
    } else {
      final results = allProducts.where((p) {
        return p.descripcion
            .toLowerCase()
            .contains(searchText.toLowerCase());
      }).toList();

      setState(() {
        filteredProducts = results;
        message = results.isEmpty ? 'No se encontró el producto' : '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventario'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: importCSV,
              child: const Text('Importar Inventario'),
            ),

            // 👇 LABEL DE TOTAL
            if (totalArticulos > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Artículos a inventariar: $totalArticulos',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Buscar',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      searchText = value;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  children: [
                    const Text('Buscar por clave'),
                    Switch(
                      value: searchByClave,
                      onChanged: (value) {
                        setState(() {
                          searchByClave = value;
                        });
                      },
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: search,
                ),
              ],
            ),

            const SizedBox(height: 16),

            if (message.isNotEmpty)
              Text(
                message,
                style: const TextStyle(color: Colors.red),
              ),

            const SizedBox(height: 8),

            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Clave')),
                    DataColumn(label: Text('Código de Barras')),
                    DataColumn(label: Text('Descripción')),
                    DataColumn(label: Text('Marca')),
                    DataColumn(label: Text('Unidad')),
                    DataColumn(label: Text('Existencia')),
                  ],
                  rows: List.generate(filteredProducts.length, (index) {
                    final product = filteredProducts[index];
                    final selected = selectedRows.contains(index);

                    return DataRow(
                      selected: selected,
                      color: selected
                          ? MaterialStateProperty.all(Colors.green.shade300)
                          : null,
                      onSelectChanged: (value) {
                        setState(() {
                          if (selected) {
                            selectedRows.remove(index);
                          } else {
                            selectedRows.add(index);
                          }
                        });
                      },
                      cells: [
                        DataCell(Text(product.clave)),
                        DataCell(Text(product.codbar)),
                        DataCell(Text(product.descripcion)),
                        DataCell(Text(product.marca)),
                        DataCell(Text(product.unidad)),
                        DataCell(Text(product.existencia)),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}