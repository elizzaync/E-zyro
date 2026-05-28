import 'package:sqflite/sqflite.dart';
import '../core/local_db.dart';
import '../models/registro_asistencia_local.dart';

class AsistenciaLocalRepo {
  static const _table = 'registro_asistencia_local';

  Future<void> insertarPendiente(RegistroAsistenciaLocal r) async {
    final db = await LocalDb.instance.database;
    if (db == null) return;
    await db.insert(
      _table,
      r.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<RegistroAsistenciaLocal>> obtenerPendientes({int limit = 50}) async {
    final db = await LocalDb.instance.database;
    if (db == null) return [];
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
    if (db == null) return 0;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as c FROM $_table WHERE estado_sync IN (?, ?)',
      [EstadoSync.pendiente.index, EstadoSync.fallido.index],
    );
    return (result.first['c'] as int?) ?? 0;
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

  Future<void> marcarEnviado(String uuid) async {
    final db = await LocalDb.instance.database;
    if (db == null) return;
    await db.update(
      _table,
      {'estado_sync': EstadoSync.enviado.index},
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

  Future<void> limpiarEnviados() async {
    final db = await LocalDb.instance.database;
    if (db == null) return;
    final cutoff30 = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
    final cutoff7  = DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
    await db.delete(
      _table,
      where: 'estado_sync = ? AND timestamp_disp < ?',
      whereArgs: [EstadoSync.enviado.index, cutoff30],
    );
    // Auto-limpiar registros abandonados con más de 7 días (no recuperables).
    await db.rawDelete('''
      DELETE FROM $_table
      WHERE retry_count >= 5 AND estado_sync != ? AND timestamp_disp < ?
    ''', [EstadoSync.enviado.index, cutoff7]);
  }

  /// Elimina todos los registros en estado fallido (incluye abandonados y
  /// errores permanentes). Llamar cuando el usuario decide limpiar la cola.
  Future<int> descartarTodosLosFallidos() async {
    final db = await LocalDb.instance.database;
    if (db == null) return 0;
    return db.delete(
      _table,
      where: 'estado_sync = ?',
      whereArgs: [EstadoSync.fallido.index],
    );
  }

  /// Devuelve cuántos registros superaron el límite de reintentos y
  /// quedaron atascados como "abandonados" (retry_count >= 5, no enviados).
  Future<int> contarAbandonados() async {
    final db = await LocalDb.instance.database;
    if (db == null) return 0;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as c FROM $_table '
      'WHERE retry_count >= 5 AND estado_sync != ?',
      [EstadoSync.enviado.index],
    );
    return (result.first['c'] as int?) ?? 0;
  }

  /// Resetea los registros "abandonados" por errores TRANSITORIOS (red, 5xx)
  /// para que puedan reintentarse. NO resetea los marcados como error permanente
  /// (retry_count = 99), porque esos tienen un error definitivo del servidor.
  Future<int> resetParaReintentar() async {
    final db = await LocalDb.instance.database;
    if (db == null) return 0;
    return db.rawUpdate('''
      UPDATE $_table
      SET retry_count = 0,
          estado_sync = ?,
          last_attempt_at = NULL
      WHERE retry_count >= 5 AND retry_count < 99 AND estado_sync != ?
    ''', [EstadoSync.pendiente.index, EstadoSync.enviado.index]);
  }

  /// Resetea los registros con error permanente (retry_count = 99) a pendiente
  /// para reintentarlos. Úsalo cuando la causa del rechazo (p. ej. un bug del
  /// backend ya corregido) dejó de aplicar.
  Future<int> resetErroresPermanentes() async {
    final db = await LocalDb.instance.database;
    if (db == null) return 0;
    return db.rawUpdate('''
      UPDATE $_table
      SET retry_count = 0,
          estado_sync = ?,
          last_attempt_at = NULL
      WHERE retry_count = 99
    ''', [EstadoSync.pendiente.index]);
  }

  /// Marca un registro con error permanente del servidor (4xx ≠ 401).
  /// Usa retry_count = 99 como centinela para distinguirlos de los abandonados
  /// por reintentos normales. Estos no se resetean con resetParaReintentar().
  Future<void> marcarErrorPermanente(String uuid) async {
    final db = await LocalDb.instance.database;
    if (db == null) return;
    await db.rawUpdate('''
      UPDATE $_table
      SET retry_count = 99,
          estado_sync = ?,
          last_attempt_at = ?
      WHERE uuid = ?
    ''', [EstadoSync.fallido.index, DateTime.now().toIso8601String(), uuid]);
  }

  /// Elimina los registros con error permanente (retry_count = 99).
  /// Se llama cuando el usuario decide descartar registros irrecuperables.
  Future<int> descartarErroresPermanentes() async {
    final db = await LocalDb.instance.database;
    if (db == null) return 0;
    return db.delete(
      _table,
      where: 'retry_count = 99',
    );
  }

  /// Cuántos registros tienen error permanente (retry_count = 99).
  Future<int> contarErroresPermanentes() async {
    final db = await LocalDb.instance.database;
    if (db == null) return 0;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as c FROM $_table WHERE retry_count = 99',
    );
    return (result.first['c'] as int?) ?? 0;
  }
}
