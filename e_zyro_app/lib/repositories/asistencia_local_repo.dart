import 'package:sqflite/sqflite.dart';
import '../core/local_db.dart';
import '../models/registro_asistencia_local.dart';

class AsistenciaLocalRepo {
  static const _table = 'registro_asistencia_local';

  Future<void> insertarPendiente(RegistroAsistenciaLocal r) async {
    final db = await LocalDb.instance.database;
    await db.insert(
      _table,
      r.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore, // dedupe por UUID PK
    );
  }

  Future<List<RegistroAsistenciaLocal>> obtenerPendientes({int limit = 50}) async {
    final db = await LocalDb.instance.database;
    final rows = await db.query(
      _table,
      where: 'estado_sync IN (?, ?)',
      whereArgs: [EstadoSync.pendiente.index, EstadoSync.fallido.index],
      orderBy: 'timestamp_disp ASC',
      limit: limit,
    );
    return rows.map(RegistroAsistenciaLocal.fromMap).toList();
  }

  Future<int> contarPendientes() async {
    final db = await LocalDb.instance.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as c FROM $_table WHERE estado_sync IN (?, ?)',
      [EstadoSync.pendiente.index, EstadoSync.fallido.index],
    );
    return (result.first['c'] as int?) ?? 0;
  }

  Future<void> marcarEnviando(String uuid) async {
    final db = await LocalDb.instance.database;
    await db.update(
      _table,
      {'estado_sync': EstadoSync.enviando.index},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  Future<void> marcarEnviado(String uuid) async {
    final db = await LocalDb.instance.database;
    await db.update(
      _table,
      {'estado_sync': EstadoSync.enviado.index},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  Future<void> registrarFallo(String uuid) async {
    final db = await LocalDb.instance.database;
    await db.rawUpdate('''
      UPDATE $_table
      SET estado_sync = ?, retry_count = retry_count + 1, last_attempt_at = ?
      WHERE uuid = ?
    ''', [EstadoSync.fallido.index, DateTime.now().toIso8601String(), uuid]);
  }

  // Limpieza de registros enviados con más de 30 días
  Future<void> limpiarEnviados() async {
    final db = await LocalDb.instance.database;
    final cutoff = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
    await db.delete(
      _table,
      where: 'estado_sync = ? AND timestamp_disp < ?',
      whereArgs: [EstadoSync.enviado.index, cutoff],
    );
  }
}
