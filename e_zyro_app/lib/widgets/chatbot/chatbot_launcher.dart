import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../../services/chatbot_service.dart';

const Color _kLime = Color(0xFF8FD11B);

/// Botón flotante (burbuja) de E-Zybot. Al tocarlo abre el panel de chat en una
/// hoja modal. Se coloca como overlay en las pantallas principales (MainShell).
class ChatbotLauncher extends StatelessWidget {
  const ChatbotLauncher({super.key});

  void _abrirChat(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ChatbotPanel(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Abrir asistente E-Zybot',
      child: Material(
        color: _kLime,
        elevation: 4,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _abrirChat(context),
          child: const SizedBox(
            width: 56,
            height: 56,
            child: Icon(Icons.smart_toy_rounded,
                color: Color(0xFF0C1506), size: 28),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Msg {
  final bool esUsuario;
  final String texto;
  final List<String> herramientas;
  const _Msg(this.esUsuario, this.texto, [this.herramientas = const []]);
}

class _ChatbotPanel extends StatefulWidget {
  const _ChatbotPanel();

  @override
  State<_ChatbotPanel> createState() => _ChatbotPanelState();
}

class _ChatbotPanelState extends State<_ChatbotPanel> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _msgs = <_Msg>[
    const _Msg(false,
        '¡Hola! Soy E-Zybot 🤖, tu asistente. Pregúntame por el inventario, '
        'EPP, equipos, personal o un resumen de la empresa.'),
  ];

  ChatbotService? _service;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  Future<void> _initService() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _service = ChatbotService(ApiClient(prefs)));
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollAbajo() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _enviar() async {
    final texto = _inputCtrl.text.trim();
    if (texto.isEmpty || _enviando || _service == null) return;

    setState(() {
      _msgs.add(_Msg(true, texto));
      _enviando = true;
      _inputCtrl.clear();
    });
    _scrollAbajo();

    // Historial completo (la API es stateless). Solo turnos reales de chat.
    final historial = _msgs
        .map((m) => ChatbotMensaje(m.esUsuario ? 'user' : 'assistant', m.texto))
        .toList();

    try {
      final r = await _service!.enviar(historial);
      if (!mounted) return;
      setState(() => _msgs.add(_Msg(false, r.respuesta, r.herramientasUsadas)));
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() => _msgs.add(_Msg(false, '⚠️ $msg')));
    } finally {
      if (mounted) setState(() => _enviando = false);
      _scrollAbajo();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final altura = MediaQuery.of(context).size.height * 0.82;

    return Padding(
      // Sube el panel por encima del teclado.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: altura,
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            _header(scheme),
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                itemCount: _msgs.length + (_enviando ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i == _msgs.length) return _typing(scheme);
                  return _burbuja(_msgs[i], scheme);
                },
              ),
            ),
            _barraEntrada(scheme),
          ],
        ),
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: _kLime.withValues(alpha: 0.25))),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 18,
            backgroundColor: _kLime,
            child: Icon(Icons.smart_toy_rounded,
                color: Color(0xFF0C1506), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('E-Zybot',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text('Asistente virtual',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _burbuja(_Msg m, ColorScheme scheme) {
    final esUser = m.esUsuario;
    return Align(
      alignment: esUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: esUser ? _kLime : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(esUser ? 16 : 4),
            bottomRight: Radius.circular(esUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              m.texto,
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: esUser ? const Color(0xFF0C1506) : scheme.onSurface,
              ),
            ),
            if (m.herramientas.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '🔧 ${m.herramientas.join(', ')}',
                style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _typing(ColorScheme scheme) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 10),
            Text('pensando…',
                style: TextStyle(
                    fontSize: 13, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _barraEntrada(ColorScheme scheme) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _enviar(),
                decoration: const InputDecoration(
                  hintText: 'Escribe tu pregunta…',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: _kLime,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _enviando ? null : _enviar,
                child: const SizedBox(
                  width: 46,
                  height: 46,
                  child: Icon(Icons.send_rounded,
                      color: Color(0xFF0C1506), size: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
