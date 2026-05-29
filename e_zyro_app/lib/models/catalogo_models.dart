/// DTOs de catálogos base (Fase 0): Ubicación, Zona, Área.
class Ubicacion {
  final String id;
  final String nombre;
  final String? region;
  const Ubicacion({required this.id, required this.nombre, this.region});
  factory Ubicacion.fromJson(Map<String, dynamic> j) => Ubicacion(
        id: j['id']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? '',
        region: j['region']?.toString(),
      );
}

class Zona {
  final String id;
  final String nombre;
  final String? tipo;
  final String? ubicacionId;
  final String? ubicacionNombre;
  const Zona({required this.id, required this.nombre, this.tipo, this.ubicacionId, this.ubicacionNombre});
  factory Zona.fromJson(Map<String, dynamic> j) => Zona(
        id: j['id']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? '',
        tipo: j['tipo']?.toString(),
        ubicacionId: j['ubicacion_id']?.toString(),
        ubicacionNombre: j['ubicacion_nombre']?.toString(),
      );
}

class Area {
  final String id;
  final String nombre;
  const Area({required this.id, required this.nombre});
  factory Area.fromJson(Map<String, dynamic> j) => Area(
        id: j['id']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? '',
      );
}
