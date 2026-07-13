import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/mantenimiento_models.dart';
import '../services/mantenimiento_service.dart';
import '../utils/api_provider.dart';
import '../utils/ui_insets.dart';
import '../utils/app_session.dart';
import 'pantalla_checklist.dart';
import 'pantalla_historial_equipo.dart';

class EquiposTab extends StatefulWidget {
  final String proyectoId;

  const EquiposTab({super.key, required this.proyectoId});

  @override
  State<EquiposTab> createState() => _EquiposTabState();
}

class _EquiposTabState extends State<EquiposTab>
    with AutomaticKeepAliveClientMixin {
  List<EquipoItem> _equipos = [];
  bool _isLoading = true;
  MantenimientoService? _service;

  static const _green = Color(0xFF8FD11B);

  @override
  bool get wantKeepAlive => true;

  // Solo Admin / Jefe de Operaciones configuran la periodicidad de mantenimiento.
  bool get _puedeEditarMant =>
      AppSession.i.isAdmin || AppSession.i.isJefeOperaciones;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _editarMantenimiento(EquipoItem e) async {
    final actualizado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditarMantenimientoSheet(equipo: e, service: _service!),
    );
    if (actualizado == true) await _load();
  }

  Future<void> _init() async {
    _service = await getMantenimientoService();
    await _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final data =
        await _service!.getEquiposProyecto(widget.proyectoId);
    if (!mounted) return;
    setState(() {
      _equipos = data;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(_green),
        ),
      );
    }

    if (_equipos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.precision_manufacturing_outlined,
                size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'Sin equipos intervenidos en este proyecto',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: _green,
      child: ListView.separated(
        padding: bottomSafePadding(context, left: 20, top: 12, right: 20, extra: 24),
        itemCount: _equipos.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _EquipoCard(
          equipo: _equipos[i],
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChecklistScreen(equipo: _equipos[i]),
            ),
          ),
          onHistorial: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PantallaHistorialEquipo(
                equipoId: _equipos[i].id,
                equipoNombre: _equipos[i].nombre,
              ),
            ),
          ),
          onEditarMant:
              _puedeEditarMant ? () => _editarMantenimiento(_equipos[i]) : null,
        ),
      ),
    );
  }
}

// ─── Equipment card ───────────────────────────────────────────────────────────

class _EquipoCard extends StatelessWidget {
  final EquipoItem equipo;
  final VoidCallback onTap;
  final VoidCallback onHistorial;
  final VoidCallback? onEditarMant;

  const _EquipoCard({
    required this.equipo,
    required this.onTap,
    required this.onHistorial,
    this.onEditarMant,
  });

  static const _green = Color(0xFF8FD11B);
  static const _amber = Color(0xFFD98A16);

  Color get _estadoColor => switch (equipo.estado.toLowerCase()) {
        'completado' => _green,
        'en_proceso' => const Color(0xFF3E80C0),
        _ => _amber,
      };

  String get _estadoLabel => switch (equipo.estado.toLowerCase()) {
        'completado' => 'Completado',
        'en_proceso' => 'En Proceso',
        _ => 'Pendiente',
      };

  String get _tipoLabel => switch ((equipo.tipo ?? '').toLowerCase()) {
        'tablero' => 'Tablero Eléctrico',
        'ups' => 'UPS',
        'pozo_tierra' => 'Pozo a Tierra',
        'generador' => 'Generador',
        'transformador' => 'Transformador',
        String t when t.isNotEmpty => t[0].toUpperCase() + t.substring(1),
        _ => '',
      };

  IconData get _iconForTipo => switch ((equipo.tipo ?? '').toLowerCase()) {
        'tablero' => Icons.electrical_services_outlined,
        'ups' => Icons.battery_charging_full_outlined,
        'pozo_tierra' => Icons.settings_input_component_outlined,
        'generador' => Icons.energy_savings_leaf_outlined,
        'transformador' => Icons.transform_outlined,
        _ => Icons.precision_manufacturing_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: isDark
              ? Border.all(
                  color: _green.withValues(alpha: 0.30), width: 1.0)
              : null,
          boxShadow: isDark
              ? [
                  BoxShadow(
                    color: _green.withValues(alpha: 0.07),
                    blurRadius: 10,
                  )
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark
                        ? _estadoColor.withValues(alpha: 0.15)
                        : _estadoColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _iconForTipo,
                    color: _estadoColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        equipo.nombre,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      if (equipo.tipo != null && equipo.tipo!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            _tipoLabel,
                            style: TextStyle(
                                color: _estadoColor.withValues(alpha: 0.8),
                                fontSize: 11,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      if (equipo.descripcion != null &&
                          equipo.descripcion!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            equipo.descripcion!,
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (equipo.ubicacion != null &&
                          equipo.ubicacion!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              const Icon(Icons.location_on_outlined,
                                  size: 11, color: Colors.grey),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  equipo.ubicacion!,
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 11),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark
                            ? _estadoColor.withValues(alpha: 0.15)
                            : _estadoColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _estadoLabel,
                        style: TextStyle(
                          color: _estadoColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onEditarMant != null)
                          GestureDetector(
                            onTap: onEditarMant,
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(Icons.event_repeat_outlined,
                                  color: Colors.grey.shade400, size: 18),
                            ),
                          ),
                        // HU-19: Botón historial
                        GestureDetector(
                          onTap: onHistorial,
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.history_rounded,
                              color: Colors.grey.shade400,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            // HU-18: Barra de progreso si hay porcentaje disponible
            if (equipo.progresoPorcentaje != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (equipo.progresoPorcentaje! / 100).clamp(0.0, 1.0),
                        backgroundColor: isDark
                            ? Colors.grey.shade800
                            : Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(_estadoColor),
                        minHeight: 4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${equipo.progresoPorcentaje!.round()}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _estadoColor,
                    ),
                  ),
                ],
              ),
            ],
            // Equipos Intervenidos: barra de tiempo hasta el próximo mantenimiento
            if (equipo.requiereMantenimiento && equipo.proximaFecha != null) ...[
              const SizedBox(height: 12),
              _BarraMantenimiento(equipo: equipo, isDark: isDark),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Barra de hitos (semáforo) hasta el próximo mantenimiento ──────────────────
class _BarraMantenimiento extends StatelessWidget {
  final EquipoItem equipo;
  final bool isDark;
  const _BarraMantenimiento({required this.equipo, required this.isDark});

  static const _verde = Color(0xFF8FD11B);
  static const _ambar = Color(0xFFD98A16);
  static const _rojo = Color(0xFFD6584F);
  static const _dots = 6;

  Color get _color => switch (equipo.estadoMantenimiento) {
        'vencido' => _rojo,
        'proximo' => _ambar,
        _ => _verde,
      };

  // Fracción de tiempo transcurrido del ciclo (0 = recién hecho, 1 = vence/vencido).
  double get _fraccion {
    if (equipo.estadoMantenimiento == 'vencido') return 1.0;
    final prox = DateTime.tryParse(equipo.proximaFecha ?? '');
    if (prox == null) return 0.0;
    final hoy = DateTime.now();
    final ult = DateTime.tryParse(equipo.ultimaFecha ?? '');
    DateTime inicio;
    if (ult != null && ult.isBefore(prox)) {
      inicio = ult;
    } else {
      // Sin última fecha: estimar el inicio del ciclo según la frecuencia.
      final dias = switch ((equipo.frecuencia ?? '').toLowerCase()) {
        'mensual' => 30,
        'trimestral' => 90,
        'semestral' => 180,
        'anual' => 365,
        _ => 180,
      };
      inicio = prox.subtract(Duration(days: dias));
    }
    final total = prox.difference(inicio).inSeconds;
    if (total <= 0) return 1.0;
    final transcurrido = hoy.difference(inicio).inSeconds;
    return (transcurrido / total).clamp(0.0, 1.0);
  }

  IconData get _icono => switch (equipo.estadoMantenimiento) {
        'vencido' => Icons.error_outline,
        'proximo' => Icons.warning_amber_rounded,
        _ => Icons.check_circle_outline,
      };

  String _texto() {
    final d = equipo.diasRestantes;
    final fecha = equipo.proximaFecha != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(equipo.proximaFecha!))
        : '—';
    if (d == null) return 'Próx. mantenimiento: $fecha';
    if (d < 0) return 'Mantenimiento vencido hace ${-d} días · $fecha';
    if (d == 0) return 'Mantenimiento vence hoy · $fecha';
    return 'Próx. mantenimiento en $d días · $fecha';
  }

  @override
  Widget build(BuildContext context) {
    final filled = (_fraccion * _dots).round().clamp(0, _dots);
    final base = isDark ? Colors.grey.shade800 : Colors.grey.shade300;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(_dots, (i) {
            final on = i < filled;
            final esUltimo = i == _dots - 1;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: esUltimo ? 0 : 5),
                child: Container(
                  height: 16,
                  decoration: BoxDecoration(
                    color: on ? _color.withValues(alpha: 0.18) : base.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: on ? _color : base, width: on ? 1.2 : 1),
                  ),
                  child: esUltimo
                      ? Icon(_icono, size: 11, color: on ? _color : base)
                      : (on
                          ? Icon(Icons.circle, size: 6, color: _color)
                          : null),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 5),
        Text(_texto(),
            style: TextStyle(
                fontSize: 11, color: _color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ─── Sheet: configurar periodicidad de mantenimiento (Admin / Jefe de Op) ──────
class _EditarMantenimientoSheet extends StatefulWidget {
  final EquipoItem equipo;
  final MantenimientoService service;
  const _EditarMantenimientoSheet({required this.equipo, required this.service});

  @override
  State<_EditarMantenimientoSheet> createState() =>
      _EditarMantenimientoSheetState();
}

class _EditarMantenimientoSheetState extends State<_EditarMantenimientoSheet> {
  static const _green = Color(0xFF8FD11B);
  static const _frecuencias = ['ninguno', 'mensual', 'trimestral', 'semestral', 'anual'];

  late bool _requiere;
  late String _frecuencia;
  DateTime? _proxima;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _requiere = widget.equipo.requiereMantenimiento;
    _frecuencia = (widget.equipo.frecuencia ?? 'ninguno');
    if (!_frecuencias.contains(_frecuencia)) _frecuencia = 'ninguno';
    _proxima = DateTime.tryParse(widget.equipo.proximaFecha ?? '');
  }

  Future<void> _pickFecha() async {
    final hoy = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _proxima ?? hoy,
      firstDate: DateTime(hoy.year - 1),
      lastDate: DateTime(hoy.year + 10),
    );
    if (picked != null) setState(() => _proxima = picked);
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    final res = await widget.service.editarConfigMantenimiento(
      widget.equipo.id,
      requiereMantenimiento: _requiere,
      frecuencia: _requiere ? _frecuencia : 'ninguno',
      proximaFecha: _requiere && _proxima != null
          ? DateFormat('yyyy-MM-dd').format(_proxima!)
          : null,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (res != null) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No se pudo guardar (¿permiso de Admin/Jefe?)'),
        backgroundColor: Color(0xFFD6584F),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Mantenimiento · ${widget.equipo.nombre}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: _green,
              title: const Text('Requiere mantenimiento periódico'),
              value: _requiere,
              onChanged: (v) => setState(() => _requiere = v),
            ),
            if (_requiere) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _frecuencia,
                decoration: const InputDecoration(
                    labelText: 'Frecuencia', border: OutlineInputBorder()),
                items: _frecuencias
                    .map((f) => DropdownMenuItem(
                        value: f,
                        child: Text(f[0].toUpperCase() + f.substring(1))))
                    .toList(),
                onChanged: (v) => setState(() => _frecuencia = v ?? 'ninguno'),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickFecha,
                child: InputDecorator(
                  decoration: const InputDecoration(
                      labelText: 'Próximo mantenimiento (del certificado)',
                      border: OutlineInputBorder()),
                  child: Text(_proxima != null
                      ? DateFormat('dd/MM/yyyy').format(_proxima!)
                      : 'Seleccionar fecha'),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'La fecha suele venir del certificado. Solo Admin / Jefe de Operaciones puede editarla.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _green),
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(
                        height: 18, width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Guardar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
