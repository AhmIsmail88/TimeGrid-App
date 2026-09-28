import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:timegrid/app/app.dart';
import 'package:timegrid/core/models/app_settings.dart';
import 'package:timegrid/core/models/locked_period.dart';
import 'package:timegrid/core/models/office.dart';
import 'package:timegrid/core/models/project.dart';
import 'package:timegrid/core/models/reporting_period.dart';
import 'package:timegrid/core/models/task.dart';
import 'package:timegrid/core/models/work_log.dart';
import 'package:timegrid/core/providers/providers.dart';
import 'package:timegrid/core/repositories/office_repository.dart';
import 'package:timegrid/core/repositories/period_lock_repository.dart';
import 'package:timegrid/core/repositories/project_repository.dart';
import 'package:timegrid/core/repositories/task_repository.dart';
import 'package:timegrid/core/repositories/work_log_repository.dart';
import 'package:timegrid/core/utils/bidi.dart';
import 'package:timegrid/core/utils/period_calculator.dart';

/// Boots the real application widget and renders it, so the parts unit
/// tests cannot reach are exercised: the localisation delegates, the
/// router, the Riverpod wiring and the screens' build methods.
///
/// Widget tests run on a fake clock, where a real SQLite read never
/// completes, so everything that would touch the database is overridden
/// with in-memory data. The database layer itself is covered by
/// `repository_crud_test.dart`, `backup_repository_test.dart` and
/// `app_database_safety_test.dart`.
///
/// The router is a top-level singleton, so each test that navigates
/// returns to the dashboard before finishing.
void main() {
  WorkLogView logView({required double hours}) => WorkLogView(
        log: WorkLog(
          id: 1,
          projectId: 1,
          taskId: 1,
          workDate: '2026-09-01',
          hours: hours,
          createdAt: '2026-09-01T00:00:00.000',
          updatedAt: '2026-09-01T00:00:00.000',
        ),
        projectNameAr: 'مشروع السيب',
        projectNameEn: 'Seeb project',
        taskNameAr: 'مراجعة رسومات',
        taskNameEn: 'Drawing review',
      );

  /// The default test window is 800x600 — much shorter than a phone — so the
  /// dashboard's lower sections would not be laid out at all. Use a realistic
  /// phone surface instead.
  void usePhoneScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  WorkLog log({required double hours}) => WorkLog(
        id: 1,
        projectId: 1,
        taskId: 1,
        workDate: '2026-09-01',
        hours: hours,
        createdAt: '2026-09-01T00:00:00.000',
        updatedAt: '2026-09-01T00:00:00.000',
      );

  Widget buildApp({
    List<WorkLog> periodLogs = const [],
    List<WorkLogView> recent = const [],
    WorkLogRepository? workLogRepository,
    ProjectRepository? projectRepository,
    TaskRepository? taskRepository,
    OfficeRepository? officeRepository,
    PeriodLockRepository? periodLockRepository,
    AppSettings settings = const AppSettings(),
    int? reportOfficeId,
  }) {
    return ProviderScope(
      overrides: [
        settingsProvider.overrideWith(() => _FakeSettings(settings)),
        // Always faked: the real ones would hit SQLite, which never completes
        // on a widget test's fake clock.
        periodLockRepositoryProvider
            .overrideWithValue(periodLockRepository ?? _FakePeriodLockRepository()),
        projectRepositoryProvider
            .overrideWithValue(projectRepository ?? _FakeProjectRepository(const [])),
        // The dashboard's totals, day strip and top projects are all derived
        // from this one list, so overriding the source keeps them consistent.
        if (reportOfficeId != null)
          reportOfficeProvider.overrideWith((ref) => reportOfficeId),
        periodLogsProvider.overrideWith((ref) async => periodLogs),
        recentEntriesProvider.overrideWith((ref) async => recent),
        if (workLogRepository != null)
          workLogRepositoryProvider.overrideWithValue(workLogRepository),
        if (officeRepository != null)
          officeRepositoryProvider.overrideWithValue(officeRepository),
        if (projectRepository != null)
          projectRepositoryProvider.overrideWithValue(projectRepository),
        if (taskRepository != null)
          taskRepositoryProvider.overrideWithValue(taskRepository),
      ],
      child: const TimeGridApp(),
    );
  }

  /// Mirrors the dashboard: the two dates are wrapped in a left-to-right
  /// isolate so the bidi algorithm cannot swap the day and the month.
  String periodLabel(ReportingPeriod period) => ltrRun(
      '${DateFormat('d MMM').format(period.start)} \u2013 '
      '${DateFormat('d MMM').format(period.end)}');

  testWidgets('boots into the Arabic dashboard, RTL, with an empty state',
      (tester) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(
      Directionality.of(tester.element(find.byType(Scaffold).first)),
      TextDirection.rtl,
    );

    expect(find.text('الفترة الحالية'), findsOneWidget);
    expect(find.text('إجمالي الساعات'), findsOneWidget);
    expect(find.text('عدد السجلات'), findsOneWidget);
    expect(find.text('لا توجد سجلات بعد'), findsOneWidget);
    // With no office chosen the numbers are for everything, and the chip says so.
    expect(find.text('كل المكاتب'), findsOneWidget);

    expect(find.text('المشاريع'), findsOneWidget);
    expect(find.text('المهام'), findsOneWidget);
    expect(find.text('التقارير'), findsOneWidget);
  });

  testWidgets('period totals and recent entries are rendered', (tester) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(buildApp(
      periodLogs: [log(hours: 3.5)],
      recent: [logView(hours: 3.0)],
    ));
    await tester.pumpAndSettle();

    expect(find.text('لا توجد سجلات بعد'), findsNothing);
    expect(find.text('3.50'), findsOneWidget);
    expect(find.text('مراجعة رسومات'), findsOneWidget);
    expect(find.textContaining('مشروع السيب'), findsOneWidget);
    expect(find.text('3.0h'), findsOneWidget);
  });

  testWidgets('the dashboard steps between reporting periods', (tester) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    const calculator = PeriodCalculator(1);
    final current = calculator.currentPeriod();
    final next = calculator.nextPeriod(current);
    final previous = calculator.previousPeriod(current);

    expect(find.text(periodLabel(current)), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();
    expect(find.text(periodLabel(next)), findsOneWidget);
    expect(find.text(periodLabel(current)), findsNothing);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text(periodLabel(current)), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text(periodLabel(previous)), findsOneWidget);
  });

  testWidgets('a deleted entry can be brought back with Undo', (tester) async {
    final repository = _FakeWorkLogRepository([logView(hours: 2.0)]);
    usePhoneScreen(tester);
    await tester.pumpWidget(buildApp(workLogRepository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('سجلات العمل'));
    await tester.pumpAndSettle();
    expect(find.text('مراجعة رسومات'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف'));
    await tester.pumpAndSettle();

    expect(repository.deletedIds, [1]);
    expect(find.text('مراجعة رسومات'), findsNothing);
    expect(find.text('تم حذف السجل'), findsOneWidget);

    await tester.tap(find.text('تراجع'));
    await tester.pumpAndSettle();

    expect(repository.restoreCount, 1);
    expect(find.text('مراجعة رسومات'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('الفترة الحالية'), findsOneWidget);
  });

  testWidgets('a duplicate entry is confirmed before it is saved again',
      (tester) async {
    final workLogs = _FakeWorkLogRepository([logView(hours: 2.0)]);
    usePhoneScreen(tester);
    await tester.pumpWidget(buildApp(
      workLogRepository: workLogs,
      projectRepository: _FakeProjectRepository([
        const Project(
          id: 1,
          nameAr: 'مشروع السيب',
          nameEn: 'Seeb project',
          createdAt: '',
          updatedAt: '',
        ),
      ]),
      taskRepository: _FakeTaskRepository([
        const TimeTask(
          id: 1,
          nameAr: 'مراجعة رسومات',
          nameEn: 'Drawing review',
          createdAt: '',
          updatedAt: '',
        ),
      ]),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('إضافة سجل'));
    await tester.pumpAndSettle();

    // The label and the empty field carry the same text, so tap the field.
    await tester.tap(find.text('المشروع').last);
    await tester.pumpAndSettle();
    expect(find.text('إضافة مشروع'), findsOneWidget);
    await tester.tap(find.text('مشروع السيب'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('المهمة').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('مراجعة رسومات'));
    await tester.pumpAndSettle();

    // 2 hours, exactly what is already on record for this date.
    await tester.enterText(find.byType(TextField), '2');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(find.text('مسجّل بالفعل'), findsOneWidget);
    expect(workLogs.insertCount, 0);

    // Declining keeps the entry out of the database.
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('إلغاء'),
    ));
    await tester.pumpAndSettle();
    expect(workLogs.insertCount, 0);
    expect(find.text('مسجّل بالفعل'), findsNothing);

    // Confirming saves it.
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('سجّلها على أي حال'));
    await tester.pumpAndSettle();
    expect(workLogs.insertCount, 1);
  });

  testWidgets('picking an office narrows the project list to that office',
      (tester) async {
    final projects = _FakeProjectRepository([
      const Project(
        id: 1,
        officeId: 1,
        nameAr: 'مشروع ألف',
        nameEn: 'Alpha project',
        createdAt: '',
        updatedAt: '',
      ),
      const Project(
        id: 2,
        officeId: 2,
        nameAr: 'مشروع باء',
        nameEn: 'Beta project',
        createdAt: '',
        updatedAt: '',
      ),
    ]);
    usePhoneScreen(tester);
    await tester.pumpWidget(buildApp(
      workLogRepository: _FakeWorkLogRepository(const []),
      projectRepository: projects,
      officeRepository: _FakeOfficeRepository([
        const Office(
          id: 1,
          nameAr: 'مكتب أ',
          nameEn: 'Alpha office',
          createdAt: '',
          updatedAt: '',
        ),
        const Office(
          id: 2,
          nameAr: 'مكتب ب',
          nameEn: 'Beta office',
          createdAt: '',
          updatedAt: '',
        ),
      ]),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('إضافة سجل'));
    await tester.pumpAndSettle();

    // Choose the office first...
    await tester.tap(find.text('اختر المكتب الاستشاري'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مكتب أ'));
    await tester.pumpAndSettle();
    expect(find.text('مكتب أ'), findsOneWidget);

    // ...then the project list only offers that office's projects.
    await tester.tap(find.text('المشروع').last);
    await tester.pumpAndSettle();
    expect(find.text('مشروع ألف'), findsOneWidget);
    expect(find.text('مشروع باء'), findsNothing);

    await tester.tap(find.text('مشروع ألف'));
    await tester.pumpAndSettle();
    expect(projects.lastOfficeId, 1);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  });

  testWidgets('a date in an earlier period asks before saving', (tester) async {
    final workLogs = _FakeWorkLogRepository(const []);
    usePhoneScreen(tester);
    await tester.pumpWidget(buildApp(
      workLogRepository: workLogs,
      projectRepository: _FakeProjectRepository([
        const Project(
            id: 1, nameAr: 'مشروع', nameEn: 'Project', createdAt: '', updatedAt: ''),
      ]),
      taskRepository: _FakeTaskRepository([
        const TimeTask(
            id: 1, nameAr: 'مهمة', nameEn: 'Task', createdAt: '', updatedAt: ''),
      ]),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('إضافة سجل'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('المشروع').last);
    await tester.pumpAndSettle();
    // Creating a project is offered straight away, without typing a search
    // first, so a new one can be added from inside the entry form.
    expect(find.text('إضافة مشروع'), findsOneWidget);
    await tester.tap(find.text('مشروع'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('المهمة').last);
    await tester.pumpAndSettle();
    // Same for tasks: no separate trip to the Tasks screen needed.
    expect(find.text('إضافة مهمة'), findsOneWidget);
    await tester.tap(find.text('مهمة'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '2');

    // Open the date picker, walk it back one month and take day 1, which
    // always lands in the previous reporting period.
    await tester.tap(find.byKey(const Key('entry-date-field')));
    await tester.pumpAndSettle();

    final datePicker = find.byType(DatePickerDialog);
    final localizations = MaterialLocalizations.of(tester.element(datePicker));
    await tester.tap(find.byTooltip(localizations.previousMonthTooltip));
    await tester.pumpAndSettle();
    await tester.tap(
        find.descendant(of: datePicker, matching: find.text('1')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: datePicker,
      matching: find.byType(TextButton),
    ).last);
    await tester.pumpAndSettle();

    final today = DateTime.now();
    final previousMonthFirst = DateTime(today.year, today.month - 1, 1);
    expect(
      find.text(ltrRun(DateFormat('EEE, d MMM yyyy').format(previousMonthFirst))),
      findsOneWidget,
      reason: 'the entry date really moved into the previous period',
    );

    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(find.text('التاريخ في فترة سابقة'), findsOneWidget);
    expect(workLogs.insertCount, 0);

    // Cancelling leaves it unsaved; confirming stores exactly one entry.
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('إلغاء'),
    ));
    await tester.pumpAndSettle();
    expect(workLogs.insertCount, 0);

    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('تأكيد'),
    ));
    await tester.pumpAndSettle();
    expect(workLogs.insertCount, 1);
  });

  testWidgets('an entry inside a locked period cannot be saved', (tester) async {
    final workLogs = _FakeWorkLogRepository(const []);
    usePhoneScreen(tester);
    await tester.pumpWidget(buildApp(
      workLogRepository: workLogs,
      projectRepository: _FakeProjectRepository([
        const Project(
            id: 1, nameAr: 'مشروع', nameEn: 'Project', createdAt: '', updatedAt: ''),
      ]),
      taskRepository: _FakeTaskRepository([
        const TimeTask(
            id: 1, nameAr: 'مهمة', nameEn: 'Task', createdAt: '', updatedAt: ''),
      ]),
      periodLockRepository: _FakePeriodLockRepository(
        lockedPeriod: LockedPeriod(
          start: DateTime(2000, 1, 1),
          end: DateTime(2100, 1, 1),
          lockedAt: '',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('إضافة سجل'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('المشروع').last);
    await tester.pumpAndSettle();
    // Creating a project is offered straight away, without typing a search
    // first, so a new one can be added from inside the entry form.
    expect(find.text('إضافة مشروع'), findsOneWidget);
    await tester.tap(find.text('مشروع'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('المهمة').last);
    await tester.pumpAndSettle();
    // Same for tasks: no separate trip to the Tasks screen needed.
    expect(find.text('إضافة مهمة'), findsOneWidget);
    await tester.tap(find.text('مهمة'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '3');

    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    expect(find.text('الفترة مقفولة'), findsOneWidget);
    expect(workLogs.insertCount, 0);

    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('تأكيد'),
    ));
    await tester.pumpAndSettle();
    expect(workLogs.insertCount, 0);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  });

  testWidgets('the dashboard names the office its numbers are for',
      (tester) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(buildApp(
      reportOfficeId: 7,
      officeRepository: _FakeOfficeRepository([
        const Office(
          id: 7,
          nameAr: 'مكتب السيب',
          nameEn: '',
          createdAt: '',
          updatedAt: '',
        ),
      ]),
    ));
    await tester.pumpAndSettle();

    // Naming it keeps the totals from being mistaken for a global figure.
    expect(find.text('مكتب السيب'), findsOneWidget);
    expect(find.text('كل المكاتب'), findsNothing);
  });

  testWidgets('the dashboard uses the cycle start day from settings',
      (tester) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(buildApp(
      settings: const AppSettings(reportingCycleStartDay: 21),
    ));
    await tester.pumpAndSettle();

    // Settings arrive asynchronously; the dashboard must end up on the
    // 21st-to-20th cycle, not on the calendar month.
    const configured = PeriodCalculator(21);
    expect(find.text(periodLabel(configured.currentPeriod())), findsOneWidget);
    expect(
      find.text(periodLabel(const PeriodCalculator(1).currentPeriod())),
      findsNothing,
    );
  });

  testWidgets('the Add Entry shortcut opens the entry form', (tester) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('إضافة سجل'));
    await tester.pumpAndSettle();

    expect(find.text('التاريخ'), findsOneWidget);
    expect(find.text('الساعات'), findsOneWidget);
    expect(find.text('حفظ'), findsOneWidget);

    // Arabic localisation means the back tooltip is not "Back", so tap the
    // button by type instead.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('الفترة الحالية'), findsOneWidget);
  });
}

class _FakeSettings extends SettingsNotifier {
  _FakeSettings(this._value);

  final AppSettings _value;

  @override
  Future<AppSettings> build() async => _value;
}

/// In-memory stand-in for the work-log table, so the list and entry screens
/// can be driven without a database.
class _FakeWorkLogRepository extends WorkLogRepository {
  _FakeWorkLogRepository(this._rows);

  List<WorkLogView> _rows;
  final List<int> deletedIds = <int>[];
  int restoreCount = 0;
  int insertCount = 0;
  WorkLogView? _removed;

  @override
  Future<List<WorkLogView>> getFiltered(WorkLogFilter filter) async =>
      List<WorkLogView>.of(_rows);

  @override
  Future<int> insert(WorkLog log) async {
    insertCount++;
    return 99;
  }

  @override
  Future<void> delete(int id) async {
    deletedIds.add(id);
    _removed = _rows.firstWhere((row) => row.log.id == id);
    _rows = _rows.where((row) => row.log.id != id).toList();
  }

  @override
  Future<void> restore(WorkLog log) async {
    restoreCount++;
    final removed = _removed;
    if (removed != null) {
      _rows = [..._rows, removed];
      _removed = null;
    }
  }
}

class _FakeProjectRepository extends ProjectRepository {
  _FakeProjectRepository(this._projects);

  final List<Project> _projects;

  int getCalls = 0;
  int? lastOfficeId;

  @override
  Future<List<Project>> getAll({
    bool includeArchived = true,
    int? officeId,
  }) async {
    getCalls++;
    lastOfficeId = officeId;
    if (officeId == null) return List<Project>.of(_projects);
    return _projects.where((p) => p.officeId == officeId).toList();
  }
}

class _FakePeriodLockRepository extends PeriodLockRepository {
  _FakePeriodLockRepository({this.lockedPeriod});

  final LockedPeriod? lockedPeriod;

  @override
  Future<List<LockedPeriod>> getAll() async =>
      lockedPeriod == null ? const [] : [lockedPeriod!];

  @override
  Future<LockedPeriod?> findForDate(DateTime date) async =>
      lockedPeriod != null && lockedPeriod!.contains(date) ? lockedPeriod : null;

  @override
  Future<bool> isDateLocked(DateTime date) async =>
      lockedPeriod != null && lockedPeriod!.contains(date);

  @override
  Future<bool> isRangeLocked(DateTime start, DateTime end) async =>
      lockedPeriod != null;

  @override
  Future<void> lock(DateTime start, DateTime end) async {}

  @override
  Future<void> unlock(DateTime start, DateTime end) async {}
}

class _FakeOfficeRepository extends OfficeRepository {
  _FakeOfficeRepository(this._offices);

  final List<Office> _offices;

  @override
  Future<List<Office>> getAll({bool includeArchived = true}) async =>
      List<Office>.of(_offices);
}

class _FakeTaskRepository extends TaskRepository {
  _FakeTaskRepository(this._tasks);

  final List<TimeTask> _tasks;

  @override
  Future<List<TimeTask>> getAll({bool includeArchived = true}) async =>
      List<TimeTask>.of(_tasks);

  @override
  Future<List<TimeTask>> getRecentlyUsedForProject(int projectId) async =>
      const <TimeTask>[];
}
