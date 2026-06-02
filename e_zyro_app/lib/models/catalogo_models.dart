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
  final String? ubicacionId;
  final String? zonaId;
  final String? ubicacionNombre;
  final String? zonaNombre;
  const Area({
    required this.id,
    required this.nombre,
    this.ubicacionId,
    this.zonaId,
    this.ubicacionNombre,
    this.zonaNombre,
  });
  factory Area.fromJson(Map<String, dynamic> j) => Area(
        id: j['id']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? '',
        ubicacionId: j['ubicacion_id']?.toString(),
        zonaId: j['zona_id']?.toString(),
        ubicacionNombre: j['ubicacion_nombre']?.toString(),
        zonaNombre: j['zona_nombre']?.toString(),
      );
}

// ── Árbol jerárquico (GET /catalogos/arbol) ────────────────────────────────
/// Nodo área dentro del árbol (solo id + nombre).
class AreaNodo {
  final String id;
  final String nombre;
  const AreaNodo({required this.id, required this.nombre});
  factory AreaNodo.fromJson(Map<String, dynamic> j) => AreaNodo(
        id: j['id']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? '',
      );
}

/// Nodo zona con sus áreas.
class ZonaArbol {
  final String id;
  final String nombre;
  final String? tipo;
  final List<AreaNodo> areas;
  const ZonaArbol({required this.id, required this.nombre, this.tipo, this.areas = const []});
  factory ZonaArbol.fromJson(Map<String, dynamic> j) => ZonaArbol(
        id: j['id']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? '',
        tipo: j['tipo']?.toString(),
        areas: ((j['areas'] as List?) ?? [])
            .map((e) => AreaNodo.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Nodo ubicación con sus zonas (raíz del árbol geográfico).
class UbicacionArbol {
  final String id;
  final String nombre;
  final String? region;
  final List<ZonaArbol> zonas;
  const UbicacionArbol({required this.id, required this.nombre, this.region, this.zonas = const []});
  factory UbicacionArbol.fromJson(Map<String, dynamic> j) => UbicacionArbol(
        id: j['id']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? '',
        region: j['region']?.toString(),
        zonas: ((j['zonas'] as List?) ?? [])
            .map((e) => ZonaArbol.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
