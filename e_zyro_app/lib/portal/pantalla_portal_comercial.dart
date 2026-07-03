import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../core/api_client.dart';

/// Tab "Comercial" del portal cliente: cotizaciones recibidas (con
/// aceptar/rechazar y PDF) y estado de cuenta (facturas y saldos).
class PantallaPortalComercial extends StatefulWidget {
  final ApiClient client;
  const PantallaPortalComercial({super.key, required this.client});

  @override
  State<PantallaPortalComercial> createState() =>
      _PantallaPortalComercialState();
}

class _PantallaPortalComercialState extends State<PantallaPortalComercial> {
  int _seccion = 0; // 0 = cotizaciones, 1 = estado de cuenta
  List<dynamic>? _cotizaciones;
  Map<String, dynamic>? _cuenta;
  bool _cargando = true;
  bool _accion = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = null; });
    try {
      final rc = await widget.client.get('/portal-cliente/cotizaciones');
      final re = await widget.client.get('/portal-cliente/estado-cuenta');
      if (!mounted) return;
      setState(() {
        _cargando = false;
        if (rc.statusCode == 200) _cotizaciones = jsonDecode(rc.body) as List;
        if (re.statusCode == 200) {
          _cuenta = jsonDecode(re.body) as Map<String, dynamic>;
        }
        if (rc.statusCode != 200 && re.statusCode != 200) {
          _error = 'No se pudo cargar la información comercial';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _cargando = false; _error = 'Sin conexión'; });
    }
  }

  Future<void> _responder(String id, String estado) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(estado == 'aceptada'
            ? '¿Aceptar la cotización?'
            : '¿Rechazar la cotización?'),
        content: const Text('Esta acción se registrará y no puede deshacerse.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor:
                    estado == 'aceptada' ? Colors.green : Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(estado == 'aceptada' ? 'Aceptar' : 'Rechazar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    setState(() => _accion = true);
    try {
      final r = await widget.client.post(
          '/portal-cliente/cotizaciones/$id/responder', {'estado': estado});
      if (!mounted) return;
      setState(() => _accion = false);
      if (r.statusCode == 200) {
        _cargar();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo registrar la respuesta')));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _accion = false);
    }
  }

  Future<void> _pdf(String id, String numero) async {
    try {
      final r = await widget.client.get('/portal-cliente/cotizaciones/$id/pdf');
      if (r.statusCode == 200) {
        await Printing.sharePdf(bytes: r.bodyBytes, filename: '$numero.pdf');
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                  value: 0,
                  label: Text('Cotizaciones'),
                  icon: Icon(Icons.request_quote_outlined, size: 16)),
              ButtonSegment(
                  value: 1,
                  label: Text('Estado de cuenta'),
                  icon: Icon(Icons.receipt_long_outlined, size: 16)),
            ],
            selected: {_seccion},
            onSelectionChanged: (s) => setState(() => _seccion = s.first),
          ),
        ),
        Expanded(
          child: _cargando
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: _seccion == 0 ? _vistaCotizaciones() : _vistaCuenta(),
                    ),
        ),
      ],
    );
  }

  // ── Cotizaciones ────────────────────────────────────────────────────────────
  Widget _vistaCotizaciones() {
    final cots = _cotizaciones ?? [];
    if (cots.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 120),
        Center(
            child: Text('No tienes cotizaciones',
                style: TextStyle(color: Colors.grey))),
      ]);
    }
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: cots.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _cardCotizacion(cots[i] as Map<String, dynamic>),
    );
  }

  Widget _cardCotizacion(Map<String, dynamic> c) {
    final estado = c['estado']?.toString() ?? '';
    final color = switch (estado) {
      'enviada' => Colors.orange,
      'aceptada' => Colors.green,
      'convertida' => Colors.indigo,
      'rechazada' => Colors.red,
      _ => Colors.grey,
    };
    final items = (c['items'] as List? ?? []);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(c['numero']?.toString() ?? '',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(estado,
                      style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Emitida ${c['fecha_emision']} · válida hasta ${c['vence']}',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const Divider(height: 18),
            for (final it in items.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text((it as Map)['descripcion']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12)),
                    ),
                    Text('S/ ${(it['total'] as num?)?.toStringAsFixed(2) ?? ''}',
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            if (items.length > 4)
              Text('… y ${items.length - 4} ítems más',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                  'TOTAL S/ ${(c['total'] as num?)?.toStringAsFixed(2) ?? ''}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () =>
                      _pdf(c['id'].toString(), c['numero']?.toString() ?? 'cotizacion'),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 17),
                  label: const Text('PDF'),
                ),
                const Spacer(),
                if (estado == 'enviada') ...[
                  OutlinedButton(
                    onPressed: _accion
                        ? null
                        : () => _responder(c['id'].toString(), 'rechazada'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Rechazar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _accion
                        ? null
                        : () => _responder(c['id'].toString(), 'aceptada'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.green),
                    child: const Text('Aceptar'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Estado de cuenta ────────────────────────────────────────────────────────
  Widget _vistaCuenta() {
    final cuenta = _cuenta;
    if (cuenta == null) {
      return ListView(children: const [
        SizedBox(height: 120),
        Center(
            child: Text('Sin información de cuenta',
                style: TextStyle(color: Colors.grey))),
      ]);
    }
    final docs = (cuenta['documentos'] as List? ?? []);
    final pendiente = (cuenta['total_pendiente'] as num?)?.toDouble() ?? 0;
    final vencido = (cuenta['total_vencido'] as num?)?.toDouble() ?? 0;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          children: [
            Expanded(
                child: _kpi('Saldo pendiente', pendiente,
                    pendiente > 0 ? Colors.orange : Colors.green)),
            const SizedBox(width: 10),
            Expanded(
                child: _kpi('Vencido', vencido,
                    vencido > 0 ? Colors.red : Colors.green)),
          ],
        ),
        const SizedBox(height: 14),
        if (docs.isEmpty)
          const Center(
              child: Padding(
            padding: EdgeInsets.only(top: 60),
            child: Text('No tienes comprobantes',
                style: TextStyle(color: Colors.grey)),
          ))
        else
          for (final d in docs) _cardDocumento(d as Map<String, dynamic>),
      ],
    );
  }

  Widget _kpi(String titulo, double v, Color c) {
    return Card(
      color: c.withValues(alpha: 0.07),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(titulo,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 4),
            FittedBox(
              child: Text('S/ ${v.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: c)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardDocumento(Map<String, dynamic> d) {
    final saldo = (d['saldo'] as num?)?.toDouble() ?? 0;
    final vencida = d['vencida'] == true;
    final pagada = saldo <= 0;
    final color = pagada ? Colors.green : (vencida ? Colors.red : Colors.orange);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: Icon(
            pagada ? Icons.check_circle_outline : Icons.schedule_outlined,
            color: color),
        title: Text('${d['tipo']} ${d['numero']}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text(
          'Emitida ${d['fecha_emision'] ?? '-'}'
          '${d['fecha_vencimiento'] != null ? ' · vence ${d['fecha_vencimiento']}' : ''}',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('S/ ${(d['total'] as num?)?.toStringAsFixed(2) ?? ''}',
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700)),
            Text(
                pagada
                    ? 'pagada'
                    : 'saldo S/ ${saldo.toStringAsFixed(2)}${vencida ? ' · VENCIDA' : ''}',
                style: TextStyle(fontSize: 10.5, color: color)),
          ],
        ),
      ),
    );
  }
}
