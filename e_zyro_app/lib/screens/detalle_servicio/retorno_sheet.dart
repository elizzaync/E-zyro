// Sheet "Declarar Devolución": al finalizar un servicio, el técnico indica
// qué materiales/equipos/herramientas retornan al almacén. Espejo del modal
// Angular "Declarar devolución" (operaciones-detalle.component.html).
part of '../pantalla_detalle_servicio.dart';

/// Abre el sheet de declaración de devolución. Devuelve `true` si se registró
/// correctamente (para que el llamador refresque el estado del servicio).
Future<bool> abrirDeclararRetornoSheet(
  BuildContext context, {
  required String servicioId,
  required List<RetornoItemPendiente> items,
  required RetornoService service,
  bool obligatorio = false,
}) async {
  final resultado = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: !obligatorio,
    enableDrag: !obligatorio,
    backgroundColor: Colors.transparent,
    builder: (_) => _DeclararRetornoSheet(
      servicioId: servicioId,
      items: items,
      service: service,
      obligatorio: obligatorio,
    ),
  );
  return resultado == true;
}

class _DeclararRetornoSheet extends StatefulWidget {
  final String servicioId;
  final List<RetornoItemPendiente> items;
  final RetornoService service;
  final bool obligatorio;

  const _DeclararRetornoSheet({
    required this.servicioId,
    required this.items,
    required this.service,
    required this.obligatorio,
  });

  @override
  State<_DeclararRetornoSheet> createState() => _DeclararRetornoSheetState();
}

class _DeclararRetornoSheetState extends State<_DeclararRetornoSheet> {
  final _notaCtrl = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _notaCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _completarObligatorios() {
    setState(() {
      for (final it in widget.items) {
        if (it.esObligatorio) it.cantidadRetornada = it.cantidadEntregada;
      }
    });
  }

  void _nadaRetorna() {
    setState(() {
      for (final it in widget.items) {
        it.cantidadRetornada = 0;
      }
    });
  }

  Future<void> _enviar() async {
    final sinRetorno =
        widget.items.where((it) => it.esObligatorio && it.cantidadRetornada <= 0).toList();
    if (sinRetorno.isNotEmpty) {
      _snack(
        'Debes indicar la cantidad a devolver de: ${sinRetorno.map((i) => i.nombre).join(', ')}',
        _danger,
      );
      return;
    }

    setState(() => _enviando = true);
    final res = await widget.service.crearDesdeServicio(
      proyectoServicioId: widget.servicioId,
      items: widget.items,
      notaTecnico: _notaCtrl.text,
    );
    if (!mounted) return;
    setState(() => _enviando = false);

    if (res.ok) {
      _snack('Devolución registrada correctamente. Logística recibirá los ítems.', _green);
      Navigator.pop(context, true);
      return;
    }
    if (res.error?.kind == ApiErrorKind.conflict) {
      _snack('La devolución ya fue registrada por otro técnico del equipo.', const Color(0xFF3E80C0));
      Navigator.pop(context, true);
      return;
    }
    _snack(res.errorMessage.isEmpty ? 'Error al registrar la devolución.' : res.errorMessage, _danger);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final maxH = MediaQuery.of(context).size.height * 0.85;
    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottom),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Declarar devolución',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(
            'Indica qué materiales, equipos y herramientas estás devolviendo al almacén.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          ),
          if (widget.obligatorio) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: _danger.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 15, color: _danger),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Acción obligatoria — debes registrar la devolución para continuar',
                      style: TextStyle(fontSize: 11.5, color: _danger, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _nadaRetorna,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Nada retorna (consumible)', style: TextStyle(fontSize: 12.5)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _completarObligatorios,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _danger,
                    side: const BorderSide(color: _danger),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Completar obligatorios', style: TextStyle(fontSize: 12.5)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final it in widget.items) _ItemRetornoTile(item: it),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notaCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Observaciones (opcional)',
              hintText: 'Ej: Equipo con golpe en la carcasa, cable dañado…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (!widget.obligatorio) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _enviando ? null : () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 13)),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                flex: widget.obligatorio ? 1 : 1,
                child: ElevatedButton(
                  onPressed: _enviando ? null : _enviar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _enviando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          widget.obligatorio ? 'Registrar devolución (obligatorio)' : 'Registrar devolución',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ItemRetornoTile extends StatefulWidget {
  final RetornoItemPendiente item;
  const _ItemRetornoTile({required this.item});

  @override
  State<_ItemRetornoTile> createState() => _ItemRetornoTileState();
}

class _ItemRetornoTileState extends State<_ItemRetornoTile> {
  late final TextEditingController _ctrl =
      TextEditingController(text: '${widget.item.cantidadRetornada}');

  @override
  void didUpdateWidget(covariant _ItemRetornoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final actual = int.tryParse(_ctrl.text) ?? -1;
    if (actual != widget.item.cantidadRetornada) {
      _ctrl.text = '${widget.item.cantidadRetornada}';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String get _tipoLabel => switch (widget.item.tipoItem) {
        'material' => 'Material',
        'equipo' => 'Equipo',
        _ => 'Herramienta',
      };

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: it.esObligatorio ? _danger.withValues(alpha: .35) : Colors.grey.shade300,
          width: it.esObligatorio ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (it.esObligatorio ? _danger : const Color(0xFF8FD11B)).withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(_tipoLabel,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: it.esObligatorio ? _danger : const Color(0xFF1E9462))),
              ),
              if (it.esObligatorio)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: _danger.withValues(alpha: .1), borderRadius: BorderRadius.circular(4)),
                  child: const Text('OBLIGATORIO',
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: _danger)),
                ),
              Text(it.nombre, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Entregado', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
                  Text('${it.cantidadEntregada}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(width: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Devolver', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
                  SizedBox(
                    width: 70,
                    height: 34,
                    child: TextField(
                      controller: _ctrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 13.5),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        var n = int.tryParse(v) ?? 0;
                        if (n < 0) n = 0;
                        if (n > it.cantidadEntregada) n = it.cantidadEntregada;
                        it.cantidadRetornada = n;
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
