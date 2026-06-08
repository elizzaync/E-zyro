// Visor del manual de usuario de Finanzas (qué hacer en cada pantalla
// y qué asiento contable PCGE genera cada acción). Contenido empaquetado
// como asset Markdown — no requiere conexión.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../utils/ui_insets.dart';

const _kGreen = Color(0xFF5A9A00);

class PantallaManualFinanzas extends StatefulWidget {
  const PantallaManualFinanzas({super.key});

  @override
  State<PantallaManualFinanzas> createState() => _PantallaManualFinanzasState();
}

class _PantallaManualFinanzasState extends State<PantallaManualFinanzas> {
  String? _contenido;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final texto = await rootBundle
          .loadString('assets/docs/manual_usuario_finanzas.md');
      if (!mounted) return;
      setState(() => _contenido = texto);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo cargar el manual.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manual de Usuario · Finanzas'),
      ),
      body: Builder(builder: (_) {
        if (_error != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, textAlign: TextAlign.center),
            ),
          );
        }
        if (_contenido == null) {
          return const Center(
            child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(_kGreen)),
          );
        }
        return Markdown(
          data: _contenido!,
          padding: bottomSafePadding(context, extra: 24),
          selectable: true,
          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
            h1: const TextStyle(
                fontSize: 21, fontWeight: FontWeight.bold, height: 1.3),
            h2: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                height: 1.4,
                color: _kGreen),
            h3: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, height: 1.4),
            p: const TextStyle(fontSize: 14, height: 1.55),
            listBullet: const TextStyle(fontSize: 14, height: 1.55),
            strong: const TextStyle(fontWeight: FontWeight.w700),
            blockquoteDecoration: BoxDecoration(
              color: _kGreen.withValues(alpha: isDark ? 0.12 : 0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border(left: BorderSide(color: _kGreen, width: 3)),
            ),
            blockquotePadding: const EdgeInsets.all(12),
            code: TextStyle(
              fontSize: 13,
              backgroundColor: scheme.surfaceContainerHighest,
              fontFamily: 'monospace',
            ),
            tableBorder: TableBorder.all(
                color: scheme.outlineVariant, width: 0.6),
            tableHead: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            tableBody: const TextStyle(fontSize: 13),
            tableCellsPadding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 8),
            horizontalRuleDecoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: scheme.outlineVariant, width: 1),
              ),
            ),
          ),
        );
      }),
    );
  }
}
