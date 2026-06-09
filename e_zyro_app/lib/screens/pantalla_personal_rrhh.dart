import 'package:flutter/material.dart';

import '../models/personal_models.dart';
import '../pdf/pdf_service.dart';
import '../pdf/pdf_preview_screen.dart';
import '../services/personal_service.dart';
import '../utils/abrir_enlace.dart';
import '../utils/api_provider.dart';

/// Personal/RR.HH. — lista de empleados → historial laboral consolidado y PDF
/// (Punto 3.1). Distinta de `PantallaPersonal` (gestión de sesiones/seguridad).
class PantallaPersonalRRHH extends StatefulWidget {
  const PantallaPersonalRRHH({super.key});

  @override
  State<PantallaPersonalRRHH> createState() => _PantallaPersonalRRHHState();
}

class _PantallaPersonalRRHHState extends State<PantallaPersonalRRHH> {
  PersonalService? _svc;
  final _busca = TextEditingController();
  List<Empleado> _empleados = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _svc = await getPersonalService();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    final r = await _svc!.listar(q: _busca.text);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (r.ok) {
        _empleados = r.data ?? [];
      } else {
        _error = r.errorMessage;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de personal', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _busca,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, cargo o código',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _cargar),
              ),
              onSubmitted: (_) => _cargar(),
            ),
          ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _empleados.isEmpty
                        ? const Center(child: Text('Sin empleados.'))
                        : RefreshIndicator(onRefresh: _cargar, child: _lista()),
          ),
        ],
      ),
    );
  }

  Widget _lista() {
    return ListView.separated(
      itemCount: _empleados.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final e = _empleados[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundImage: (e.fotoUrl != null && e.fotoUrl!.isNotEmpty) ? NetworkImage(e.fotoUrl!) : null,
            child: (e.fotoUrl == null || e.fotoUrl!.isEmpty) ? const Icon(Icons.person_outline) : null,
          ),
          title: Text(e.nombre ?? e.codigo ?? e.id),
          subtitle: Text([e.cargo, e.area].where((s) => s != null && s.isNotEmpty).join(' · ')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PantallaHistorialPersonal(empleado: e)),
          ),
        );
      },
    );
  }
}

/// Detalle del historial laboral de un empleado.
class PantallaHistorialPersonal extends StatefulWidget {
  final Empleado empleado;
  const PantallaHistorialPersonal({super.key, required this.empleado});

  @override
  State<PantallaHistorialPersonal> createState() => _PantallaHistorialPersonalState();
}

class _PantallaHistorialPersonalState extends State<PantallaHistorialPersonal> {
  HistorialPersonal? _h;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    final svc = await getPersonalService();
    final r = await svc.historial(widget.empleado.id);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (r.ok) {
        _h = r.data;
      } else {
        _error = r.errorMessage;
      }
    });
  }

  Future<void> _exportarPdf() async {
    final h = _h;
    if (h == null) return;
    final bytes = await PdfService.historialPersonal(h);
    if (!mounted) return;
    await PdfPreviewScreen.abrir(
      context,
      bytes: bytes,
      nombreArchivo: 'historial_personal_${widget.empleado.id}.pdf',
      titulo: 'Historial de personal',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.empleado.nombre ?? 'Historial',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_h != null)
            IconButton(
                onPressed: _exportarPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                tooltip: 'Exportar PDF'),
          IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _h == null
                  ? const Center(child: Text('Sin datos.'))
                  : _contenido(_h!),
    );
  }

  Widget _contenido(HistorialPersonal h) {
    final e = h.empleado;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _seccion('Datos del colaborador'),
        _kv('Código', e.codigo),
        _kv('Cargo', e.cargo),
        _kv('Área', e.area),
        _kv('Tipo', e.tipo),
        _kv('Ingreso', e.fechaIngreso),
        _kv('Fin contrato', e.fechaFinContrato),
        _kv('Estado', e.activo ? 'Activo' : 'Inactivo'),

        _seccion('Resumen de asistencia'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _chip('Total', h.asistencia.total, Colors.blueGrey),
          _chip('Validados', h.asistencia.validados, Colors.green),
          _chip('Pendientes', h.asistencia.pendientes, Colors.orange),
          _chip('Rechazados', h.asistencia.rechazados, Colors.red),
        ]),

        _seccion('Evaluaciones'),
        _kv('Total', '${h.evaluaciones.total}'),
        _kv('Promedio', h.evaluaciones.promedioGeneral?.toStringAsFixed(2)),
        _kv('Último periodo', h.evaluaciones.ultimoPeriodo),

        _seccion('Contratos (${h.contratos.length})'),
        if (h.contratos.isEmpty) _vacio('Sin contratos.')
        else ...h.contratos.map((c) => ListTile(
              dense: true,
              leading: const Icon(Icons.description_outlined),
              title: Text(c.tipo),
              subtitle: Text('${c.fechaInicio ?? '-'} → ${c.fechaFin ?? '-'} · ${c.estado ?? '-'}'),
            )),

        _seccion('Solicitudes (${h.solicitudes.length})'),
        if (h.solicitudes.isEmpty) _vacio('Sin solicitudes.')
        else ...h.solicitudes.map((s) => ListTile(
              dense: true,
              leading: const Icon(Icons.event_note_outlined),
              title: Text(s.tipo),
              subtitle: Text('${s.fechaInicio ?? '-'} → ${s.fechaFin ?? '-'} · ${s.estado ?? '-'}'),
              trailing: s.urlPdf != null
                  ? IconButton(
                      icon: const Icon(Icons.open_in_new, size: 18),
                      onPressed: () => abrirEnlace(s.urlPdf))
                  : null,
            )),

        _seccion('EPP entregado (${h.epp.length})'),
        if (h.epp.isEmpty) _vacio('Sin entregas.')
        else ...h.epp.map((x) => ListTile(
              dense: true,
              leading: const Icon(Icons.health_and_safety_outlined),
              title: Text('${x.fecha ?? '-'} · ${x.items} ítem(s)'),
              subtitle: Text(x.estado ?? '-'),
              trailing: x.pdfUrl != null
                  ? IconButton(
                      icon: const Icon(Icons.open_in_new, size: 18),
                      onPressed: () => abrirEnlace(x.pdfUrl))
                  : null,
            )),

        _seccion('Últimas marcaciones (${h.marcaciones.length})'),
        if (h.marcaciones.isEmpty) _vacio('Sin marcaciones.')
        else ...h.marcaciones.map((m) => ListTile(
              dense: true,
              leading: const Icon(Icons.access_time),
              title: Text(m.tipo),
              subtitle: Text('${m.fechaHora ?? '-'} · ${m.estado ?? '-'}'),
            )),
      ],
    );
  }

  Widget _seccion(String t) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(t.toUpperCase(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
      );

  Widget _kv(String k, String? v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 120, child: Text(k, style: const TextStyle(color: Colors.black54))),
          Expanded(child: Text((v == null || v.isEmpty) ? '—' : v)),
        ]),
      );

  Widget _chip(String k, int v, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$v', style: TextStyle(fontWeight: FontWeight.bold, color: c, fontSize: 16)),
          const SizedBox(width: 6),
          Text(k, style: const TextStyle(color: Colors.black54)),
        ]),
      );

  Widget _vacio(String t) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(t, style: const TextStyle(color: Colors.black45)));
}
