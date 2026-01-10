class Product {
  final String clave;
  final String codbar;
  final String descripcion;
  final String marca;
  final String unit;
  final double existencia;
  final double fisica;

  Product({
    required this.clave,
    required this.codbar,
    required this.descripcion,
    required this.marca,
    required this.unit,
    required this.existencia,
    this.fisica = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'clave': clave,
      'codbar': codbar,
      'descripcion': descripcion,
      'marca': marca,
      'unit': unit,
      'existencia': existencia,
      'fisica': fisica,
    };
  }
}
