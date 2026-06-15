// Implementación móvil/desktop: diálogo nativo vía file_picker.
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<String?> guardarArchivo({
  required String fileName,
  required List<int> bytes,
  String? dialogTitle,
}) {
  return FilePicker.platform.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    bytes: Uint8List.fromList(bytes),
  );
}
