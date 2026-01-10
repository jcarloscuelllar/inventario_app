import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final controller = MobileScannerController();
  bool isDetected = false;
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Escaneando...")),
      body: MobileScanner(
        controller: controller,
        onDetect: (cap) {
          if (isDetected) return;
          final code = cap.barcodes.first.rawValue;
          if (code != null) {
            isDetected = true;
            Navigator.pop(context, code);
          }
        },
      ),
    );
  }
}
