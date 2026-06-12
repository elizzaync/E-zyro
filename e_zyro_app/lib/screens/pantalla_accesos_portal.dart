import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../models/portal_acceso_models.dart';
import '../portal/portal_estilos.dart';
import '../services/portal_accesos_service.dart';

/// Administración de cuentas del Portal Empresa: el Admin crea, restablece o
/// revoca el acceso de cada cliente. La contraseña temporal solo viaja una
/// vez, por lo que se muestra en un diálogo con opción de copiar.
class PantallaAccesosPortal extends StatefulWidget {
  const PantallaAccesosPortal({super.key});

  @override
  State<PantallaAccesosPortal> createState() => _PantallaAccesosPortalState();
}

class _PantallaAccesosPortalState extends State<PantallaAccesosPortal> {
  PortalAccesosService? _svc;
  List<AccesoPortalCliente> _accesos = [];
  bool _cargando = true;
  String _error = '';
  String _busqueda = '';
  final TextEditingController _busquedaCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _svc = PortalAccesosService(ApiClient(prefs));
    await _cargar();
  }

  Future<void> _cargar() async {
    final svc = _svc;
    if (svc == null) return;
    setState(() {
      _cargando = true;
      _error = '';
    });
    final res = await svc.getAccesos();
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (res.ok) {
        _accesos = res.data ?? [];
      } else {
        _error = res.errorMessage;
      }
    });
  }

  List<AccesoPortalCliente> get _filtrados {
    final q = _busqueda.trim().toLowerCase();
    if (q.isEmpty) return _accesos;
    return _accesos
        .where((a) =>
            a.razonSocial.toLowerCase().contains(q) ||
            a.ruc.toLowerCase().contains(q))
        .toList();
  }

  // ── Acciones ────────────────────────────────────────────────────────────────

  Future<void> _crearAcceso(AccesoPortalCliente a) async {
    final ok = await _confirmar(
      'Crear acceso',
      'Se creará una cuenta del portal para "${a.razonSocial}" y se generará '
          'una contraseña temporal. ¿Continuar?',
    );
    if (ok != true || !mounted) return;
    final res = await _svc!.crearAcceso(a.clienteId);
    if (!mounted) return;
    if (res.ok && res.data != null) {
      await _mostrarCredenciales(res.data!);
      await _cargar();
    } else {
      _mostrarError(res.errorMessage);
    }
  }

  Future<void> _resetPassword(AccesoPortalCliente a, {bool reactivar = false}) async {
    final ok = await _confirmar(
      reactivar ? 'Reactivar acceso' : 'Restablecer contraseña',
      reactivar
          ? 'Se reactivará el acceso de "${a.razonSocial}" y se generará una '
              'nueva contraseña temporal. ¿Continuar?'
          : 'Se generará una nueva contraseña temporal para '
              '"${a.razonSocial}". La contraseña actual dejará de funcionar. '
              '¿Continuar?',
    );
    if (ok != true || !mounted) return;
    final res = await _svc!.resetPassword(a.clienteId);
    if (!mounted) return;
    if (res.ok && res.data != null) {
      await _mostrarCredenciales(res.data!);
      await _cargar();
    } else {
      _mostrarError(res.errorMessage);
    }
  }

  Future<void> _revocarAcceso(AccesoPortalCliente a) async {
    final ok = await _confirmar(
      'Revocar acceso',
      'El cliente "${a.razonSocial}" ya no podrá ingresar al portal. '
          '¿Revocar el acceso?',
      destructivo: true,
    );
    if (ok != true || !mounted) return;
    final res = await _svc!.revocarAcceso(a.clienteId);
    if (!mounted) return;
    if (res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Acceso revocado.')),
      );
      await _cargar();
    } else {
      _mostrarError(res.errorMessage);
    }
  }

  // ── Diálogos ────────────────────────────────────────────────────────────────

  Future<bool?> _confirmar(String titulo, String mensaje,
      {bool destructivo = false}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              destructivo ? 'Revocar' : 'Continuar',
              style: TextStyle(color: destructivo ? kPortalRojo : null),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarCredenciales(CredencialesPortal cred) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Credenciales del portal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _filaCredencial(ctx, 'Usuario', cred.username),
            const SizedBox(height: 10),
            _filaCredencial(ctx, 'Contraseña temporal', cred.passwordTemporal),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: kPortalAmbar.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kPortalAmbar.withValues(alpha: 0.45)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: kPortalAmbar, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Esta contraseña no se volverá a mostrar. Cópiala y '
                      'entrégala al cliente de forma segura.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copiar'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(
                text:
                    'Usuario: ${cred.username}\nContraseña: ${cred.passwordTemporal}',
              ));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Credenciales copiadas.')),
                );
              }
            },
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _filaCredencial(BuildContext ctx, String etiqueta, String valor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          etiqueta,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(
          valor,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  void _mostrarError(String mensaje) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No se pudo completar'),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Accesos Portal Cliente')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _busquedaCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar por razón social o RUC',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _busqueda.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _busquedaCtrl.clear();
                          setState(() => _busqueda = '');
                        },
                      ),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (v) => setState(() => _busqueda = v),
            ),
          ),
          Expanded(child: _buildCuerpo()),
        ],
      ),
    );
  }

  Widget _buildCuerpo() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 44, color: kPortalGris),
              const SizedBox(height: 12),
              Text(_error, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _cargar,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final lista = _filtrados;
    return RefreshIndicator(
      onRefresh: _cargar,
      child: lista.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 120),
                const Icon(Icons.business_outlined,
                    size: 44, color: kPortalGris),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    _busqueda.trim().isEmpty
                        ? 'No hay clientes activos para gestionar.'
                        : 'Sin resultados para "${_busqueda.trim()}".',
                    style: const TextStyle(color: kPortalGris),
                  ),
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: lista.length,
              itemBuilder: (_, i) => _buildFila(lista[i]),
            ),
    );
  }

  Widget _buildFila(AccesoPortalCliente a) {
    return cardPortal(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.razonSocial.isEmpty ? '(Sin razón social)' : a.razonSocial,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'RUC: ${a.ruc.isEmpty ? '—' : a.ruc}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _chipAcceso(a),
                      if (a.tieneAcceso && (a.username ?? '').isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            a.username!,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'monospace',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            _menuAcciones(a),
          ],
        ),
      ),
    );
  }

  Widget _chipAcceso(AccesoPortalCliente a) {
    final String texto;
    final Color color;
    if (!a.tieneAcceso) {
      texto = 'Sin acceso';
      color = kPortalGris;
    } else if (a.revocado) {
      texto = 'Revocado';
      color = kPortalRojo;
    } else {
      texto = 'Con acceso';
      color = kPortalVerde;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _menuAcciones(AccesoPortalCliente a) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      tooltip: 'Acciones',
      onSelected: (accion) {
        switch (accion) {
          case 'crear':
            _crearAcceso(a);
          case 'reset':
            _resetPassword(a);
          case 'reactivar':
            _resetPassword(a, reactivar: true);
          case 'revocar':
            _revocarAcceso(a);
        }
      },
      itemBuilder: (_) {
        if (!a.tieneAcceso) {
          return const [
            PopupMenuItem(
              value: 'crear',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.person_add_alt_outlined, size: 20),
                title: Text('Crear acceso'),
              ),
            ),
          ];
        }
        if (a.revocado) {
          return const [
            PopupMenuItem(
              value: 'reactivar',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.restart_alt_outlined, size: 20),
                title: Text('Reactivar (nueva contraseña)'),
              ),
            ),
          ];
        }
        return const [
          PopupMenuItem(
            value: 'reset',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.lock_reset_outlined, size: 20),
              title: Text('Restablecer contraseña'),
            ),
          ),
          PopupMenuItem(
            value: 'revocar',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading:
                  Icon(Icons.person_off_outlined, size: 20, color: kPortalRojo),
              title: Text('Revocar acceso',
                  style: TextStyle(color: kPortalRojo)),
            ),
          ),
        ];
      },
    );
  }
}
