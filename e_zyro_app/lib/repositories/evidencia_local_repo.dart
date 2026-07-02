import 'package:sqflite/sqflite.dart';
import '../core/local_db.dart';
import '../models/evidencia_pendiente.dart';
import '../models/registro_asistencia_local.dart' show EstadoSync;

/// Cola local de evidencias de procedimientos pendientes de subir.
/// Espeja [AsistenciaLocalRepo]; al subir con éxito se elimina la fila
/// (la evidencia ya vive en el servidor) y el archivo se borra aparte.
class EvidenciaLocalRepo {
  static const _table = 'evidencia_pendiente';

  Future<void> insertarPendiente(EvidenciaPendiente e) async {
    final db = await LocalDb.instance.database;
    if (db == null) return;
    await db.insert(
      _table,
      e.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<EvidenciaPendiente>> obtenerPendientes({int limit = 50}) async {
    final db = await LocalDb.instance.database;
    if (db == null) return [];
    final rows = await db.query(
      _table,
      where: 'estado_sync IN (?, ?)',
      whereArgs: [EstadoSync.pendiente.index, EstadoSync.fallido.index],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(EvidenciaPendiente.fromMap).toList();
  }

  Future<int> contarPendientes() async {
    final db = await LocalDb.instance.database;
    if (db == null) return 0;
    final r = await db.rawQuery(
      'SELECT COUNT(*) as c FROM $_table WHERE estado_sync IN (?, ?)',
      [EstadoSync.pendiente.index, EstadoSync.fallido.index],
    );
    return (r.first['c'] as int?) ?? 0;
  }

  Future<void> marcarEnviando(String uuid) async {
    final db = await LocalDb.instance.database;
    if (db == null) return;
    await db.update(
      _table,
      {'estado_sync': EstadoSync.enviando.index},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
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

  /// Marca un rechazo PERMANENTE del servidor (4xx ≠ 401): no tiene sentido
  /// reintentar. Espeja [AsistenciaLocalRepo.marcarErrorPermanente] — usa
  /// retry_count = 99 como centinela para distinguirlo de un abandono por
  /// reintentos normales (retry_count >= 5 por fallas transitorias).
  Future<void> marcarErrorPermanente(String uuid) async {
    final db = await LocalDb.instance.database;
    if (db == null) return;
    await db.rawUpdate('''
      UPDATE $_table
      SET retry_count = 99, estado_sync = ?, last_attempt_at = ?
      WHERE uuid = ?
    ''', [EstadoSync.fallido.index, DateTime.now().toIso8601String(), uuid]);
  }

  /// Elimina la evidencia de la cola (tras subirla con éxito o descartarla).
  Future<void> eliminar(String uuid) async {
    final db = await LocalDb.instance.database;
    if (db == null) return;
    await db.delete(_table, where: 'uuid = ?', whereArgs: [uuid]);
  }

  /// Evidencias que agotaron los 5 reintentos (atascadas).
  Future<int> contarAbandonadas() async {
    final db = await LocalDb.instance.database;
    if (db == null) return 0;
    final r = await db.rawQuery(
      'SELECT COUNT(*) as c FROM $_table WHERE retry_count >= 5',
    );
    return (r.first['c'] as int?) ?? 0;
  }

  Future<List<EvidenciaPendiente>> obtenerAbandonadas() async {
    final db = await LocalDb.instance.database;
    if (db == null) return [];
    final rows = await db.query(_table, where: 'retry_count >= 5');
    return rows.map(EvidenciaPendiente.fromMap).toList();
  }

  /// Reinicia las abandonadas para volver a intentarlas.
  Future<int> resetParaReintentar() async {
    final db = await LocalDb.instance.database;
    if (db == null) return 0;
    return db.rawUpdate('''
      UPDATE $_table
      SET retry_count = 0, estado_sync = ?, last_attempt_at = NULL
      WHERE retry_count >= 5
    ''', [EstadoSync.pendiente.index]);
  }
}
