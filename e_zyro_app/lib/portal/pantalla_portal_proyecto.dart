import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';
import 'portal_estilos.dart';
import 'portal_models.dart';
import 'portal_service.dart';

/// Detalle de un proyecto del Portal Empresa (solo lectura):
/// GET /portal-cliente/proyecto/{id}/detalles. Cabecera con avance, lista
/// expandible de servicios (progreso, pasos, cronograma y equipo), sección
/// de personal del proyecto y de equipos intervenidos.
class PortalProyectoDetalleScreen extends StatefulWidget {
  const PortalProyectoDetalleScreen({
    super.key,
    required this.proyectoId,
    required this.nombre,
  });

  final String proyectoId;
  final String nombre;

  @override
  State<PortalProyectoDetalleScreen> createState() =>
      _PortalProyectoDetalleScreenState();
}

class _PortalProyectoDetalleScreenState
    extends State<PortalProyectoDetalleScreen> {
  PortalService? _svc;
  PortalProyectoDetalle? _detalle;
  bool _cargando = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _svc = PortalService(ApiClient(prefs));
    await _cargar();
  }

  Future<void> _cargar() async {
    final svc = _svc;
    if (svc == null) return;
    setState(() {
      _cargando = true;
      _error = '';
    });
    final r = await svc.getProyectoDetalles(widget.proyectoId);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (r.ok && r.data != null) {
        _detalle = r.data;
      } else if (_detalle == null) {
        _error = r.errorMessage.isEmpty
            ? 'No se pudo cargar el proyecto.'
            : r.errorMessage;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.nombre.isEmpty ? 'Proyecto' : widget.nombre,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: _cargando && _detalle == null
          ? const Center(child: CircularProgressIndicator())
          : _detalle == null
              ? _vistaError()
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: _vistaDetalle(context, _detalle!),
                ),
    );
  }

  Widget _vistaError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                _error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _cargar,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );

  // ── Vista principal ────────────────────────────────────────────────────────

  Widget _vistaDetalle(BuildContext context, PortalProyectoDetalle d) {
    final secundario = Theme.of(context).colorScheme.onSurfaceVariant;
    final p = d.proyecto;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // ── Cabecera con avance ─────────────────────────────────────────────
        cardPortal(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.nombreProyecto.isEmpty
                            ? widget.nombre
                            : p.nombreProyecto,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 8),
                    chipEstado(p.estado),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (p.avancePct.clamp(0, 100)) / 100,
                    minHeight: 8,
                    color: colorPorEstado(
                        p.avancePct >= 100 ? 'completado' : 'en_proceso'),
                    backgroundColor: Colors.grey.withValues(alpha: 0.2),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${p.avancePct}% de avance',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: secundario),
                ),
                const SizedBox(height: 4),
                Text(
                  'Inicio: ${formatearFecha(p.fechaInicio)}  ·  '
                  'Fin estimado: ${formatearFecha(p.fechaFinEstimada)}',
                  style: TextStyle(fontSize: 11.5, color: secundario),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // ── Servicios ───────────────────────────────────────────────────────
        Text('Servicios (${d.servicios.length})',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (d.servicios.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text('Este proyecto no tiene servicios registrados.',
                  style: TextStyle(fontSize: 12.5, color: secundario)),
            ),
          ),
        for (final s in d.servicios) _tarjetaServicio(context, s),

        // ── Personal del proyecto ───────────────────────────────────────────
        if (d.personal.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('Personal del proyecto (${d.personal.length})',
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          cardPortal(
            child: Column(
              children: [
                for (final per in d.personal)
                  ListTile(
                    dense: true,
                    leading: _avatarPersona(context, per, radio: 17),
                    title: Text(
                      per.nombreCompleto.isEmpty ? 'Persona' : per.nombreCompleto,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      [per.cargo, per.rolProyecto]
                          .whereType<String>()
                          .join('  ·  '),
                      style: TextStyle(fontSize: 11, color: secundario),
                    ),
                  ),
              ],
            ),
          ),
        ],

        // ── Equipos intervenidos ────────────────────────────────────────────
        if (d.equipos.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('Equipos intervenidos (${d.equipos.length})',
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final e in d.equipos)
            cardPortal(
              child: ListTile(
                dense: true,
                leading: Icon(Icons.precision_manufacturing_outlined,
                    color: colorPorEstado(e.estado)),
                title: Text(
                  e.nombre.isEmpty ? 'Equipo' : e.nombre,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  [
                    if (e.codigo != null) e.codigo!,
                    [e.marca, e.modelo].whereType<String>().join(' '),
                  ].where((t) => t.isNotEmpty).join('  ·  '),
                  style: TextStyle(fontSize: 11, color: secundario),
                ),
                trailing: chipEstado(e.estado),
              ),
            ),
        ],
      ],
    );
  }

  // ── Servicio (ExpansionTile) ───────────────────────────────────────────────

  Widget _tarjetaServicio(BuildContext context, PortalServicio s) {
    final secundario = Theme.of(context).colorScheme.onSurfaceVariant;
    return cardPortal(
      child: Theme(
        // Quita los divisores por defecto del ExpansionTile.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Text(
            s.nombre.isEmpty ? 'Servicio' : s.nombre,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (s.progreso.clamp(0, 100)) / 100,
                      minHeight: 6,
                      color: colorPorEstado(
                          s.progreso >= 100 ? 'completado' : 'en_proceso'),
                      backgroundColor: Colors.grey.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${s.progreso}%',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: secundario)),
              ],
            ),
          ),
          leading: chipEstado(s.estado),
          children: [
            if (s.descripcion != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(s.descripcion!,
                      style: TextStyle(fontSize: 12, color: secundario)),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Programado: ${formatearFecha(s.fechaProgramada)}  ·  '
                'Inicio: ${formatearFecha(s.fechaInicio)}  ·  '
                'Fin: ${formatearFecha(s.fechaFin)}',
                style: TextStyle(fontSize: 11, color: secundario),
              ),
            ),

            // Pasos
            if (s.pasos.isNotEmpty) ...[
              _subtitulo(context, 'Pasos'),
              for (final paso in s.pasos)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Icon(
                        colorPorEstado(paso.estado) == kPortalVerde
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 16,
                        color: colorPorEstado(paso.estado),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(paso.nombre,
                            style: const TextStyle(fontSize: 12)),
                      ),
                      chipEstado(paso.estado),
                    ],
                  ),
                ),
            ],

            // Cronograma
            if (s.cronograma.isNotEmpty) ...[
              _subtitulo(context, 'Cronograma'),
              for (final t in s.cronograma)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          color: colorPorEstado(t.estado),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.nombre,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                            Text(
                              '${formatearFecha(t.fechaInicio)} → '
                              '${formatearFecha(t.fechaFin)}'
                              '${t.responsable != null ? '  ·  ${t.responsable}' : ''}',
                              style: TextStyle(
                                  fontSize: 10.5, color: secundario),
                            ),
                          ],
                        ),
                      ),
                      chipEstado(t.estado),
                    ],
                  ),
                ),
            ],

            // Equipo de trabajo
            if (s.equipo.isNotEmpty) ...[
              _subtitulo(context, 'Equipo de trabajo'),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    for (final per in s.equipo)
                      SizedBox(
                        width: 76,
                        child: Column(
                          children: [
                            _avatarPersona(context, per, radio: 22),
                            const SizedBox(height: 4),
                            Text(
                              per.nombreCompleto.isEmpty
                                  ? '—'
                                  : per.nombreCompleto,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600),
                            ),
                            if (per.cargo != null)
                              Text(
                                per.cargo!,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 9.5, color: secundario),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _subtitulo(BuildContext context, String texto) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            texto,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
          ),
        ),
      );

  Widget _avatarPersona(BuildContext context, PortalPersona p,
      {double radio = 20}) {
    final primario = Theme.of(context).colorScheme.primary;
    return CircleAvatar(
      radius: radio,
      backgroundColor: primario.withValues(alpha: 0.15),
      backgroundImage: p.fotoUrl != null ? NetworkImage(p.fotoUrl!) : null,
      child: p.fotoUrl == null
          ? Text(
              iniciales(p.nombre, p.apellido),
              style: TextStyle(
                fontSize: radio * 0.65,
                fontWeight: FontWeight.w800,
                color: primario,
              ),
            )
          : null,
    );
  }
}
