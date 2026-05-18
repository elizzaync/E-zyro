import 'package:flutter_test/flutter_test.dart';
import 'package:e_zyro_app/models/mantenimiento_models.dart';

/// Replica the sequential blocking logic from ChecklistScreen's
/// SliverChildBuilderDelegate so it can be tested in isolation.
bool isStepBlocked(
  int index,
  List<PasoChecklist> pasos,
  Map<String, FotosMaquina> progress,
) {
  if (index == 0) return false;
  final prevId = pasos[index - 1].id;
  return !(progress[prevId] ?? FotosMaquina()).isComplete;
}

PasoChecklist _paso(String id, int orden) => PasoChecklist(
      id: id,
      nombre: 'Paso $orden',
      descripcion: '',
      orden: orden,
      estado: 'pendiente',
      fotosUrls: [],
    );

void main() {
  group('Bloqueo secuencial de pasos', () {
    final pasos = [_paso('s1', 1), _paso('s2', 2), _paso('s3', 3)];

    test('primer paso nunca está bloqueado', () {
      final progress = <String, FotosMaquina>{};
      expect(isStepBlocked(0, pasos, progress), isFalse);
    });

    test('segundo paso bloqueado cuando primero incompleto', () {
      final progress = <String, FotosMaquina>{
        's1': FotosMaquina(antes: '/a.jpg'), // solo ANTES — incompleto
      };
      expect(isStepBlocked(1, pasos, progress), isTrue);
    });

    test('segundo paso desbloqueado cuando primero completo', () {
      final progress = <String, FotosMaquina>{
        's1': FotosMaquina(
          antes: '/a.jpg',
          durante: '/d.jpg',
          despues: '/dp.jpg',
        ),
      };
      expect(isStepBlocked(1, pasos, progress), isFalse);
    });

    test('tercer paso bloqueado cuando segundo incompleto', () {
      final progress = <String, FotosMaquina>{
        's1': FotosMaquina(
          antes: '/a.jpg',
          durante: '/d.jpg',
          despues: '/dp.jpg',
        ),
        's2': FotosMaquina(antes: '/a2.jpg'), // incompleto
      };
      expect(isStepBlocked(2, pasos, progress), isTrue);
    });

    test('tercer paso desbloqueado cuando segundo completo', () {
      final progress = <String, FotosMaquina>{
        's1': FotosMaquina(
            antes: '/a.jpg', durante: '/d.jpg', despues: '/dp.jpg'),
        's2': FotosMaquina(
            antes: '/a2.jpg', durante: '/d2.jpg', despues: '/dp2.jpg'),
      };
      expect(isStepBlocked(2, pasos, progress), isFalse);
    });

    test('paso sin entrada en progress es tratado como incompleto', () {
      // progress vacío — s1 no tiene entrada
      final progress = <String, FotosMaquina>{};
      expect(isStepBlocked(1, pasos, progress), isTrue);
    });
  });
}
