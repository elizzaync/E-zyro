// DTOs del módulo Personal/RR.HH. (Punto 3.1 — historial consolidado).

class Empleado {
  final String id;
  final String usuarioId;
  final String? nombre;
  final String? codigo;
  final String? cargo;
  final String? area;
  final String? tipo;
  final String? fechaIngreso;
  final String? fechaFinContrato;
  final bool activo;
  final String? fotoUrl;

  const Empleado({
    required this.id,
    required this.usuarioId,
    this.nombre,
    this.codigo,
    this.cargo,
    this.area,
    this.tipo,
    this.fechaIngreso,
    this.fechaFinContrato,
    this.activo = true,
    this.fotoUrl,
  });

  factory Empleado.fromJson(Map<String, dynamic> j) => Empleado(
        id: j['id']?.toString() ?? '',
        usuarioId: j['usuario_id']?.toString() ?? '',
        nombre: j['nombre']?.toString(),
        codigo: j['codigo']?.toString(),
        cargo: j['cargo']?.toString(),
        area: j['area']?.toString(),
        tipo: j['tipo']?.toString(),
        fechaIngreso: j['fecha_ingreso']?.toString(),
        fechaFinContrato: j['fecha_fin_contrato']?.toString(),
        activo: j['activo'] as bool? ?? true,
        fotoUrl: j['foto_url']?.toString(),
      );
}

class ContratoItem {
  final String tipo;
  final String? fechaInicio;
  final String? fechaFin;
  final String? estado;

  const ContratoItem({required this.tipo, this.fechaInicio, this.fechaFin, this.estado});

  factory ContratoItem.fromJson(Map<String, dynamic> j) => ContratoItem(
        tipo: j['tipo']?.toString() ?? '',
        fechaInicio: j['fecha_inicio']?.toString(),
        fechaFin: j['fecha_fin']?.toString(),
        estado: j['estado']?.toString(),
      );
}

class AsistenciaResumen {
  final int total;
  final int validados;
  final int pendientes;
  final int rechazados;

  const AsistenciaResumen({this.total = 0, this.validados = 0, this.pendientes = 0, this.rechazados = 0});

  factory AsistenciaResumen.fromJson(Map<String, dynamic> j) => AsistenciaResumen(
        total: (j['total'] as num?)?.toInt() ?? 0,
        validados: (j['validados'] as num?)?.toInt() ?? 0,
        pendientes: (j['pendientes'] as num?)?.toInt() ?? 0,
        rechazados: (j['rechazados'] as num?)?.toInt() ?? 0,
      );
}

class MarcacionItem {
  final String tipo;
  final String? fechaHora;
  final String? estado;

  const MarcacionItem({required this.tipo, this.fechaHora, this.estado});

  factory MarcacionItem.fromJson(Map<String, dynamic> j) => MarcacionItem(
        tipo: j['tipo']?.toString() ?? '',
        fechaHora: j['fecha_hora']?.toString(),
        estado: j['estado']?.toString(),
      );
}

class SolicitudItem {
  final String tipo;
  final String? estado;
  final String? fechaInicio;
  final String? fechaFin;
  final String? urlPdf;

  const SolicitudItem({required this.tipo, this.estado, this.fechaInicio, this.fechaFin, this.urlPdf});

  factory SolicitudItem.fromJson(Map<String, dynamic> j) => SolicitudItem(
        tipo: j['tipo']?.toString() ?? '',
        estado: j['estado']?.toString(),
        fechaInicio: j['fecha_inicio']?.toString(),
        fechaFin: j['fecha_fin']?.toString(),
        urlPdf: j['url_pdf']?.toString(),
      );
}

class EppEntregaItem {
  final String? fecha;
  final String? estado;
  final int items;
  final String? pdfUrl;

  const EppEntregaItem({this.fecha, this.estado, this.items = 0, this.pdfUrl});

  factory EppEntregaItem.fromJson(Map<String, dynamic> j) => EppEntregaItem(
        fecha: j['fecha']?.toString(),
        estado: j['estado']?.toString(),
        items: (j['items'] as num?)?.toInt() ?? 0,
        pdfUrl: j['pdf_url']?.toString(),
      );
}

class EvaluacionResumen {
  final int total;
  final double? promedioGeneral;
  final String? ultimoPeriodo;

  const EvaluacionResumen({this.total = 0, this.promedioGeneral, this.ultimoPeriodo});

  factory EvaluacionResumen.fromJson(Map<String, dynamic> j) => EvaluacionResumen(
        total: (j['total'] as num?)?.toInt() ?? 0,
        promedioGeneral: (j['promedio_general'] as num?)?.toDouble(),
        ultimoPeriodo: j['ultimo_periodo']?.toString(),
      );
}

class HistorialPersonal {
  final Empleado empleado;
  final List<ContratoItem> contratos;
  final AsistenciaResumen asistencia;
  final List<MarcacionItem> marcaciones;
  final List<SolicitudItem> solicitudes;
  final List<EppEntregaItem> epp;
  final EvaluacionResumen evaluaciones;

  const HistorialPersonal({
    required this.empleado,
    required this.contratos,
    required this.asistencia,
    required this.marcaciones,
    required this.solicitudes,
    required this.epp,
    required this.evaluaciones,
  });

  factory HistorialPersonal.fromJson(Map<String, dynamic> j) => HistorialPersonal(
        empleado: Empleado.fromJson(j['empleado'] as Map<String, dynamic>),
        contratos: ((j['contratos'] as List?) ?? [])
            .map((e) => ContratoItem.fromJson(e as Map<String, dynamic>)).toList(),
        asistencia: AsistenciaResumen.fromJson((j['asistencia'] as Map<String, dynamic>?) ?? {}),
        marcaciones: ((j['marcaciones'] as List?) ?? [])
            .map((e) => MarcacionItem.fromJson(e as Map<String, dynamic>)).toList(),
        solicitudes: ((j['solicitudes'] as List?) ?? [])
            .map((e) => SolicitudItem.fromJson(e as Map<String, dynamic>)).toList(),
        epp: ((j['epp'] as List?) ?? [])
            .map((e) => EppEntregaItem.fromJson(e as Map<String, dynamic>)).toList(),
        evaluaciones: EvaluacionResumen.fromJson((j['evaluaciones'] as Map<String, dynamic>?) ?? {}),
      );
}
