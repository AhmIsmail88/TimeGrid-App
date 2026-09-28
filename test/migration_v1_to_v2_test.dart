// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timegrid/core/database/app_database.dart';

/// Schema v1 -> v2 added consulting offices and `projects.office_id`.
///
/// This is the test that matters most for a user who already has real data
/// on the device: it builds a database exactly as the *old* release left it,
/// then opens it with the new code and checks that every stored row is still
/// there, unchanged, alongside the new structure.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  /// The v1 schema, verbatim: no `offices`, no `projects.office_id`.
  Future<void> buildV1Database(String path) async {
    final db = await databaseFactory.openDatabase(path);
    await db.execute('''
      CREATE TABLE projects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name_ar TEXT NOT NULL DEFAULT '',
        name_en TEXT NOT NULL DEFAULT '',
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    await db.execute('''
      CREATE TABLE tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name_ar TEXT NOT NULL DEFAULT '',
        name_en TEXT NOT NULL DEFAULT '',
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    await db.execute('''
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
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
    ''');

    await db.insert('projects', {
      'name_ar': 'مشروع قديم',
      'name_en': 'Legacy project',
      'is_archived': 0,
      'created_at': '2026-08-01T00:00:00.000',
      'updated_at': '2026-08-01T00:00:00.000',
    });
    await db.insert('tasks', {
      'name_ar': 'مهمة قديمة',
      'name_en': 'Legacy task',
      'is_archived': 0,
      'created_at': '2026-08-01T00:00:00.000',
      'updated_at': '2026-08-01T00:00:00.000',
    });
    await db.insert('work_logs', {
      'project_id': 1,
      'task_id': 1,
      'work_date': '2026-08-15',
      'hours': 7.5,
      'notes': 'ملاحظة قديمة',
      'created_at': '2026-08-15T00:00:00.000',
      'updated_at': '2026-08-15T00:00:00.000',
    });
    await db.insert('settings', {'key': 'employee_name', 'value': 'أحمد'});

    await db.execute('PRAGMA user_version = 1');
    await db.close();
  }

  test('upgrading v1 -> v2 keeps every stored row and adds the office layer',
      () async {
    final name = 'timegrid_migration_${DateTime.now().microsecondsSinceEpoch}.db';
    AppDatabase.dbFileName = name;
    final dir = await getDatabasesPath();
    final path = p.join(dir, name);

    await buildV1Database(path);

    final db = await AppDatabase.instance.database;

    // --- the schema actually moved forward --------------------------------
    final version = (await db.rawQuery('PRAGMA user_version')).first.values.first;
    expect(version, AppDatabase.schemaVersion);

    final tables = (await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table'"))
        .map((r) => r['name'] as String)
        .toList();
    expect(tables, contains('offices'));

    final projectColumns = (await db.rawQuery('PRAGMA table_info(projects)'))
        .map((r) => r['name'] as String)
        .toList();
    expect(projectColumns, contains('office_id'));

    // --- and no user data was harmed --------------------------------------
    final projects = await db.query('projects');
    expect(projects.length, 1);
    expect(projects.single['name_ar'], 'مشروع قديم');
    expect(projects.single['office_id'], isNull,
        reason: 'an existing project simply has no office yet');

    final tasks = await db.query('tasks');
    expect(tasks.length, 1);
    expect(tasks.single['name_ar'], 'مهمة قديمة');

    final logs = await db.query('work_logs');
    expect(logs.length, 1);
    expect(logs.single['hours'], 7.5);
    expect(logs.single['notes'], 'ملاحظة قديمة');

    final settings = await db.query('settings');
    expect(settings.single['value'], 'أحمد');

    // --- the pre-upgrade copy is on disk, with the old data in it ---------
    final backup = File('$path.pre-v1.bak');
    expect(backup.existsSync(), isTrue,
        reason: 'a safety copy must be written before the upgrade runs');

    final restored = await databaseFactory.openDatabase(backup.path,
        options: OpenDatabaseOptions(readOnly: true));
    expect((await restored.query('projects')).single['name_en'],
        'Legacy project');
    final backupTables = (await restored.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table'"))
        .map((r) => r['name'] as String)
        .toList();
    expect(backupTables, isNot(contains('offices')));
    await restored.close();
  });

  test('a fresh v2 database has the office layer from the start', () async {
    AppDatabase.dbFileName =
        'timegrid_fresh_v2_${DateTime.now().microsecondsSinceEpoch}.db';

    final db = await AppDatabase.instance.database;

    final tables = (await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table'"))
        .map((r) => r['name'] as String)
        .toList();
    expect(tables, containsAll(<String>['offices', 'projects', 'tasks', 'work_logs']));

    final indexes = (await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'index'"))
        .map((r) => r['name'] as String)
        .toList();
    expect(indexes, contains('idx_projects_office'));

    // Inserting an office works and is readable back.
    await db.insert('offices', {
      'name_ar': 'مكتب الاستشاري',
      'name_en': 'Consultant office',
      'is_archived': 0,
      'created_at': '2026-09-01T00:00:00.000',
      'updated_at': '2026-09-01T00:00:00.000',
    });
    expect((await db.query('offices')).single['name_ar'], 'مكتب الاستشاري');
  });
}
