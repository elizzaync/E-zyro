import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = join(dir, 'ezyro_local.db');
    return openDatabase(
      path,
      version: 2,
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
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE registro_asistencia_local ADD COLUMN fuente_tiempo TEXT NOT NULL DEFAULT 'device_only'",
          );
        }
      },
    );
  }
}
