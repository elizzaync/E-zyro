import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:e_zyro_app/core/api_client.dart';
import 'package:e_zyro_app/models/intervencion_models.dart';
import 'package:e_zyro_app/services/intervencion_service.dart';
import 'package:e_zyro_app/utils/informe_general_config.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'auth_token': 'test-token'});
  });

  Future<IntervencionService> svc(MockClient client) async {
    final prefs = await SharedPreferences.getInstance();
    return IntervencionService(ApiClient(prefs, httpClient: client));
  }

  group('getEquiposIntervenidos', () {
    test('parsea la lista con campos snake_case en respuesta 200', () async {
      final client = MockClient((req) async {
        expect(req.url.path,
            contains('/operaciones/servicio/s1/equipos-intervenidos'));
        expect(req.headers['Authorization'], 'Bearer test-token');
        return http.Response(
          jsonEncode([
            {
              'id': 'ei1',
              'nombre': 'TD-01',
              'codigo': 'ARE-TAB-001',
              'ubicacion_referencia': 'Sala eléctrica, 2do piso',
              'tipo_nombre': 'TABLEROS',
              'tipo_equipo_id': 't1',
              'estado': 'operativo',
              'ubicacion': 'AREQUIPA',
              'zona': 'RAMPA',
              'ultimo_mantenimiento': '2026-01-15',
              'estado_intervencion': 'en_proceso',
            }
          ]),
          200,
        );
      });

      final res = await (await svc(client)).getEquiposIntervenidos('s1');

      expect(res.ok, isTrue);
      final eq = res.data!.single;
      expect(eq.id, 'ei1');
      expect(eq.codigo, 'ARE-TAB-001');
      expect(eq.ubicacionReferencia, 'Sala eléctrica, 2do piso');
      expect(eq.tipoNombre, 'TABLEROS');
      expect(eq.zona, 'RAMPA');
      expect(eq.estadoIntervencion, 'en_proceso');
    });

    test('clasifica 404 como notFound con el detail del backend', () async {
      final client = MockClient((_) async =>
          http.Response('{"detail":"Servicio no encontrado"}', 404));
      final res = await (await svc(client)).getEquiposIntervenidos('s1');
      expect(res.ok, isFalse);
      expect(res.errorMessage, 'Servicio no encontrado');
    });
  });

  group('crearEquipo', () {
    test('envía el payload del frontend y omite vacíos como null', () async {
      late Map<String, dynamic> sent;
      final client = MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
            '{"id":"ei9","nombre":"TD-09","codigo":"ARE-TAB-009",'
            '"estado_intervencion":"sin_inspeccion"}',
            201);
      });

      final res = await (await svc(client)).crearEquipo(
        's1',
        nombre: 'TD-09',
        tipoEquipoId: '',
        ubicacionReferencia: '',
        descripcion: '',
      );

      expect(res.ok, isTrue);
      expect(res.data!.codigo, 'ARE-TAB-009');
      // Ubicación/zona no van en el body: el backend las hereda de la sede.
      expect(sent.containsKey('ubicacion_id'), isFalse);
      expect(sent['tipo_equipo_id'], isNull);
      expect(sent['ubicacion_referencia'], isNull);
      expect(sent['estado'], 'operativo');
    });

    test('expone el 409 anti-duplicado del backend', () async {
      final client = MockClient((_) async => http.Response(
          '{"detail":"Ya existe \'TD-01\' (codigo ARE-TAB-001) en esta ubicacion y zona."}',
          409));
      final res =
          await (await svc(client)).crearEquipo('s1', nombre: 'TD-01');
      expect(res.ok, isFalse);
      expect(res.errorMessage, contains('Ya existe'));
    });
  });

  group('inspección', () {
    test('getInspeccionActiva parsea sesión, pasos y equipo', () async {
      final client = MockClient((_) async => http.Response(
          jsonEncode({
            'inspeccion_id': 'hi1',
            'estado': 'en_proceso',
            'resultado': [
              {
                'orden': 1,
                'nombre': 'Inspección visual',
                'descripcion': 'Revisar estado',
                'completado': true,
                'foto_url': 'https://cdn/x.jpg',
                'foto_public_id': 'pid1',
              },
              {'orden': 2, 'nombre': 'Medición', 'completado': false},
            ],
            'observaciones': 'ok',
            'proxima_fecha': '2026-12-01',
            'equipo': {
              'id': 'ei1',
              'nombre': 'POZO PT-01',
              'tipo_nombre': 'POZOS',
              'estado_intervencion': 'en_proceso',
            },
          }),
          200));

      final res =
          await (await svc(client)).getInspeccionActiva('s1', 'ei1');

      expect(res.ok, isTrue);
      final insp = res.data!;
      expect(insp.inspeccionId, 'hi1');
      expect(insp.pasos.length, 2);
      expect(insp.pasos.first.completado, isTrue);
      expect(insp.pasos.first.fotoUrl, 'https://cdn/x.jpg');
      expect(insp.proximaFecha, '2026-12-01');
      expect(insp.equipo.tipoNombre, 'POZOS');
    });

    test('guardarInspeccion manda {orden, completado} y lee todos_completados',
        () async {
      late Map<String, dynamic> sent;
      final client = MockClient((req) async {
        expect(req.url.path, contains('/operaciones/inspeccion/hi1/guardar'));
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response('{"ok":true,"todos_completados":true}', 200);
      });

      final pasos = [
        PasoInspeccion(orden: 1, nombre: 'A', completado: true),
        PasoInspeccion(orden: 2, nombre: 'B', completado: true),
      ];
      final res = await (await svc(client))
          .guardarInspeccion('hi1', pasos: pasos, observaciones: '  ');

      expect(res.ok, isTrue);
      expect(res.data, isTrue); // todos_completados
      expect(sent['resultado'], [
        {'orden': 1, 'completado': true},
        {'orden': 2, 'completado': true},
      ]);
      // Observaciones en blanco → null (no sobreescribir con espacios).
      expect(sent['observaciones'], isNull);
    });

    test('finalizarInspeccion incluye proxima_fecha_mantenimiento', () async {
      late Map<String, dynamic> sent;
      final client = MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response('{"ok":true}', 200);
      });

      final res = await (await svc(client)).finalizarInspeccion(
        'hi1',
        pasos: [PasoInspeccion(orden: 1, nombre: 'A', completado: true)],
        proximaFechaMantenimiento: '2026-12-01',
      );

      expect(res.ok, isTrue);
      expect(sent['proxima_fecha_mantenimiento'], '2026-12-01');
    });

    test('finalizar con sesión ya cerrada expone el 404 del backend',
        () async {
      final client = MockClient((_) async => http.Response(
          '{"detail":"Sesión no encontrada o ya finalizada"}', 404));
      final res = await (await svc(client))
          .finalizarInspeccion('hi1', pasos: const []);
      expect(res.ok, isFalse);
      expect(res.errorMessage, 'Sesión no encontrada o ya finalizada');
    });
  });

  group('documentos (blobs)', () {
    test('generarInformeGeneral devuelve los bytes del .docx', () async {
      final bytes = [0x50, 0x4B, 0x03, 0x04]; // cabecera ZIP de un .docx
      final client = MockClient((req) async {
        expect(req.url.path,
            contains('/operaciones/servicio/s1/informe/generar'));
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['oc'], 'OC-123');
        expect(body['tipo_base'], 'POZOS');
        return http.Response.bytes(bytes, 200);
      });

      final res = await (await svc(client)).generarInformeGeneral('s1', {
        'oc': 'OC-123',
        'tipo_base': 'POZOS',
        'equipos': [],
        'epps': [],
        'materiales': [],
        'herramientas': [],
        'personal': [],
      });

      expect(res.ok, isTrue);
      expect(res.data, bytes);
    });

    test('certificado de pozo con inspección incompleta expone el 400',
        () async {
      final client = MockClient((_) async => http.Response(
          '{"detail":"El certificado solo puede generarse cuando la inspección esté completada al 100%. Estado actual: \'en_proceso\'."}',
          400));
      final res = await (await svc(client))
          .generarCertificadoPozo('s1', 'ei1', const {});
      expect(res.ok, isFalse);
      expect(res.errorMessage, contains('completada al 100%'));
    });
  });

  group('dashboard', () {
    test('parsea métricas y servicios del envelope {status, data}', () async {
      final client = MockClient((_) async => http.Response(
          jsonEncode({
            'status': 'success',
            'data': {
              'metricas': [
                {
                  'id': 'pendientes',
                  'titulo': 'Pendientes',
                  'valor': 3,
                  'colorIcono': '#f59e0b',
                  'resaltado': false,
                },
              ],
              'servicios': [
                {
                  'id': 's1',
                  'cliente': 'ACME',
                  'tipoServicio': 'Mantenimiento pozos',
                  'fechaStr': '10 Jun 2026',
                  'estado': 'Activo',
                  'alerta': true,
                  'estadoColor': 'rojo',
                },
              ],
            },
          }),
          200));

      final res = await (await svc(client)).getDashboard();

      expect(res.ok, isTrue);
      expect(res.data!.metricas.single.valor, 3);
      expect(res.data!.servicios.single.estadoColor, 'rojo');
      expect(res.data!.servicios.single.alerta, isTrue);
    });
  });

  group('informe_general_config (port del frontend)', () {
    test('determinarTipoBase replica la prioridad TABLERO > POZO > UPS', () {
      expect(determinarTipoBase(['TABLEROS ELÉCTRICOS']),
          TipoBaseInforme.tableros);
      expect(determinarTipoBase(['POZOS']), TipoBaseInforme.pozos);
      expect(determinarTipoBase(['TRANS. AISLAMIENTO']), TipoBaseInforme.ups);
      expect(determinarTipoBase(['LUMINARIAS', null]), TipoBaseInforme.otro);
      // El primero que matchea gana (mismo orden de chequeo que Angular).
      expect(
          determinarTipoBase(['POZOS', 'TABLEROS']), TipoBaseInforme.pozos);
    });

    test('los defaults por tipo coinciden en tamaño con el config Angular',
        () {
      expect(kEppsConfig[TipoBaseInforme.otro], hasLength(6));
      expect(kMaterialesConfig[TipoBaseInforme.pozos], hasLength(7));
      expect(kMaterialesConfig[TipoBaseInforme.otro], hasLength(14));
      expect(kHerramientasConfig[TipoBaseInforme.otro], hasLength(15));
      expect(kAeropuertos['LIMA'], contains('Jorge Chávez'));
    });
  });
}
