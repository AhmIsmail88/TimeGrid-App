// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timegrid/core/database/app_database.dart';
import 'package:timegrid/core/models/export_record.dart';
import 'package:timegrid/core/repositories/export_repository.dart';

/// The log of produced timesheets: it answers "have I already sent this
/// period?" without hunting through the file system.
void main() {
  final exports = ExportRepository();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    AppDatabase.dbFileName =
        'timegrid_exports_${DateTime.now().microsecondsSinceEpoch}.db';
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  ExportRecord record({
    int? officeId,
    String officeName = 'مكتب الاستشاري',
    DateTime? start,
    DateTime? end,
    String fileName = 'TimeGrid_Timesheet.xlsx',
    String format = 'xlsx',
    String exportedAt = '2026-09-28T12:00:00.000',
  }) =>
      ExportRecord(
        officeId: officeId,
        officeName: officeName,
        periodStart: start ?? DateTime(2026, 9, 21),
        periodEnd: end ?? DateTime(2026, 10, 20),
        fileName: fileName,
        filePath: '/tmp/$fileName',
        format: format,
        exportedAt: exportedAt,
      );

  test('an export is stored and read back', () async {
    await exports.record(record(officeId: 3));

    final all = await exports.getRecent();
    expect(all.length, 1);
    expect(all.single.officeName, 'مكتب الاستشاري');
    expect(all.single.format, 'xlsx');
    expect(all.single.periodStart, DateTime(2026, 9, 21));
    expect(all.single.periodEnd, DateTime(2026, 10, 20));
  });

  test('the newest export comes first', () async {
    await exports.record(record(exportedAt: '2026-09-01T09:00:00.000'));
    await exports.record(record(exportedAt: '2026-09-28T18:00:00.000'));
    await exports.record(record(exportedAt: '2026-09-10T12:00:00.000'));

    final all = await exports.getRecent();
    expect(all.map((e) => e.exportedAt).toList(), [
      '2026-09-28T18:00:00.000',
      '2026-09-10T12:00:00.000',
      '2026-09-01T09:00:00.000',
    ]);
  });

  test('asking whether a period was already exported is per office', () async {
    await exports.record(record(officeId: 1));

    expect(
      await exports.hasExported(
        officeId: 1,
        start: DateTime(2026, 9, 21),
        end: DateTime(2026, 10, 20),
      ),
      isTrue,
    );

    // A different office, the same dates: not sent yet.
    expect(
      await exports.hasExported(
        officeId: 2,
        start: DateTime(2026, 9, 21),
        end: DateTime(2026, 10, 20),
      ),
      isFalse,
    );

    // A different period for the same office: not sent either.
    expect(
      await exports.hasExported(
        officeId: 1,
        start: DateTime(2026, 10, 21),
        end: DateTime(2026, 11, 20),
      ),
      isFalse,
    );
  });

  test('a PDF export is recorded as such', () async {
    await exports.record(
        record(fileName: 'Timesheet.pdf', format: 'pdf', officeId: 1));

    expect((await exports.getRecent()).single.format, 'pdf');
  });

  test('upgrading v3 -> v4 adds the export log and keeps the data', () async {
    final name = 'timegrid_v3_${DateTime.now().microsecondsSinceEpoch}.db';
    AppDatabase.dbFileName = name;
    final dir = await getDatabasesPath();
    final path = p.join(dir, name);

    // Build the database exactly as the v3 release left it.
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
    await legacy.execute('''
      CREATE TABLE locked_periods (
        start_date TEXT PRIMARY KEY,
        end_date TEXT NOT NULL,
        locked_at TEXT NOT NULL
      );
    ''');
    await legacy.insert('offices', {
      'name_ar': 'مكتب قديم',
      'name_en': 'Legacy office',
      'is_archived': 0,
      'created_at': '2026-09-01T00:00:00.000',
      'updated_at': '2026-09-01T00:00:00.000',
    });
    await legacy.insert('locked_periods', {
      'start_date': '2026-08-21',
      'end_date': '2026-09-20',
      'locked_at': '2026-09-21T00:00:00.000',
    });
    await legacy.execute('PRAGMA user_version = 3');
    await legacy.close();

    final db = await AppDatabase.instance.database;

    expect((await db.rawQuery('PRAGMA user_version')).first.values.first,
        AppDatabase.schemaVersion);
    final tables = (await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table'"))
        .map((r) => r['name'] as String)
        .toList();
    expect(tables, contains('exports'));

    // Nothing that was already stored moved.
    expect((await db.query('offices')).single['name_en'], 'Legacy office');
    expect((await db.query('locked_periods')).single['start_date'],
        '2026-08-21');

    final backup = File('$path.pre-v3.bak');
    expect(backup.existsSync(), isTrue);
    final restored = await databaseFactory.openDatabase(backup.path,
        options: OpenDatabaseOptions(readOnly: true));
    final backupTables = (await restored.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table'"))
        .map((r) => r['name'] as String)
        .toList();
    expect(backupTables, isNot(contains('exports')));
    await restored.close();
  });
}
