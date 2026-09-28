// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timegrid/core/database/app_database.dart';
import 'package:timegrid/core/repositories/backup_repository.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.documentsPath);

  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

/// Converts a legacy TimeGrid database (the Android/Room build that shipped
/// as `com.aistudio.timegrid.krqzyb`) into this app's own backup format, so
/// the entries can be brought over with Settings -> Restore data.
///
/// Runs only when TIMEGRID_LEGACY_DB is set; TIMEGRID_LEGACY_OUT names the
/// JSON file to write.
///
/// Mapping notes:
///  * the legacy table is flat (`taskName` / `projectName` as free text), so
///    distinct names become rows in `projects` and `tasks`;
///  * `description` becomes `notes`; when a `category` is present it is kept
///    in the same field, because the new schema has no category column;
///  * `company` is a constant ("ICE") in the source and has no home in the
///    new schema - the company name lives in the Excel template instead.
void main() {
  final sourcePath = Platform.environment['TIMEGRID_LEGACY_DB'] ?? '';
  final outPath = Platform.environment['TIMEGRID_LEGACY_OUT'] ?? '';

  test('convert a legacy database into a TimeGrid backup', () async {
    if (sourcePath.isEmpty || !File(sourcePath).existsSync()) {
      markTestSkipped('TIMEGRID_LEGACY_DB not set');
      return;
    }
    expect(outPath, isNotEmpty, reason: 'TIMEGRID_LEGACY_OUT must be set');

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Work on copies so SQLite can fold the write-ahead log in safely.
    final work = Directory.systemTemp.createTempSync('legacy_convert');
    final copy = File('${work.path}/legacy.db');
    File(sourcePath).copySync(copy.path);
    for (final suffix in ['-wal', '-shm']) {
      final side = File('$sourcePath$suffix');
      if (side.existsSync()) side.copySync('${copy.path}$suffix');
    }

    final db = await databaseFactory.openDatabase(copy.path);
    await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    final logs = await db.query('time_logs', orderBy: 'dateString ASC, id ASC');
    await db.close();

    print('legacy rows: ${logs.length}');

    final projectIds = <String, int>{};
    final taskIds = <String, int>{};
    final projects = <Map<String, Object?>>[];
    final tasks = <Map<String, Object?>>[];
    final workLogs = <Map<String, Object?>>[];

    String iso(int? millis) => DateTime.fromMillisecondsSinceEpoch(
          millis ?? DateTime.now().millisecondsSinceEpoch,
        ).toIso8601String();

    var logId = 0;
    for (final row in logs) {
      final projectName = (row['projectName'] as String? ?? '').trim();
      final taskName = (row['taskName'] as String? ?? '').trim();
      if (projectName.isEmpty && taskName.isEmpty) continue;

      final projectId = projectIds.putIfAbsent(projectName, () {
        final id = projects.length + 1;
        projects.add({
          'id': id,
          'name_ar': projectName,
          'name_en': '',
          'is_archived': 0,
          'created_at': iso(row['timestamp'] as int?),
          'updated_at': iso(row['timestamp'] as int?),
        });
        return id;
      });

      final taskId = taskIds.putIfAbsent(taskName, () {
        final id = tasks.length + 1;
        tasks.add({
          'id': id,
          'name_ar': taskName,
          'name_en': '',
          'is_archived': 0,
          'created_at': iso(row['timestamp'] as int?),
          'updated_at': iso(row['timestamp'] as int?),
        });
        return id;
      });

      final category = (row['category'] as String? ?? '').trim();
      final description = (row['description'] as String? ?? '').trim();
      final notes = category.isEmpty
          ? (description.isEmpty ? null : description)
          : (description.isEmpty ? category : '$category \u00b7 $description');

      workLogs.add({
        'id': ++logId,
        'project_id': projectId,
        'task_id': taskId,
        'work_date': (row['dateString'] as String? ?? '').trim(),
        'hours': (row['hours'] as num?)?.toDouble() ?? 0.0,
        'notes': notes,
        'created_at': iso(row['timestamp'] as int?),
        'updated_at': iso(row['timestamp'] as int?),
      });
    }

    final payload = <String, Object?>{
      'format': 'timegrid_backup',
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'source': 'legacy com.aistudio.timegrid.krqzyb',
      'projects': projects,
      'tasks': tasks,
      'work_logs': workLogs,
      'settings': <Map<String, Object?>>[
        {'key': 'language_code', 'value': 'ar'},
        {'key': 'reporting_cycle_start_day', 'value': '1'},
      ],
    };

    final out = File(outPath);
    out.writeAsStringSync(jsonEncode(payload), flush: true);

    print('projects  : ${projects.length}');
    print('tasks     : ${tasks.length}');
    print('work logs : ${workLogs.length}');
    print('written   : ${out.path} (${out.lengthSync()} bytes)');

    // Sanity checks: nothing invented, nothing dropped.
    expect(workLogs.length, logs.length);
    expect(workLogs.every((l) => (l['hours'] as double) > 0), isTrue);
    expect(
        workLogs.every((l) => (l['work_date'] as String).length == 10), isTrue);
    expect(projects.map((p) => p['name_ar']).toSet().length, projects.length);
    expect(tasks.map((t) => t['name_ar']).toSet().length, tasks.length);

    final dates = workLogs.map((l) => l['work_date'] as String).toList()..sort();
    print('date range: ${dates.first} .. ${dates.last}');

    final hours =
        workLogs.fold<double>(0, (sum, l) => sum + (l['hours'] as double));
    print('total hours: $hours');
  });

  // The real proof: feed the converted file to the app's own restore path and
  // check that every entry arrives intact. If this passes, the user's data
  // really does land in the new app.
  test('the converted file restores into a fresh app database', () async {
    final importFile = File(
        outPath.isNotEmpty ? outPath : p.join('dist', 'TimeGrid_Legacy_Import.json'));
    if (!importFile.existsSync()) {
      markTestSkipped('converted import file not present');
      return;
    }

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final documents = await Directory.systemTemp.createTemp('legacy_restore');
    PathProviderPlatform.instance = _FakePathProvider(documents.path);
    AppDatabase.dbFileName =
        'timegrid_legacy_${DateTime.now().microsecondsSinceEpoch}.db';

    try {
      final summary =
          jsonDecode(importFile.readAsStringSync()) as Map<String, dynamic>;
      final expectedProjects = (summary['projects'] as List).length;
      final expectedTasks = (summary['tasks'] as List).length;
      final expectedLogs = (summary['work_logs'] as List).length;
      final expectedHours = (summary['work_logs'] as List).fold<double>(
          0, (sum, row) => sum + ((row as Map)['hours'] as num).toDouble());

      final safety = await BackupRepository().restoreBackup(importFile);
      expect(safety.existsSync(), isTrue);

      final db = await AppDatabase.instance.database;
      Future<int> count(String table) async {
        final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
        return rows.first['c'] as int;
      }

      expect(await count('projects'), expectedProjects);
      expect(await count('tasks'), expectedTasks);
      expect(await count('work_logs'), expectedLogs);

      final rows = await db.rawQuery(
          'SELECT COALESCE(SUM(hours), 0) AS total FROM work_logs');
      expect((rows.first['total'] as num).toDouble(), expectedHours);

      // Every stored log points at a project and a task that exist.
      final orphans = await db.rawQuery('''
        SELECT COUNT(*) AS c FROM work_logs w
        LEFT JOIN projects p ON p.id = w.project_id
        LEFT JOIN tasks t ON t.id = w.task_id
        WHERE p.id IS NULL OR t.id IS NULL
      ''');
      expect(orphans.first['c'], 0);

      print('restored projects=$expectedProjects tasks=$expectedTasks '
          'logs=$expectedLogs hours=$expectedHours');
    } finally {
      await AppDatabase.instance.close();
      if (documents.existsSync()) documents.deleteSync(recursive: true);
    }
  });
}
