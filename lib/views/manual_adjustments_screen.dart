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
    itemsOrdenados.sort((a, b) => a['descripcion'].toString().compareTo(b['descripcion'].toString()));
  }

  Map<String, dynamic> _obtenerDetalleAjuste(Map<String, dynamic> p) {
    final clave = p['clave'].toString();
    double stockSistema = (p['existencia']?.toDouble() ?? 0.0);
    double stockFisico = (p['fisica']?.toDouble() ?? 0.0);
    double diffOriginal = stockFisico - stockSistema;

    final letra = asignaciones.value[clave];
    if (letra == null) {
      return {
        'texto': "${diffOriginal > 0 ? '+' : ''}${diffOriginal.toInt()}",
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
    String rStr = residuo == 0 ? "" : "${residuo > 0 ? '+' : ''}${residuo.toInt()} ";
    String aStr = (ajuste == 0) ? "" : "${ajuste > 0 ? '+' : ''}${ajuste.toInt()}$letra";

    return {
      'texto': "$rStr$aStr".trim(),
      'ajuste': ajuste,
      'residuo': residuo,
      'letra': letra
    };
  }

  Future<void> _exportarPDF() async {
    final pdf = pw.Document();
    List<Map<String, dynamic>> tMatch = [];
    List<Map<String, dynamic>> tSobrante = [];
    List<Map<String, dynamic>> tFaltante = [];

    for (var p in itemsOrdenados) {
      final detalle = _obtenerDetalleAjuste(p);
      final double ajuste = detalle['ajuste'];
      final double residuo = detalle['residuo'];
      final int sis = (p['existencia']?.toInt() ?? 0);
      final int fis = (p['fisica']?.toInt() ?? 0);

      Map<String, dynamic> dataFila(String regStr, double valorDiferencia, String letra) {
        return {
          'clave': p['clave'].toString(),
          'reg': regStr,
          'desc': p['descripcion'].toString(),
          'sis': sis.toString(),
          'fis': fis.toString(),
          'sob': valorDiferencia > 0 ? valorDiferencia.toInt().toString() : '',
          'fal': valorDiferencia < 0 ? valorDiferencia.abs().toInt().toString() : '',
          'letra': letra,
          'valor': valorDiferencia, // Para ordenamiento
        };
      }

      if (ajuste != 0) {
        tMatch.add(dataFila("${ajuste > 0 ? '+' : ''}${ajuste.toInt()}${detalle['letra']}", ajuste, detalle['letra']));
      }

      if (residuo != 0) {
        final fila = dataFila("${residuo > 0 ? '+' : ''}${residuo.toInt()}", residuo, "");
        residuo > 0 ? tSobrante.add(fila) : tFaltante.add(fila);
      }
    }

    // --- ORDENAMIENTO ESPECIAL TABLA 1 (MATCH) ---
    // 1. Por Letra (A, B, C...).
    // 2. Por Valor (Sobrantes primero que faltantes: + antes que -)
    tMatch.sort((a, b) {
      int compLetra = a['letra'].compareTo(b['letra']);
      if (compLetra != 0) return compLetra;
      return (b['valor'] as double).compareTo(a['valor'] as double);
    });

    // --- ORDENAMIENTO POR DESCRIPCIÓN PARA LAS OTRAS TABLAS ---
    tSobrante.sort((a, b) => a['desc'].compareTo(b['desc']));
    tFaltante.sort((a, b) => a['desc'].compareTo(b['desc']));

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.letter.landscape,
      margin: const pw.EdgeInsets.all(25),
      build: (context) => [
        pw.Header(level: 0, child: pw.Text("AJUSTES DE INVENTARIO")),
        _buildPdfTable("1. AJUSTE UNO POR OTRO", tMatch, PdfColors.blue900),
        _buildPdfTable("2. AJUSTE POR SOBRANTE DE MERCANCIA", tSobrante, PdfColors.green900),
        _buildPdfTable("3. AJUSTE POR FALTANTE DE MERCANCIA", tFaltante, PdfColors.red900),
        pw.SizedBox(height: 40),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceAround, children: [
          _buildFirma("Inventarista"),
          _buildFirma("Gerencia"),
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
        child: pw.Text(titulo, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: color, fontSize: 10)),
      ),
      pw.TableHelper.fromTextArray(
        headers: ['CLAVE', 'REGISTRO', 'DESCRIPCION', 'SIS', 'FIS', 'SOB', 'FAL'],
        data: data.map((i) => [
          i['clave'], i['reg'], i['desc'], i['sis'], i['fis'], i['sob'], i['fal']
        ]).toList(),
        headerDecoration: pw.BoxDecoration(color: color),
        headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8),
        cellStyle: const pw.TextStyle(fontSize: 8),
        columnWidths: {
          0: const pw.FlexColumnWidth(1.5),
          1: const pw.FlexColumnWidth(1.5),
          2: const pw.FlexColumnWidth(5),
          3: const pw.FlexColumnWidth(1),
          4: const pw.FlexColumnWidth(1),
          5: const pw.FlexColumnWidth(1),
          6: const pw.FlexColumnWidth(1),
        },
        cellAlignment: pw.Alignment.centerLeft,
        headerAlignment: pw.Alignment.center,
      ),
    ]);
  }

  pw.Widget _buildFirma(String texto) {
    return pw.Column(children: [
      pw.Container(width: 160, decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide()))),
      pw.SizedBox(height: 4),
      pw.Text(texto, style: const pw.TextStyle(fontSize: 9)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Ajustes"),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
            onPressed: () => asignaciones.value = {},
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
