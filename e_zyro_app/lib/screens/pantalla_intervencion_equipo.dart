import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';
import '../models/intervencion_models.dart';
import '../services/equipo_intervenido_service.dart';
import '../services/intervencion_service.dart';
import '../utils/api_provider.dart';
import '../utils/procedimientos_locales.dart';
import 'pantalla_camara_campo.dart';
import 'pantalla_certificado_equipo.dart';
import 'pantalla_informe_termografico.dart';
import 'pantalla_protocolo_resistencia.dart';

const _green = Color(0xFF8FD11B);
const _amber = Color(0xFFD98A16);
const _danger = Color(0xFFD6584F);

/// Inspección de un equipo intervenido dentro de un servicio. Réplica del
/// componente Angular `intervencion-equipo`: checklist de procedimientos con
/// foto por paso, observaciones, guardar progreso y finalizar (con alerta si
/// hay pasos incompletos). Al finalizar habilita el certificado del equipo
/// (pozo o operatividad según el tipo).
class PantallaIntervencionEquipo extends StatefulWidget {
  final String servicioId;
  final String eiId;
  final String nombreEquipo;

  const PantallaIntervencionEquipo({
    super.key,
    required this.servicioId,
    required this.eiId,
    this.nombreEquipo = '',
  });

  @override
  State<PantallaIntervencionEquipo> createState() =>
      _PantallaIntervencionEquipoState();
}

class _PantallaIntervencionEquipoState
    extends State<PantallaIntervencionEquipo> {
  IntervencionService? _svc;
  EquipoIntervenidoService? _eiSvc;
  bool _cargando = true;
  bool _error = false;
  bool _guardando = false;
  bool _finalizando = false;
  bool _mostrarFinalizar = false;

  InspeccionActiva? _data;
  final _obsCtrl = TextEditingController();
  String _proximaFecha = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _obsCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _svc = IntervencionService(ApiClient(prefs));
    _eiSvc = await getEquipoIntervenidoService();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() {
      _cargando = true;
      _error = false;
    });
    final res = await _svc!.getInspeccionActiva(widget.servicioId, widget.eiId);
    if (!mounted) return;
    if (res.ok && res.data != null) {
      var data = res.data!;
      // Si el backend no tiene procedimientos, cargar los locales por tipo.
      if (data.pasos.isEmpty) {
        final tipo = data.equipo.tipoNombre ?? '';
        final locales = await cargarProcedimientosLocales(tipo);
        if (locales.isNotEmpty) {
          data = InspeccionActiva(
            inspeccionId: data.inspeccionId,
            estado: data.estado,
            pasos: locales,
            observaciones: data.observaciones,
            proximaFecha: data.proximaFecha,
            equipo: data.equipo,
            inspeccionPadreId: data.inspeccionPadreId,
            padre: data.padre,
            intervencionAnterior: data.intervencionAnterior,
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _data = data;
        _obsCtrl.text = data.observaciones ?? '';
        _proximaFecha = data.proximaFecha ?? '';
        _mostrarFinalizar = _todosCompletados;
      });
    } else {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = true;
      });
    }
  }

  // ── Computed (mismos getters que el componente Angular) ─────────────────────
  List<PasoInspeccion> get _pasos => _data?.pasos ?? const [];
  int get _completados => _pasos.where((p) => p.completado).length;
  int get _total => _pasos.length;
  double get _progreso => _total == 0 ? 0 : _completados / _total;
  bool get _todosCompletados => _total > 0 && _completados == _total;
  bool get _estaFinalizado =>
      _data?.equipo.estadoIntervencion == 'completado' ||
      _data?.estado == 'completado';
  String get _tipoCertificado =>
      (_data?.equipo.tipoNombre ?? '').toUpperCase().contains('POZO')
          ? 'pozo'
          : 'operatividad';

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Foto: cámara de campo unificada (in-app) sobre el checklist ─────────────
  // Abre la cámara ya apuntando a este paso; las flechas permiten recorrer el
  // resto y el "Almacén" sube fotos tomadas fuera del app. La cámara muta los
  // mismos objetos PasoInspeccion, así que al volver solo hay que repintar.
  Future<void> _subirFoto(PasoInspeccion paso) async {
    final d = _data;
    if (d == null) return;
    final idx = _pasos.indexOf(paso);
    await CamaraCampoScreen.paraInspeccion(
      context,
      servicioId: widget.servicioId,
      eiId: widget.eiId,
      servicioNombre: d.equipo.clienteNombre ?? '',
      equipoNombre: d.equipo.nombre,
      insp: d,
      pasoInicial: idx < 0 ? 0 : idx,
    );
    if (mounted) setState(() {});
  }

  Future<void> _quitarFoto(PasoInspeccion paso) async {
    final urlAnterior = paso.fotoUrl;
    setState(() {
      paso.fotoUrl = null;
      paso.fotoPublicId = null;
    });
    if (urlAnterior == null || !urlAnterior.startsWith('http')) return;
    final res =
        await _svc!.quitarFotoInspeccion(_data!.inspeccionId, paso.orden);
    if (!mounted) return;
    if (!res.ok) {
      // Rollback optimista (igual que el frontend).
      setState(() => paso.fotoUrl = urlAnterior);
      _snack('No se pudo quitar la foto.', _danger);
    }
  }

  // ── Observación / recomendación por paso (antecedente de procedimientos) ────
  Future<void> _editarNotas(PasoInspeccion paso) async {
    final obsCtrl = TextEditingController(text: paso.observacion ?? '');
    final recCtrl = TextEditingController(text: paso.recomendacion ?? '');
    final guardar = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Notas — ${paso.orden}. ${paso.nombre}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: obsCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Observación', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: recCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Recomendación', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: _green, padding: const EdgeInsets.symmetric(vertical: 13)),
                child: const Text('Guardar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
    if (guardar != true) return;
    setState(() {
      paso.observacion = obsCtrl.text.trim().isEmpty ? null : obsCtrl.text.trim();
      paso.recomendacion = recCtrl.text.trim().isEmpty ? null : recCtrl.text.trim();
    });
    await _guardar();
  }

  Future<void> _verAntecedente(PasoInspeccion paso) async {
    if (_eiSvc == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        expand: false,
        builder: (ctx, scrollCtrl) => FutureBuilder(
          future: _eiSvc!.antecedenteProcedimiento(widget.eiId, paso.orden),
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(_green)));
            }
            final res = snap.data;
            final items = (res != null && res.ok) ? (res.data ?? []) : <AntecedenteProcedimiento>[];
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Antecedente — ${paso.orden}. ${paso.nombre}',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Expanded(
                    child: items.isEmpty
                        ? Center(
                            child: Text('Sin antecedentes para este paso.',
                                style: TextStyle(color: Colors.grey.shade500)))
                        : ListView.separated(
                            controller: scrollCtrl,
                            itemCount: items.length,
                            separatorBuilder: (_, _) => const Divider(),
                            itemBuilder: (_, i) {
                              final a = items[i];
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(a.fecha ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                    if ((a.observacion ?? '').isNotEmpty)
                                      Text('Observación: ${a.observacion}', style: const TextStyle(fontSize: 12)),
                                    if ((a.recomendacion ?? '').isNotEmpty)
                                      Text('Recomendación: ${a.recomendacion}', style: const TextStyle(fontSize: 12)),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Guardar progreso (sin finalizar) ────────────────────────────────────────
  Future<void> _guardar() async {
    if (_guardando || _data == null) return;
    setState(() => _guardando = true);
    final res = await _svc!.guardarInspeccion(
      _data!.inspeccionId,
      pasos: _pasos,
      observaciones: _obsCtrl.text,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (res.ok) {
      _snack('Progreso guardado correctamente.', _green);
      if (res.data == true) setState(() => _mostrarFinalizar = true);
    } else {
      _snack(res.errorMessage.isEmpty ? 'Error al guardar.' : res.errorMessage,
          _danger);
    }
  }

  // ── Finalizar inspección ────────────────────────────────────────────────────
  Future<void> _intentarFinalizar() async {
    if (_finalizando) return;
    if (!_todosCompletados) {
      // Alerta de confirmación con pasos incompletos (showAlertaFinalizar).
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Finalizar con pasos incompletos'),
          content: Text(
              'Hay ${_total - _completados} paso(s) sin completar. ¿Deseas finalizar la inspección de todas formas?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: _amber),
                child: const Text('Sí, finalizar',
                    style: TextStyle(color: Colors.white))),
          ],
        ),
      );
      if (confirmar != true) return;
    }
    await _finalizar();
  }

  Future<void> _finalizar() async {
    if (_finalizando || _data == null) return;
    setState(() => _finalizando = true);
    final res = await _svc!.finalizarInspeccion(
      _data!.inspeccionId,
      pasos: _pasos,
      observaciones: _obsCtrl.text,
      proximaFechaMantenimiento: _proximaFecha,
    );
    if (!mounted) return;
    setState(() => _finalizando = false);
    if (res.ok) {
      setState(() => _data!.equipo.estadoIntervencion = 'completado');
      _snack('¡Inspección finalizada y guardada en historial!', _green);
    } else {
      _snack(
          res.errorMessage.isEmpty ? 'Error al finalizar.' : res.errorMessage,
          _danger);
    }
  }

  Future<void> _pickProximaFecha() async {
    final hoy = DateTime.now();
    final actual = DateTime.tryParse(_proximaFecha) ??
        DateTime(hoy.year, hoy.month + 6, hoy.day);
    final d = await showDatePicker(
      context: context,
      initialDate: actual.isBefore(hoy) ? hoy : actual,
      firstDate: hoy,
      lastDate: DateTime(hoy.year + 5),
    );
    if (d != null) {
      setState(() => _proximaFecha = d.toIso8601String().split('T').first);
    }
  }

  // ── Historial de inspecciones completadas ───────────────────────────────────
  Future<void> _verHistorial() async {
    final res = await _svc!.getHistorialEquipo(widget.servicioId, widget.eiId);
    if (!mounted) return;
    final items = res.data ?? [];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Container(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          padding: const EdgeInsets.all(16),
          child: items.isEmpty
              ? const SizedBox(
                  height: 120,
                  child: Center(child: Text('Sin inspecciones previas.')))
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final h = items[i];
                    final done =
                        h.resultado.where((p) => p.completado).length;
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.task_alt, color: _green),
                      title: Text(
                          'Inspección ${h.fechaFin?.split('T').first ?? ''}',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '$done/${h.resultado.length} pasos'
                        '${(h.observaciones ?? '').isNotEmpty ? ' · ${h.observaciones}' : ''}'
                        '${(h.proximaFechaMantenimiento ?? '').isNotEmpty ? '\nPróx. mantenimiento: ${h.proximaFechaMantenimiento}' : ''}'
                        '${h.inspeccionPadreId != null ? '\n↳ Da seguimiento a una intervención anterior' : ''}',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  // ── Vínculo con una intervención anterior del mismo equipo ──────────────────
  Future<void> _vincular(String? padreId) async {
    if (_data == null) return;
    final res = await _svc!
        .vincularInspeccion(_data!.inspeccionId, padreId: padreId);
    if (!mounted) return;
    if (res.ok) {
      _snack(
          padreId == null
              ? 'Vínculo eliminado.'
              : 'Vinculado a la intervención anterior.',
          _green);
      await _cargar();
    } else {
      _snack(
          res.errorMessage.isEmpty
              ? 'No se pudo actualizar el vínculo.'
              : res.errorMessage,
          _danger);
    }
  }

  /// Abre un selector con TODAS las intervenciones anteriores del equipo para
  /// que el usuario elija a cuál vincular la inspección actual.
  Future<void> _abrirSelectorVinculo() async {
    if (_data == null) return;
    final res =
        await _svc!.getIntervencionesPrevias(widget.servicioId, widget.eiId);
    if (!mounted) return;
    final items = res.data ?? [];
    if (items.isEmpty) {
      _snack('No hay intervenciones anteriores para vincular.', _amber);
      return;
    }
    final elegido = await showModalBottomSheet<VinculoInspeccion>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Container(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Elegir servicio anterior',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final it = items[i];
                    final yaEs = _data!.inspeccionPadreId == it.id;
                    return ListTile(
                      dense: true,
                      leading: Icon(Icons.history,
                          color: yaEs ? _green : Colors.grey),
                      title: Text(it.servicioNombre ?? 'Servicio',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text('Finalizado: ${it.fechaCorta}',
                          style: const TextStyle(fontSize: 11.5)),
                      trailing: yaEs
                          ? const Icon(Icons.check_circle,
                              color: _green, size: 18)
                          : null,
                      onTap: () => Navigator.pop(ctx, it),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (elegido == null || !mounted) return;
    await _vincular(elegido.id);
  }

  /// Tarjeta de vínculo: muestra el padre si existe, o sugiere encadenar con la
  /// última intervención del equipo. Lista vacía si no hay nada que ofrecer.
  List<Widget> _vinculoCardChildren() {
    final d = _data;
    if (d == null) return const [];
    final padre = d.padre;
    final anterior = d.intervencionAnterior;
    if (padre == null && anterior == null) return const [];

    final bool vinculado = padre != null;
    final Color baseColor =
        vinculado ? const Color(0xFF3E80C0) : Colors.grey;

    final card = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: vinculado ? 0.08 : 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: baseColor.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(vinculado ? Icons.link : Icons.history_toggle_off,
                  size: 18,
                  color: vinculado
                      ? const Color(0xFF3E80C0)
                      : Colors.grey.shade600),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vinculado
                          ? 'Da seguimiento a una intervención anterior'
                          : '¿Da seguimiento a un trabajo anterior?',
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      vinculado
                          ? '${padre.servicioNombre ?? 'Intervención'} · ${padre.fechaCorta}'
                          : 'Última intervención: '
                              '${anterior!.servicioNombre ?? 'servicio'} · ${anterior.fechaCorta}',
                      style: TextStyle(
                          fontSize: 11.5, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!_estaFinalizado) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: vinculado
                  ? [
                      TextButton(
                        onPressed: _abrirSelectorVinculo,
                        child: const Text('Cambiar',
                            style: TextStyle(fontSize: 12)),
                      ),
                      TextButton(
                        onPressed: () => _vincular(null),
                        child: const Text('Quitar',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ]
                  : [
                      TextButton(
                        onPressed: _abrirSelectorVinculo,
                        child: const Text('Elegir…',
                            style: TextStyle(fontSize: 12)),
                      ),
                      TextButton(
                        onPressed: () => _vincular(anterior!.id),
                        child: const Text('Vincular última',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ],
            ),
          ],
        ],
      ),
    );
    return [card, const SizedBox(height: 12)];
  }

  void _irACertificado() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PantallaCertificadoEquipo(
          servicioId: widget.servicioId,
          eiId: widget.eiId,
          tipo: _tipoCertificado,
        ),
      ),
    );
  }

  void _irAReporteSecundario() {
    final equipoNombre = _data?.equipo.nombre ?? widget.nombreEquipo;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _tipoCertificado == 'pozo'
            ? PantallaProtocoloResistencia(
                servicioId: widget.servicioId, eiId: widget.eiId, equipoNombre: equipoNombre)
            : PantallaInformeTermografico(
                servicioId: widget.servicioId, eiId: widget.eiId, equipoNombre: equipoNombre),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eq = _data?.equipo;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          eq?.nombre ?? widget.nombreEquipo,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, size: 20),
            tooltip: 'Historial de inspecciones',
            onPressed: _data == null ? null : _verHistorial,
          ),
        ],
      ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(_green)))
          : _error || _data == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline,
                          size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text('No se pudo cargar la inspección',
                          style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 12),
                      OutlinedButton(
                          onPressed: _cargar, child: const Text('Reintentar')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  color: _green,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      _HeaderEquipo(equipo: eq!),
                      const SizedBox(height: 12),
                      ..._vinculoCardChildren(),
                      // Progreso
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: _progreso,
                                minHeight: 8,
                                backgroundColor:
                                    Colors.grey.withValues(alpha: 0.2),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                    _green),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text('$_completados/$_total',
                              style: const TextStyle(
                                  fontSize: 12.5, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      if (_estaFinalizado) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: _green.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: _green.withValues(alpha: 0.40)),
                          ),
                          child: const Row(children: [
                            Icon(Icons.task_alt, size: 16, color: _green),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                  'Inspección completada — solo lectura',
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: _green)),
                            ),
                          ]),
                        ),
                      ],
                      const SizedBox(height: 14),
                      // Checklist de procedimientos
                      for (final paso in _pasos)
                        _PasoCard(
                          paso: paso,
                          readOnly: _estaFinalizado,
                          onToggle: _estaFinalizado
                              ? null
                              : () => setState(
                                  () => paso.completado = !paso.completado),
                          onFoto: _estaFinalizado ? null : () => _subirFoto(paso),
                          onQuitarFoto:
                              _estaFinalizado ? null : () => _quitarFoto(paso),
                          onNotas: _estaFinalizado ? null : () => _editarNotas(paso),
                          onAntecedente: () => _verAntecedente(paso),
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _obsCtrl,
                        maxLines: 3,
                        readOnly: _estaFinalizado,
                        decoration: const InputDecoration(
                          labelText: 'Observaciones',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (!_estaFinalizado) ...[
                        // Próxima fecha de mantenimiento (opcional al finalizar)
                        InkWell(
                          onTap: _pickProximaFecha,
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Próximo mantenimiento (opcional)',
                              border: OutlineInputBorder(),
                              suffixIcon: Icon(Icons.event_outlined, size: 18),
                            ),
                            child: Text(
                              _proximaFecha.isEmpty
                                  ? 'Automático: hoy + frecuencia del equipo'
                                  : _proximaFecha,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _guardando ? null : _guardar,
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: _green),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 13),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: _guardando
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: _green))
                                    : const Icon(Icons.save_outlined,
                                        size: 18, color: _green),
                                label: const Text('Guardar',
                                    style: TextStyle(
                                        color: _green,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: (_finalizando ||
                                        !(_mostrarFinalizar ||
                                            _todosCompletados ||
                                            _completados > 0))
                                    ? null
                                    : _intentarFinalizar,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _green,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 13),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: _finalizando
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white))
                                    : const Icon(Icons.task_alt,
                                        size: 18, color: Colors.white),
                                label: const Text('Finalizar',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _irACertificado,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _green,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.workspace_premium_outlined,
                                size: 18, color: Colors.white),
                            label: Text(
                              _tipoCertificado == 'pozo'
                                  ? 'Protocolo de Pozo a Tierra'
                                  : 'Certificado de Operatividad',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _irAReporteSecundario,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _green,
                              side: BorderSide(color: _green.withValues(alpha: 0.5)),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.description_outlined, size: 18),
                            label: Text(
                              _tipoCertificado == 'pozo'
                                  ? 'Protocolo de Resistencia'
                                  : 'Informe Termográfico',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }
}

// ─── Header con la ficha del equipo ───────────────────────────────────────────

class _HeaderEquipo extends StatelessWidget {
  final EquipoInspeccionInfo equipo;
  const _HeaderEquipo({required this.equipo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _green.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _green.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(equipo.nombre,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w800)),
              ),
              if ((equipo.codigo ?? '').isNotEmpty)
                Text(equipo.codigo!,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 3,
            children: [
              if ((equipo.tipoNombre ?? '').isNotEmpty)
                _dato(Icons.category_outlined, equipo.tipoNombre!),
              if ((equipo.clienteNombre ?? '').isNotEmpty)
                _dato(Icons.business_outlined, equipo.clienteNombre!),
              if ((equipo.ubicacionReferencia ?? '').isNotEmpty)
                _dato(Icons.push_pin_outlined, equipo.ubicacionReferencia!),
              if (equipo.nMantenimientos != null)
                _dato(Icons.build_outlined,
                    '${equipo.nMantenimientos} mantenimiento(s)'),
              if ((equipo.ultimoMantenimiento ?? '').isNotEmpty)
                _dato(Icons.history, 'Últ.: ${equipo.ultimoMantenimiento}'),
              if ((equipo.proximoMantenimiento ?? '').isNotEmpty)
                _dato(Icons.event_outlined,
                    'Próx.: ${equipo.proximoMantenimiento}'),
            ],
          ),
          if ((equipo.descripcion ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(equipo.descripcion!,
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700)),
          ],
        ],
      ),
    );
  }

  Widget _dato(IconData icon, String texto) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.grey.shade600),
          const SizedBox(width: 3),
          Text(texto,
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700)),
        ],
      );
}

// ─── Card de un paso del checklist ────────────────────────────────────────────

class _PasoCard extends StatelessWidget {
  final PasoInspeccion paso;
  final bool readOnly;
  final VoidCallback? onToggle;
  final VoidCallback? onFoto;
  final VoidCallback? onQuitarFoto;
  final VoidCallback? onNotas;
  final VoidCallback? onAntecedente;

  const _PasoCard({
    required this.paso,
    this.readOnly = false,
    this.onToggle,
    this.onFoto,
    this.onQuitarFoto,
    this.onNotas,
    this.onAntecedente,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: paso.completado
              ? _green.withValues(alpha: 0.5)
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  paso.completado
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 22,
                  color: paso.completado ? _green : Colors.grey,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${paso.orden}. ${paso.nombre}',
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600)),
                  if (paso.descripcion.isNotEmpty)
                    Text(paso.descripcion,
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600)),
                  if ((paso.observacion ?? '').isNotEmpty ||
                      (paso.recomendacion ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.sticky_note_2_outlined,
                              size: 12, color: Colors.amber.shade700),
                          const SizedBox(width: 3),
                          Text('Con notas',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  color: Colors.amber.shade700,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onNotas != null)
                  IconButton(
                    tooltip: 'Observación / recomendación',
                    icon: Icon(Icons.edit_note,
                        size: 20,
                        color: ((paso.observacion ?? '').isNotEmpty ||
                                (paso.recomendacion ?? '').isNotEmpty)
                            ? _green
                            : Colors.grey),
                    onPressed: onNotas,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                if (onAntecedente != null)
                  IconButton(
                    tooltip: 'Ver antecedente',
                    icon: const Icon(Icons.history, size: 20, color: Colors.grey),
                    onPressed: onAntecedente,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            const SizedBox(width: 4),
            // Foto del paso: miniatura + reemplazar/quitar, o botón de cámara.
            if ((paso.fotoUrl ?? '').isNotEmpty)
              Stack(
                children: [
                  InkWell(
                    onTap: onFoto,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: paso.fotoUrl!,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        memCacheWidth: 150,
                        errorWidget: (_, _, _) => Container(
                          width: 44,
                          height: 44,
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.broken_image_outlined,
                              size: 18, color: Colors.grey),
                        ),
                      ),
                    ),
                  ),
                  if (!readOnly)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: InkWell(
                        onTap: onQuitarFoto,
                        child: Container(
                          decoration: const BoxDecoration(
                              color: _danger, shape: BoxShape.circle),
                          padding: const EdgeInsets.all(2),
                          child: const Icon(Icons.close,
                              size: 11, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              )
            else if (!readOnly)
              InkWell(
                onTap: onFoto,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.grey.withValues(alpha: 0.4)),
                  ),
                  child: const Icon(Icons.add_a_photo_outlined,
                      size: 18, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
