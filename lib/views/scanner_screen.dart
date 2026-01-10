import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  // En la v5.x se recomienda inicializar el controlador así
  final MobileScannerController controller = MobileScannerController();
  bool isDetected = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Escaneando..."),
        actions: [
          // Corrección del Torch: Escuchamos directamente al controlador
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (context, state, child) {
              final torchState = state.torchState;
              return IconButton(
                icon: Icon(
                  torchState == TorchState.on ? Icons.flash_on : Icons.flash_off,
                ),
                onPressed: () => controller.toggleTorch(),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios),
            onPressed: () => controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: (cap) {
              if (isDetected) return;
              // Acceso correcto a los barcodes en v5.x
              final code = cap.barcodes.first.rawValue;
              if (code != null) {
                isDetected = true;
                Navigator.pop(context, code);
              }
            },
          ),
          // Cuadro guía visual
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
