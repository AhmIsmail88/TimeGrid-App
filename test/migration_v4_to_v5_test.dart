// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timegrid/core/database/app_database.dart';

/// Schema v4 -> v5 added the contact details an office is sent the timesheet
/// through: `email`, `phone` and `whatsapp`.
///
/// Same test as the earlier migrations, for the same reason: a database that
/// already holds the user's offices has to come out of the upgrade with every
/// row, and every value, unchanged.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  /// The v4 schema, verbatim: offices with no contact columns.
  Future<void> buildV4Database(String path) async {
    final db = await databaseFactory.openDatabase(path);
    await db.execute('''
      CREATE TABLE offices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name_ar TEXT NOT NULL DEFAULT '',
        name_en TEXT NOT NULL DEFAULT '',
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    await db.execute('''
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
        updated_at TEXT NOT NULL
      );
    ''');
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
    ''');
    await db.execute('''
      CREATE TABLE locked_periods (
        start_date TEXT PRIMARY KEY,
        end_date TEXT NOT NULL,
        locked_at TEXT NOT NULL
      );
    ''');
    await db.execute('''
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
    ''');

    await db.insert('offices', {
      'name_ar': 'مكتب السيب',
      'name_en': 'Seeb office',
      'is_archived': 0,
      'created_at': '2026-09-01T00:00:00.000',
      'updated_at': '2026-09-01T00:00:00.000',
    });
    await db.insert('projects', {
      'office_id': 1,
      'name_ar': 'مشروع قديم',
      'name_en': 'Legacy project',
      'is_archived': 0,
      'created_at': '2026-09-01T00:00:00.000',
      'updated_at': '2026-09-01T00:00:00.000',
    });
    await db.insert('tasks', {
      'name_ar': 'مهمة قديمة',
      'name_en': 'Legacy task',
      'is_archived': 0,
      'created_at': '2026-09-01T00:00:00.000',
      'updated_at': '2026-09-01T00:00:00.000',
    });
    await db.insert('work_logs', {
      'project_id': 1,
      'task_id': 1,
      'work_date': '2026-09-15',
      'hours': 7.5,
      'notes': 'ملاحظة قديمة',
      'created_at': '2026-09-15T00:00:00.000',
      'updated_at': '2026-09-15T00:00:00.000',
    });
    await db.insert('locked_periods', {
      'start_date': '2026-08-21',
      'end_date': '2026-09-20',
      'locked_at': '2026-09-21T00:00:00.000',
    });
    await db.execute('PRAGMA user_version = 4');
    await db.close();
  }

  test('upgrading v4 -> v5 keeps the offices and adds their contact details',
      () async {
    final name =
        'timegrid_migration_v5_${DateTime.now().microsecondsSinceEpoch}.db';
    AppDatabase.dbFileName = name;
    final dir = await getDatabasesPath();
    final path = p.join(dir, name);

    await buildV4Database(path);

    final db = await AppDatabase.instance.database;

    // --- the schema moved forward -----------------------------------------
    final version = (await db.rawQuery('PRAGMA user_version')).first.values.first;
    expect(version, AppDatabase.schemaVersion);

    final officeColumns = (await db.rawQuery('PRAGMA table_info(offices)'))
        .map((r) => r['name'] as String)
        .toList();
    expect(officeColumns, containsAll(<String>['email', 'phone', 'whatsapp']));

    // --- and nothing the user had was harmed ------------------------------
    final offices = await db.query('offices');
    expect(offices.length, 1);
    expect(offices.single['name_ar'], 'مكتب السيب');
    expect(offices.single['name_en'], 'Seeb office');
    expect(offices.single['created_at'], '2026-09-01T00:00:00.000');
    expect(offices.single['email'], isNull,
        reason: 'an office that existed before has no contact details yet');
    expect(offices.single['phone'], isNull);
    expect(offices.single['whatsapp'], isNull);

    final projects = await db.query('projects');
    expect(projects.single['office_id'], 1);
    expect(projects.single['name_en'], 'Legacy project');

    final logs = await db.query('work_logs');
    expect(logs.single['hours'], 7.5);
    expect(logs.single['notes'], 'ملاحظة قديمة');

    final locks = await db.query('locked_periods');
    expect(locks.single['start_date'], '2026-08-21');

    // --- the pre-upgrade copy is on disk, still at v4 ---------------------
    final backup = File('$path.pre-v4.bak');
    expect(backup.existsSync(), isTrue,
        reason: 'a safety copy must be written before the upgrade runs');
    final restored = await databaseFactory.openDatabase(backup.path,
        options: OpenDatabaseOptions(readOnly: true));
    final backupColumns = (await restored.rawQuery('PRAGMA table_info(offices)'))
        .map((r) => r['name'] as String)
        .toList();
    expect(backupColumns, isNot(contains('email')));
    expect((await restored.query('offices')).single['name_en'], 'Seeb office');
    await restored.close();

    // --- the new columns accept values -----------------------------------
    await db.update(
      'offices',
      {
        'email': 'pm@example.com',
        'phone': '+20 100 000 0000',
        'whatsapp': '+20 100 000 0000',
      },
      where: 'id = ?',
      whereArgs: [1],
    );
    final updated = (await db.query('offices')).single;
    expect(updated['email'], 'pm@example.com');
    expect(updated['whatsapp'], '+20 100 000 0000');
  });

  test('a fresh database has the contact columns from the start', () async {
    AppDatabase.dbFileName =
        'timegrid_fresh_v5_${DateTime.now().microsecondsSinceEpoch}.db';

    final db = await AppDatabase.instance.database;
    final officeColumns = (await db.rawQuery('PRAGMA table_info(offices)'))
        .map((r) => r['name'] as String)
        .toList();
    expect(officeColumns, containsAll(<String>['email', 'phone', 'whatsapp']));

    await db.insert('offices', {
      'name_ar': 'مكتب جديد',
      'name_en': 'New office',
      'email': 'a@b.com',
      'phone': '100',
      'whatsapp': '111',
      'is_archived': 0,
      'created_at': '2026-09-01T00:00:00.000',
      'updated_at': '2026-09-01T00:00:00.000',
    });
    expect((await db.query('offices')).single['email'], 'a@b.com');
  });
}
