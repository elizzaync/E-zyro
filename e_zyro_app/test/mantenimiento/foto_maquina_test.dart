import 'package:flutter_test/flutter_test.dart';
import 'package:e_zyro_app/models/mantenimiento_models.dart';

void main() {
  group('FotosMaquina — máquina de estados', () {
    test('estado inicial: solo ANTES habilitado', () {
      final m = FotosMaquina();
      expect(m.canCapture(FotoTipo.antes), isTrue);
      expect(m.canCapture(FotoTipo.durante), isFalse);
      expect(m.canCapture(FotoTipo.despues), isFalse);
      expect(m.isComplete, isFalse);
    });

    test('tras capturar ANTES: DURANTE habilitado', () {
      final m = FotosMaquina();
      m.set(FotoTipo.antes, '/tmp/antes.jpg');

      expect(m.canCapture(FotoTipo.antes), isFalse);
      expect(m.canCapture(FotoTipo.durante), isTrue);
      expect(m.canCapture(FotoTipo.despues), isFalse);
      expect(m.isComplete, isFalse);
    });

    test('tras capturar ANTES y DURANTE: DESPUÉS habilitado', () {
      final m = FotosMaquina();
      m.set(FotoTipo.antes, '/tmp/antes.jpg');
      m.set(FotoTipo.durante, '/tmp/durante.jpg');

      expect(m.canCapture(FotoTipo.antes), isFalse);
      expect(m.canCapture(FotoTipo.durante), isFalse);
      expect(m.canCapture(FotoTipo.despues), isTrue);
      expect(m.isComplete, isFalse);
    });

    test('tras capturar las tres fotos: isComplete = true', () {
      final m = FotosMaquina();
      m.set(FotoTipo.antes, '/tmp/antes.jpg');
      m.set(FotoTipo.durante, '/tmp/durante.jpg');
      m.set(FotoTipo.despues, '/tmp/despues.jpg');

      expect(m.canCapture(FotoTipo.antes), isFalse);
      expect(m.canCapture(FotoTipo.durante), isFalse);
      expect(m.canCapture(FotoTipo.despues), isFalse);
      expect(m.isComplete, isTrue);
    });

    test('pathFor devuelve el path correcto por tipo', () {
      final m = FotosMaquina(
        antes: '/tmp/a.jpg',
        durante: '/tmp/d.jpg',
        despues: '/tmp/dp.jpg',
      );
      expect(m.pathFor(FotoTipo.antes), '/tmp/a.jpg');
      expect(m.pathFor(FotoTipo.durante), '/tmp/d.jpg');
      expect(m.pathFor(FotoTipo.despues), '/tmp/dp.jpg');
    });

    test('serialización roundtrip toJson/fromJson', () {
      final original = FotosMaquina(
        antes: '/tmp/a.jpg',
        durante: null,
        despues: null,
      );
      final restored = FotosMaquina.fromJson(original.toJson());
      expect(restored.antes, original.antes);
      expect(restored.durante, original.durante);
      expect(restored.despues, original.despues);
    });
  });

  group('EvidenciaPendiente — serialización', () {
    test('roundtrip incluye lat/lng/accuracy', () {
      final ev = EvidenciaPendiente(
        id: 'test-id',
        pasoId: 'paso-1',
        tipo: FotoTipo.antes,
        filePath: '/tmp/foto.jpg',
        createdAt: DateTime(2025, 6, 1, 10, 0, 0),
        lat: -12.0464,
        lng: -77.0428,
        accuracy: 5.0,
      );

      final restored = EvidenciaPendiente.fromJson(ev.toJson());

      expect(restored.id, ev.id);
      expect(restored.pasoId, ev.pasoId);
      expect(restored.tipo, FotoTipo.antes);
      expect(restored.lat, ev.lat);
      expect(restored.lng, ev.lng);
      expect(restored.accuracy, ev.accuracy);
    });

    test('lat/lng opcionales: serializa sin ellos si son null', () {
      final ev = EvidenciaPendiente(
        id: 'x',
        pasoId: 'p',
        tipo: FotoTipo.despues,
        filePath: '/tmp/f.jpg',
        createdAt: DateTime(2025, 1, 1),
      );
      final json = ev.toJson();
      expect(json.containsKey('lat'), isFalse);
      expect(json.containsKey('lng'), isFalse);
    });
  });
}
