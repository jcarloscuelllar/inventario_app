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
  // --- SIGNALS PARA ESTADO REACTIVO ---
  final letraActiva = signal('A');
  final asignaciones = mapSignal<String, String>({});
  late final List<Map<String, dynamic>> itemsOrdenados;

  @override
  void initState() {
    super.initState();
    _prepararDatos();
  }

  void _prepararDatos() {
    // Ordenar por descripción y poner Sobrantes (+) junto a Faltantes (-)
    itemsOrdenados = List.from(widget.initialData);
    itemsOrdenados.sort((a, b) {
      int comp = a['descripcion'].toString().compareTo(b['descripcion'].toString());
      if (comp != 0) return comp;
      
      double diffA = (a['fisica'] ?? 0.0) - (a['existencia'] ?? 0.0);
      double diffB = (b['fisica'] ?? 0.0) - (b['existencia'] ?? 0.0);
      return diffB.compareTo(diffA); // Sobrantes arriba
    });
  }

  // --- LÓGICA DE NOMENCLATURA DINÁMICA ---
  String _calcularRegistro(Map<String, dynamic> p) {
    final clave = p['clave'].toString();
    double diffOriginal = (p['fisica'] ?? 0.0) - (p['existencia'] ?? 0.0);
    final letra = asignaciones.value[clave];

    if (letra == null) return "${diffOriginal > 0 ? '+' : ''}${diffOriginal.toInt()}";

    double saldoOtros = 0;
    asignaciones.value.forEach((c, l) {
      if (l == letra && c != clave) {
        final item = widget.initialData.firstWhere((i) => i['clave'].toString() == c);
        saldoOtros += (item['fisica'] ?? 0.0) - (item['existencia'] ?? 0.0);
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

    return (ajuste == 0) ? rStr.trim() : "$rStr$aStr".trim();
  }

  // --- GENERACIÓN DE REPORTE PDF ---
  Future<void> _exportarPDF() async {
    final pdf = pw.Document();
    
    // Clasificación de tablas
    List<Map<String, dynamic>> tMatch = [];
    List<Map<String, dynamic>> tSobrante = [];
    List<Map<String, dynamic>> tFaltante = [];

    for (var p in itemsOrdenados) {
      final registro = _calcularRegistro(p);
      final diff = (p['fisica'] ?? 0.0) - (p['existencia'] ?? 0.0);
      final row = {
        'clave': p['clave'],
        'ajuste': registro,
        'desc': p['descripcion'],
        'sis': p['existencia'],
        'fis': p['fisica'],
        'sob': diff > 0 ? diff : 0,
        'fal': diff < 0 ? diff.abs() : 0,
      };

      if (registro.contains(RegExp(r'[A-Z]'))) {
        tMatch.add(row);
      } else if (diff > 0) {
        tSobrante.add(row);
      } else {
        tFaltante.add(row);
      }
    }

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.letter.landscape(),
      build: (context) => [
        pw.Header(level: 0, child: pw.Text("REPORTE AUDITORÍA DE INVENTARIO")),
        _buildPdfTable("1. AJUSTES UNO POR OTRO (MATCH)", tMatch, PdfColors.blue900),
        _buildPdfTable("2. SOBRANTES NETOS", tSobrante, PdfColors.green900),
        _buildPdfTable("3. FALTANTES NETOS", tFaltante, PdfColors.red900),
        pw.SizedBox(height: 40),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          children: [
            _buildFirma("Firma Auditor"),
            _buildFirma("Firma Almacén"),
          ]
        )
      ],
    ));

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  pw.Widget _buildPdfTable(String titulo, List<Map<String, dynamic>> data, PdfColor color) {
    return pw.Column(cross: pw.CrossAxisAlignment.start, children: [
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 15, bottom: 5),
        child: pw.Text(titulo, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: color)),
      ),
      pw.TableHelper.fromTextArray(
        headers: ['CLAVE', 'AJUSTE', 'DESCRIPCION', 'SIST', 'FIS', 'SOB', 'FAL'],
        data: data.map((i) => [i['clave'], i['ajuste'], i['desc'], i['sis'], i['fis'], i['sob'], i['fal']]).toList(),
        headerDecoration: pw.BoxDecoration(color: color),
        headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold),
        cellHeight: 20,
        columnWidths: {2: const pw.FixedColumnWidth(200)}, // Descripción más ancha
      ),
    ]);
  }

  pw.Widget _buildFirma(String texto) {
    return pw.Column(children: [
      pw.Container(width: 150, border: const pw.Border(top: pw.BorderSide())),
      pw.Text(texto),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Conciliación de Diferencias"),
        actions: [
          IconButton(icon: const Icon(Icons.picture_as_pdf), onPressed: _exportarPDF),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: _buildBarraLetras(),
        ),
      ),
      body: Watch((context) {
        return ListView.builder(
          itemCount: itemsOrdenados.length,
          itemBuilder: (context, i) {
            final p = itemsOrdenados[i];
            final clave = p['clave'].toString();
            final letra = asignaciones.value[clave];
            double diff = (p['fisica'] ?? 0.0) - (p['existencia'] ?? 0.0);

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
                    backgroundColor: letra != null ? Colors.blue : Colors.grey[300],
                    child: Text(letra ?? '', style: const TextStyle(color: Colors.white)),
                  ),
                  title: Text(p['descripcion']),
                  subtitle: Text("Clave: $clave | Sis: ${p['existencia']} | Fis: ${p['fisica']}"),
                  trailing: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(4)),
                    child: Text(_calcularRegistro(p), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                  ),
                  onTap: () {
                    if (asignaciones.value[clave] == letraActiva.value) {
                      asignaciones.remove(clave);
                    } else {
                      asignaciones[clave] = letraActiva.value;
                    }
                  },
                ),
              ],
            );
          },
        );
      }),
    );
  }

  Widget _buildBarraLetras() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: ['A', 'B', 'C', 'D', 'E'].map((l) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: ChoiceChip(
            label: Text("Letra $l"),
            selected: letraActiva.watch(context) == l,
            onSelected: (_) => letraActiva.value = l,
          ),
        )).toList(),
      ),
    );
  }
}
