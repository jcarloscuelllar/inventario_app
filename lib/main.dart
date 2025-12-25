import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  runApp(const MyApp());
}

const String CODIGO_PRUEBA = '4006000015897';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ScannerPage(),
    );
  }
}

/* =========================
   PANTALLA ESCÁNER
========================= */
class ScannerPage extends StatelessWidget {
  const ScannerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear producto')),
      body: MobileScanner(
        onDetect: (capture) {
          final String? code = capture.barcodes.first.rawValue;

          if (code == null) return;

          if (code == CODIGO_PRUEBA) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ConteoPage(),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Código no reconocido: $code')),
            );
          }
        },
      ),
    );
  }
}

/* =========================
   PANTALLA CONTEO
========================= */
class ConteoPage extends StatefulWidget {
  const ConteoPage({super.key});

  @override
  State<ConteoPage> createState() => _ConteoPageState();
}

class _ConteoPageState extends State<ConteoPage> {
  int cantidad = 0;

  void incrementar() {
    setState(() {
      cantidad++;
    });
  }

  void decrementar() {
    if (cantidad > 0) {
      setState(() {
        cantidad--;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conteo físico')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Cantidad',
              style: TextStyle(fontSize: 22),
            ),
            const SizedBox(height: 20),
            Text(
              cantidad.toString(),
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 30),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove, size: 40),
                  onPressed: decrementar,
                ),
                const SizedBox(width: 40),
                IconButton(
                  icon: const Icon(Icons.add, size: 40),
                  onPressed: incrementar,
                ),
              ],
            ),

            const SizedBox(height: 40),

            ElevatedButton(
              onPressed: () {
                // Aquí después irá la calculadora
              },
              child: const Text('Calcular'),
            ),
          ],
        ),
      ),
    );
  }
}