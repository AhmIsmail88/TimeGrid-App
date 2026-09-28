import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timegrid/core/database/app_database.dart';
import 'package:timegrid/core/models/office.dart';
import 'package:timegrid/core/models/project.dart';
import 'package:timegrid/core/repositories/office_repository.dart';
import 'package:timegrid/core/models/task.dart';
import 'package:timegrid/core/models/work_log.dart';
import 'package:timegrid/core/repositories/project_repository.dart';
import 'package:timegrid/core/repositories/task_repository.dart';
import 'package:timegrid/core/repositories/work_log_repository.dart';

/// The consulting-office layer: offices are the unit a report is produced
/// for, so an office that still has projects must never be hard-deleted.
void main() {
  const stamp = '2026-09-01T00:00:00.000';

  final offices = OfficeRepository();
  final projects = ProjectRepository();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    AppDatabase.dbFileName =
        'timegrid_office_${DateTime.now().microsecondsSinceEpoch}.db';
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  Future<int> addOffice(String ar, String en) => offices.insert(
      Office(nameAr: ar, nameEn: en, createdAt: stamp, updatedAt: stamp));

  Future<int> addProject(String ar, String en, {int? officeId}) =>
      projects.insert(Project(
        officeId: officeId,
        nameAr: ar,
        nameEn: en,
        createdAt: stamp,
        updatedAt: stamp,
      ));

  test('offices are stored, read back and listed in order', () async {
    final second = await addOffice('مكتب ب', 'beta office');
    final first = await addOffice('مكتب أ', 'Alpha office');

    expect((await offices.getById(first))!.nameEn, 'Alpha office');
    expect((await offices.getAll()).map((o) => o.nameEn).toList(),
        ['Alpha office', 'beta office']);
    // the second insert gets the larger id
    expect(first, greaterThan(second));
  });

  test('archiving hides an office from the active list only', () async {
    final id = await addOffice('مكتب', 'Office');
    await offices.setArchived(id, true);

    expect(await offices.getAll(includeArchived: false), isEmpty);
    expect((await offices.getAll()).single.isArchived, isTrue);

    await offices.setArchived(id, false);
    expect((await offices.getAll(includeArchived: false)).length, 1);
  });

  test('a project belongs to one office and lists are scoped by it', () async {
    final alpha = await addOffice('مكتب أ', 'Alpha office');
    final beta = await addOffice('مكتب ب', 'Beta office');

    await addProject('مشروع ألف', 'Alpha project', officeId: alpha);
    await addProject('مشروع باء', 'Beta project', officeId: beta);
    await addProject('مشروع بدون مكتب', 'Unowned project');

    expect((await projects.getAll()).length, 3);
    expect(
      (await projects.getAll(officeId: alpha)).map((p) => p.nameEn).toList(),
      ['Alpha project'],
    );
    expect(
      (await projects.getAll(officeId: beta)).map((p) => p.nameEn).toList(),
      ['Beta project'],
    );

    // A project with no office is not silently attached to anyone.
    expect(
      (await projects.getAll(officeId: alpha)).map((p) => p.nameEn),
      isNot(contains('Unowned project')),
    );
  });

  test('an office with projects cannot be hard-deleted', () async {
    final id = await addOffice('مكتب', 'Office');
    await addProject('مشروع', 'Project', officeId: id);

    expect(await offices.projectCount(id), 1);
    expect(await offices.deleteIfUnused(id), isFalse);
    expect(await offices.getById(id), isNotNull);
  });

  test('an unused office is removed', () async {
    final used = await addOffice('مستخدم', 'Used');
    await addProject('مشروع', 'Project', officeId: used);
    final unused = await addOffice('فاضي', 'Unused');

    expect(await offices.deleteIfUnused(unused), isTrue);
    expect(await offices.getById(unused), isNull);
    expect(await offices.getById(used), isNotNull);
  });

  test('logs can be fetched for one office only', () async {
    final alpha = await addOffice('مكتب أ', 'Alpha office');
    final beta = await addOffice('مكتب ب', 'Beta office');
    final alphaProject =
        await addProject('مشروع ألف', 'Alpha project', officeId: alpha);
    final betaProject =
        await addProject('مشروع باء', 'Beta project', officeId: beta);
    final taskId = await TaskRepository().insert(const TimeTask(
        nameAr: 'مهمة', nameEn: 'Task', createdAt: stamp, updatedAt: stamp));

    final logs = WorkLogRepository();
    Future<void> addLog(int projectId, String date, double hours) =>
        logs.insert(WorkLog(
          projectId: projectId,
          taskId: taskId,
          workDate: date,
          hours: hours,
          createdAt: stamp,
          updatedAt: stamp,
        ));

    await addLog(alphaProject, '2026-09-10', 2);
    await addLog(betaProject, '2026-09-10', 5);
    await addLog(alphaProject, '2026-10-01', 9); // outside the period

    final start = DateTime(2026, 9, 1);
    final end = DateTime(2026, 9, 30);

    final alphaLogs = await logs.getForPeriodForOffice(start, end, alpha);
    expect(alphaLogs.length, 1);
    expect(alphaLogs.single.hours, 2);

    final betaLogs = await logs.getForPeriodForOffice(start, end, beta);
    expect(betaLogs.single.hours, 5);
  });

  test('re-pointing a project to another office moves it between lists',
      () async {
    final alpha = await addOffice('مكتب أ', 'Alpha office');
    final beta = await addOffice('مكتب ب', 'Beta office');
    final projectId =
        await addProject('مشروع', 'Project', officeId: alpha);

    final project = (await projects.getById(projectId))!;
    await projects.update(Project(
      id: project.id,
      officeId: beta,
      nameAr: project.nameAr,
      nameEn: project.nameEn,
      isArchived: project.isArchived,
      createdAt: project.createdAt,
      updatedAt: stamp,
    ));

    expect(await projects.getAll(officeId: alpha), isEmpty);
    expect((await projects.getAll(officeId: beta)).single.id, projectId);
  });
}
