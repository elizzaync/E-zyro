// Descarga/guardado de archivos multiplataforma.
//
// En móvil/desktop abre el diálogo nativo (file_picker).
// En web dispara la descarga del navegador (file_picker NO implementa
// saveFile en web → lanzaba UnimplementedError).
import 'descarga_archivo_io.dart'
    if (dart.library.js_interop) 'descarga_archivo_web.dart' as impl;

/// Guarda `bytes` como `fileName`.
/// Devuelve la ruta/identificador del archivo, o `null` si el usuario canceló.
/// Lanza si ocurre un error real de guardado.
Future<String?> guardarArchivo({
  required String fileName,
  required List<int> bytes,
  String? dialogTitle,
}) {
  return impl.guardarArchivo(
    fileName: fileName,
    bytes: bytes,
    dialogTitle: dialogTitle,
  );
}
