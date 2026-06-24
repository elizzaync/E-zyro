// form_articulo_dinamico.dart — formulario dinámico reutilizable que construye
// sus campos a partir de un [FormSchemaOut] del backend. Estilo visual alineado
// al panel de Logística (Style E · es_tokens / es_widgets).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/ingreso_directo_models.dart';
import '../screens/logistica/almacen/es_tokens.dart';

/// Conjunto de campos nativos de [IngresoItem] que el formulario sabe mapear
/// directamente cuando `FormFieldDef.nativo == true`. Cualquier otra `key`
/// nativa que no esté aquí cae igualmente en `atributos` (modo seguro).
const Set<String> _kCamposNativos = {
  'nombre',
  'codigo',
  'descripcion',
  'cantidad',
  'precioCompra',
  'almacenId',
  'imagenUrl',
  'categoriaId',
  'unidadId',
  'stockMinimo',
  'categoriaEquipoId',
  'marcaId',
  'modeloId',
  'marca',
  'numeroSerie',
  'ubicacionId',
  'zonaId',
  'areaId',
  'estado',
  'asignadoA',
  'fechaGarantia',
  'observaciones',
};

/// Controla un [FormArticuloDinamico]: valida y arma el [IngresoItem] resultante.
class FormArticuloController {
  _FormArticuloDinamicoState? _state;

  /// Valida todos los campos requeridos. true si el formulario es válido.
  bool validar() => _state?._validar() ?? false;

  /// Valores capturados crudos (key → valor) tal como se ingresaron.
  Map<String, dynamic> get valores => _state?._valores() ?? {};

  /// Arma un [IngresoItem] con los valores actuales. Reparte cada valor entre
  /// un campo nativo del ítem o `atributos[key]` según `FormFieldDef.nativo`.
  /// [base] permite preestablecer clase/modo/existenteId/cantidad, etc.
  IngresoItem buildItem({required IngresoItem base}) =>
      _state?._buildItem(base) ?? base;
}

/// Formulario dinámico que renderiza los campos de un [FormSchemaOut].
class FormArticuloDinamico extends StatefulWidget {
  final FormSchemaOut schema;
  final FormArticuloController controller;

  /// Valores iniciales por key (p. ej. al clonar un artículo existente).
  final Map<String, dynamic>? valoresIniciales;

  /// Se dispara cuando cambia cualquier campo (para previsualizaciones).
  final VoidCallback? onChanged;

  const FormArticuloDinamico({
    super.key,
    required this.schema,
    required this.controller,
    this.valoresIniciales,
    this.onChanged,
  });

  @override
  State<FormArticuloDinamico> createState() => _FormArticuloDinamicoState();
}

class _FormArticuloDinamicoState extends State<FormArticuloDinamico> {
  final _formKey = GlobalKey<FormState>();

  /// Controllers de campos de texto (text/number/textarea/ip/mac/image-url).
  final Map<String, TextEditingController> _text = {};

  /// Valor seleccionado en selects (id de la opción).
  final Map<String, String?> _select = {};

  /// Fechas seleccionadas (almacenadas como "YYYY-MM-DD").
  final Map<String, String?> _fecha = {};

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
    _initValores();
  }

  @override
  void didUpdateWidget(covariant FormArticuloDinamico old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller._state = null;
      widget.controller._state = this;
    }
    // Si cambia el esquema (otra clase), reconstruye el estado de campos.
    if (old.schema != widget.schema) {
      for (final c in _text.values) {
        c.dispose();
      }
      _text.clear();
      _select.clear();
      _fecha.clear();
      _initValores();
    }
  }

  void _initValores() {
    final ini = widget.valoresIniciales ?? const {};
    for (final f in widget.schema.campos) {
      final v = ini[f.key];
      switch (f.inputType) {
        case 'select':
          _select[f.key] = v?.toString();
          break;
        case 'date':
          _fecha[f.key] = v?.toString();
          break;
        default:
          _text[f.key] = TextEditingController(text: v?.toString() ?? '');
      }
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    if (widget.controller._state == this) widget.controller._state = null;
    super.dispose();
  }

  // ── API expuesta al controller ───────────────────────────────────────────

  bool _validar() => _formKey.currentState?.validate() ?? false;

  Map<String, dynamic> _valores() {
    final out = <String, dynamic>{};
    for (final f in widget.schema.campos) {
      out[f.key] = _rawValor(f);
    }
    return out;
  }

  /// Valor tipado de un campo (int/double para number, String para el resto).
  dynamic _rawValor(FormFieldDef f) {
    switch (f.inputType) {
      case 'select':
        return _select[f.key];
      case 'date':
        return _fecha[f.key];
      case 'number':
        final raw = _text[f.key]?.text.trim() ?? '';
        if (raw.isEmpty) return null;
        // stockMinimo / cantidad son enteros; precioCompra es double.
        final asInt = int.tryParse(raw);
        if (asInt != null && !raw.contains('.') && !raw.contains(',')) {
          return asInt;
        }
        return double.tryParse(raw.replaceAll(',', '.'));
      default:
        final raw = _text[f.key]?.text.trim() ?? '';
        return raw.isEmpty ? null : raw;
    }
  }

  IngresoItem _buildItem(IngresoItem base) {
    final nativos = <String, dynamic>{};
    final atributos = <String, dynamic>{};

    for (final f in widget.schema.campos) {
      final v = _rawValor(f);
      if (v == null) continue;
      if (f.nativo && _kCamposNativos.contains(f.key)) {
        nativos[f.key] = v;
      } else {
        atributos[f.key] = v;
      }
    }

    int? asInt(dynamic v) =>
        v is int ? v : (v is num ? v.toInt() : int.tryParse('$v'));
    double? asDouble(dynamic v) =>
        v is double ? v : (v is num ? v.toDouble() : double.tryParse('$v'));

    final mergedAtributos = <String, dynamic>{
      ...?base.atributos,
      ...atributos,
    };

    return base.copyWith(
      nombre: nativos['nombre'] as String?,
      codigo: nativos['codigo'] as String?,
      descripcion: nativos['descripcion'] as String?,
      cantidad: nativos.containsKey('cantidad')
          ? asInt(nativos['cantidad'])
          : null,
      precioCompra: asDouble(nativos['precioCompra']),
      almacenId: nativos['almacenId'] as String?,
      imagenUrl: nativos['imagenUrl'] as String?,
      categoriaId: nativos['categoriaId'] as String?,
      unidadId: nativos['unidadId'] as String?,
      stockMinimo: asInt(nativos['stockMinimo']),
      categoriaEquipoId: nativos['categoriaEquipoId'] as String?,
      marcaId: nativos['marcaId'] as String?,
      modeloId: nativos['modeloId'] as String?,
      marca: nativos['marca'] as String?,
      numeroSerie: nativos['numeroSerie'] as String?,
      ubicacionId: nativos['ubicacionId'] as String?,
      zonaId: nativos['zonaId'] as String?,
      areaId: nativos['areaId'] as String?,
      estado: nativos['estado'] as String?,
      asignadoA: nativos['asignadoA'] as String?,
      fechaGarantia: nativos['fechaGarantia'] as String?,
      observaciones: nativos['observaciones'] as String?,
      atributos: mergedAtributos.isEmpty ? null : mergedAtributos,
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Agrupa los campos por `grupo` conservando el orden de aparición.
    final grupos = <String, List<FormFieldDef>>{};
    for (final f in widget.schema.campos) {
      grupos.putIfAbsent(f.grupo ?? '', () => []).add(f);
    }

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in grupos.entries) ...[
            if (entry.key.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 8, left: 2),
                child: Text(
                  entry.key.toUpperCase(),
                  style: pj(
                      size: 12,
                      weight: FontWeight.w700,
                      color: ESC.inkFaint,
                      spacing: 1.1),
                ),
              ),
            ],
            for (final f in entry.value)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _buildCampo(f),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildCampo(FormFieldDef f) {
    switch (f.inputType) {
      case 'select':
        return _selectField(f);
      case 'date':
        return _dateField(f);
      case 'textarea':
        return _textField(f, maxLines: 4);
      case 'number':
        return _textField(
          f,
          keyboard: const TextInputType.numberWithOptions(decimal: true),
          formatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
        );
      case 'ip':
        return _textField(
          f,
          keyboard: TextInputType.number,
          formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          validatorExtra: _validarIp,
        );
      case 'mac':
        return _textField(
          f,
          keyboard: TextInputType.text,
          formatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F:.-]')),
          ],
          validatorExtra: _validarMac,
        );
      case 'image':
        return _imageField(f);
      case 'text':
      default:
        return _textField(f);
    }
  }

  // ── Estilo de input compartido ───────────────────────────────────────────

  InputDecoration _decoration(FormFieldDef f, {Widget? suffixIcon}) =>
      InputDecoration(
        labelText: f.required ? '${f.label} *' : f.label,
        hintText: f.placeholder,
        labelStyle: pj(size: 13.5, color: ESC.inkSub),
        hintStyle: pj(size: 13.5, color: ESC.inkFaint),
        filled: true,
        fillColor: ESC.surface,
        suffixIcon: suffixIcon,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ESC.lineStrong, width: 1.4),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ESC.brandDeep, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ESC.vencido, width: 1.4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ESC.vencido, width: 1.8),
        ),
      );

  // ── Campos concretos ────────────────────────────────────────────────────

  Widget _textField(
    FormFieldDef f, {
    int maxLines = 1,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    String? Function(String?)? validatorExtra,
  }) {
    return TextFormField(
      controller: _text[f.key],
      maxLines: maxLines,
      keyboardType: keyboard,
      inputFormatters: formatters,
      style: pj(size: 14.5, color: ESC.ink),
      decoration: _decoration(f),
      onChanged: (_) => widget.onChanged?.call(),
      validator: (v) {
        if (f.required && (v == null || v.trim().isEmpty)) {
          return 'Campo obligatorio';
        }
        if (validatorExtra != null) return validatorExtra(v);
        return null;
      },
    );
  }

  Widget _selectField(FormFieldDef f) {
    final opciones = f.opciones ?? const <FormOpcion>[];
    final value = _select[f.key];
    final exists = opciones.any((o) => o.id == value);
    return DropdownButtonFormField<String>(
      initialValue: exists ? value : null,
      isExpanded: true,
      style: pj(size: 14.5, color: ESC.ink),
      decoration: _decoration(f),
      items: [
        for (final o in opciones)
          DropdownMenuItem(
            value: o.id,
            child: Text(o.nombre, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) {
        setState(() => _select[f.key] = v);
        widget.onChanged?.call();
      },
      validator: (v) {
        if (f.required && (v == null || v.isEmpty)) return 'Selecciona una opción';
        return null;
      },
    );
  }

  Widget _dateField(FormFieldDef f) {
    final value = _fecha[f.key];
    return FormField<String>(
      initialValue: value,
      validator: (_) {
        if (f.required && (_fecha[f.key] == null || _fecha[f.key]!.isEmpty)) {
          return 'Selecciona una fecha';
        }
        return null;
      },
      builder: (state) {
        final shown = _fecha[f.key];
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            final now = DateTime.now();
            DateTime initial = now;
            if (shown != null) {
              initial = DateTime.tryParse(shown) ?? now;
            }
            final picked = await showDatePicker(
              context: context,
              initialDate: initial,
              firstDate: DateTime(now.year - 20),
              lastDate: DateTime(now.year + 20),
            );
            if (picked != null) {
              final iso =
                  '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
              setState(() => _fecha[f.key] = iso);
              state.didChange(iso);
              widget.onChanged?.call();
            }
          },
          child: InputDecorator(
            decoration: _decoration(
              f,
              suffixIcon:
                  const Icon(Icons.calendar_today_outlined, size: 18, color: ESC.inkSub),
            ).copyWith(errorText: state.errorText),
            child: Text(
              shown ?? (f.placeholder ?? 'Seleccionar fecha'),
              style: pj(
                size: 14.5,
                color: shown == null ? ESC.inkFaint : ESC.ink,
              ),
            ),
          ),
        );
      },
    );
  }

  /// Placeholder de imagen: por ahora captura una URL de imagen (imagenUrl).
  /// La subida real de archivos se conectará en la ola de pantallas.
  Widget _imageField(FormFieldDef f) {
    return _textField(
      f,
      keyboard: TextInputType.url,
    );
  }

  // ── Validadores específicos ───────────────────────────────────────────────

  static final _ipRe = RegExp(
      r'^(25[0-5]|2[0-4]\d|1?\d?\d)(\.(25[0-5]|2[0-4]\d|1?\d?\d)){3}$');
  static final _macRe =
      RegExp(r'^([0-9a-fA-F]{2}([:-])){5}[0-9a-fA-F]{2}$');

  String? _validarIp(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return null;
    return _ipRe.hasMatch(s) ? null : 'IP inválida';
  }

  String? _validarMac(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return null;
    return _macRe.hasMatch(s) ? null : 'MAC inválida';
  }
}
