import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/intervencion_models.dart';

/// Mapeo de palabras clave en el tipo de equipo → archivo JSON de procedimientos.
/// Orden importa: la primera coincidencia gana.
const _mapaTipos = [
  (['POZO', 'TIERRA', 'PUESTA A TIERRA'], 'pozos'),
  (['TABLERO', 'PANEL ELÉCTRICO', 'CUADRO ELÉCTRICO'], 'tableros'),
  (['UPS', 'SAI', 'NO BREAK'], 'ups'),
  (['TRANSFORMADOR', 'TRANS.', 'AISLAMIENTO'], 'transformadores'),
];

/// Devuelve la clave del archivo JSON para el tipo de equipo dado.
/// Si no hay coincidencia devuelve 'general'.
String _claveParaTipo(String tipoNombre) {
  final t = tipoNombre.toUpperCase();
  for (final entry in _mapaTipos) {
    if (entry.$1.any((k) => t.contains(k))) return entry.$2;
  }
  return 'general';
}

/// Carga los procedimientos locales para el tipo de equipo indicado.
/// Devuelve una lista de [PasoInspeccion] con todos los campos vacíos
/// (sin foto, sin completar) listos para llenar durante la inspección.
Future<List<PasoInspeccion>> cargarProcedimientosLocales(
    String tipoNombre) async {
  final clave = _claveParaTipo(tipoNombre);
  try {
    final raw =
        await rootBundle.loadString('assets/procedimientos/$clave.json');
    final lista = jsonDecode(raw) as List<dynamic>;
    return lista.map((e) {
      final m = e as Map<String, dynamic>;
      return PasoInspeccion(
        orden: m['orden'] as int,
        nombre: m['nombre'] as String,
        descripcion: m['descripcion'] as String,
        completado: false,
        fotoUrl: null,
        fotoPublicId: null,
      );
    }).toList();
  } catch (_) {
    return [];
  }
}
