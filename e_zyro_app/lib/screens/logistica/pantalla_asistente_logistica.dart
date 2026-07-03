import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../services/chatbot_service.dart';
import '../../utils/api_provider.dart';

/// Asistente de Logística — chat REST puro contra el proxy del backend.
/// Sin WebSocket: cada pregunta es un POST /chatbot/chat y el historial por
/// usuario vive en el servidor; aquí la lista de mensajes es solo en memoria.
class PantallaAsistenteLogistica extends StatefulWidget {
  /// Pantalla de origen (contexto que viaja al asistente).
  final String? pantalla;
  const PantallaAsistenteLogistica({super.key, this.pantalla});

  @override
  State<PantallaAsistenteLogistica> createState() =>
      _PantallaAsistenteLogisticaState();
}

enum _Autor { usuario, bot, error }

class _Mensaje {
  final _Autor autor;
  final String texto;
  const _Mensaje(this.autor, this.texto);
}

class _PantallaAsistenteLogisticaState
    extends State<PantallaAsistenteLogistica> {
  static const _green = Color(0xFF8FD11B); // mismo verde del ChatTab

  ChatbotService? _service;
  final _mensajes = <_Mensaje>[];
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _esperando = false;
  String? _ultimoFallido; // pregunta que falló, para el botón reintentar

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _service = await getChatbotService();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollAbajo() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _enviarNuevo() {
    final t = _inputCtrl.text.trim();
    if (t.isEmpty || _esperando || _service == null) return;
    _inputCtrl.clear();
    setState(() {
      _mensajes.removeWhere((m) => m.autor == _Autor.error);
      _ultimoFallido = null;
      _mensajes.add(_Mensaje(_Autor.usuario, t));
    });
    _preguntar(t);
  }

  void _reintentar() {
    final t = _ultimoFallido;
    if (t == null || _esperando) return;
    setState(() {
      _mensajes.removeWhere((m) => m.autor == _Autor.error);
      _ultimoFallido = null;
    });
    _preguntar(t);
  }

  Future<void> _preguntar(String texto) async {
    setState(() => _esperando = true);
    _scrollAbajo();
    try {
      final answer =
          await _service!.preguntar(texto, pantalla: widget.pantalla);
      if (!mounted) return;
      setState(() {
        _esperando = false;
        _mensajes.add(_Mensaje(_Autor.bot, answer));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _esperando = false;
        _ultimoFallido = texto;
        _mensajes.add(_Mensaje(
            _Autor.error, e.toString().replaceFirst('Exception: ', '')));
      });
    }
    _scrollAbajo();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asistente de Logística',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: Column(children: [
        Expanded(
          child: _mensajes.isEmpty && !_esperando
              ? _vacio()
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: _mensajes.length + (_esperando ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == _mensajes.length) return _burbujaEscribiendo();
                    return _burbuja(_mensajes[i]);
                  },
                ),
        ),
        _inputBar(),
      ]),
    );
  }

  Widget _vacio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: _green.withValues(alpha: 0.15),
              child: const Icon(Icons.smart_toy_outlined,
                  size: 34, color: Color(0xFF5E8F0D)),
            ),
            const SizedBox(height: 14),
            const Text('¿En qué te ayudo?',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
              'Pregúntame por stock, requerimientos, compras o movimientos de inventario.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _burbuja(_Mensaje m) {
    switch (m.autor) {
      case _Autor.usuario:
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8, left: 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.25),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: Text(m.texto, style: const TextStyle(fontSize: 14)),
          ),
        );
      case _Autor.bot:
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8, right: 32),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
            ),
            child: MarkdownBody(
              data: m.texto,
              selectable: true,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                  .copyWith(p: const TextStyle(fontSize: 14, height: 1.35)),
            ),
          ),
        );
      case _Autor.error:
        return Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(m.texto,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12.5, color: Colors.red.shade700)),
                TextButton.icon(
                  onPressed: _reintentar,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        );
    }
  }

  Widget _burbujaEscribiendo() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('escribiendo…',
                style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
              top: BorderSide(
                  color: Colors.grey.withValues(alpha: 0.25), width: 0.5)),
        ),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              enabled: !_esperando,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _enviarNuevo(),
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: _esperando
                    ? 'Esperando al asistente…'
                    : 'Escribe tu pregunta…',
                hintStyle: const TextStyle(fontSize: 14),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            onPressed: _esperando ? null : _enviarNuevo,
            icon: const Icon(Icons.send_rounded),
            color: const Color(0xFF5E8F0D),
          ),
        ]),
      ),
    );
  }
}
