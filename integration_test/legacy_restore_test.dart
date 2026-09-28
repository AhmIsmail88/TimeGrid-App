import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:timegrid/core/database/app_database.dart';
import 'package:timegrid/core/repositories/backup_repository.dart';

/// Restores the real "TimeGrid_Legacy_Import.json" **on the phone**, using
/// the exact code path the Settings screen uses, and checks that the counts
/// and hours come out as expected.
///
/// Android's scoped storage stops the app from reading Downloads, so the file
/// is placed in the app's own external files directory before the run:
///
///   adb push dist/TimeGrid_Legacy_Import.json \
///     /sdcard/Android/data/com.example.timegrid/files/legacy_import.json
///
/// The test skips itself when the file is not there, so it is harmless to
/// leave in the suite.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the legacy import restores on the device', (tester) async {
    final external = await getExternalStorageDirectory();
    if (external == null) {
      markTestSkipped('no external files directory on this device');
      return;
    }
    final source = File(p.join(external.path, 'legacy_import.json'));
    if (!await source.exists()) {
      markTestSkipped('legacy_import.json was not pushed');
      return;
    }

    final payload =
        jsonDecode(await source.readAsString()) as Map<String, dynamic>;
    final expectedProjects = (payload['projects'] as List).length;
    final expectedTasks = (payload['tasks'] as List).length;
    final expectedLogs = (payload['work_logs'] as List).length;
    final expectedHours = (payload['work_logs'] as List).fold<double>(
        0, (sum, row) => sum + ((row as Map)['hours'] as num).toDouble());

    // ignore: avoid_print
    print('importing: $expectedProjects projects, $expectedTasks tasks, '
        '$expectedLogs logs, $expectedHours hours');

    // Same call the Restore button makes, including its pre-restore snapshot.
    final safety = await BackupRepository().restoreBackup(source);
    expect(await safety.exists(), isTrue);

    final db = await AppDatabase.instance.database;
    Future<int> count(String table) async {
      final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
      return rows.first['c'] as int;
    }

    expect(await count('projects'), expectedProjects);
    expect(await count('tasks'), expectedTasks);
    expect(await count('work_logs'), expectedLogs);

    final total = (await db
        .rawQuery('SELECT COALESCE(SUM(hours), 0) AS t FROM work_logs')
        .then((rows) => rows.first['t'])) as num;
    expect(total.toDouble(), expectedHours);

    // Every restored row still points at a real project and task.
    final orphans = await db.rawQuery('''
      SELECT COUNT(*) AS c FROM work_logs w
      LEFT JOIN projects p ON p.id = w.project_id
      LEFT JOIN tasks t ON t.id = w.task_id
      WHERE p.id IS NULL OR t.id IS NULL
    ''');
    expect(orphans.first['c'], 0);

    final oldest = await db
        .rawQuery('SELECT MIN(work_date) AS d FROM work_logs')
        .then((rows) => rows.first['d']);
    final newest = await db
        .rawQuery('SELECT MAX(work_date) AS d FROM work_logs')
        .then((rows) => rows.first['d']);
    // ignore: avoid_print
    print('restored on device: $oldest .. $newest');

    await AppDatabase.instance.close();
  });
}
