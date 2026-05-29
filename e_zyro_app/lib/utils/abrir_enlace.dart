import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Abre [url] en el visor/navegador externo. Si no se puede, copia el enlace
/// al portapapeles como respaldo. Devuelve true si abrió, false si copió/falló.
Future<bool> abrirEnlace(String? url) async {
  if (url == null || url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  if (uri != null) {
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      }
    } catch (_) {}
  }
  await Clipboard.setData(ClipboardData(text: url));
  return false;
}
