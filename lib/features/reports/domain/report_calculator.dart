import 'package:collection/collection.dart';

import '../../../core/models/reporting_period.dart';
import '../../../core/models/work_log.dart';

/// Aggregation key: a unique Project + Task pair produces exactly one
/// report row (PRD §9.3). The same task under two different projects
/// produces two separate rows.
class ProjectTaskKey {
  final int projectId;
  final int taskId;
  const ProjectTaskKey(this.projectId, this.taskId);

  @override
  bool operator ==(Object other) =>
      other is ProjectTaskKey &&
      other.projectId == projectId &&
      other.taskId == taskId;

  @override
  int get hashCode => Object.hash(projectId, taskId);
}

/// One output row of the report: a project/task pair with hours spread
/// across the days of the period.
class ReportRow {
  final int projectId;
  final int taskId;
  final String projectNameAr;
  final String projectNameEn;
  final String taskNameAr;
  final String taskNameEn;

  /// Keyed by ISO date ('YYYY-MM-DD') -> summed hours for that day.
  /// Only dates with at least one log appear here; callers should
  /// treat missing dates as zero (PRD §9.4).
  final Map<String, double> hoursByDate;

  ReportRow({
    required this.projectId,
    required this.taskId,
    required this.projectNameAr,
    required this.projectNameEn,
    required this.taskNameAr,
    required this.taskNameEn,
    required this.hoursByDate,
  });

  double get rowTotal =>
      hoursByDate.values.fold(0.0, (sum, h) => sum + h);
}

class ReportData {
  final ReportingPeriod period;
  final List<ReportRow> rows;

  ReportData({required this.period, required this.rows});

  double get grandTotal => rows.fold(0.0, (sum, r) => sum + r.rowTotal);

  int get entryCount => rows.length;
}

/// Turns raw [WorkLog] rows into the grouped/aggregated shape the
/// Reports screen and the Excel exporter both need. Grouping key is
/// exactly `project_id + task_id + work_date` per PRD §9.5 — multiple
/// logs sharing that key are summed into a single cell value.
class ReportCalculator {
  ReportData build({
    required ReportingPeriod period,
    required List<WorkLog> logsInPeriod,
    required Map<int, String> projectNameAr,
    required Map<int, String> projectNameEn,
    required Map<int, String> taskNameAr,
    required Map<int, String> taskNameEn,
  }) {
    // Defensive filter: only include logs whose date actually falls
    // inside the period (PRD §5 rule 9 / §9.4).
    final relevant = logsInPeriod.where((log) {
      final parts = log.workDate.split('-').map(int.parse).toList();
      final date = DateTime(parts[0], parts[1], parts[2]);
      return period.contains(date);
    });

    final grouped = groupBy(relevant, (WorkLog l) => ProjectTaskKey(l.projectId, l.taskId));

    final rows = grouped.entries.map((entry) {
      final key = entry.key;
      final logs = entry.value;
      final byDate = <String, double>{};
      for (final log in logs) {
        byDate.update(log.workDate, (v) => v + log.hours, ifAbsent: () => log.hours);
      }
      return ReportRow(
        projectId: key.projectId,
        taskId: key.taskId,
        projectNameAr: projectNameAr[key.projectId] ?? '',
        projectNameEn: projectNameEn[key.projectId] ?? '',
        taskNameAr: taskNameAr[key.taskId] ?? '',
        taskNameEn: taskNameEn[key.taskId] ?? '',
        hoursByDate: byDate,
      );
    }).toList();

    // Stable, readable ordering: by project name, then task name.
    rows.sort((a, b) {
      final p = a.projectNameEn.toLowerCase().compareTo(b.projectNameEn.toLowerCase());
      if (p != 0) return p;
      return a.taskNameEn.toLowerCase().compareTo(b.taskNameEn.toLowerCase());
    });

    return ReportData(period: period, rows: rows);
  }
}
