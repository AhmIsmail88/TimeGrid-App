import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timegrid/core/database/app_database.dart';
import 'package:timegrid/core/models/app_settings.dart';
import 'package:timegrid/core/models/project.dart';
import 'package:timegrid/core/models/task.dart';
import 'package:timegrid/core/models/work_log.dart';
import 'package:timegrid/core/repositories/project_repository.dart';
import 'package:timegrid/core/repositories/settings_repository.dart';
import 'package:timegrid/core/repositories/task_repository.dart';
import 'package:timegrid/core/repositories/work_log_repository.dart';

/// Runs the real repository SQL against a real SQLite database on the
/// host (sqflite's FFI backend), so the query and delete rules are
/// exercised without a device.
void main() {
  const stamp = '2026-09-01T00:00:00.000';

  final projects = ProjectRepository();
  final tasks = TaskRepository();
  final logs = WorkLogRepository();
  final settings = SettingsRepository();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    AppDatabase.dbFileName =
        'timegrid_repo_${DateTime.now().microsecondsSinceEpoch}.db';
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  Future<int> addProject(String ar, String en) => projects.insert(
        Project(nameAr: ar, nameEn: en, createdAt: stamp, updatedAt: stamp),
      );

  Future<int> addTask(String ar, String en) => tasks.insert(
        TimeTask(nameAr: ar, nameEn: en, createdAt: stamp, updatedAt: stamp),
      );

  Future<int> addLog(int projectId, int taskId, String date, double hours) =>
      logs.insert(WorkLog(
        projectId: projectId,
        taskId: taskId,
        workDate: date,
        hours: hours,
        createdAt: stamp,
        updatedAt: stamp,
      ));

  test('projects and tasks are stored, read back and listed in order',
      () async {
    final betaId = await addProject('بيتا', 'beta');
    final alphaId = await addProject('ألفا', 'Alpha');
    final taskId = await addTask('مراجعة', 'Review');

    expect(betaId, greaterThan(0));
    expect((await projects.getById(alphaId))!.nameEn, 'Alpha');
    expect((await tasks.getById(taskId))!.nameAr, 'مراجعة');

    // Ordered case-insensitively by the English name.
    expect((await projects.getAll()).map((p) => p.nameEn).toList(),
        ['Alpha', 'beta']);
  });

  test('updating a project keeps the row addressable', () async {
    final id = await addProject('قديم', 'Old');
    final current = (await projects.getById(id))!;

    await projects.update(current.copyWith(nameAr: 'جديد', nameEn: 'New'));

    final updated = (await projects.getById(id))!;
    expect(updated.nameAr, 'جديد');
    expect(updated.displayName('ar'), 'جديد');
    expect(updated.displayName('en'), 'New');
  });

  test('archiving hides a project from the active list only', () async {
    final id = await addProject('مشروع', 'Project');
    await projects.setArchived(id, true);

    expect(await projects.getAll(includeArchived: false), isEmpty);
    expect((await projects.getAll()).single.isArchived, isTrue);

    await projects.setArchived(id, false);
    expect((await projects.getAll(includeArchived: false)).length, 1);
  });

  test('a project or task with history can never be hard-deleted', () async {
    final projectId = await addProject('له سجل', 'Has history');
    final taskId = await addTask('له سجل', 'Has history');
    await addLog(projectId, taskId, '2026-09-02', 2);

    // Refused, and the rows are still there.
    expect(await projects.deleteIfUnused(projectId), isFalse);
    expect(await tasks.deleteIfUnused(taskId), isFalse);
    expect(await projects.getById(projectId), isNotNull);
    expect(await tasks.getById(taskId), isNotNull);
  });

  test('an unused project or task is removed', () async {
    final projectId = await addProject('فاضي', 'Unused');
    final taskId = await addTask('فاضي', 'Unused');

    expect(await projects.deleteIfUnused(projectId), isTrue);
    expect(await tasks.deleteIfUnused(taskId), isTrue);
    expect(await projects.getById(projectId), isNull);
    expect(await tasks.getById(taskId), isNull);
  });

  test('period totals and counts only include the given range', () async {
    final projectId = await addProject('مشروع', 'Project');
    final taskId = await addTask('مهمة', 'Task');
    await addLog(projectId, taskId, '2026-08-31', 9);
    await addLog(projectId, taskId, '2026-09-01', 1);
    await addLog(projectId, taskId, '2026-09-05', 1.5);
    await addLog(projectId, taskId, '2026-09-06', 9);

    expect(
      await logs.totalHoursForPeriod(DateTime(2026, 9, 1), DateTime(2026, 9, 5)),
      2.5,
    );
    expect(
      await logs.countForPeriod(DateTime(2026, 9, 1), DateTime(2026, 9, 5)),
      2,
    );
  });

  test('getRecent applies its limit in SQL and returns the newest first',
      () async {
    final projectId = await addProject('مشروع', 'Project');
    final taskId = await addTask('مهمة', 'Task');
    for (var day = 1; day <= 8; day++) {
      await addLog(projectId, taskId, '2026-09-0$day', 1);
    }

    final recent = await logs.getRecent(limit: 3);

    expect(recent.length, 3);
    expect(recent.first.log.workDate, '2026-09-08');
    expect(recent.last.log.workDate, '2026-09-06');
  });

  test('search treats % and _ as literal characters', () async {
    final percentId = await addProject('مشروع', 'A%B');
    final percentTask = await addTask('مهمة', 'Task');
    await addLog(percentId, percentTask, '2026-09-01', 1);

    final otherId = await addProject('مشروع', 'AXB');
    final otherTask = await addTask('مهمة', 'Task2');
    await addLog(otherId, otherTask, '2026-09-02', 1);

    final exact = await logs.getFiltered(const WorkLogFilter(searchText: 'A%B'));
    expect(exact.length, 1);
    expect(exact.single.projectNameEn, 'A%B');

    // A bare % must match the literal character, not "everything".
    final wildcard = await logs.getFiltered(const WorkLogFilter(searchText: '%'));
    expect(wildcard.length, 1);
    expect(wildcard.single.projectNameEn, 'A%B');
  });

  test('settings round-trip, and an empty database yields defaults', () async {
    final initial = await settings.load();
    expect(initial.languageCode, 'ar');
    expect(initial.reportingCycleStartDay, 1);
    expect(initial.excelTemplatePath, isNull);

    await settings.save(const AppSettings(
      languageCode: 'en',
      employeeName: 'Ahmed',
      reportingCycleStartDay: 21,
    ));

    final loaded = await settings.load();
    expect(loaded.languageCode, 'en');
    expect(loaded.employeeName, 'Ahmed');
    expect(loaded.reportingCycleStartDay, 21);
    expect(loaded.excelTemplatePath, isNull);
  });
}
