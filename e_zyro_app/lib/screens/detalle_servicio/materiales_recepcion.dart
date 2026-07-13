// Materiales: recepcion (HU-16) — tarjeta + sheet de firma.
part of '../pantalla_detalle_servicio.dart';

// ─── Recepción de materiales: tarjeta AGRUPADA por etapa + firma (HU-16) ──────
// Varias solicitudes de la misma etapa se juntan en una sola tarjeta. En la
// etapa "listo para recibir" una sola firma recibe todas a la vez.

const _kBlueRecepcion = Color(0xFF3E80C0);

class _RecepcionGrupoCard extends StatelessWidget {
  final String bucket; // 'listo' | 'compra' | 'recibido' | 'cerrado'
  final List<ReqRecepcion> reqs;
  final bool firmando; // firma de lote en progreso (solo bucket 'listo')
  final VoidCallback? onFirmar; // solo bucket 'listo'

  const _RecepcionGrupoCard({
    required this.bucket,
    required this.reqs,
    this.firmando = false,
    this.onFirmar,
  });

  (String, Color, IconData) get _cfg => switch (bucket) {
        'cerrado' => ('Cerrado por logística', _green, Icons.verified_outlined),
        'recibido' => ('Recibido · pendiente cierre log', _kBlueRecepcion,
            Icons.assignment_turned_in_outlined),
        'compra' => ('En compra · llegará pronto', _amber,
            Icons.shopping_cart_outlined),
        _ => ('Listo para recibir', _green, Icons.inventory_2_outlined),
      };

  @override
  Widget build(BuildContext context) {
    if (reqs.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final (titulo, colorEstado, iconoEstado) = _cfg;
    final alguienFirmando = reqs.any((r) => r.hayAlguienFirmando);
    final firmandoPor = reqs
        .firstWhere((r) => r.hayAlguienFirmando,
            orElse: () => reqs.first)
        .firmandoPorNombre;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: colorEstado.withValues(alpha: isDark ? 0.30 : 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(iconoEstado, size: 16, color: colorEstado),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: colorEstado.withValues(alpha: isDark ? 1 : 0.9)),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorEstado.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${reqs.length} solicitud(es)',
                    style: TextStyle(
                        color: colorEstado,
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Cada solicitud del grupo, distinguible pero dentro de la misma tarjeta.
          for (var i = 0; i < reqs.length; i++) ...[
            if (i > 0)
              Divider(height: 18, color: Colors.grey.withValues(alpha: 0.25)),
            _reqBloque(context, reqs[i], isDark),
          ],
          const SizedBox(height: 12),
          ..._footer(context, alguienFirmando, firmandoPor),
        ],
      ),
    );
  }

  Widget _reqBloque(BuildContext context, ReqRecepcion req, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Solicitado por ${req.solicitanteNombre}'
                '${req.fecha != null ? ' · ${req.fecha}' : ''}',
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ),
            Text(
                'REQ ${req.id.substring(0, req.id.length >= 6 ? 6 : req.id.length).toUpperCase()}',
                style: const TextStyle(
                    color: Colors.grey, fontSize: 10, fontFamily: 'monospace')),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: req.itemsValidos
              .map((it) => Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${it.nombre} × ${it.cantidadEfectiva} ${it.unidad}'
                      '${it.esCompra ? ' (compra)' : ''}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }

  List<Widget> _footer(
      BuildContext context, bool alguienFirmando, String? firmandoPor) {
    switch (bucket) {
      case 'cerrado':
        return const [
          Row(children: [
            Icon(Icons.verified, size: 16, color: _green),
            SizedBox(width: 6),
            Expanded(
              child: Text('Cerrado · doble firma archivada',
                  style: TextStyle(
                      color: _green, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          ]),
        ];
      case 'recibido':
        return const [
          Row(children: [
            Icon(Icons.check_circle, size: 16, color: _kBlueRecepcion),
            SizedBox(width: 6),
            Expanded(
              child: Text('Firmado por el equipo · esperando cierre de logística',
                  style: TextStyle(
                      color: _kBlueRecepcion,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ),
          ]),
        ];
      case 'compra':
        return const [
          Row(children: [
            Icon(Icons.schedule, size: 16, color: _amber),
            SizedBox(width: 6),
            Expanded(
              child: Text('Sin stock · en proceso de compra',
                  style: TextStyle(
                      color: _amber, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          ]),
        ];
      default: // 'listo'
        return [
          if (alguienFirmando && !firmando)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: _amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _amber.withValues(alpha: 0.4)),
              ),
              child: Row(children: [
                const Icon(Icons.draw_outlined, size: 14, color: _amber),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('${firmandoPor ?? 'Otro técnico'} está firmando ahora…',
                      style: const TextStyle(
                          fontSize: 11.5,
                          color: _amber,
                          fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (firmando || alguienFirmando) ? null : onFirmar,
              icon: firmando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.draw_outlined, size: 16),
              label: Text(
                  firmando
                      ? 'Firmando...'
                      : (alguienFirmando
                          ? 'Otro técnico está firmando'
                          : 'Firmar recepción (${reqs.length})'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade400,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ];
    }
  }
}

/// Bottom sheet de firma de recepción. Reutiliza el patrón de firma de
/// Trámites/Permisos: dibujar con el dedo, usar la firma guardada en la nube,
/// o subir una imagen. Devuelve la firma como URL (nube) o data-url base64.
class _FirmaRecepcionSheet extends StatefulWidget {
  /// Nº de ítems que se reciben con esta firma (puede abarcar varias solicitudes).
  final int itemsCount;
  const _FirmaRecepcionSheet({required this.itemsCount});

  @override
  State<_FirmaRecepcionSheet> createState() => _FirmaRecepcionSheetState();
}

class _FirmaRecepcionSheetState extends State<_FirmaRecepcionSheet> {
  late final SignatureController _controller;
  String? _firmaGuardadaUrl;
  bool _usarGuardada = false;
  bool _cargandoGuardada = true;

  @override
  void initState() {
    super.initState();
    _controller = SignatureController(
      penColor: Colors.black,
      penStrokeWidth: 3.0,
      exportBackgroundColor: Colors.white,
    );
    _cargarFirmaGuardada();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _cargarFirmaGuardada() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final r = await http.get(
        Uri.parse('${AppConstants.baseUrl}/permisos/mi-firma'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        final url = data['data']?['url_firma'] as String?;
        if (url != null && url.isNotEmpty && mounted) {
          setState(() {
            _firmaGuardadaUrl = url;
            _usarGuardada = true;
          });
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _cargandoGuardada = false);
    }
  }

  Future<void> _confirmar() async {
    // Usar la firma guardada en la nube → enviar esa URL.
    if (_usarGuardada && _firmaGuardadaUrl != null) {
      Navigator.pop(context, _firmaGuardadaUrl);
      return;
    }
    // Firma dibujada → exportar PNG como data-url base64.
    if (_controller.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dibuja tu firma o usa la guardada'),
          backgroundColor: _danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final bytes = await _controller.toPngBytes();
    if (bytes == null || !mounted) return;
    final dataUrl = 'data:image/png;base64,${base64Encode(bytes)}';
    Navigator.pop(context, dataUrl);
  }

  Future<void> _subirGaleria() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;
    final Uint8List bytes = await image.readAsBytes();
    final dataUrl = 'data:image/png;base64,${base64Encode(bytes)}';
    if (mounted) Navigator.pop(context, dataUrl);
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    final usandoGuardada = _usarGuardada && _firmaGuardadaUrl != null;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(
              children: [
                const Icon(Icons.draw_outlined, color: _green, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Firmar recepción de materiales',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: muted, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text('Recibe: los ${widget.itemsCount} ítem(s) aprobados',
                style: TextStyle(color: muted, fontSize: 12)),
            const SizedBox(height: 14),

            // Toggle: usar guardada / dibujar nueva (si hay guardada)
            if (_cargandoGuardada)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _green),
                ),
              )
            else if (_firmaGuardadaUrl != null) ...[
              Row(
                children: [
                  _firmaTab('Usar guardada', _usarGuardada,
                      () => setState(() => _usarGuardada = true)),
                  const SizedBox(width: 8),
                  _firmaTab('Dibujar nueva', !_usarGuardada,
                      () => setState(() => _usarGuardada = false)),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Lienzo o preview de firma guardada
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: usandoGuardada
                    ? Image.network(_firmaGuardadaUrl!, fit: BoxFit.contain)
                    : Signature(
                        controller: _controller,
                        backgroundColor: Colors.white,
                      ),
              ),
            ),
            const SizedBox(height: 8),
            if (!usandoGuardada)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Firma en el recuadro con tu dedo',
                      style: TextStyle(color: muted, fontSize: 12)),
                  TextButton.icon(
                    onPressed: () => _controller.clear(),
                    icon: Icon(Icons.refresh, size: 15, color: muted),
                    label: Text('Limpiar',
                        style: TextStyle(color: muted, fontSize: 13)),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _subirGaleria,
                    icon: const Icon(Icons.photo_library_outlined, size: 16),
                    label: const Text('Galería'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: muted,
                      side: BorderSide(color: Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _confirmar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Confirmar firma y notificar',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _firmaTab(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? _green : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? _green : Colors.grey.shade300),
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? Colors.white : Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}

