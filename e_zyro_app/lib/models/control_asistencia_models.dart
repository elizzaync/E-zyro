// Modelos del Control de Asistencias (supervisión) — alimentan
// pantalla_control_asistencias.dart desde /asistencia/control-diario y /turnos.

class ControlAsistenciaDia {
  final String fecha;
  final ControlResumen resumen;
  final List<ControlItem> items;

  const ControlAsistenciaDia({
    required this.fecha,
    required this.resumen,
    required this.items,
  });

  factory ControlAsistenciaDia.fromJson(Map<String, dynamic> j) =>
      ControlAsistenciaDia(
        fecha: j['fecha'] as String? ?? '',
        resumen: ControlResumen.fromJson(
            (j['resumen'] as Map<String, dynamic>?) ?? const {}),
        items: ((j['items'] as List?) ?? const [])
            .map((e) => ControlItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ControlResumen {
  final int total;
  final int completos;
  final int incompletos;
  final int enCurso;
  final int ausentes;

  const ControlResumen({
    this.total = 0,
    this.completos = 0,
    this.incompletos = 0,
    this.enCurso = 0,
    this.ausentes = 0,
  });

  factory ControlResumen.fromJson(Map<String, dynamic> j) => ControlResumen(
        total: j['total'] as int? ?? 0,
        completos: j['completos'] as int? ?? 0,
        incompletos: j['incompletos'] as int? ?? 0,
        enCurso: j['en_curso'] as int? ?? 0,
        ausentes: j['ausentes'] as int? ?? 0,
      );
}

class ControlItem {
  final String empleadoId;
  final String nombre;
  final String apellido;
  final String cargo;
  final String tipo;
  final String turnoNombre;
  final bool esExcepcion;
  final String horaEntradaTurno;
  final String horaSalidaTurno;
  final String? entradaHora;
  final String? salidaHora;
  final String? inicioAlmuerzoHora;
  final String? finAlmuerzoHora;
  final int? minutosAlmuerzo;
  final int? minutosTrabajados;
  final int minutosRequeridos;
  final double horasRequeridas;
  final bool llegoTarde;
  final int minutosTarde;
  final bool salioTemprano;
  final int minutosAntesSalida;
  final String estado; // completo | incompleto | en_curso | ausente
  final bool cumple;

  const ControlItem({
    required this.empleadoId,
    required this.nombre,
    required this.apellido,
    required this.cargo,
    required this.tipo,
    required this.turnoNombre,
    required this.esExcepcion,
    this.horaEntradaTurno = '',
    this.horaSalidaTurno = '',
    this.entradaHora,
    this.salidaHora,
    this.inicioAlmuerzoHora,
    this.finAlmuerzoHora,
    this.minutosAlmuerzo,
    this.minutosTrabajados,
    required this.minutosRequeridos,
    required this.horasRequeridas,
    this.llegoTarde = false,
    this.minutosTarde = 0,
    this.salioTemprano = false,
    this.minutosAntesSalida = 0,
    required this.estado,
    required this.cumple,
  });

  /// Horario designado, formato "HH:MM–HH:MM".
  String get turnoHorario => (horaEntradaTurno.isNotEmpty && horaSalidaTurno.isNotEmpty)
      ? '$horaEntradaTurno–$horaSalidaTurno'
      : '';

  String get nombreCompleto => '$nombre $apellido'.trim();

  /// Horas:minutos trabajados en formato "Xh YYm" (o "—" si aún no aplica).
  String get trabajadoLabel => _hm(minutosTrabajados);

  String get requeridoLabel => _hm(minutosRequeridos);

  static String _hm(int? mins) {
    if (mins == null) return '—';
    final h = mins ~/ 60;
    final m = mins % 60;
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  factory ControlItem.fromJson(Map<String, dynamic> j) => ControlItem(
        empleadoId: j['empleado_id'] as String? ?? '',
        nombre: j['nombre'] as String? ?? '',
        apellido: j['apellido'] as String? ?? '',
        cargo: j['cargo'] as String? ?? '',
        tipo: j['tipo'] as String? ?? '',
        turnoNombre: j['turno_nombre'] as String? ?? '',
        esExcepcion: j['es_excepcion'] as bool? ?? false,
        horaEntradaTurno: j['hora_entrada_turno'] as String? ?? '',
        horaSalidaTurno: j['hora_salida_turno'] as String? ?? '',
        entradaHora: j['entrada_hora'] as String?,
        salidaHora: j['salida_hora'] as String?,
        inicioAlmuerzoHora: j['inicio_almuerzo_hora'] as String?,
        finAlmuerzoHora: j['fin_almuerzo_hora'] as String?,
        minutosAlmuerzo: j['minutos_almuerzo'] as int?,
        minutosTrabajados: j['minutos_trabajados'] as int?,
        minutosRequeridos: j['minutos_requeridos'] as int? ?? 0,
        horasRequeridas: (j['horas_requeridas'] as num? ?? 0).toDouble(),
        llegoTarde: j['llego_tarde'] as bool? ?? false,
        minutosTarde: j['minutos_tarde'] as int? ?? 0,
        salioTemprano: j['salio_temprano'] as bool? ?? false,
        minutosAntesSalida: j['minutos_antes_salida'] as int? ?? 0,
        estado: j['estado'] as String? ?? 'ausente',
        cumple: j['cumple'] as bool? ?? false,
      );
}

class TurnoItem {
  final String id;
  final String nombre;
  final String horaEntrada;
  final String horaSalida;
  final int duracionAlmuerzoMinutos;
  final int toleranciaMinutos;
  final double horasNetas;

  const TurnoItem({
    required this.id,
    required this.nombre,
    required this.horaEntrada,
    required this.horaSalida,
    required this.duracionAlmuerzoMinutos,
    required this.toleranciaMinutos,
    required this.horasNetas,
  });

  factory TurnoItem.fromJson(Map<String, dynamic> j) => TurnoItem(
        id: j['id'] as String? ?? '',
        nombre: j['nombre'] as String? ?? '',
        horaEntrada: j['hora_entrada'] as String? ?? '',
        horaSalida: j['hora_salida'] as String? ?? '',
        duracionAlmuerzoMinutos: j['duracion_almuerzo_minutos'] as int? ?? 0,
        toleranciaMinutos: j['tolerancia_minutos'] as int? ?? 0,
        horasNetas: (j['horas_netas'] as num? ?? 0).toDouble(),
      );
}
