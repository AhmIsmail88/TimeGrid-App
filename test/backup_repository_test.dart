import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timegrid/core/database/app_database.dart';
import 'package:timegrid/core/models/app_settings.dart';
import 'package:timegrid/core/models/project.dart';
import 'package:timegrid/core/models/task.dart';
import 'package:timegrid/core/models/work_log.dart';
import 'package:timegrid/core/repositories/backup_repository.dart';
import 'package:timegrid/core/repositories/project_repository.dart';
import 'package:timegrid/core/repositories/settings_repository.dart';
import 'package:timegrid/core/repositories/task_repository.dart';
import 'package:timegrid/core/repositories/work_log_repository.dart';

/// Points path_provider at a throwaway directory instead of a device.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.documentsPath);

  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

/// Covers the app's safety net: what a backup actually contains, that a
/// restore is itself reversible, and that bad input can never destroy the
/// live data.
void main() {
  const stamp = '2026-09-01T00:00:00.000';

  late Directory documents;

  final backups = BackupRepository();
  final projects = ProjectRepository();
  final tasks = TaskRepository();
  final logs = WorkLogRepository();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('timegrid_backup_test');
    PathProviderPlatform.instance = _FakePathProvider(documents.path);
    AppDatabase.dbFileName =
        'timegrid_backup_${DateTime.now().microsecondsSinceEpoch}.db';
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    if (documents.existsSync()) {
      documents.deleteSync(recursive: true);
    }
  });

  Future<void> seedCurrentData() async {
    final projectId = await projects.insert(const Project(
        nameAr: 'حالي', nameEn: 'Current', createdAt: stamp, updatedAt: stamp));
    final taskId = await tasks.insert(const TimeTask(
        nameAr: 'حالي', nameEn: 'Current task', createdAt: stamp, updatedAt: stamp));
    await logs.insert(WorkLog(
      projectId: projectId,
      taskId: taskId,
      workDate: '2026-09-01',
      hours: 2,
      createdAt: stamp,
      updatedAt: stamp,
    ));
  }

  Map<String, Object?> incomingBackup({int version = 1}) => {
        'format': 'timegrid_backup',
        'version': version,
        'exported_at': '2026-09-20T00:00:00.000',
        'projects': [
          {
            'id': 1,
            'name_ar': 'وارد',
            'name_en': 'Incoming',
            'is_archived': 0,
            'created_at': stamp,
            'updated_at': stamp,
          }
        ],
        'tasks': [
          {
            'id': 1,
            'name_ar': 'مهمة',
            'name_en': 'Task',
            'is_archived': 0,
            'created_at': stamp,
            'updated_at': stamp,
          }
        ],
        'work_logs': [
          {
            'id': 1,
            'project_id': 1,
            'task_id': 1,
            'work_date': '2026-09-05',
            'hours': 4.0,
            'notes': null,
            'created_at': stamp,
            'updated_at': stamp,
          }
        ],
        'settings': [],
      };

  File writeFixture(String name, Object payload) {
    final file = File(p.join(documents.path, name));
    file.writeAsStringSync(
        payload is String ? payload : jsonEncode(payload));
    return file;
  }

  test('a backup contains every table, not just part of one', () async {
    await seedCurrentData();
    await SettingsRepository()
        .save(const AppSettings(employeeName: 'Ahmed', languageCode: 'ar'));

    final file = await backups.createBackup();
    expect(file.existsSync(), isTrue);
    expect(p.basename(file.path), startsWith('TimeGrid_Backup'));

    final payload = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(payload['format'], 'timegrid_backup');
    expect(payload['version'], BackupRepository.backupFormatVersion);
    expect((payload['projects'] as List).length, 1);
    expect((payload['tasks'] as List).length, 1);
    expect((payload['work_logs'] as List).length, 1);
    expect((payload['settings'] as List), isNotEmpty);
  });

  test('a restore is reversible: the previous data is written out first',
      () async {
    await seedCurrentData();
    final incoming = writeFixture('incoming.json', incomingBackup());

    final safety = await backups.restoreBackup(incoming);

    // The safety copy exists, is clearly labelled, and holds the data that
    // was live *before* the restore.
    expect(safety.existsSync(), isTrue);
    expect(p.basename(safety.path), startsWith('TimeGrid_PreRestore_Backup'));
    final saved = jsonDecode(safety.readAsStringSync()) as Map<String, dynamic>;
    expect(((saved['projects'] as List).single as Map)['name_en'], 'Current');

    // ...and the live database now holds the incoming data.
    expect((await projects.getAll()).single.nameEn, 'Incoming');
    expect((await logs.getRecent()).single.log.hours, 4.0);
  });

  test('a file that is not a backup is refused and changes nothing', () async {
    await seedCurrentData();

    final wrongFormat = writeFixture('wrong.json', '{"format":"something_else"}');
    final notJson = writeFixture('broken.json', 'not json at all');

    await expectLater(
        backups.restoreBackup(wrongFormat), throwsA(isA<FormatException>()));
    await expectLater(
        backups.restoreBackup(notJson), throwsA(isA<FormatException>()));
    await expectLater(
      backups.restoreBackup(File(p.join(documents.path, 'missing.json'))),
      throwsA(isA<FileSystemException>()),
    );

    // Nothing was touched.
    expect((await projects.getAll()).single.nameEn, 'Current');
    expect((await logs.getRecent()).length, 1);
  });

  test('a backup written by a newer app version is refused', () async {
    await seedCurrentData();
    final fromTheFuture = writeFixture(
        'future.json',
        incomingBackup(version: BackupRepository.backupFormatVersion + 1));

    await expectLater(
        backups.restoreBackup(fromTheFuture), throwsA(isA<FormatException>()));
    expect((await projects.getAll()).single.nameEn, 'Current');
  });
}
