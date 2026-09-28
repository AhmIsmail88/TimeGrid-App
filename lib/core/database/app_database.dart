import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Central SQLite access point. Created lazily on first use and reused
/// (singleton) for the lifetime of the app process.
///
/// DATA-SAFETY CONTRACT — this is the only place allowed to change the
/// on-device schema:
///
///  * The database file lives in the app's private databases directory,
///    so it is preserved across app updates as long as the Android
///    applicationId and the signing key stay unchanged.
///  * Migrations are always ADDITIVE. `fallbackToDestructiveMigration`
///    must never be used here: recreating the schema would silently
///    discard the user's entire history.
///  * Before an existing file is upgraded to a newer schema version, a
///    byte-for-byte copy is written next to it
///    (`timegrid.db.pre-v<old>.bak`), so even an unexpected migration
///    can be recovered manually.
///  * Downgrades are refused instead of deleting data.
class AppDatabase {
  AppDatabase._internal();
  static final AppDatabase instance = AppDatabase._internal();

  /// Current schema version.
  ///  * 1 — projects, tasks, work_logs, settings
  ///  * 2 — consulting offices/clients, and the office a project belongs to
  ///  * 3 — periods already reported to an office, locked against edits
  ///  * 4 — a log of the timesheets that have been produced
  static const int schemaVersion = 4;

  /// Name of the database file inside the app's databases directory.
  /// Not const, and overridable, so tests can work on their own file and
  /// never touch the real database.
  static String dbFileName = 'timegrid.db';

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<String> _dbPath() async {
    final dbPath = await getDatabasesPath();
    return p.join(dbPath, dbFileName);
  }

  // --- Shared DDL, so creating and migrating can never drift apart --------

  static const String _createOfficesTable = '''
      CREATE TABLE offices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name_ar TEXT NOT NULL DEFAULT '',
        name_en TEXT NOT NULL DEFAULT '',
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''';

  static const String _addProjectOfficeColumn =
      'ALTER TABLE projects ADD COLUMN office_id INTEGER;';

  static const String _createProjectsOfficeIndex =
      'CREATE INDEX idx_projects_office ON projects (office_id);';

  static const String _createExportsTable = '''
      CREATE TABLE exports (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        office_id INTEGER,
        office_name TEXT NOT NULL DEFAULT '',
        period_start TEXT NOT NULL,
        period_end TEXT NOT NULL,
        file_name TEXT NOT NULL DEFAULT '',
        file_path TEXT NOT NULL DEFAULT '',
        format TEXT NOT NULL DEFAULT '',
        exported_at TEXT NOT NULL
      );
    ''';

  static const String _createExportsIndex =
      'CREATE INDEX idx_exports_period ON exports (period_start, period_end);';

  static const String _createLockedPeriodsTable = '''
      CREATE TABLE locked_periods (
        start_date TEXT PRIMARY KEY,
        end_date TEXT NOT NULL,
        locked_at TEXT NOT NULL
      );
    ''';

  /// Ordered, additive migrations. Entry `i` upgrades schema `i + 1` to
  /// `i + 2`. Never drop or rewrite user data in here.
  static final List<Future<void> Function(DatabaseExecutor db)> _migrations =
      <Future<void> Function(DatabaseExecutor db)>[
    // 1 -> 2: the consulting office / client a project is delivered for.
    (db) async {
      await db.execute(_createOfficesTable);
      await db.execute(_addProjectOfficeColumn);
      await db.execute(_createProjectsOfficeIndex);
    },
    // 2 -> 3: periods that were already reported to an office.
    (db) async {
      await db.execute(_createLockedPeriodsTable);
    },
    // 3 -> 4: the log of produced timesheets.
    (db) async {
      await db.execute(_createExportsTable);
      await db.execute(_createExportsIndex);
    },
  ];

  /// Reads the schema version recorded inside an existing database file,
  /// without going through the migrating open path.
  Future<int?> _readOnDiskVersion(String path) async {
    if (!await File(path).exists()) return null;
    Database? probe;
    try {
      probe = await openDatabase(path, readOnly: true, singleInstance: false);
      final rows = await probe.rawQuery('PRAGMA user_version');
      if (rows.isEmpty) return null;
      final value = rows.first.values.first;
      return value is int ? value : null;
    } catch (_) {
      // Unreadable file: leave it to the normal open path to report.
      return null;
    } finally {
      try {
        await probe?.close();
      } catch (_) {
        // Ignore: the probe is only used to read one value.
      }
    }
  }

  /// Keeps a safety copy of the pre-upgrade database file. An existing
  /// copy is never overwritten, so the oldest recoverable state survives.
  Future<void> _safetyCopyBeforeUpgrade(String path, int fromVersion) async {
    try {
      final source = File(path);
      if (!await source.exists()) return;
      final target = File('$path.pre-v$fromVersion.bak');
      if (await target.exists()) return;
      await source.copy(target.path);
    } catch (_) {
      // A failed safety copy must never stop the app from starting; the
      // migration itself is still additive.
    }
  }

  Future<Database> _open() async {
    final path = await _dbPath();

    final onDiskVersion = await _readOnDiskVersion(path);
    if (onDiskVersion != null && onDiskVersion < schemaVersion) {
      await _safetyCopyBeforeUpgrade(path, onDiskVersion);
    }

    return openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        for (var from = oldVersion; from < newVersion; from++) {
          final index = from - 1;
          if (index >= 0 && index < _migrations.length) {
            await _migrations[index](db);
          }
        }
      },
      onDowngrade: (db, oldVersion, newVersion) async {
        // Refuse rather than destroy: an older APK must not wipe the
        // user's data just because it does not know the newer schema.
        throw StateError(
          'Refusing to downgrade the TimeGrid database from v$oldVersion '
          'to v$newVersion, because that would discard the stored data.',
        );
      },
    );
  }

  Future<void> _createSchema(Database db) async {
    final batch = db.batch();

    batch.execute(_createOfficesTable);

    // office_id is nullable on purpose: projects created before the office
    // feature existed simply have none, and a project is never deleted just
    // because its office is.
    batch.execute('''
      CREATE TABLE projects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        office_id INTEGER,
        name_ar TEXT NOT NULL DEFAULT '',
        name_en TEXT NOT NULL DEFAULT '',
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');

    batch.execute('''
      CREATE TABLE tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name_ar TEXT NOT NULL DEFAULT '',
        name_en TEXT NOT NULL DEFAULT '',
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');

    // project_id/task_id are intentionally NOT NULL (a log always
    // belongs to exactly one project + one task) but tasks themselves
    // are never exclusively tied to one project (PRD A4.2 / A7.8).
    batch.execute('''
      CREATE TABLE work_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER NOT NULL,
        task_id INTEGER NOT NULL,
        work_date TEXT NOT NULL,
        hours REAL NOT NULL CHECK (hours > 0),
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (project_id) REFERENCES projects (id) ON DELETE RESTRICT,
        FOREIGN KEY (task_id) REFERENCES tasks (id) ON DELETE RESTRICT
      );
    ''');

    batch.execute(
        'CREATE INDEX idx_work_logs_date ON work_logs (work_date);');
    batch.execute(
        'CREATE INDEX idx_work_logs_project ON work_logs (project_id);');
    batch.execute('CREATE INDEX idx_work_logs_task ON work_logs (task_id);');
    batch.execute(_createProjectsOfficeIndex);

    batch.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
    ''');

    batch.execute(_createLockedPeriodsTable);
    batch.execute(_createExportsTable);
    batch.execute(_createExportsIndex);

    await batch.commit(noResult: true);
  }

  Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }
}
