import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timegrid/app/localization/gen/app_localizations.dart';
import 'package:timegrid/app/theme.dart';
import 'package:timegrid/core/models/locked_period.dart';
import 'package:timegrid/core/models/work_log.dart';
import 'package:timegrid/core/providers/providers.dart';
import 'package:timegrid/core/repositories/period_lock_repository.dart';
import 'package:timegrid/core/repositories/work_log_repository.dart';
import 'package:timegrid/core/utils/project_accent.dart';
import 'package:timegrid/core/widgets/week_strip.dart';
import 'package:timegrid/features/work_logs/presentation/work_logs_screen.dart';
import 'package:timegrid/features/work_logs/presentation/widgets/work_log_card.dart';

/// Widget tests for the work-logs list pieces: the accent bar, the lock chip
/// and the week-strip day filter. The database is faked out, exactly like in
/// `app_smoke_test.dart`, because a real SQLite read never completes on the
/// widget-test fake clock.
void main() {
  WorkLogView entry({
    int id = 1,
    int projectId = 1,
    String date = '2026-09-01',
    double hours = 2,
  }) =>
      WorkLogView(
        log: WorkLog(
          id: id,
          projectId: projectId,
          taskId: id,
          workDate: date,
          hours: hours,
          createdAt: '2026-09-01T00:00:00.000',
          updatedAt: '2026-09-01T00:00:00.000',
        ),
        projectNameAr: 'مشروع السيب',
        projectNameEn: 'Seeb project',
        taskNameAr: 'مراجعة رسومات',
        taskNameEn: 'Drawing review',
      );

  Finder dayCells() => find.byWidgetPredicate((widget) =>
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith('week-day-'));

  Widget cardHarness({required WorkLogView view, required bool isLocked}) =>
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: Scaffold(
          body: WorkLogCard(
            view: view,
            locale: 'en',
            isLocked: isLocked,
            onTap: () {},
            onDelete: () {},
          ),
        ),
      );

  Widget screenHarness({
    required WorkLogRepository workLogRepository,
    required PeriodLockRepository periodLockRepository,
    ThemeData? theme,
  }) =>
      ProviderScope(
        overrides: [
          workLogRepositoryProvider.overrideWithValue(workLogRepository),
          periodLockRepositoryProvider.overrideWithValue(periodLockRepository),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: theme ?? AppTheme.light(),
          home: const WorkLogsScreen(),
        ),
      );

  group('ProjectAccent', () {
    test('is stable per project id', () {
      expect(ProjectAccent.of(2, Brightness.light),
          ProjectAccent.of(2, Brightness.light));
      expect(ProjectAccent.of(2, Brightness.light),
          ProjectAccent.of(2, Brightness.light));
      expect(ProjectAccent.of(2, Brightness.light),
          ProjectAccent.of(2, Brightness.light));
    });

    test('distinguishes most ids and follows the brightness', () {
      expect(ProjectAccent.of(1, Brightness.light),
          isNot(ProjectAccent.of(2, Brightness.light)));
      expect(ProjectAccent.of(2, Brightness.dark),
          isNot(ProjectAccent.of(2, Brightness.light)));
      expect(ProjectAccent.of(null, Brightness.light),
          ProjectAccent.light.first);
    });
  });

  testWidgets('the card shows the project accent bar and the lock chip',
      (tester) async {
    await tester
        .pumpWidget(cardHarness(view: entry(projectId: 3), isLocked: false));

    final bar =
        tester.widget<Container>(find.byKey(const Key('work-log-accent')));
    expect(bar.color, ProjectAccent.of(3, Brightness.light));
    expect(find.byIcon(Icons.lock_outline), findsNothing);

    await tester
        .pumpWidget(cardHarness(view: entry(projectId: 3), isLocked: true));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });

  testWidgets('the card uses the dark palette on a dark theme',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.dark(),
      home: Scaffold(
        body: WorkLogCard(
          view: entry(projectId: 1),
          locale: 'en',
          isLocked: false,
          onTap: () {},
          onDelete: () {},
        ),
      ),
    ));

    final bar = tester.widget<Container>(find.byKey(const Key('work-log-accent')));
    expect(bar.color, ProjectAccent.of(1, Brightness.dark));
  });

  testWidgets('the list filters to a tapped day and clears again',
      (tester) async {
    final repository = _FakeWorkLogRepository([
      entry(id: 1, projectId: 1, date: '2026-09-01'),
      entry(id: 2, projectId: 2, date: '2026-09-02'),
    ]);
    await tester.pumpWidget(screenHarness(
      workLogRepository: repository,
      periodLockRepository: _FakePeriodLockRepository(),
    ));
    await tester.pumpAndSettle();

    expect(repository.lastFilter!.periodStart, isNull);
    expect(repository.lastFilter!.periodEnd, isNull);
    expect(find.byType(WorkLogCard), findsNWidgets(2));
    expect(find.byType(WeekStrip), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);

    final firstKey =
        (tester.widget(dayCells().first).key! as ValueKey<String>).value;
    final firstDay = DateTime.parse(firstKey.substring('week-day-'.length));

    await tester.tap(dayCells().first);
    await tester.pumpAndSettle();

    expect(repository.lastFilter!.periodStart, firstDay);
    expect(repository.lastFilter!.periodEnd, firstDay);
    expect(find.byType(ActionChip), findsOneWidget);

    await tester.tap(find.byType(ActionChip));
    await tester.pumpAndSettle();

    expect(repository.lastFilter!.periodStart, isNull);
    expect(repository.lastFilter!.periodEnd, isNull);
    expect(find.byType(ActionChip), findsNothing);
  });

  testWidgets('marks the one entry that sits inside a locked period',
      (tester) async {
    final repository = _FakeWorkLogRepository([
      entry(id: 1, projectId: 1, date: '2026-09-01'),
      entry(id: 2, projectId: 2, date: '2026-09-02'),
    ]);
    await tester.pumpWidget(screenHarness(
      workLogRepository: repository,
      periodLockRepository: _FakePeriodLockRepository(
        lockedPeriod: LockedPeriod(
          start: DateTime(2026, 9, 1),
          end: DateTime(2026, 9, 1),
          lockedAt: '2026-09-30T00:00:00.000',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(WorkLogCard), findsNWidgets(2));
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });

  testWidgets('renders on the dark theme with strip and cards', (tester) async {
    final repository =
        _FakeWorkLogRepository([entry(id: 1, projectId: 1, date: '2026-09-01')]);
    await tester.pumpWidget(screenHarness(
      workLogRepository: repository,
      periodLockRepository: _FakePeriodLockRepository(),
      theme: AppTheme.dark(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(WeekStrip), findsOneWidget);
    expect(find.byType(WorkLogCard), findsOneWidget);
    final bar =
        tester.widget<Container>(find.byKey(const Key('work-log-accent')));
    expect(bar.color, ProjectAccent.of(1, Brightness.dark));
  });
}

class _FakeWorkLogRepository extends WorkLogRepository {
  _FakeWorkLogRepository(this._rows);

  final List<WorkLogView> _rows;
  WorkLogFilter? lastFilter;

  @override
  Future<List<WorkLogView>> getFiltered(WorkLogFilter filter) async {
    lastFilter = filter;
    return List<WorkLogView>.of(_rows);
  }
}

class _FakePeriodLockRepository extends PeriodLockRepository {
  _FakePeriodLockRepository({this.lockedPeriod});

  final LockedPeriod? lockedPeriod;

  @override
  Future<List<LockedPeriod>> getAll() async =>
      lockedPeriod == null ? const [] : [lockedPeriod!];
}
