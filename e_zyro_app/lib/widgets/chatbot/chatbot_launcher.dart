import 'package:flutter/material.dart';

const Color _kLime = Color(0xFF8FD11B);

/// Botón flotante (burbuja) de E-Zybot.
///
/// Por ahora es solo un ícono flotante sin lógica: al tocarlo muestra un aviso
/// de "próximamente". La UI completa del chat (panel + integración con
/// ChatbotService) está guardada en el historial de git (commit 88900dc3) y se
/// reintegrará aquí cuando se le meta la lógica.
class ChatbotLauncher extends StatelessWidget {
  const ChatbotLauncher({super.key});

  void _proximamente(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('E-Zybot 🤖 estará disponible pronto'),
          duration: Duration(seconds: 2),
        ),
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
          onTap: () => _proximamente(context),
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
