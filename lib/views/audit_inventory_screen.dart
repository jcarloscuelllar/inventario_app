import 'dart:io';
import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../controllers/db_helper.dart';

class AuditHistoryScreen extends StatefulWidget {
  const AuditHistoryScreen({super.key});
  @override
  State<AuditHistoryScreen> createState() => _AuditHistoryScreenState();
}

class _AuditHistoryScreenState extends State<AuditHistoryScreen> {
  List<Map<String, dynamic>> _allLogs = [];
  List<Map<String, dynamic>> _filteredLogs = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() async {
    final data = await DbHelper.getFullAudit();
    setState(() { _allLogs = data; _filteredLogs = data; });
  }

  // --- ESTA ES LA NUEVA FUNCIÓN DE EXPORTACIÓN ---
  Future<void> _exportAuditCSV() async {
    final data = await DbHelper.getAuditForExport();
    
    List<List<dynamic>> csvData = [
      ['Fecha/Hora', 'Clave', 'Producto', 'Área/Zona', 'Cantidad']
    ];

    for (var row in data) {
      csvData.add([
        row['fecha'],
        row['clave'],
        row['descripcion'],
        row['zona'],
        row['cantidad'],
      ]);
    }

    String csvString = const ListToCsvConverter().convert(csvData);
    final directory = await getTemporaryDirectory();
    final file = File("${directory.path}/reporte_auditoria_detallado.csv");
    await file.writeAsString(csvString);
    
    await Share.shareXFiles(
      [XFile(file.path)], 
      text: 'Historial de Auditoría Detallado'
    );
  }

  void _filter(String q) {
    setState(() {
      _filteredLogs = _allLogs.where((l) {
        final text = "${l['descripcion']} ${l['zona']} ${l['clave']}".toLowerCase();
        return text.contains(q.toLowerCase());
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Historial por Áreas"),
        // --- AQUÍ AÑADIMOS EL BOTÓN EN EL APPBAR ---
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportAuditCSV,
            tooltip: "Exportar Historial",
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              onChanged: _filter,
              decoration: const InputDecoration(
                hintText: "Filtrar por producto o área...",
                prefixIcon: Icon(Icons.filter_list),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Hora')),
                    DataColumn(label: Text('Producto')),
                    DataColumn(label: Text('Área')),
                    DataColumn(label: Text('Cant.')),
                    DataColumn(label: Text('Acción')),
                  ],
                  rows: _filteredLogs.map((log) {
                    return DataRow(cells: [
                      DataCell(Text(log['fecha'].toString().split(' ')[1])),
                      DataCell(Text(log['descripcion'])),
                      DataCell(Text(log['zona'])),
                      DataCell(Text(log['cantidad'].toString().replaceAll(RegExp(r'\.0$'), ''))),
                      DataCell(IconButton(
                        icon: const Icon(Icons.delete_forever, color: Colors.red),
                        onPressed: () => _confirmDelete(log),
                      )),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(Map<String, dynamic> log) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Eliminar registro?"),
        content: Text("Se restará ${log['cantidad']} de ${log['descripcion']}"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () async {
              await DbHelper.eliminarRegistroAuditoria(log['id'], log['clave'], log['cantidad']);
              Navigator.pop(ctx);
              _loadData();
            },
            child: const Text("Eliminar"),
          )
        ],
      ),
    );
  }
}
