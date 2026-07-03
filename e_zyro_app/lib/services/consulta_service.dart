import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';

/// Consulta RUC (SUNAT) / DNI (RENIEC) para autocompletar formularios.
class ConsultaRuc {
  final String ruc, razonSocial;
  final String? direccion, estado, condicion;
  ConsultaRuc({
    required this.ruc, required this.razonSocial,
    this.direccion, this.estado, this.condicion,
  });
}

class ConsultaDni {
  final String dni, nombres, nombreCompleto;
  ConsultaDni({required this.dni, required this.nombres, required this.nombreCompleto});
}

class ConsultaService {
  /// null si no se encontró o hubo error (el form sigue editable a mano).
  static Future<ConsultaRuc?> ruc(String ruc) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final r = await ApiClient(prefs).get('/consultas/ruc/$ruc');
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      return ConsultaRuc(
        ruc: j['ruc'].toString(),
        razonSocial: j['razon_social']?.toString() ?? '',
        direccion: j['direccion']?.toString(),
        estado: j['estado']?.toString(),
        condicion: j['condicion']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<ConsultaDni?> dni(String dni) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final r = await ApiClient(prefs).get('/consultas/dni/$dni');
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      return ConsultaDni(
        dni: j['dni'].toString(),
        nombres: j['nombres']?.toString() ?? '',
        nombreCompleto: j['nombre_completo']?.toString() ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}
