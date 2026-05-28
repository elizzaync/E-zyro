import 'package:sqflite/sqflite.dart';
import '../core/local_db.dart';
import '../models/accion_pendiente.dart';
import '../models/registro_asistencia_local.dart' show EstadoSync;

/// Cola local de acciones de operaciones pendientes de enviar (offline-first).
/// FIFO por `created_at` para preservar el orden en que el técnico las hizo.
class AccionLocalRepo {
  static const _table = 'accion_pendiente';

  Future<void> insertar(AccionPendiente a) async {
    final db = await LocalDb.instance.database;
    if (db == null) return;
    await db.insert(_table, a.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<AccionPendiente>> obtenerPendientes({int limit = 100}) async {
    final db = await LocalDb.instance.database;
    if (db == null) return [];
    final rows = await db.query(
      _table,
      where: 'estado_sync IN (?, ?) AND retry_count < 5',
      whereArgs: [EstadoSync.pendiente.index, EstadoSync.fallido.index],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(AccionPendiente.fromMap).toList();
  }

  Future<int> contarPendientes() async {
    final db = await LocalDb.instance.database;
    if (db == null) return 0;
    final r = await db.rawQuery(
      'SELECT COUNT(*) c FROM $_table WHERE estado_sync IN (?, ?) AND retry_count < 5',
      [EstadoSync.pendiente.index, EstadoSync.fallido.index],
    );
    return (r.first['c'] as int?) ?? 0;
  }

  Future<void> marcarEnviando(String uuid) async {
    final db = await LocalDb.instance.database;
    if (db == null) return;
    await db.update(_table, {'estado_sync': EstadoSync.enviando.index},
        where: 'uuid = ?', whereArgs: [uuid]);
  }

  Future<void> registrarFallo(String uuid) async {
    final db = await LocalDb.instance.database;
    if (db == null) return;
    await db.rawUpdate('''
      UPDATE $_table
      SET estado_sync = ?, retry_count = retry_count + 1, last_attempt_at = ?
      WHERE uuid = ?
    ''', [EstadoSync.fallido.index, DateTime.now().toIso8601String(), uuid]);
  }

  Future<void> eliminar(String uuid) async {
    final db = await LocalDb.instance.database;
    if (db == null) return;
    await db.delete(_table, where: 'uuid = ?', whereArgs: [uuid]);
  }
}
