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
  // --- SIGNALS PARA ESTADO REACTIVO (v6.3.0) ---
  final letraActiva = signal('A');
  final asignaciones = signal<Map<String, String>>({});
  late final List<Map<String, dynamic>> itemsOrdenados;

  @override
  void initState() {
    super.initState();
    _prepararDatos();
  }

  void _prepararDatos() {
    // Ordenar por descripción y poner Sobrantes (+) junto a Faltantes (-) para facilitar el match
    itemsOrdenados = List.from(widget.initialData);
    itemsOrdenados.sort((a, b) {
      int comp = a['descripcion'].toString().compareTo(b['descripcion'].toString());
      if (comp != 0) return comp;
      
      double diffA = (a['fisica']?.toDouble() ?? 0.0) - (a['existencia']?.toDouble() ?? 0.0);
      double diffB = (b['fisica']?.toDouble() ?? 0.0) - (b['existencia'] ?? 0.0);
      return diffB.compareTo(diffA); // Sobrantes (+) arriba de Faltantes (-)
    });
  }

  // --- LÓGICA DE NOMENCLATURA DINÁMICA (+1 +2A) ---
  String _calcularRegistro(Map<String, dynamic> p) {
    final clave = p['clave'].toString();
    double stockSistema = (p['existencia']?.toDouble() ?? 0.0);
    double stockFisico = (p['fisica']?.toDouble() ?? 0.0);
    double diffOriginal = stockFisico - stockSistema;
    
    final letra = asignaciones.value[clave];

    if (letra == null) return "${diffOriginal > 0 ? '+' : ''}${diffOriginal.toInt()}";

    // Cálculo de saldo del grupo (sin el item actual) para ver cuánto podemos compensar
    double saldoOtros = 0;
    asignaciones.value.forEach((c, l) {
      if (l == letra && c != clave) {
        final item = widget.initialData.firstWhere((i) => i['clave'].toString() == c);
        double sSis = (item['existencia']?.toDouble() ?? 0.0);
        double sFis = (item['fisica']?.toDouble() ?? 0.0);
        saldoOtros += (sFis - sSis);
      }
    });

    double ajuste;
    if (diffOriginal > 0) {
      // Si sobra: ¿Cuánto falta en los otros del grupo?
      double necesidad = saldoOtros < 0 ? saldoOtros.abs() : 0;
      ajuste = diffOriginal > necesidad ? necesidad : diffOriginal;
    } else {
      // Si falta: ¿Cuánto sobra en los otros del grupo?
      double disponibilidad = saldoOtros > 0 ? saldoOtros : 0;
      ajuste = diffOriginal.abs() > disponibilidad ? disponibilidad : diffOriginal.abs();
      ajuste = -ajuste; // Mantener signo negativo
    }

    double residuo = diffOriginal - ajuste;
    String rStr = residuo == 0 ? "" : "${residuo > 0 ? '+' : ''}${residuo.toInt()} ";
    String aStr = "${ajuste > 0 ? '+' : ''}${ajuste.toInt()}$letra";

    return (ajuste == 0) ? rStr.trim() : "$rStr$aStr".trim();
  }

  // --- GENERACIÓN DE REPORTE PDF CON TRES TABLAS ---
  Future<void> _exportarPDF() async {
    final pdf = pw.Document();
    
    List<Map<String, dynamic>> tMatch = [];
    List<Map<String, dynamic>> tSobrante = [];
    List<Map<String, dynamic>> tFaltante = [];

    for (var p in itemsOrdenados) {
      final registro = _calcularRegistro(p);
      double stockSis = (p['existencia']?.toDouble() ?? 0.0);
      double stockFis = (p['fisica']?.toDouble() ?? 0.0);
      final diff = stockFis - stockSis;

      final row = {
        'clave': p['clave'],
        'ajuste': registro,
        'desc': p['descripcion'],
        'sis': stockSis.toInt(),
        'fis': stockFis.toInt(),
        'sob': diff > 0 ? diff.toInt() : 0,
        'fal': diff < 0 ? diff.abs().toInt() : 0,
      };

      if (registro.contains(RegExp(r'[A-E]'))) {
        tMatch.add(row);
      } else if (diff > 0) {
        tSobrante.add(row);
      } else if (diff < 0) {
        tFaltante.add(row);
      }
    }

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.letter.landscape(),
      build: (context) => [
        pw.Header(level: 0, child: pw.Text("REPORTE DE AUDITORÍA Y CONCILIACIÓN")),
        _buildPdfTable("1. AJUSTES POR INTERCAMBIO (UNO POR OTRO)", tMatch, PdfColors.blue900),
        _buildPdfTable("2. AJUSTES POR SOBRANTE (CARGOS)", tSobrante, PdfColors.green900),
        _buildPdfTable("3. AJUSTES POR FALTANTE (DESCARGOS)", tFaltante, PdfColors.red900),
        pw.SizedBox(height: 50),
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
    if (data.isEmpty) return pw.SizedBox();
    return pw.Column(cross: pw.CrossAxisAlignment.start, children: [
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 15, bottom: 5),
        child: pw.Text(titulo, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: color)),
      ),
      pw.TableHelper.fromTextArray(
        headers: ['CLAVE', 'REGISTRO', 'DESCRIPCION', 'SIS', 'FIS', 'SOB', 'FAL'],
        data: data.map((i) => [
          i['clave'], i['ajuste'], i['desc'], i['sis'], i['fis'], 
          i['sob'] == 0 ? '' : i['sob'], 
          i['fal'] == 0 ? '' : i['fal']
        ]).toList(),
        headerDecoration: pw.BoxDecoration(color: color),
        headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
        cellStyle: const pw.TextStyle(fontSize: 9),
        cellHeight: 18,
        columnWidths: {2: const pw.FixedColumnWidth(220)},
      ),
    ]);
  }

  pw.Widget _buildFirma(String texto) {
    return pw.Column(children: [
      pw.Container(width: 150, border: const pw.Border(top: pw.BorderSide())),
      pw.Text(texto, style: const pw.TextStyle(fontSize: 10)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Ajustes Manuales"),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, size: 28), 
            onPressed: _exportarPDF,
            tooltip: 'Exportar Reporte PDF',
          ),
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
            final letraP = asignaciones.value[clave];
            double diff = (p['fisica']?.toDouble() ?? 0.0) - (p['existencia']?.toDouble() ?? 0.0);

            return Column(
              children: [
                // Separador alfabético visual
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
                    child: Text(letraP ?? '', style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ),
                  title: Text(p['descripcion'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  subtitle: Text("Clave: $clave | Sis: ${p['existencia'].toInt()} | Fis: ${p['fisica'].toInt()}"),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.black12), 
                      borderRadius: BorderRadius.circular(4)
                    ),
                    child: Text(
                      _calcularRegistro(p), 
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)
                    ),
                  ),
                  onTap: () {
                    // Lógica reactiva para Signals v6.3.0
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
            selectedColor: Colors.blue.withOpacity(0.2),
          ),
        )).toList(),
      ),
    );
  }
}
