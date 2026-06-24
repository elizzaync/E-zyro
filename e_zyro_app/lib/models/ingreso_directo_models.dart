// Modelos del módulo "Ingreso Directo" de Logística.
//
// Contrato de API CONGELADO — las claves JSON son exactamente las que esperan
// los endpoints `/logistica/form-schema/{clase}`, `/logistica/articulos/by-codigo/{codigo}`
// y `POST /logistica/ingreso-directo`. fromJson/toJson son tolerantes a null;
// las fechas viajan como String "YYYY-MM-DD".

// ── FormSchema ────────────────────────────────────────────────────────────────

/// Una opción seleccionable en un campo `select` (catálogo).
class FormOpcion {
  final String id;
  final String nombre;
  const FormOpcion({required this.id, required this.nombre});

  factory FormOpcion.fromJson(Map<String, dynamic> j) => FormOpcion(
        id: j['id']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? '',
      );
}

/// Definición de un campo del formulario dinámico provisto por el backend.
class FormFieldDef {
  final String key;
  final String label;

  /// text | number | date | select | textarea | image | ip | mac
  final String inputType;
  final bool required;

  /// true → el valor va en un campo propio de [IngresoItem] (nombre, codigo,
  /// marcaId…). false → el valor va dentro de `atributos[key]`.
  final bool nativo;

  final String? grupo;
  final String? placeholder;
  final List<String>? sugerencias;
  final List<FormOpcion>? opciones;

  const FormFieldDef({
    required this.key,
    required this.label,
    required this.inputType,
    required this.required,
    required this.nativo,
    this.grupo,
    this.placeholder,
    this.sugerencias,
    this.opciones,
  });

  factory FormFieldDef.fromJson(Map<String, dynamic> j) => FormFieldDef(
        key: j['key']?.toString() ?? '',
        label: j['label']?.toString() ?? '',
        inputType: j['inputType']?.toString() ?? 'text',
        required: j['required'] as bool? ?? false,
        nativo: j['nativo'] as bool? ?? false,
        grupo: j['grupo']?.toString(),
        placeholder: j['placeholder']?.toString(),
        sugerencias: (j['sugerencias'] as List?)
            ?.map((e) => e.toString())
            .toList(),
        opciones: (j['opciones'] as List?)
            ?.map((e) => FormOpcion.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Esquema completo del formulario para una clase de artículo.
class FormSchemaOut {
  final String clase;
  final String titulo;
  final List<FormFieldDef> campos;

  const FormSchemaOut({
    required this.clase,
    required this.titulo,
    required this.campos,
  });

  factory FormSchemaOut.fromJson(Map<String, dynamic> j) => FormSchemaOut(
        clase: j['clase']?.toString() ?? '',
        titulo: j['titulo']?.toString() ?? '',
        campos: (j['campos'] as List? ?? [])
            .map((e) => FormFieldDef.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ── Destino ───────────────────────────────────────────────────────────────────

/// Destino del ingreso: a stock, a un servicio o a un correctivo.
class DestinoIngreso {
  /// stock | servicio | correctivo
  final String tipo;
  final String? servicioId;
  final String? correctivoId;

  const DestinoIngreso({
    required this.tipo,
    this.servicioId,
    this.correctivoId,
  });

  const DestinoIngreso.stock()
      : tipo = 'stock',
        servicioId = null,
        correctivoId = null;

  factory DestinoIngreso.fromJson(Map<String, dynamic> j) => DestinoIngreso(
        tipo: j['tipo']?.toString() ?? 'stock',
        servicioId: j['servicioId']?.toString(),
        correctivoId: j['correctivoId']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'tipo': tipo,
        if (servicioId != null) 'servicioId': servicioId,
        if (correctivoId != null) 'correctivoId': correctivoId,
      };

  DestinoIngreso copyWith({
    String? tipo,
    String? servicioId,
    String? correctivoId,
  }) =>
      DestinoIngreso(
        tipo: tipo ?? this.tipo,
        servicioId: servicioId ?? this.servicioId,
        correctivoId: correctivoId ?? this.correctivoId,
      );
}

// ── Item de ingreso (request) ───────────────────────────────────────────────

/// Un ítem a registrar dentro de un ingreso directo. Cubre material, equipo,
/// herramienta y equipo_tecnologico; los campos no aplicables quedan en null.
class IngresoItem {
  /// material | equipo | herramienta | equipo_tecnologico
  final String clase;

  /// nuevo | existente
  final String modo;
  final String? existenteId; // requerido si modo == 'existente'

  // Comunes
  final String? nombre;
  final String? codigo;
  final String? descripcion;
  final int cantidad;
  final double? precioCompra;
  final String? almacenId;
  final String? imagenUrl;

  // Material
  final String? categoriaId;
  final String? unidadId;
  final int? stockMinimo;

  // Equipo / herramienta / equipo_tecnologico
  final String? categoriaEquipoId;
  final String? marcaId;
  final String? modeloId;
  final String? marca;
  final String? numeroSerie;
  final String? ubicacionId;
  final String? zonaId;
  final String? areaId;
  final String? estado;
  final String? asignadoA;
  final String? fechaGarantia; // "YYYY-MM-DD"
  final String? observaciones;

  /// Atributos dinámicos (campos con nativo=false del FormSchema).
  final Map<String, dynamic>? atributos;

  const IngresoItem({
    required this.clase,
    this.modo = 'nuevo',
    this.existenteId,
    this.nombre,
    this.codigo,
    this.descripcion,
    this.cantidad = 1,
    this.precioCompra,
    this.almacenId,
    this.imagenUrl,
    this.categoriaId,
    this.unidadId,
    this.stockMinimo,
    this.categoriaEquipoId,
    this.marcaId,
    this.modeloId,
    this.marca,
    this.numeroSerie,
    this.ubicacionId,
    this.zonaId,
    this.areaId,
    this.estado,
    this.asignadoA,
    this.fechaGarantia,
    this.observaciones,
    this.atributos,
  });

  IngresoItem copyWith({
    String? clase,
    String? modo,
    String? existenteId,
    String? nombre,
    String? codigo,
    String? descripcion,
    int? cantidad,
    double? precioCompra,
    String? almacenId,
    String? imagenUrl,
    String? categoriaId,
    String? unidadId,
    int? stockMinimo,
    String? categoriaEquipoId,
    String? marcaId,
    String? modeloId,
    String? marca,
    String? numeroSerie,
    String? ubicacionId,
    String? zonaId,
    String? areaId,
    String? estado,
    String? asignadoA,
    String? fechaGarantia,
    String? observaciones,
    Map<String, dynamic>? atributos,
  }) =>
      IngresoItem(
        clase: clase ?? this.clase,
        modo: modo ?? this.modo,
        existenteId: existenteId ?? this.existenteId,
        nombre: nombre ?? this.nombre,
        codigo: codigo ?? this.codigo,
        descripcion: descripcion ?? this.descripcion,
        cantidad: cantidad ?? this.cantidad,
        precioCompra: precioCompra ?? this.precioCompra,
        almacenId: almacenId ?? this.almacenId,
        imagenUrl: imagenUrl ?? this.imagenUrl,
        categoriaId: categoriaId ?? this.categoriaId,
        unidadId: unidadId ?? this.unidadId,
        stockMinimo: stockMinimo ?? this.stockMinimo,
        categoriaEquipoId: categoriaEquipoId ?? this.categoriaEquipoId,
        marcaId: marcaId ?? this.marcaId,
        modeloId: modeloId ?? this.modeloId,
        marca: marca ?? this.marca,
        numeroSerie: numeroSerie ?? this.numeroSerie,
        ubicacionId: ubicacionId ?? this.ubicacionId,
        zonaId: zonaId ?? this.zonaId,
        areaId: areaId ?? this.areaId,
        estado: estado ?? this.estado,
        asignadoA: asignadoA ?? this.asignadoA,
        fechaGarantia: fechaGarantia ?? this.fechaGarantia,
        observaciones: observaciones ?? this.observaciones,
        atributos: atributos ?? this.atributos,
      );

  Map<String, dynamic> toJson() => {
        'clase': clase,
        'modo': modo,
        if (existenteId != null) 'existenteId': existenteId,
        if (nombre != null) 'nombre': nombre,
        if (codigo != null) 'codigo': codigo,
        if (descripcion != null) 'descripcion': descripcion,
        'cantidad': cantidad,
        if (precioCompra != null) 'precioCompra': precioCompra,
        if (almacenId != null) 'almacenId': almacenId,
        if (imagenUrl != null) 'imagenUrl': imagenUrl,
        if (categoriaId != null) 'categoriaId': categoriaId,
        if (unidadId != null) 'unidadId': unidadId,
        if (stockMinimo != null) 'stockMinimo': stockMinimo,
        if (categoriaEquipoId != null) 'categoriaEquipoId': categoriaEquipoId,
        if (marcaId != null) 'marcaId': marcaId,
        if (modeloId != null) 'modeloId': modeloId,
        if (marca != null) 'marca': marca,
        if (numeroSerie != null) 'numeroSerie': numeroSerie,
        if (ubicacionId != null) 'ubicacionId': ubicacionId,
        if (zonaId != null) 'zonaId': zonaId,
        if (areaId != null) 'areaId': areaId,
        if (estado != null) 'estado': estado,
        if (asignadoA != null) 'asignadoA': asignadoA,
        if (fechaGarantia != null) 'fechaGarantia': fechaGarantia,
        if (observaciones != null) 'observaciones': observaciones,
        if (atributos != null && atributos!.isNotEmpty) 'atributos': atributos,
      };
}

// ── Request del ingreso directo ─────────────────────────────────────────────

/// Comprobante del proveedor → al enviarlo, el backend crea la CxP (Cuenta por
/// Pagar) pendiente + su asiento. Si es null, no se genera CxP.
class ComprobanteCompra {
  final String proveedorId;
  final String tipoDocumento; // factura | boleta | nota_credito | nota_debito
  final String numeroDocumento;
  final String fechaEmision; // "YYYY-MM-DD"
  final String fechaVencimiento; // "YYYY-MM-DD"
  final double subtotal;
  final double igv;
  final String? moneda;

  const ComprobanteCompra({
    required this.proveedorId,
    this.tipoDocumento = 'factura',
    required this.numeroDocumento,
    required this.fechaEmision,
    required this.fechaVencimiento,
    required this.subtotal,
    this.igv = 0.0,
    this.moneda,
  });

  double get total => subtotal + igv;

  Map<String, dynamic> toJson() => {
        'proveedorId': proveedorId,
        'tipoDocumento': tipoDocumento,
        'numeroDocumento': numeroDocumento,
        'fechaEmision': fechaEmision,
        'fechaVencimiento': fechaVencimiento,
        'subtotal': subtotal,
        'igv': igv,
        if (moneda != null) 'moneda': moneda,
      };
}

class IngresoDirectoRequest {
  final String? personalCompraId; // default: usuario logueado (backend)
  final String? fechaCompra; // "YYYY-MM-DD" — default hoy (backend)
  final String? proveedor;
  final DestinoIngreso destino;
  final String? notas;
  final List<IngresoItem> items;
  final ComprobanteCompra? comprobante; // opcional → genera CxP

  const IngresoDirectoRequest({
    this.personalCompraId,
    this.fechaCompra,
    this.proveedor,
    required this.destino,
    this.notas,
    required this.items,
    this.comprobante,
  });

  Map<String, dynamic> toJson() => {
        if (personalCompraId != null) 'personalCompraId': personalCompraId,
        if (fechaCompra != null) 'fechaCompra': fechaCompra,
        if (proveedor != null) 'proveedor': proveedor,
        'destino': destino.toJson(),
        if (notas != null) 'notas': notas,
        'items': items.map((e) => e.toJson()).toList(),
        if (comprobante != null) 'comprobante': comprobante!.toJson(),
      };

  IngresoDirectoRequest copyWith({
    String? personalCompraId,
    String? fechaCompra,
    String? proveedor,
    DestinoIngreso? destino,
    String? notas,
    List<IngresoItem>? items,
    ComprobanteCompra? comprobante,
  }) =>
      IngresoDirectoRequest(
        personalCompraId: personalCompraId ?? this.personalCompraId,
        fechaCompra: fechaCompra ?? this.fechaCompra,
        proveedor: proveedor ?? this.proveedor,
        destino: destino ?? this.destino,
        notas: notas ?? this.notas,
        items: items ?? this.items,
        comprobante: comprobante ?? this.comprobante,
      );
}

// ── Resultado del ingreso directo ───────────────────────────────────────────

class IngresoItemResult {
  final String clase;
  final String articuloId;
  final String nombre;
  final int cantidad;
  final bool creado;

  const IngresoItemResult({
    required this.clase,
    required this.articuloId,
    required this.nombre,
    required this.cantidad,
    required this.creado,
  });

  factory IngresoItemResult.fromJson(Map<String, dynamic> j) =>
      IngresoItemResult(
        clase: j['clase']?.toString() ?? '',
        articuloId: j['articuloId']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? '',
        cantidad: (j['cantidad'] as num?)?.toInt() ?? 0,
        creado: j['creado'] as bool? ?? false,
      );
}

class IngresoDirectoResult {
  final String ingresoId;
  final int totalItems;

  /// stock | servicio | correctivo
  final String destino;
  final List<IngresoItemResult> items;
  final String? cxpFacturaId; // CxP creada (si vino comprobante)
  final String? cxpError; // motivo si la CxP no se pudo crear

  const IngresoDirectoResult({
    required this.ingresoId,
    required this.totalItems,
    required this.destino,
    required this.items,
    this.cxpFacturaId,
    this.cxpError,
  });

  factory IngresoDirectoResult.fromJson(Map<String, dynamic> j) =>
      IngresoDirectoResult(
        ingresoId: j['ingresoId']?.toString() ?? '',
        totalItems: (j['totalItems'] as num?)?.toInt() ?? 0,
        destino: j['destino']?.toString() ?? 'stock',
        items: (j['items'] as List? ?? [])
            .map((e) => IngresoItemResult.fromJson(e as Map<String, dynamic>))
            .toList(),
        cxpFacturaId: j['cxpFacturaId']?.toString(),
        cxpError: j['cxpError']?.toString(),
      );
}

// ── Artículo por código (escanear/clonar) ────────────────────────────────────

/// Artículo existente hallado por código o número de serie. Tolerante a campos
/// faltantes; conserva el JSON crudo en [raw] para campos no mapeados.
class ArticuloPorCodigo {
  /// material | equipo
  final String tipo;
  final String id;
  final String nombre;
  final String codigo;
  final String? clase;
  final Map<String, dynamic> raw;

  const ArticuloPorCodigo({
    required this.tipo,
    required this.id,
    required this.nombre,
    required this.codigo,
    this.clase,
    this.raw = const {},
  });

  factory ArticuloPorCodigo.fromJson(Map<String, dynamic> j) =>
      ArticuloPorCodigo(
        tipo: j['tipo']?.toString() ?? '',
        id: j['id']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? '',
        codigo: j['codigo']?.toString() ?? '',
        clase: j['clase']?.toString(),
        raw: Map<String, dynamic>.from(j),
      );

  /// Lee cualquier campo extra del artículo (p. ej. marcaId, categoriaId).
  dynamic operator [](String key) => raw[key];
}
