import 'package:flutter/material.dart';
import '../controllers/db_helper.dart';

class AddProductScreen extends StatefulWidget {
  final String? initialCode;
  const AddProductScreen({super.key, this.initialCode});
  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _claveCtrl = TextEditingController();
  final _barCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _marcaCtrl = TextEditingController();
  final _stockCtrl = TextEditingController(text: "0");

  @override
  void initState() {
    super.initState();
    if (widget.initialCode != null) {
      _barCtrl.text = widget.initialCode!;
      _claveCtrl.text = widget.initialCode!;
    }
  }

  void _save() async {
    if (_formKey.currentState!.validate()) {
      await DbHelper.insertProduct({
        'clave': _claveCtrl.text,
        'codbar': _barCtrl.text,
        'descripcion': _descCtrl.text,
        'marca': _marcaCtrl.text,
        'unit': 'PZ',
        'existencia': double.tryParse(_stockCtrl.text) ?? 0.0,
        'fisica': 0.0
      });
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Nuevo Producto")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(controller: _claveCtrl, decoration: const InputDecoration(labelText: "Clave *"), validator: (v) => v!.isEmpty ? "Requerido" : null),
              TextFormField(controller: _barCtrl, decoration: const InputDecoration(labelText: "Código de Barras")),
              TextFormField(controller: _descCtrl, decoration: const InputDecoration(labelText: "Descripción *"), validator: (v) => v!.isEmpty ? "Requerido" : null),
              TextFormField(controller: _marcaCtrl, decoration: const InputDecoration(labelText: "Marca")),
              TextFormField(controller: _stockCtrl, decoration: const InputDecoration(labelText: "Stock en Sistema"), keyboardType: TextInputType.number),
              const SizedBox(height: 30),
              ElevatedButton(onPressed: _save, child: const Text("GUARDAR")),
            ],
          ),
        ),
      ),
    );
  }
}
