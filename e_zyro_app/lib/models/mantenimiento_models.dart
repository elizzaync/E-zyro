enum FotoTipo { antes, durante, despues }

extension FotoTipoLabel on FotoTipo {
  String get label => switch (this) {
        FotoTipo.antes => 'ANTES',
        FotoTipo.durante => 'DURANTE',
        FotoTipo.despues => 'DESPUÉS',
      };

  String get apiValue => switch (this) {
        FotoTipo.antes => 'ANTES',
        FotoTipo.durante => 'DURANTE',
        FotoTipo.despues => 'DESPUES',
      };
}

// ── Resultado de captura (path + geolocalización) ─────────────────────────────

class CaptureResult {
  final String path;
  final double? lat;
  final double? lng;
  final double? accuracy;

  const CaptureResult({
    required this.path,
    this.lat,
    this.lng,
    this.accuracy,
  });
}

// ── Equipo ────────────────────────────────────────────────────────────────────

class EquipoItem {
  final String id;
  final String nombre;
  final String? descripcion;
  final String? ubicacion;
  final String estado; // 'pendiente' | 'en_proceso' | 'completado'

  const EquipoItem({
    required this.id,
    required this.nombre,
    this.descripcion,
    this.ubicacion,
    required this.estado,
  });

  factory EquipoItem.fromJson(Map<String, dynamic> j) => EquipoItem(
        id: j['id'] as String? ?? '',
        nombre: j['nombre'] as String? ?? '',
        descripcion: j['descripcion'] as String?,
        ubicacion: j['ubicacion'] as String?,
        estado: j['estado'] as String? ?? 'pendiente',
      );
}

// ── Paso del checklist ────────────────────────────────────────────────────────

class PasoChecklist {
  final String id;
  final String nombre;
  final String descripcion;
  final int orden;
  final String estado; // 'pendiente' | 'completado'
  final List<String> fotosUrls;

  const PasoChecklist({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.orden,
    required this.estado,
    required this.fotosUrls,
  });

  factory PasoChecklist.fromJson(Map<String, dynamic> j) => PasoChecklist(
        id: j['id'] as String? ?? '',
        nombre: j['nombre'] as String? ?? '',
        descripcion: j['descripcion'] as String? ?? '',
        orden: j['orden'] as int? ?? 0,
        estado: j['estado'] as String? ?? 'pendiente',
        fotosUrls: (j['fotos_urls'] as List? ?? []).cast<String>(),
      );
}

// ── Checklist completo de un equipo ──────────────────────────────────────────

class ChecklistEquipo {
  final String equipoId;
  final String equipoNombre;
  final List<PasoChecklist> pasos;

  const ChecklistEquipo({
    required this.equipoId,
    required this.equipoNombre,
    required this.pasos,
  });

  factory ChecklistEquipo.fromJson(Map<String, dynamic> j) => ChecklistEquipo(
        equipoId: j['equipo_id'] as String? ?? '',
        equipoNombre: j['equipo_nombre'] as String? ?? '',
        pasos: (j['pasos'] as List? ?? [])
            .map((e) => PasoChecklist.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ── Máquina de estados de fotos ANTES/DURANTE/DESPUÉS ────────────────────────

class FotosMaquina {
  String? antes;
  String? durante;
  String? despues;

  FotosMaquina({this.antes, this.durante, this.despues});

  bool get isComplete => antes != null && durante != null && despues != null;

  bool canCapture(FotoTipo tipo) => switch (tipo) {
        FotoTipo.antes => antes == null,
        FotoTipo.durante => antes != null && durante == null,
        FotoTipo.despues => durante != null && despues == null,
      };

  String? pathFor(FotoTipo tipo) => switch (tipo) {
        FotoTipo.antes => antes,
        FotoTipo.durante => durante,
        FotoTipo.despues => despues,
      };

  void set(FotoTipo tipo, String path) {
    switch (tipo) {
      case FotoTipo.antes:
        antes = path;
      case FotoTipo.durante:
        durante = path;
      case FotoTipo.despues:
        despues = path;
    }
  }

  Map<String, dynamic> toJson() => {
        'antes': antes,
        'durante': durante,
        'despues': despues,
      };

  factory FotosMaquina.fromJson(Map<String, dynamic> j) => FotosMaquina(
        antes: j['antes'] as String?,
        durante: j['durante'] as String?,
        despues: j['despues'] as String?,
      );
}

// ── Cola de evidencias pendientes (offline) ───────────────────────────────────

class EvidenciaPendiente {
  final String id; // uuid local
  final String pasoId;
  final FotoTipo tipo;
  final String filePath;
  final DateTime createdAt;
  final double? lat;
  final double? lng;
  final double? accuracy;

  const EvidenciaPendiente({
    required this.id,
    required this.pasoId,
    required this.tipo,
    required this.filePath,
    required this.createdAt,
    this.lat,
    this.lng,
    this.accuracy,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'paso_id': pasoId,
        'tipo': tipo.apiValue,
        'file_path': filePath,
        'created_at': createdAt.toIso8601String(),
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (accuracy != null) 'accuracy': accuracy,
      };

  factory EvidenciaPendiente.fromJson(Map<String, dynamic> j) =>
      EvidenciaPendiente(
        id: j['id'] as String,
        pasoId: j['paso_id'] as String,
        tipo: _tipoFromApi(j['tipo'] as String),
        filePath: j['file_path'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        accuracy: (j['accuracy'] as num?)?.toDouble(),
      );

  static FotoTipo _tipoFromApi(String v) => switch (v) {
        'ANTES' => FotoTipo.antes,
        'DURANTE' => FotoTipo.durante,
        _ => FotoTipo.despues,
      };
}
