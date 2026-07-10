// Modelos de Legajo Digital (RR.HH.). Consumen los routers /rrhh/legajo/* y,
// para "mis documentos" propios, /dashboard/perfil/boletas — ambos devuelven
// el mismo DocumentoLaboral pero con nombres de campo distintos, ver
// DocumentoLegajo.fromJson.
import 'package:intl/intl.dart';

class LegajoEmpleadoResumen {
  final String id, nombreCompleto, cargo, area, estado, iniciales, fotoUrl, ultimaActualizacion;
  final int documentosCount;

  LegajoEmpleadoResumen({
    required this.id, required this.nombreCompleto, required this.cargo,
    required this.area, required this.estado, required this.iniciales,
    required this.fotoUrl, required this.ultimaActualizacion, required this.documentosCount,
  });

  factory LegajoEmpleadoResumen.fromJson(Map<String, dynamic> j) => LegajoEmpleadoResumen(
        id: j['id'].toString(),
        nombreCompleto: j['nombreCompleto']?.toString() ?? '',
        cargo: j['cargo']?.toString() ?? '',
        area: j['area']?.toString() ?? '',
        estado: j['estado']?.toString() ?? 'Activo',
        iniciales: j['iniciales']?.toString() ?? '?',
        fotoUrl: j['fotoUrl']?.toString() ?? '',
        ultimaActualizacion: j['ultimaActualizacion']?.toString() ?? '—',
        documentosCount: (j['documentosCount'] as num?)?.toInt() ?? 0,
      );
}

class LegajoEmpleadoDetalle {
  final String id, nombreCompleto, cargo, area, estado, iniciales, fotoUrl;
  final int total, contratos, firmados, pendientesFirma;
  final List<DocumentoLegajo> documentos;

  LegajoEmpleadoDetalle({
    required this.id, required this.nombreCompleto, required this.cargo,
    required this.area, required this.estado, required this.iniciales, required this.fotoUrl,
    required this.total, required this.contratos, required this.firmados,
    required this.pendientesFirma, required this.documentos,
  });

  factory LegajoEmpleadoDetalle.fromJson(Map<String, dynamic> j) {
    final emp = j['empleado'] as Map<String, dynamic>? ?? {};
    final stats = j['stats'] as Map<String, dynamic>? ?? {};
    return LegajoEmpleadoDetalle(
      id: emp['id']?.toString() ?? '',
      nombreCompleto: emp['nombreCompleto']?.toString() ?? '',
      cargo: emp['cargo']?.toString() ?? '',
      area: emp['area']?.toString() ?? '',
      estado: emp['estado']?.toString() ?? 'Activo',
      iniciales: emp['iniciales']?.toString() ?? '?',
      fotoUrl: emp['fotoUrl']?.toString() ?? '',
      total: (stats['total'] as num?)?.toInt() ?? 0,
      contratos: (stats['contratos'] as num?)?.toInt() ?? 0,
      firmados: (stats['firmados'] as num?)?.toInt() ?? 0,
      pendientesFirma: (stats['pendientes_firma'] as num?)?.toInt() ?? 0,
      documentos: ((j['documentos'] ?? []) as List)
          .map((e) => DocumentoLegajo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Un documento del legajo. Cubre dos formas de respuesta del backend:
/// - GET /rrhh/legajo/* (admin): nombre, url_archivo, fecha_emision (ISO).
/// - GET /dashboard/perfil/boletas (propio): titulo, url, fecha (ya formateada).
class DocumentoLegajo {
  final String id, tipo, nombre, urlArchivo;
  final String? fechaEmisionIso;
  final String? fechaDisplay;
  final bool requiereFirma;

  DocumentoLegajo({
    required this.id, required this.tipo, required this.nombre, required this.urlArchivo,
    this.fechaEmisionIso, this.fechaDisplay, required this.requiereFirma,
  });

  factory DocumentoLegajo.fromJson(Map<String, dynamic> j) => DocumentoLegajo(
        id: j['id'].toString(),
        tipo: j['tipo']?.toString() ?? 'Otro',
        nombre: (j['nombre'] ?? j['titulo'])?.toString() ?? '—',
        urlArchivo: (j['url_archivo'] ?? j['url'])?.toString() ?? '',
        fechaEmisionIso: j['fecha_emision']?.toString(),
        fechaDisplay: j['fecha']?.toString(),
        requiereFirma: j['requiere_firma'] == true,
      );

  String get fechaTexto {
    if (fechaDisplay != null && fechaDisplay!.isNotEmpty) return fechaDisplay!;
    final d = fechaEmisionIso != null ? DateTime.tryParse(fechaEmisionIso!) : null;
    return d != null ? DateFormat('dd/MM/yyyy').format(d) : '—';
  }
}
