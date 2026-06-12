import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/api_client.dart';
import '../core/api_result.dart';
import '../services/auth_service.dart';
import 'pantalla_portal_proyecto.dart';
import 'portal_estilos.dart';
import 'portal_models.dart';
import 'portal_service.dart';

/// Shell del "Portal Empresa": vista exclusiva para clientes externos
/// (rol ClienteExterno). Consume únicamente `/portal-cliente/*` (solo
/// lectura) y NO expone nada del sistema interno.
///
/// 4 tabs: Inicio (KPIs + resumen), Proyectos, Equipos y Documentos.
class PortalShell extends StatefulWidget {
  const PortalShell({super.key});

  @override
  State<PortalShell> createState() => _PortalShellState();
}

class _PortalShellState extends State<PortalShell> {
  SharedPreferences? _prefs;
  ApiClient? _client;
  PortalService? _svc;
  PortalPerfil? _perfil;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _client = ApiClient(prefs);
      _svc = PortalService(_client!);
    });
    _cargarPerfil(); // lazy: el AppBar se actualiza cuando llegue
  }

  Future<void> _cargarPerfil() async {
    final svc = _svc;
    if (svc == null || _perfil != null) return;
    final r = await svc.getPerfil();
    if (!mounted) return;
    if (r.ok && r.data != null) setState(() => _perfil = r.data);
  }

  // ── Menú (perfil / cerrar sesión) ──────────────────────────────────────────

  Future<void> _mostrarPerfil() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_perfil == null && _svc != null) {
      final r = await _svc!.getPerfil();
      if (r.ok && r.data != null) _perfil = r.data;
    }
    if (!mounted) return;
    final p = _perfil;
    if (p == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo cargar el perfil.')),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _HojaPerfil(perfil: p),
    );
  }

  Future<void> _cerrarSesion() async {
    final navigator = Navigator.of(context);
    final client = _client;
    final prefs = _prefs;
    if (client == null || prefs == null) return;
    await AuthService(client, prefs).logout();
    navigator.pushNamedAndRemoveUntil('/login', (r) => false);
  }

  // ── Carga combinada del tab Inicio ─────────────────────────────────────────

  Future<ApiResult<_DatosInicio>> _cargarInicio() async {
    final svc = _svc!;
    final fKpis = svc.getKpis();
    final fDash = svc.getDashboard();
    final kpis = await fKpis;
    final dash = await fDash;
    if (!kpis.ok || kpis.data == null) return ApiResult.fail(kpis.error);
    if (!dash.ok || dash.data == null) return ApiResult.fail(dash.error);
    return ApiResult.ok(_DatosInicio(kpis.data!, dash.data!));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final empresa = _perfil?.empresa ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          empresa.isEmpty ? 'Portal Empresa' : empresa,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'Cuenta',
            onSelected: (v) {
              if (v == 'perfil') {
                _mostrarPerfil();
              } else if (v == 'salir') {
                _cerrarSesion();
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'perfil',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.person_outline),
                  title: Text('Mi perfil'),
                ),
              ),
              PopupMenuItem(
                value: 'salir',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout_outlined),
                  title: Text('Cerrar sesión'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: _svc == null
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(
              index: _tab,
              children: [
                _TabCargador<_DatosInicio>(
                  cargar: _cargarInicio,
                  builder: _vistaInicio,
                ),
                _TabCargador<List<PortalProyecto>>(
                  cargar: () => _svc!.getProyectos(),
                  builder: _vistaProyectos,
                ),
                _TabCargador<List<PortalEquipoHistorial>>(
                  cargar: () => _svc!.getEquiposHistorial(),
                  builder: _vistaEquipos,
                ),
                _TabCargador<List<PortalDocumento>>(
                  cargar: () => _svc!.getDocumentos(),
                  builder: _vistaDocumentos,
                ),
              ],
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        onTap: (i) => setState(() => _tab = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.folder_open_outlined),
            activeIcon: Icon(Icons.folder),
            label: 'Proyectos',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.handyman_outlined),
            activeIcon: Icon(Icons.handyman),
            label: 'Equipos',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.description_outlined),
            activeIcon: Icon(Icons.description),
            label: 'Documentos',
          ),
        ],
      ),
    );
  }

  // ── Tab Inicio ─────────────────────────────────────────────────────────────

  Widget _vistaInicio(BuildContext context, _DatosInicio datos) {
    final k = datos.kpis;
    final d = datos.dashboard;
    final secundario = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.1,
          children: [
            _TarjetaKpi(
              icono: Icons.precision_manufacturing_outlined,
              color: Theme.of(context).colorScheme.primary,
              titulo: 'Total equipos',
              valor: k.totalEquipos,
            ),
            _TarjetaKpi(
              icono: Icons.check_circle_outline,
              color: kPortalVerde,
              titulo: 'Mant. completados',
              valor: k.mantenimientosCompletados,
            ),
            _TarjetaKpi(
              icono: Icons.autorenew_outlined,
              color: kPortalAmbar,
              titulo: 'En proceso',
              valor: k.enProceso,
            ),
            _TarjetaKpi(
              icono: Icons.event_outlined,
              color: kPortalRojo,
              titulo: 'Próximos 30 días',
              valor: k.proximos30Dias,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _TarjetaResumen(
                icono: Icons.folder_open_outlined,
                titulo: 'Proyectos activos',
                valor: d.proyectosActivos,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _TarjetaResumen(
                icono: Icons.task_alt_outlined,
                titulo: 'Completados este mes',
                valor: d.completadosEsteMes,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const _TituloSeccion('Próximos mantenimientos'),
        const SizedBox(height: 8),
        if (d.proximosMantenimientos.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Text(
                'No hay mantenimientos programados.',
                style: TextStyle(fontSize: 13, color: secundario),
              ),
            ),
          ),
        for (final m in d.proximosMantenimientos)
          cardPortal(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.event_repeat_outlined,
                      size: 22, color: colorPorEstado(m.estado)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.nombre.isEmpty ? 'Mantenimiento' : m.nombre,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        if (m.proyecto.isNotEmpty)
                          Text(
                            m.proyecto,
                            style:
                                TextStyle(fontSize: 11.5, color: secundario),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        Text(
                          formatearFecha(m.fechaProgramada,
                              vacio: 'Sin fecha programada'),
                          style: TextStyle(fontSize: 11.5, color: secundario),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  chipEstado(m.estado),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ── Tab Proyectos ──────────────────────────────────────────────────────────

  Widget _vistaProyectos(BuildContext context, List<PortalProyecto> proyectos) {
    final secundario = Theme.of(context).colorScheme.onSurfaceVariant;
    if (proyectos.isEmpty) {
      return _ListaVacia(mensaje: 'No tienes proyectos registrados.');
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: proyectos.length,
      itemBuilder: (ctx, i) {
        final p = proyectos[i];
        return cardPortal(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PortalProyectoDetalleScreen(
                  proyectoId: p.id,
                  nombre: p.nombreProyecto,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.nombreProyecto.isEmpty
                              ? 'Proyecto'
                              : p.nombreProyecto,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 8),
                      chipEstado(p.estado),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (p.avancePct.clamp(0, 100)) / 100,
                      minHeight: 7,
                      color: colorPorEstado(
                          p.avancePct >= 100 ? 'completado' : 'en_proceso'),
                      backgroundColor:
                          Colors.grey.withValues(alpha: 0.2),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        '${p.avancePct}% de avance',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: secundario),
                      ),
                      const Spacer(),
                      Text(
                        '${p.serviciosCompletados}/${p.totalServicios} servicios',
                        style: TextStyle(fontSize: 11.5, color: secundario),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Inicio: ${formatearFecha(p.fechaInicio)}  ·  '
                    'Fin estimado: ${formatearFecha(p.fechaFinEstimada)}',
                    style: TextStyle(fontSize: 11, color: secundario),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Tab Equipos ────────────────────────────────────────────────────────────

  Widget _vistaEquipos(
      BuildContext context, List<PortalEquipoHistorial> equipos) {
    final secundario = Theme.of(context).colorScheme.onSurfaceVariant;
    if (equipos.isEmpty) {
      return _ListaVacia(mensaje: 'No hay equipos registrados.');
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: equipos.length,
      itemBuilder: (ctx, i) {
        final e = equipos[i];
        final detalle = [
          if (e.codigo != null) e.codigo!,
          [e.marca, e.modelo].whereType<String>().join(' '),
        ].where((s) => s.isNotEmpty).join('  ·  ');
        return cardPortal(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.nombre.isEmpty ? 'Equipo' : e.nombre,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    chipEstado(e.estadoIntervencion.isEmpty
                        ? e.estado
                        : e.estadoIntervencion),
                  ],
                ),
                if (detalle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(detalle,
                        style: TextStyle(fontSize: 11.5, color: secundario)),
                  ),
                if (e.ubicacion != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        Icon(Icons.place_outlined, size: 13, color: secundario),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            e.ubicacion!,
                            style:
                                TextStyle(fontSize: 11.5, color: secundario),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Último mant.: ${formatearFecha(e.ultimoMantenimiento)}',
                        style: TextStyle(fontSize: 11, color: secundario),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Próximo: ${formatearFecha(e.proximoMantenimiento)}'
                        '${e.frecuenciaMeses != null ? ' (c/${e.frecuenciaMeses} meses)' : ''}',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: secundario),
                      ),
                    ),
                  ],
                ),
                if (e.proyecto != null || e.servicio != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      [e.proyecto, e.servicio]
                          .whereType<String>()
                          .join('  ·  '),
                      style: TextStyle(fontSize: 11, color: secundario),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Tab Documentos ─────────────────────────────────────────────────────────

  static IconData _iconoDocumento(String tipo) {
    final t = tipo.toLowerCase();
    if (t.contains('pdf') || t.contains('certificado')) {
      return Icons.picture_as_pdf_outlined;
    }
    if (t.contains('informe') || t.contains('reporte')) {
      return Icons.assignment_outlined;
    }
    if (t.contains('carta') || t.contains('garant')) {
      return Icons.verified_outlined;
    }
    if (t.contains('foto') || t.contains('imagen')) {
      return Icons.image_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  Future<void> _abrirDocumento(PortalDocumento d) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = d.url.isEmpty ? null : Uri.tryParse(d.url);
    if (uri == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('El documento no tiene enlace disponible.')),
      );
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No se pudo abrir el documento.')),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el documento.')),
      );
    }
  }

  Widget _vistaDocumentos(BuildContext context, List<PortalDocumento> docs) {
    final secundario = Theme.of(context).colorScheme.onSurfaceVariant;
    if (docs.isEmpty) {
      return _ListaVacia(mensaje: 'Aún no hay documentos publicados.');
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: docs.length,
      itemBuilder: (ctx, i) {
        final d = docs[i];
        final sub = [
          if (d.proyecto != null) d.proyecto!,
          if (d.servicio != null) d.servicio!,
          formatearFecha(d.fecha ?? d.createdAt, vacio: ''),
        ].where((s) => s.isNotEmpty).join('  ·  ');
        return cardPortal(
          child: ListTile(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            leading: Icon(_iconoDocumento(d.tipo),
                color: Theme.of(context).colorScheme.primary),
            title: Text(
              d.titulo.isEmpty
                  ? (d.tipo.isEmpty ? 'Documento' : etiquetaEstado(d.tipo))
                  : d.titulo,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            subtitle: sub.isEmpty
                ? null
                : Text(sub,
                    style: TextStyle(fontSize: 11.5, color: secundario),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _abrirDocumento(d),
          ),
        );
      },
    );
  }
}

// ── Datos combinados del tab Inicio ───────────────────────────────────────────

class _DatosInicio {
  final PortalKpis kpis;
  final PortalDashboard dashboard;
  _DatosInicio(this.kpis, this.dashboard);
}

// ── Cargador genérico de tab: carga + error/reintentar + pull-to-refresh ─────

class _TabCargador<T> extends StatefulWidget {
  const _TabCargador({super.key, required this.cargar, required this.builder});

  final Future<ApiResult<T>> Function() cargar;
  final Widget Function(BuildContext context, T datos) builder;

  @override
  State<_TabCargador<T>> createState() => _TabCargadorState<T>();
}

class _TabCargadorState<T> extends State<_TabCargador<T>> {
  T? _datos;
  bool _cargando = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    final r = await widget.cargar();
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (r.ok && r.data != null) {
        _datos = r.data;
      } else if (_datos == null) {
        _error = r.errorMessage.isEmpty
            ? 'No se pudo cargar la información.'
            : r.errorMessage;
      }
    });
    // Si el refresh falla pero ya había datos, se conservan y se avisa.
    if (!r.ok && _datos != null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(r.errorMessage)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando && _datos == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_datos == null) {
      return Center(
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
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: widget.builder(context, _datos as T),
    );
  }
}

// ── Widgets de apoyo ──────────────────────────────────────────────────────────

class _TarjetaKpi extends StatelessWidget {
  const _TarjetaKpi({
    required this.icono,
    required this.color,
    required this.titulo,
    required this.valor,
  });

  final IconData icono;
  final Color color;
  final String titulo;
  final int valor;

  @override
  Widget build(BuildContext context) {
    final secundario = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icono, size: 26, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$valor',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800)),
                Text(titulo,
                    style: TextStyle(fontSize: 11, color: secundario),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaResumen extends StatelessWidget {
  const _TarjetaResumen({
    required this.icono,
    required this.titulo,
    required this.valor,
  });

  final IconData icono;
  final String titulo;
  final int valor;

  @override
  Widget build(BuildContext context) {
    final secundario = Theme.of(context).colorScheme.onSurfaceVariant;
    return cardPortal(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Icon(icono, size: 22, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$valor',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800)),
                  Text(titulo,
                      style: TextStyle(fontSize: 10.5, color: secundario),
                      maxLines: 2),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TituloSeccion extends StatelessWidget {
  const _TituloSeccion(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Text(
        texto,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      );
}

class _ListaVacia extends StatelessWidget {
  const _ListaVacia({required this.mensaje});
  final String mensaje;

  @override
  Widget build(BuildContext context) {
    // ListView para que el pull-to-refresh siga funcionando con lista vacía.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        Center(
          child: Text(
            mensaje,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

// ── Hoja "Mi perfil" ──────────────────────────────────────────────────────────

class _HojaPerfil extends StatelessWidget {
  const _HojaPerfil({required this.perfil});
  final PortalPerfil perfil;

  Widget _fila(BuildContext context, IconData icono, String etiqueta,
      String? valor) {
    if (valor == null || valor.isEmpty) return const SizedBox.shrink();
    final secundario = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 18, color: secundario),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: Text(etiqueta,
                style: TextStyle(fontSize: 12, color: secundario)),
          ),
          Expanded(
            child: Text(valor,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = perfil;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
              backgroundImage:
                  p.fotoUrl != null ? NetworkImage(p.fotoUrl!) : null,
              child: p.fotoUrl == null
                  ? Text(
                      iniciales(p.nombre, p.apellido),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 10),
            Text(
              p.nombreCompleto.isEmpty ? 'Cliente' : p.nombreCompleto,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            if (p.rol != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: chipEstado(p.rol),
              ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 10),
            _fila(context, Icons.business_outlined, 'Empresa', p.empresa),
            _fila(context, Icons.badge_outlined, 'RUC', p.ruc),
            _fila(context, Icons.mail_outline, 'Correo', p.correo),
            _fila(context, Icons.phone_outlined, 'Teléfono', p.telefono),
            _fila(context, Icons.alternate_email_outlined, 'Email empresa',
                p.empresaEmail),
            _fila(
              context,
              Icons.calendar_today_outlined,
              'Cliente desde',
              p.fechaCreacion == null
                  ? null
                  : formatearFecha(p.fechaCreacion),
            ),
          ],
        ),
      ),
    );
  }
}
