// Implementación web: dispara la descarga del navegador con un <a download>.
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<String?> guardarArchivo({
  required String fileName,
  required List<int> bytes,
  String? dialogTitle,
}) async {
  final data = Uint8List.fromList(bytes);
  final blob = web.Blob(
    <JSUint8Array>[data.toJS].toJS,
    web.BlobPropertyBag(type: 'application/octet-stream'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  // En web no hay "cancelar": la descarga se dispara siempre.
  return fileName;
}
