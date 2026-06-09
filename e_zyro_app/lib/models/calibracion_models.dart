/// DTOs de Calibraciones + estado operativo de equipos (Fase 3).
class Calibracion {
  final String id;
  final String equipoId;
  final String? equipoNombre;
  final String? fechaUltima;
  final String? fechaProxima;
  final String? empresaResponsable;
  final String? certificadoUrl;
  final String? observacion;
  final int totalEventos;

  const Calibracion({
    required this.id,
    required this.equipoId,
    this.equipoNombre,
    this.fechaUltima,
    this.fechaProxima,
    this.empresaResponsable,
    this.certificadoUrl,
    this.observacion,
    this.totalEventos = 0,
  });

  factory Calibracion.fromJson(Map<String, dynamic> j) => Calibracion(
        id: j['id']?.toString() ?? '',
        equipoId: j['equipo_id']?.toString() ?? '',
        equipoNombre: j['equipo_nombre']?.toString(),
        fechaUltima: j['fecha_ultima']?.toString(),
        fechaProxima: j['fecha_proxima']?.toString(),
        empresaResponsable: j['empresa_responsable']?.toString(),
        certificadoUrl: j['certificado_url']?.toString(),
        observacion: j['observacion']?.toString(),
        totalEventos: (j['total_eventos'] as num?)?.toInt() ?? 0,
      );
}

/// Un evento del historial de calibraciones de un equipo.
class CalibracionEvento {
  final String id;
  final String equipoId;
  final String? equipoNombre;
  final String? fechaRealizada;
  final int? periodicidadMeses;
  final String? fechaProxima;
  final String? realizadaPor;
  final String? empresaResponsable;
  final String? numeroCertificado;
  final String? resultado;
  final String? certificadoUrl;
  final String? observacion;

  const CalibracionEvento({
    required this.id,
    required this.equipoId,
    this.equipoNombre,
    this.fechaRealizada,
    this.periodicidadMeses,
    this.fechaProxima,
    this.realizadaPor,
    this.empresaResponsable,
    this.numeroCertificado,
    this.resultado,
    this.certificadoUrl,
    this.observacion,
  });

  factory CalibracionEvento.fromJson(Map<String, dynamic> j) => CalibracionEvento(
        id: j['id']?.toString() ?? '',
        equipoId: j['equipo_id']?.toString() ?? '',
        equipoNombre: j['equipo_nombre']?.toString(),
        fechaRealizada: j['fecha_realizada']?.toString(),
        periodicidadMeses: (j['periodicidad_meses'] as num?)?.toInt(),
        fechaProxima: j['fecha_proxima']?.toString(),
        realizadaPor: j['realizada_por']?.toString(),
        empresaResponsable: j['empresa_responsable']?.toString(),
        numeroCertificado: j['numero_certificado']?.toString(),
        resultado: j['resultado']?.toString(),
        certificadoUrl: j['certificado_url']?.toString(),
        observacion: j['observacion']?.toString(),
      );
}

class EquipoEstado {
  final String equipoId;
  final String? nombre;
  final int cantidad;
  final int cantidadInoperativa;
  final String estadoOperativo;

  const EquipoEstado({
    required this.equipoId,
    this.nombre,
    required this.cantidad,
    required this.cantidadInoperativa,
    required this.estadoOperativo,
  });

  factory EquipoEstado.fromJson(Map<String, dynamic> j) => EquipoEstado(
        equipoId: j['equipo_id']?.toString() ?? '',
        nombre: j['nombre']?.toString(),
        cantidad: (j['cantidad'] as num?)?.toInt() ?? 0,
        cantidadInoperativa: (j['cantidad_inoperativa'] as num?)?.toInt() ?? 0,
        estadoOperativo: j['estado_operativo']?.toString() ?? 'operativo',
      );
}
