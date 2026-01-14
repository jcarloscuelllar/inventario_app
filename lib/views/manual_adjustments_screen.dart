import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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
    itemsOrdenados.sort((a, b) {
      int comp = a['descripcion'].toString().compareTo(b['descripcion'].toString());
      if (comp != 0) return comp;
      double diffA = (a['fisica']?.toDouble() ?? 0.0) - (a['existencia']?.toDouble() ?? 0.0);
      double diffB = (b['fisica']?.toDouble() ?? 0.0) - (b['existencia']?.toDouble() ?? 0.0);
      return diffB.compareTo(diffA); 
    });
  }

  // --- LÓGICA DE CÁLCULO (OBJETO DE RETORNO PARA PDF) ---
  Map<String, dynamic> _obtenerDetalleAjuste(Map<String, dynamic> p) {
    final clave = p['clave'].toString();
    double stockSistema = (p['existencia']?.toDouble() ?? 0.0);
    double stockFisico = (p['fisica']?.toDouble() ?? 0.0);
    double diffOriginal = stockFisico - stockSistema;
    
    final letra = asignaciones.value[clave];
    if (letra == null) {
      return {'texto': "${diffOriginal > 0 ? '+' : ''}${diffOriginal.toInt()}", 'ajuste': 0.0, 'residuo': diffOriginal, 'letra': ''};
    }

    double saldoOtros = 0;
    asignaciones.value.forEach((c, l) {
      if (l == letra && c != clave) {
        final item = widget.initialData.firstWhere((i) => i['clave'].toString() == c);
        saldoOtros += (item['fisica']?.toDouble() ?? 0.0) - (item['existencia']?.toDouble() ?? 0.0);
      }
    });

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
    String rStr = residuo == 0 ? "" : "${residuo > 0 ? '+' : ''}${residuo.toInt()} ";
    String aStr = "${ajuste > 0 ? '+' : ''}${ajuste.toInt()}$letra";

    return {
      'texto': (ajuste == 0) ? rStr.trim() : "$rStr$aStr".trim(),
      'ajuste': ajuste,
      'residuo': residuo,
      'letra': letra
    };
  }

  // --- GENERACIÓN DE REPORTE PDF CON RECLASIFICACIÓN ---
  Future<void> _exportarPDF() async {
    final pdf = pw.Document();
    
    List<Map<String, dynamic>> tMatch = [];
    List<Map<String, dynamic>> tSobrante = [];
    List<Map<String, dynamic>> tFaltante = [];

    for (var p in itemsOrdenados) {
      final detalle = _obtenerDetalleAjuste(p);
      final double ajuste = detalle['ajuste'];
      final double residuo = detalle['residuo'];

      // 1. Si hubo intercambio (Match), se va a la Tabla 1
      if (ajuste != 0) {
        tMatch.add({
          'clave': p['clave'],
          'ajuste': "${ajuste > 0 ? '+' : ''}${ajuste.toInt()}${detalle['letra']}",
          'desc': p['descripcion'],
        });
      }

      // 2. El residuo (lo que no se pudo ajustar) se clasifica como Sobrante o Faltante Neto
      if (residuo != 0) {
        final rowResiduo = {
          'clave': p['clave'],
          'ajuste': "${residuo > 0 ? '+' : ''}${residuo.toInt()}",
          'desc': p['descripcion'],
        };
        if (residuo > 0) {
          tSobrante.add(rowResiduo);
        } else {
          tFaltante.add(rowResiduo);
        }
      }
    }

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.letter.landscape,
      build: (context) => [
        pw.Header(level: 0, child: pw.Text("AJUSTES DEL INVENTARIO")),
        _buildPdfTable("AJUSTE UNO POR OTRO", tMatch, PdfColors.blue900),
        _buildPdfTable("AJUSTE POR SOBRANTE DE MERCANCIA", tSobrante, PdfColors.green900),
        _buildPdfTable("AJUSTE POR SOBRANTE DE MERCANCIA", tFaltante, PdfColors.red900),
        pw.SizedBox(height: 50),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceAround, children: [
          _buildFirma("INVENTARISTA"),
          _buildFirma("GERENCIA"),
        ])
      ],
    ));

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  pw.Widget _buildPdfTable(String titulo, List<Map<String, dynamic>> data, PdfColor color) {
    if (data.isEmpty) return pw.SizedBox();
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 15, bottom: 5),
        child: pw.Text(titulo, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: color)),
      ),
      pw.TableHelper.fromTextArray(
        headers: ['CLAVE', 'CANTIDAD/AJUSTE', 'DESCRIPCION'],
        data: data.map((i) => [i['clave'], i['ajuste'], i['desc']]).toList(),
        headerDecoration: pw.BoxDecoration(color: color),
        headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
        cellStyle: const pw.TextStyle(fontSize: 9),
        columnWidths: {2: const pw.FixedColumnWidth(300)},
      ),
    ]);
  }

  pw.Widget _buildFirma(String texto) {
    return pw.Column(children: [
      pw.Container(width: 150, decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide()))),
      pw.Text(texto, style: const pw.TextStyle(fontSize: 10)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Conciliación Pro"),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
            onPressed: () => asignaciones.value = {},
            tooltip: 'Limpiar Todo',
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf), 
            onPressed: _exportarPDF,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: _buildBarraLetras(),
        ),
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
                  subtitle: Text("Sis: ${p['existencia'].toInt()} | Fis: ${p['fisica'].toInt()}"),
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
