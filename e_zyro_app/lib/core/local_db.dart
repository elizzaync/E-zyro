import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  Database? _db;

  /// Returns null on web (sqflite not supported); use guards before calling.
  Future<Database?> get database async {
    if (kIsWeb) return null;
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = join(dir, 'ezyro_local.db');
    return openDatabase(
      path,
      version: 5,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE registro_asistencia_local (
            uuid              TEXT PRIMARY KEY,
            timestamp_disp    TEXT NOT NULL,
            latitud           REAL NOT NULL,
            longitud          REAL NOT NULL,
            tipo_marcacion    TEXT NOT NULL,
            evidencia_path    TEXT,
            estado_sync       INTEGER NOT NULL DEFAULT 0,
            retry_count       INTEGER NOT NULL DEFAULT 0,
            last_attempt_at   TEXT,
            fuente_tiempo     TEXT NOT NULL DEFAULT 'device_only'
          )
        ''');
        await _crearCacheKv(db);
        await _crearEvidenciaPendiente(db);
        await _crearAccionPendiente(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE registro_asistencia_local ADD COLUMN fuente_tiempo TEXT NOT NULL DEFAULT 'device_only'",
          );
        }
        if (oldVersion < 3) {
          await _crearCacheKv(db);
        }
        if (oldVersion < 4) {
          await _crearEvidenciaPendiente(db);
        }
        if (oldVersion < 5) {
          await _crearAccionPendiente(db);
        }
      },
    );
  }

  /// Cola genérica de acciones de operaciones pendientes de enviar (offline).
  /// Acciones con ID de servidor estable y sin dependencias entre sí:
  /// toggle de tarea, firma de recepción y notas (add/edit/delete).
  static Future<void> _crearAccionPendiente(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS accion_pendiente (
        uuid            TEXT PRIMARY KEY,
        tipo            TEXT NOT NULL,
        payload         TEXT NOT NULL,
        servicio_id     TEXT,
        estado_sync     INTEGER NOT NULL DEFAULT 0,
        retry_count     INTEGER NOT NULL DEFAULT 0,
        last_attempt_at TEXT,
        created_at      TEXT NOT NULL
      )
    ''');
  }

  /// Cola de evidencias de procedimientos pendientes de subir (offline-first).
  static Future<void> _crearEvidenciaPendiente(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS evidencia_pendiente (
        uuid             TEXT PRIMARY KEY,
        procedimiento_id TEXT NOT NULL,
        servicio_id      TEXT,
        etapa            TEXT NOT NULL,
        descripcion      TEXT,
        foto_path        TEXT NOT NULL,
        estado_sync      INTEGER NOT NULL DEFAULT 0,
        retry_count      INTEGER NOT NULL DEFAULT 0,
        last_attempt_at  TEXT,
        created_at       TEXT NOT NULL
      )
    ''');
  }

  /// Caché genérico clave→valor (JSON) para datos de solo lectura offline
  /// (proyectos, servicios, detalle de servicio, etc.).
  static Future<void> _crearCacheKv(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cache_kv (
        clave      TEXT PRIMARY KEY,
        valor      TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }
}
