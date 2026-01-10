

import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const ItemInfoScreen(),
    );
  }
}

class ItemInfoScreen extends StatelessWidget {
  const ItemInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        backgroundColor: Colors.blue[700],
        leading: const Icon(Icons.menu, color: Colors.white),
        title: const Text('Item Info', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.search, color: Colors.white)),
          IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert, color: Colors.white)),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            // CARD 1: INFORMACIÓN GENERAL
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('JNJCORNBBQ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                        Text('\$ 2.37', style: TextStyle(fontSize: 18, color: Colors.grey[700])),
                      ],
                    ),
                    const Divider(),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _DetailItem(label: 'UPC', value: '480001610106'),
                        _DetailItem(label: 'Clave', value: '31045710'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _DetailItem(label: 'Size', value: '200G'),
                        _DetailItem(label: 'Dept', value: '92'),
                        _DetailItem(label: 'Color', value: 'RED'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 10),

            // CARD 2: INVENTARIO
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              color: Colors.white,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Align(alignment: Alignment.centerLeft, child: Text('Inventory', style: TextStyle(color: Colors.grey))),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _InventoryMetric(value: '36', label: 'Bin'),
                            _OnHandCircle(value: '35'),
                            _InventoryMetric(value: '-1', label: 'Sales Floor', color: Colors.red),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _IconLabel(icon: Icons.inventory_2, label: 'Case Pack 18'),
                        _IconLabel(icon: Icons.view_quilt, label: 'SHELF CAP 18', color: Colors.blue),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
        backgroundColor: Colors.orange[400],
        label: const Text('SCAN'),
        icon: const Icon(Icons.qr_code_scanner),
      ),
    );
  }
}

// Widgets de soporte para limpieza de código
class _DetailItem extends StatelessWidget {
  final String label, value;
  const _DetailItem({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _InventoryMetric extends StatelessWidget {
  final String value, label;
  final Color? color;
  const _InventoryMetric({required this.value, required this.label, this.color});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(color: Colors.grey)),
      ],
    );
  }
}

class _OnHandCircle extends StatelessWidget {
  final String value;
  const _OnHandCircle({required this.value});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.orange, width: 3),
      ),
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
          const Text('On Hand', style: TextStyle(fontSize: 10)),
        ],
      ),
    );
  }
}

class _IconLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _IconLabel({required this.icon, required this.label, this.color = Colors.grey});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
