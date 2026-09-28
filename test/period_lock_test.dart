// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timegrid/core/database/app_database.dart';
import 'package:timegrid/core/repositories/period_lock_repository.dart';

/// A period whose report has already gone to a consulting office is locked
/// against later edits, so this covers both the rule and the schema change
/// that introduced it.
void main() {
  final locks = PeriodLockRepository();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    AppDatabase.dbFileName =
        'timegrid_lock_${DateTime.now().microsecondsSinceEpoch}.db';
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  final periodStart = DateTime(2026, 9, 21);
  final periodEnd = DateTime(2026, 10, 20);

  test('a locked period covers its dates and nothing outside them', () async {
    await locks.lock(periodStart, periodEnd);

    expect(await locks.isDateLocked(DateTime(2026, 9, 21)), isTrue);
    expect(await locks.isDateLocked(DateTime(2026, 10, 5)), isTrue);
    expect(await locks.isDateLocked(DateTime(2026, 10, 20)), isTrue);

    expect(await locks.isDateLocked(DateTime(2026, 9, 20)), isFalse);
    expect(await locks.isDateLocked(DateTime(2026, 10, 21)), isFalse);
  });

  test('the locked period can be found for a date and listed', () async {
    await locks.lock(periodStart, periodEnd);

    final found = await locks.findForDate(DateTime(2026, 10, 1));
    expect(found, isNotNull);
    expect(found!.start, periodStart);
    expect(found.end, periodEnd);

    expect(await locks.findForDate(DateTime(2026, 1, 1)), isNull);

    final all = await locks.getAll();
    expect(all.length, 1);
    expect(all.single.contains(DateTime(2026, 10, 1)), isTrue);
  });

  test('locking the same period twice does not duplicate it', () async {
    await locks.lock(periodStart, periodEnd);
    await locks.lock(periodStart, periodEnd);

    expect((await locks.getAll()).length, 1);
    expect(await locks.isRangeLocked(periodStart, periodEnd), isTrue);
  });

  test('a period can be unlocked again, deliberately', () async {
    await locks.lock(periodStart, periodEnd);
    expect(await locks.isRangeLocked(periodStart, periodEnd), isTrue);

    await locks.unlock(periodStart, periodEnd);

    expect(await locks.isRangeLocked(periodStart, periodEnd), isFalse);
    expect(await locks.isDateLocked(DateTime(2026, 10, 1)), isFalse);
    expect(await locks.getAll(), isEmpty);
  });

  test('two different periods can be locked independently', () async {
    await locks.lock(periodStart, periodEnd);
    await locks.lock(DateTime(2026, 10, 21), DateTime(2026, 11, 20));

    expect((await locks.getAll()).length, 2);
    expect(await locks.isDateLocked(DateTime(2026, 9, 25)), isTrue);
    expect(await locks.isDateLocked(DateTime(2026, 11, 1)), isTrue);
    expect(await locks.isDateLocked(DateTime(2026, 12, 1)), isFalse);
  });

  test('upgrading v2 -> v3 adds locked periods and keeps the data', () async {
    final name = 'timegrid_v2_${DateTime.now().microsecondsSinceEpoch}.db';
    AppDatabase.dbFileName = name;
    final dir = await getDatabasesPath();
    final path = p.join(dir, name);

    // Build the database exactly as the v2 release left it.
    final legacy = await databaseFactory.openDatabase(path);
    await legacy.execute('''
      CREATE TABLE offices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name_ar TEXT NOT NULL DEFAULT '',
        name_en TEXT NOT NULL DEFAULT '',
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    await legacy.execute('''
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
    await legacy.execute('''
      CREATE TABLE tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name_ar TEXT NOT NULL DEFAULT '',
        name_en TEXT NOT NULL DEFAULT '',
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    await legacy.execute('''
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
    await legacy.execute(
        'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    await legacy.insert('offices', {
      'name_ar': 'مكتب قديم',
      'name_en': 'Legacy office',
      'is_archived': 0,
      'created_at': '2026-09-01T00:00:00.000',
      'updated_at': '2026-09-01T00:00:00.000',
    });
    await legacy.insert('projects', {
      'office_id': 1,
      'name_ar': 'مشروع قديم',
      'name_en': 'Legacy project',
      'is_archived': 0,
      'created_at': '2026-09-01T00:00:00.000',
      'updated_at': '2026-09-01T00:00:00.000',
    });
    await legacy.execute('PRAGMA user_version = 2');
    await legacy.close();

    final db = await AppDatabase.instance.database;

    expect((await db.rawQuery('PRAGMA user_version')).first.values.first,
        AppDatabase.schemaVersion);
    final tables = (await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table'"))
        .map((r) => r['name'] as String)
        .toList();
    expect(tables, contains('locked_periods'));

    // Nothing that was already stored moved.
    expect((await db.query('offices')).single['name_en'], 'Legacy office');
    final project = (await db.query('projects')).single;
    expect(project['name_en'], 'Legacy project');
    expect(project['office_id'], 1, reason: 'the office link must survive');

    // And the safety copy exists, without the new table in it.
    final backup = File('$path.pre-v2.bak');
    expect(backup.existsSync(), isTrue);
    final restored = await databaseFactory.openDatabase(backup.path,
        options: OpenDatabaseOptions(readOnly: true));
    final backupTables = (await restored.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table'"))
        .map((r) => r['name'] as String)
        .toList();
    expect(backupTables, isNot(contains('locked_periods')));
    await restored.close();
  });
}
