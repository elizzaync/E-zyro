import 'package:flutter/material.dart';

import '../../widgets/chatbot/chat_conversacion.dart';

/// Asistente E-zyro a pantalla completa (entradas: bandeja de requerimientos
/// y menú Más). La misma conversación existe como panel flotante estilo
/// Messenger en ChatbotLauncher; el historial por usuario vive en el servidor
/// del chatbot, así que el contexto se comparte entre ambas.
class PantallaAsistenteEzyro extends StatelessWidget {
  /// Pantalla de origen (contexto que viaja al asistente).
  final String? pantalla;
  const PantallaAsistenteEzyro({super.key, this.pantalla});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asistente E-zyro',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: ChatConversacion(pantalla: pantalla),
    );
  }
}
