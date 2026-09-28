import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timegrid/core/database/app_database.dart';

/// Verifies the data-safety contract of [AppDatabase] on the host, using
/// the FFI implementation of sqflite instead of an Android device:
///
///  * a fresh install creates the whole schema;
///  * re-opening an existing database never rebuilds it, so stored rows
///    survive;
///  * when a database file on disk is older than the current schema, a
///    byte copy is written next to it *before* anything is upgraded.
///
/// Each test uses its own file name, so nothing here can touch a real
/// database and no cleanup is required.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  Future<String> dbPathFor(String name) async {
    final dir = await getDatabasesPath();
    return p.join(dir, name);
  }

  String freshName(String label) =>
      'timegrid_test_${label}_${DateTime.now().microsecondsSinceEpoch}.db';

  test('a fresh database gets the full schema', () async {
    AppDatabase.dbFileName = freshName('fresh');

    final db = await AppDatabase.instance.database;
    final tables = (await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"))
        .map((row) => row['name'] as String)
        .toList();

    expect(tables, containsAll(<String>['projects', 'tasks', 'work_logs', 'settings']));

    final indexes = (await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'index'"))
        .map((row) => row['name'] as String)
        .toList();
    expect(indexes, contains('idx_work_logs_date'));

    // Foreign keys are enforced, so a log cannot point at a missing project.
    await db.insert('projects', {
      'id': 1,
      'name_ar': 'مشروع',
      'name_en': 'Project',
      'is_archived': 0,
      'created_at': '2026-09-01T00:00:00.000',
      'updated_at': '2026-09-01T00:00:00.000',
    });
    expect(
      () => db.insert('work_logs', {
        'project_id': 99,
        'task_id': 99,
        'work_date': '2026-09-01',
        'hours': 1.0,
        'created_at': '2026-09-01T00:00:00.000',
        'updated_at': '2026-09-01T00:00:00.000',
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('re-opening an existing database keeps the stored rows', () async {
    final name = freshName('reopen');
    AppDatabase.dbFileName = name;

    final first = await AppDatabase.instance.database;
    await first.insert('projects', {
      'name_ar': 'مشروع محفوظ',
      'name_en': 'Saved project',
      'is_archived': 0,
      'created_at': '2026-09-01T00:00:00.000',
      'updated_at': '2026-09-01T00:00:00.000',
    });
    await AppDatabase.instance.close();

    // Re-open exactly as a new app launch would.
    final second = await AppDatabase.instance.database;
    final rows = await second.query('projects');

    expect(rows.length, 1);
    expect(rows.single['name_ar'], 'مشروع محفوظ');

    // Opening at the current version must not trigger a safety copy.
    final path = await dbPathFor(name);
    expect(File('$path.pre-v0.bak').existsSync(), isFalse);
    expect(File('$path.pre-v1.bak').existsSync(), isFalse);
  });

  test('an older on-disk database is copied aside before it is opened',
      () async {
    final name = freshName('upgrade');
    AppDatabase.dbFileName = name;
    final path = await dbPathFor(name);

    // Build a "previous release" file: an unrelated table plus one row of
    // real user data, recorded as schema version 0.
    final legacy = await databaseFactory.openDatabase(path);
    await legacy.execute(
        'CREATE TABLE legacy (id INTEGER PRIMARY KEY, note TEXT NOT NULL)');
    await legacy.insert('legacy', {'note': 'بيانات قديمة'});
    await legacy.execute('PRAGMA user_version = 0');
    await legacy.close();

    final db = await AppDatabase.instance.database;

    // The safety copy exists and still holds the original data...
    final backup = File('$path.pre-v0.bak');
    expect(backup.existsSync(), isTrue,
        reason: 'a copy must be written before upgrading');

    final restored = await databaseFactory.openDatabase(backup.path,
        options: OpenDatabaseOptions(readOnly: true));
    expect((await restored.query('legacy')).single['note'], 'بيانات قديمة');
    await restored.close();

    // ...while the live database has been brought up to the app schema.
    final tables = (await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table'"))
        .map((row) => row['name'] as String)
        .toList();
    expect(tables, contains('work_logs'));
  });
}
