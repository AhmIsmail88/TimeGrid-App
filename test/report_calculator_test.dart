import 'package:flutter_test/flutter_test.dart';
import 'package:timegrid/core/models/reporting_period.dart';
import 'package:timegrid/core/models/work_log.dart';
import 'package:timegrid/features/reports/domain/report_calculator.dart';

/// The aggregation rules the reports screen and the Excel export both
/// depend on (PRD A9.3 / A9.4 / A9.5): one row per project+task pair,
/// same-day logs summed, out-of-period logs ignored, never destructive.
void main() {
  final period = ReportingPeriod(
    start: DateTime(2026, 8, 21),
    end: DateTime(2026, 9, 20),
  );

  WorkLog log({
    required int projectId,
    required int taskId,
    required String date,
    required double hours,
  }) =>
      WorkLog(
        projectId: projectId,
        taskId: taskId,
        workDate: date,
        hours: hours,
        createdAt: '2026-09-21T00:00:00.000',
        updatedAt: '2026-09-21T00:00:00.000',
      );

  ReportData build(List<WorkLog> logs) => ReportCalculator().build(
        period: period,
        logsInPeriod: logs,
        projectNameAr: const {1: 'مشروع ألف', 2: 'مشروع باء'},
        projectNameEn: const {1: 'Alpha', 2: 'Beta'},
        taskNameAr: const {1: 'مهمة ألف', 2: 'مهمة باء'},
        taskNameEn: const {1: 'Task A', 2: 'Task B'},
      );

  test('sums logs sharing the same project, task and day into one cell', () {
    final data = build([
      log(projectId: 1, taskId: 1, date: '2026-08-23', hours: 1.5),
      log(projectId: 1, taskId: 1, date: '2026-08-23', hours: 2.0),
      log(projectId: 1, taskId: 1, date: '2026-08-24', hours: 3.0),
    ]);

    expect(data.rows.length, 1);
    expect(data.rows.single.hoursByDate,
        {'2026-08-23': 3.5, '2026-08-24': 3.0});
    expect(data.rows.single.rowTotal, 6.5);
    expect(data.grandTotal, 6.5);
    expect(data.entryCount, 1);
  });

  test('the same task under two projects stays two separate rows', () {
    final data = build([
      log(projectId: 1, taskId: 1, date: '2026-08-23', hours: 1),
      log(projectId: 2, taskId: 1, date: '2026-08-23', hours: 2),
    ]);

    expect(data.rows.length, 2);
    expect(data.grandTotal, 3);
  });

  test('ignores logs outside the period, including the boundary days', () {
    final data = build([
      log(projectId: 1, taskId: 1, date: '2026-08-20', hours: 5),
      log(projectId: 1, taskId: 1, date: '2026-09-21', hours: 5),
      log(projectId: 1, taskId: 1, date: '2026-08-21', hours: 1),
      log(projectId: 1, taskId: 1, date: '2026-09-20', hours: 1),
    ]);

    expect(data.rows.single.hoursByDate,
        {'2026-08-21': 1.0, '2026-09-20': 1.0});
    expect(data.grandTotal, 2);
  });

  test('orders rows by project name then task name, case-insensitively', () {
    final data = ReportCalculator().build(
      period: period,
      logsInPeriod: [
        log(projectId: 1, taskId: 1, date: '2026-08-23', hours: 1),
        log(projectId: 1, taskId: 2, date: '2026-08-23', hours: 1),
        log(projectId: 2, taskId: 1, date: '2026-08-23', hours: 1),
        log(projectId: 2, taskId: 2, date: '2026-08-23', hours: 1),
      ],
      projectNameAr: const {1: 'مشروع ألف', 2: 'مشروع باء'},
      projectNameEn: const {1: 'beta', 2: 'Alpha'},
      taskNameAr: const {1: 'مهمة ألف', 2: 'مهمة باء'},
      taskNameEn: const {1: 'zeta', 2: 'alpha'},
    );

    expect(data.rows.map((r) => r.projectNameEn).toList(),
        ['Alpha', 'Alpha', 'beta', 'beta']);
    expect(data.rows.map((r) => r.taskNameEn).toList(),
        ['alpha', 'zeta', 'alpha', 'zeta']);
  });

  test('an empty period produces an empty report, not a failure', () {
    final data = build(const []);

    expect(data.rows, isEmpty);
    expect(data.grandTotal, 0);
    expect(data.entryCount, 0);
  });

  test('WorkLogView prefers the requested language and falls back', () {
    final view = WorkLogView(
      log: log(projectId: 1, taskId: 1, date: '2026-08-23', hours: 1),
      projectNameAr: 'مشروع',
      projectNameEn: 'Project',
      taskNameAr: '',
      taskNameEn: 'Task',
    );

    expect(view.projectName('ar'), 'مشروع');
    expect(view.projectName('en'), 'Project');
    // Empty Arabic falls back to English rather than showing a blank cell.
    expect(view.taskName('ar'), 'Task');
    expect(view.taskName('en'), 'Task');
  });

  test('ReportingPeriod is inclusive on both ends and lists every day', () {
    expect(period.contains(DateTime(2026, 8, 21)), isTrue);
    expect(period.contains(DateTime(2026, 9, 20)), isTrue);
    expect(period.contains(DateTime(2026, 8, 20)), isFalse);
    expect(period.contains(DateTime(2026, 9, 21)), isFalse);
    expect(period.dayCount, 31);
    expect(period.allDates.first, DateTime(2026, 8, 21));
    expect(period.allDates.last, DateTime(2026, 9, 20));
  });
}
