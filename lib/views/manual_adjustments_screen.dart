import 'dart:io';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' as xl;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ManualAdjustmentsScreen extends StatefulWidget {
  final List<Map<String, dynamic>> initialData;

  const ManualAdjustmentsScreen({super.key, required this.initialData});

  @override
  State<ManualAdjustmentsScreen> createState() => _ManualAdjustmentsScreenState();
}

class _ManualAdjustmentsScreenState extends State<ManualAdjustmentsScreen> {
  final letraActiva = signal('A');
  final asignaciones = signal<Map<String, String>>({});
  late final List<Map<String, dynamic>> itemsOrdenados;
  final List<String> abecedario = List.generate(26, (index) => String.fromCharCode(65 + index));

  @override
  void initState() {
    super.initState();
    _prepararDatos();
  }

  void _prepararDatos() {
    itemsOrdenados = List.from(widget.initialData);
    itemsOrdenados.sort((a, b) => a['descripcion'].toString().compareTo(b['descripcion'].toString()));
  }

  // FUNCIÓN MAGICA: Formatea 2.0 a "2" y 2.98 a "2.98"
  String _formatNum(double n) {
    if (n == 0) return "";
    // Si el resto de dividir entre 1 es 0, es entero
    return n % 1 == 0 ? n.toInt().toString() : n.toStringAsFixed(2);
  }

  Map<String, dynamic> _obtenerDetalleAjuste(Map<String, dynamic> p) {
    final clave = p['clave'].toString();
    double stockSistema = (p['existencia']?.toDouble() ?? 0.0);
    double stockFisico = (p['fisica']?.toDouble() ?? 0.0);
    double diffOriginal = stockFisico - stockSistema;

    final letra = asignaciones.value[clave];
    if (letra == null) {
      String signo = diffOriginal > 0 ? '+' : '';
      return {
        'texto': "$signo${_formatNum(diffOriginal)}",
        'ajuste': 0.0,
        'residuo': diffOriginal,
        'letra': ''
      };
    }

    double saldoOtros = 0;
    for (var entry in asignaciones.value.entries) {
      if (entry.value == letra && entry.key != clave) {
        final item = widget.initialData.firstWhere((i) => i['clave'].toString() == entry.key);
        saldoOtros += (item['fisica']?.toDouble() ?? 0.0) - (item['existencia']?.toDouble() ?? 0.0);
      }
    }

    double ajuste;
    if (diffOriginal > 0) {
      double necesidad = saldoOtros < 0 ? saldoOtros.abs() : 0;
      ajuste = diffOriginal > necesidad ? necesidad : diffOriginal;
    } else {
      double disponibilidad = saldoOtros > 0 ? saldoOtros : 0;
      ajuste = diffOriginal.abs() > disponibilidad ? disponibilidad : diffOriginal.abs();
      ajuste = -ajuste;
    }

    double residuo = diffOriginal - ajuste;
    
    String rStr = residuo == 0 ? "" : "${residuo > 0 ? '+' : ''}${_formatNum(residuo)} ";
    String aStr = ajuste == 0 ? "" : "${ajuste > 0 ? '+' : ''}${_formatNum(ajuste)}$letra";

    return {
      'texto': "$rStr$aStr".trim(),
      'ajuste': ajuste,
      'residuo': residuo,
      'letra': letra
    };
  }

  Future<void> _exportarExcel() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      var excel = xl.Excel.createExcel();
      xl.Sheet sheetMatch = excel['1-Match'];
      xl.Sheet sheetSob = excel['2-Sobrantes'];
      xl.Sheet sheetFal = excel['3-Faltantes'];
      excel.delete('Sheet1');

      List<xl.CellValue> header = [
        xl.TextCellValue("CLAVE"),
        xl.TextCellValue("REGISTRO"),
        xl.TextCellValue("DESCRIPCION"),
        xl.TextCellValue("SIS"),
        xl.TextCellValue("FIS"),
        xl.TextCellValue("DIF")
      ];
      
      sheetMatch.appendRow(header);
      sheetSob.appendRow(header);
      sheetFal.appendRow(header);

      for (var p in itemsOrdenados) {
        final detalle = _obtenerDetalleAjuste(p);
        final double ajuste = detalle['ajuste'];
        final double residuo = detalle['residuo'];
        
        // Función interna para decidir si enviar Int o Double a la celda de Excel
        xl.CellValue _xlNum(double n) => n % 1 == 0 ? xl.IntCellValue(n.toInt()) : xl.DoubleCellValue(n);

        List<xl.CellValue> dataRow(String reg, double val) => [
          xl.TextCellValue(p['clave'].toString()),
          xl.TextCellValue(reg),
          xl.TextCellValue(p['descripcion'].toString()),
          _xlNum(p['existencia']?.toDouble() ?? 0),
          _xlNum(p['fisica']?.toDouble() ?? 0),
          _xlNum(val),
        ];

        if (ajuste != 0) {
          sheetMatch.appendRow(dataRow("${ajuste > 0 ? '+' : ''}${_formatNum(ajuste)}${detalle['letra']}", ajuste));
        }
        if (residuo != 0) {
          if (residuo > 0) {
            sheetSob.appendRow(dataRow("${_formatNum(residuo)}", residuo));
          } else {
            sheetFal.appendRow(dataRow("${_formatNum(residuo)}", residuo));
          }
        }
      }

      final fileBytes = excel.save();
      final directory = await getTemporaryDirectory();
      final String filePath = "${directory.path}/Ajustes_Inventario.xlsx";
      final file = File(filePath);
      await file.writeAsBytes(fileBytes!);

      if (mounted) Navigator.pop(context);
      await Share.shareXFiles([XFile(filePath)], text: 'Reporte de Ajustes');

    } catch (e) {
      if (mounted) Navigator.pop(context);
      debugPrint("Error Excel: $e");
    }
  }

  // Mantenemos PDF pero con la nueva lógica de formato
  Future<void> _exportarPDF() async {
    final pdf = pw.Document();
    final List<List<String>> tMatch = [];
    final List<List<String>> tSobrante = [];
    final List<List<String>> tFaltante = [];

    for (var p in itemsOrdenados) {
      final detalle = _obtenerDetalleAjuste(p);
      if (detalle['ajuste'] != 0) {
        tMatch.add([p['clave'].toString(), "${detalle['ajuste'] > 0 ? '+' : ''}${_formatNum(detalle['ajuste'])}${detalle['letra']}", p['descripcion'].toString(), _formatNum(p['existencia']?.toDouble() ?? 0), _formatNum(p['fisica']?.toDouble() ?? 0), _formatNum(detalle['ajuste']), ""]);
      }
      if (detalle['residuo'] != 0) {
        double r = detalle['residuo'];
        tSobrante.add([p['clave'].toString(), _formatNum(r), p['descripcion'].toString(), _formatNum(p['existencia']?.toDouble() ?? 0), _formatNum(p['fisica']?.toDouble() ?? 0), r > 0 ? _formatNum(r) : "", r < 0 ? _formatNum(r.abs()) : ""]);
      }
    }
    // ... resto del PDF igual ...
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.letter.landscape,
      build: (context) => [
        pw.Text("REPORTE DE AJUSTES", style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        _buildPdfTable("1. MATCH", tMatch, PdfColors.blue900),
      ],
    ));
    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  pw.Widget _buildPdfTable(String titulo, List<List<String>> data, PdfColor color) {
    if (data.isEmpty) return pw.SizedBox();
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 5), child: pw.Text(titulo, style: pw.TextStyle(color: color, fontWeight: pw.FontWeight.bold))),
      pw.TableHelper.fromTextArray(
        headers: ['CLAVE', 'REGISTRO', 'DESCRIPCION', 'SIS', 'FIS', 'SOB', 'FAL'],
        data: data,
        headerDecoration: pw.BoxDecoration(color: color),
        headerStyle: pw.TextStyle(color: PdfColors.white, fontSize: 8),
        cellStyle: const pw.TextStyle(fontSize: 8),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Ajustes"),
        actions: [
          IconButton(icon: const Icon(Icons.table_view, color: Colors.green), onPressed: _exportarExcel),
          IconButton(icon: const Icon(Icons.picture_as_pdf, color: Colors.red), onPressed: _exportarPDF),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(60), child: _buildBarraLetras()),
      ),
      body: ListView.builder(
        itemCount: itemsOrdenados.length,
        itemBuilder: (context, i) {
          final p = itemsOrdenados[i];
          final clave = p['clave'].toString();
          double diff = (p['fisica']?.toDouble() ?? 0.0) - (p['existencia']?.toDouble() ?? 0.0);

          return Watch((context) {
            final letraP = asignaciones.value[clave];
            final registro = _obtenerDetalleAjuste(p);

            return Column(
              children: [
                if (i == 0 || itemsOrdenados[i]['descripcion'][0] != itemsOrdenados[i - 1]['descripcion'][0])
                  Container(
                    width: double.infinity,
                    color: Colors.grey[200],
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Text(p['descripcion'][0], style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ListTile(
                  tileColor: diff > 0 ? Colors.green.withOpacity(0.05) : Colors.red.withOpacity(0.05),
                  leading: CircleAvatar(
                    backgroundColor: letraP != null ? Colors.blue : Colors.grey[300],
                    child: Text(letraP ?? '', style: const TextStyle(color: Colors.white)),
                  ),
                  title: Text(p['descripcion']),
                  subtitle: Text("Sis: ${_formatNum(p['existencia']?.toDouble() ?? 0)} | Fis: ${_formatNum(p['fisica']?.toDouble() ?? 0)}"),
                  trailing: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(4)),
                    child: Text(registro['texto'], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                  ),
                  onTap: () {
                    final nuevoMapa = Map<String, String>.from(asignaciones.value);
                    if (nuevoMapa[clave] == letraActiva.value) {
                      nuevoMapa.remove(clave);
                    } else {
                      nuevoMapa[clave] = letraActiva.value;
                    }
                    asignaciones.value = nuevoMapa;
                  },
                ),
                const Divider(height: 1),
              ],
            );
          });
        },
      ),
    );
  }

  Widget _buildBarraLetras() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: abecedario.map((l) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Watch((context) {
              final sel = letraActiva.value == l;
              return ChoiceChip(
                label: Text(l),
                selected: sel,
                selectedColor: Colors.blue,
                labelStyle: TextStyle(color: sel ? Colors.white : Colors.black),
                onSelected: (_) => letraActiva.value = l,
              );
            }),
          )).toList(),
        ),
      ),
    );
  }
}
