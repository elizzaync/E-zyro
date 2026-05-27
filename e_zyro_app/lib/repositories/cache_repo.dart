import 'package:sqflite/sqflite.dart';
import '../core/local_db.dart';

/// Caché genérico clave→valor (JSON crudo) para datos de solo lectura que el
/// técnico necesita ver sin conexión (proyectos, servicios, detalle de servicio).
/// En web la BD local no existe → todas las operaciones son no-op.
class CacheRepo {
  static const _table = 'cache_kv';

  Future<void> put(String clave, String jsonValor) async {
    final db = await LocalDb.instance.database;
    if (db == null) return;
    await db.insert(
      _table,
      {
        'clave': clave,
        'valor': jsonValor,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> get(String clave) async {
    final db = await LocalDb.instance.database;
    if (db == null) return null;
    final rows = await db.query(
      _table,
      columns: ['valor'],
      where: 'clave = ?',
      whereArgs: [clave],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['valor'] as String?;
  }

  /// Borra todo el caché. Llamar al cerrar sesión para no mezclar usuarios.
  Future<void> clearAll() async {
    final db = await LocalDb.instance.database;
    if (db == null) return;
    await db.delete(_table);
  }
}
