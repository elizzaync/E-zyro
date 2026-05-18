import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:e_zyro_app/core/api_client.dart';
import 'package:e_zyro_app/models/mantenimiento_models.dart';
import 'package:e_zyro_app/services/mantenimiento_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'auth_token': 'test-token'});
  });

  Future<MantenimientoService> svc(MockClient client) async {
    final prefs = await SharedPreferences.getInstance();
    return MantenimientoService(ApiClient(prefs, httpClient: client));
  }

  group('getEquiposProyecto', () {
    test('retorna lista en respuesta 200', () async {
      final client = MockClient((req) async {
        expect(req.url.path, contains('/operaciones/proyecto/p1/equipos'));
        expect(req.headers['Authorization'], 'Bearer test-token');
        return http.Response(
          '[{"id":"eq1","nombre":"Bomba A","estado":"pendiente"}]',
          200,
        );
      });

      final result = await (await svc(client)).getEquiposProyecto('p1');

      expect(result.length, 1);
      expect(result.first.id, 'eq1');
      expect(result.first.nombre, 'Bomba A');
      expect(result.first.estado, 'pendiente');
    });

    test('retorna lista vacía en respuesta 500', () async {
      final client = MockClient((_) async => http.Response('Error', 500));
      final result = await (await svc(client)).getEquiposProyecto('p1');
      expect(result, isEmpty);
    });

    test('retorna lista vacía si el servidor responde JSON inválido', () async {
      final client = MockClient((_) async => http.Response('not json', 200));
      final result = await (await svc(client)).getEquiposProyecto('p1');
      expect(result, isEmpty);
    });
  });

  group('getChecklist', () {
    test('parsea pasos correctamente en respuesta 200', () async {
      const json = '{'
          '"equipo_id":"eq1","equipo_nombre":"Bomba A",'
          '"pasos":[{"id":"s1","nombre":"Inspección visual",'
          '"descripcion":"Revisar estado","orden":1,"estado":"pendiente","fotos_urls":[]}]}';

      final client = MockClient((_) async => http.Response(json, 200));
      final result = await (await svc(client)).getChecklist('eq1');

      expect(result, isNotNull);
      expect(result!.equipoId, 'eq1');
      expect(result.pasos.length, 1);
      expect(result.pasos.first.nombre, 'Inspección visual');
      expect(result.pasos.first.orden, 1);
    });

    test('retorna null en respuesta 404', () async {
      final client = MockClient((_) async => http.Response('{}', 404));
      final result = await (await svc(client)).getChecklist('eq1');
      expect(result, isNull);
    });
  });

  group('uploadEvidencia', () {
    test('retorna true en respuesta 201', () async {
      final tempFile = File(
          '${Directory.systemTemp.path}/test_ev_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0]); // JPEG header

      try {
        final client = MockClient((_) async => http.Response('{"id":"ev1"}', 201));
        final result = await (await svc(client)).uploadEvidencia(
          'paso1',
          FotoTipo.antes,
          tempFile.path,
          lat: -12.0464,
          lng: -77.0428,
          takenAt: '2025-06-01T10:00:00.000Z',
        );
        expect(result, isTrue);
      } finally {
        await tempFile.delete();
      }
    });

    test('retorna false en respuesta 400', () async {
      final tempFile = File(
          '${Directory.systemTemp.path}/test_ev2_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0]);

      try {
        final client = MockClient((_) async => http.Response('Bad Request', 400));
        final result = await (await svc(client)).uploadEvidencia(
          'paso1',
          FotoTipo.durante,
          tempFile.path,
        );
        expect(result, isFalse);
      } finally {
        await tempFile.delete();
      }
    });
  });

  group('patchMantenimiento', () {
    test('envía PATCH con status y retorna true en 200', () async {
      String? capturedMethod;
      String? capturedPath;

      final client = MockClient((req) async {
        capturedMethod = req.method;
        capturedPath = req.url.path;
        return http.Response('{"status":"completado"}', 200);
      });

      final result =
          await (await svc(client)).patchMantenimiento('eq1', 'completado');

      expect(result, isTrue);
      expect(capturedMethod, 'PATCH');
      expect(capturedPath, contains('/operaciones/equipo/eq1/mantenimiento'));
    });

    test('retorna false en respuesta de error', () async {
      final client = MockClient((_) async => http.Response('Error', 500));
      final result =
          await (await svc(client)).patchMantenimiento('eq1', 'completado');
      expect(result, isFalse);
    });
  });
}
