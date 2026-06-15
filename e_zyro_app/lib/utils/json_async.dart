import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Decodifica JSON FUERA del hilo de UI cuando el payload es grande, para no
/// congelar la interfaz al parsear listas pesadas (auditoría, compras, etc.).
///
/// - Payloads pequeños se decodifican en línea (compute tiene overhead de
///   serializar el mensaje entre isolates; no compensa para textos chicos).
/// - En web, `compute` corre en el mismo hilo (no hay isolates) → sin coste
///   extra ni beneficio, pero sigue siendo correcto.
const int _kUmbralCompute = 40000; // ~40 KB

Future<dynamic> decodeJson(String source) {
  if (source.length < _kUmbralCompute) {
    return Future.value(jsonDecode(source));
  }
  return compute(_decodeEnIsolate, source);
}

dynamic _decodeEnIsolate(String source) => jsonDecode(source);
