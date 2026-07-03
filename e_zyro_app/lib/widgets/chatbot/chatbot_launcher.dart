import 'package:flutter/material.dart';

import 'chat_conversacion.dart';

const Color _kLime = Color(0xFF8FD11B);
const Color _kInk = Color(0xFF0C1506);

/// Burbuja flotante de E-Zybot, estilo Messenger: tocarla despliega un panel
/// de chat anclado abajo-derecha sobre la pantalla actual; minimizar lo
/// devuelve a burbuja SIN perder la conversación (el panel queda montado en
/// Offstage). El historial real además vive por usuario en el servidor.
///
/// Origen: rama `chatbot-app` (c7d0c5b7) — la burbuja era un placeholder;
/// ahora contiene la conversación real contra el proxy /chatbot/chat.
class ChatbotLauncher extends StatefulWidget {
  /// Pantalla activa — viaja como contexto al asistente y se actualiza en
  /// caliente si el usuario cambia de tab con el panel abierto.
  final String? pantalla;
  const ChatbotLauncher({super.key, this.pantalla});

  @override
  State<ChatbotLauncher> createState() => _ChatbotLauncherState();
}

class _ChatbotLauncherState extends State<ChatbotLauncher> {
  bool _abierto = false;
  // La conversación se monta recién en la PRIMERA apertura: así el saludo
  // "__init__" no se dispara al arrancar la app con el panel aún oculto.
  bool _montado = false;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final tecladoAlto = MediaQuery.viewInsetsOf(context).bottom;
    final panelAncho = (size.width - 24).clamp(0.0, 360.0);
    // Con teclado abierto el panel se encoge para no desbordar hacia arriba.
    final panelAlto =
        (size.height - tecladoAlto - 150).clamp(240.0, 520.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Tras la primera apertura queda montado (Offstage) para conservar
        // la conversación al minimizar.
        if (_montado)
          Offstage(
            offstage: !_abierto,
            child: SizedBox(
              width: panelAncho,
              height: panelAlto,
              child: _panel(context),
            ),
          ),
        if (!_abierto) _burbuja(),
      ],
    );
  }

  Widget _burbuja() {
    return Semantics(
      button: true,
      label: 'Abrir asistente E-Zybot',
      child: Material(
        color: _kLime,
        elevation: 4,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => setState(() {
            _abierto = true;
            _montado = true;
          }),
          child: const SizedBox(
            width: 56,
            height: 56,
            child: Icon(Icons.smart_toy_rounded, color: _kInk, size: 28),
          ),
        ),
      ),
    );
  }

  Widget _panel(BuildContext context) {
    return Material(
      elevation: 10,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      color: Theme.of(context).colorScheme.surface,
      child: Column(children: [
        Container(
          color: _kLime,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(children: [
            const Icon(Icons.smart_toy_rounded, color: _kInk, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('E-Zybot',
                  style: TextStyle(
                      color: _kInk,
                      fontWeight: FontWeight.w800,
                      fontSize: 15)),
            ),
            Semantics(
              button: true,
              label: 'Minimizar asistente',
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _abierto = false),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child:
                      Icon(Icons.remove_rounded, color: _kInk, size: 22),
                ),
              ),
            ),
          ]),
        ),
        Expanded(
          child: ChatConversacion(
            pantalla: widget.pantalla,
            // Al navegar desde un chip, minimizar para no tapar el destino.
            onNavegar: () => setState(() => _abierto = false),
          ),
        ),
      ]),
    );
  }
}
