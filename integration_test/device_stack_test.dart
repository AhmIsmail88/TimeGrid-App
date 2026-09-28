import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:timegrid/app/app.dart';
import 'package:timegrid/core/database/app_database.dart';
import 'package:timegrid/core/models/app_settings.dart';
import 'package:timegrid/core/models/project.dart';
import 'package:timegrid/core/models/task.dart';
import 'package:timegrid/core/models/work_log.dart';
import 'package:timegrid/core/repositories/project_repository.dart';
import 'package:timegrid/core/repositories/settings_repository.dart';
import 'package:timegrid/core/repositories/task_repository.dart';
import 'package:timegrid/core/repositories/work_log_repository.dart';
import 'package:timegrid/core/utils/period_calculator.dart';

/// Runs **on the phone**, with the real database, the real repositories and
/// the real app widget — no fakes anywhere. It is the only check that the
/// whole stack fits together: an entry written through the repository layer
/// has to come back out through the dashboard.
///
/// It also pauses for a moment at the end so the screen can be captured from
/// outside while the app is showing real data.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const stamp = '2026-09-01T00:00:00.000';

  Future<void> wipe() async {
    final db = await AppDatabase.instance.database;
    for (final table in ['work_logs', 'tasks', 'projects', 'offices', 'settings']) {
      await db.delete(table);
    }
  }

  testWidgets('an entry saved through the repositories shows on the dashboard',
      (tester) async {
    await wipe();

    // The user's own cycle: the 21st to the 20th, not the calendar month.
    await SettingsRepository().save(const AppSettings(
      employeeName: 'أحمد',
      reportingCycleStartDay: 21,
    ));

    final projectId = await ProjectRepository().insert(const Project(
      nameAr: 'مشروع السيب',
      nameEn: '',
      createdAt: stamp,
      updatedAt: stamp,
    ));
    final taskId = await TaskRepository().insert(const TimeTask(
      nameAr: 'مراجعة رسومات',
      nameEn: '',
      createdAt: stamp,
      updatedAt: stamp,
    ));

    // Two entries inside the current 21-to-20 cycle.
    const calculator = PeriodCalculator(21);
    final period = calculator.currentPeriod();
    final logs = WorkLogRepository();
    await logs.insert(WorkLog(
      projectId: projectId,
      taskId: taskId,
      workDate: _iso(period.start),
      hours: 3.0,
      createdAt: stamp,
      updatedAt: stamp,
    ));
    await logs.insert(WorkLog(
      projectId: projectId,
      taskId: taskId,
      workDate: _iso(period.start.add(const Duration(days: 2))),
      hours: 2.5,
      createdAt: stamp,
      updatedAt: stamp,
    ));

    await tester.pumpWidget(const ProviderScope(child: TimeGridApp()));
    await tester.pumpAndSettle();

    // The period on screen is the configured cycle, not the month.
    final label =
        '${DateFormat('d MMM').format(period.start)} \u2013 ${DateFormat('d MMM').format(period.end)}';
    expect(find.text(label), findsOneWidget);
    expect(
      find.text(
          '${DateFormat('d MMM').format(DateTime(period.start.year, period.start.month, 1))}'
          ' \u2013 '
          '${DateFormat('d MMM').format(DateTime(period.start.year, period.start.month + 1, 0))}'),
      findsNothing,
    );

    // The numbers came back out of the database.
    expect(find.text('5.50'), findsOneWidget, reason: 'period total');
    expect(find.text('مراجعة رسومات'), findsWidgets);
    expect(find.textContaining('مشروع السيب'), findsWidgets);

    // Hold the screen with real data on it long enough to be captured.
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(seconds: 25));
  });
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
