import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// (WidgetRef comes from flutter_riverpod as well; imported implicitly)

import '../models/app_settings.dart';
import '../models/reporting_period.dart';
import '../models/work_log.dart';
import '../repositories/backup_repository.dart';
import '../repositories/office_repository.dart';
import '../repositories/export_repository.dart';
import '../repositories/period_lock_repository.dart';
import '../repositories/project_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/task_repository.dart';
import '../repositories/work_log_repository.dart';
import '../utils/period_calculator.dart';

// --- Repositories (stateless singletons) ---------------------------------

final officeRepositoryProvider = Provider((ref) => OfficeRepository());
final projectRepositoryProvider = Provider((ref) => ProjectRepository());
final taskRepositoryProvider = Provider((ref) => TaskRepository());
final workLogRepositoryProvider = Provider((ref) => WorkLogRepository());
final settingsRepositoryProvider = Provider((ref) => SettingsRepository());
final periodLockRepositoryProvider = Provider((ref) => PeriodLockRepository());
final exportRepositoryProvider = Provider((ref) => ExportRepository());
final backupRepositoryProvider = Provider((ref) => BackupRepository());

// --- Settings (drives locale, employee name, reporting cycle day) -------

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    return ref.read(settingsRepositoryProvider).load();
  }

  Future<void> updateSettings(AppSettings Function(AppSettings current) updater) async {
    final current = state.value ?? const AppSettings();
    final next = updater(current);
    await ref.read(settingsRepositoryProvider).save(next);
    state = AsyncData(next);
  }
}

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

// --- Reporting period calculator, derived from settings ------------------

final periodCalculatorProvider = Provider<PeriodCalculator>((ref) {
  final settings = ref.watch(settingsProvider).value;
  final startDay = settings?.reportingCycleStartDay ?? 1;
  return PeriodCalculator(startDay);
});

/// The period currently selected for viewing (Dashboard/Reports).
/// Defaults to "today's" period and can be moved by the user.
/// The consulting office a report is produced for. Null means "not chosen
/// yet"; exporting is blocked until the user picks one, because a global
/// timesheet is not what a consulting office asks for.
final reportOfficeProvider = StateProvider<int?>((ref) => null);

/// The reporting period shown on the Dashboard and used by Reports.
///
/// Settings load asynchronously, and until they arrive the calculator reports
/// a start day of 1 — which would show a calendar month even when the user
/// configured, say, the 21st. So the period is rebuilt from settings once they
/// load, and only then; once the user has moved the period by hand it is left
/// where they put it.
class SelectedPeriodNotifier extends Notifier<ReportingPeriod> {
  ReportingPeriod? _current;
  int? _appliedStartDay;
  bool _userMoved = false;

  @override
  ReportingPeriod build() {
    final startDay = ref.watch(periodCalculatorProvider).startDay;
    if (_current == null || (!_userMoved && _appliedStartDay != startDay)) {
      _appliedStartDay = startDay;
      _current = PeriodCalculator(startDay).currentPeriod();
    }
    return _current!;
  }

  /// Moves to another period, which then sticks even if settings change.
  void moveTo(ReportingPeriod period) {
    _userMoved = true;
    _current = period;
    state = period;
  }

  /// Back to the period containing today, following settings again.
  void resetToToday() {
    final calculator = ref.read(periodCalculatorProvider);
    _userMoved = false;
    _appliedStartDay = calculator.startDay;
    _current = calculator.currentPeriod();
    state = _current!;
  }
}

final selectedPeriodProvider =
    NotifierProvider<SelectedPeriodNotifier, ReportingPeriod>(
        SelectedPeriodNotifier.new);

// --- A bump counter other providers can watch to know "data changed" ----
// Incrementing this after any insert/update/delete/restore invalidates
// every dependent FutureProvider below, keeping totals in sync (PRD §5
// rule 8: edits/deletes must update all downstream totals).
final dataVersionProvider = StateProvider<int>((ref) => 0);

/// Call after any insert/update/delete/restore so every dependent
/// FutureProvider above re-fetches: `ref.bumpDataVersion();`
extension BumpDataVersionOnRef on Ref {
  void bumpDataVersion() => read(dataVersionProvider.notifier).state++;
}

extension BumpDataVersionOnWidgetRef on WidgetRef {
  void bumpDataVersion() => read(dataVersionProvider.notifier).state++;
}

// --- Derived data for the Dashboard ---------------------------------------

/// Timesheets that have been produced, newest first.
final exportHistoryProvider = FutureProvider((ref) {
  ref.watch(dataVersionProvider);
  return ref.read(exportRepositoryProvider).getRecent();
});

/// Periods that have already been reported to a consulting office.
final lockedPeriodsProvider = FutureProvider((ref) {
  ref.watch(dataVersionProvider);
  return ref.read(periodLockRepositoryProvider).getAll();
});

final officesProvider = FutureProvider((ref) {
  ref.watch(dataVersionProvider);
  return ref.read(officeRepositoryProvider).getAll();
});

final projectsProvider = FutureProvider((ref) {
  ref.watch(dataVersionProvider);
  return ref.read(projectRepositoryProvider).getAll();
});

final tasksProvider = FutureProvider((ref) {
  ref.watch(dataVersionProvider);
  return ref.read(taskRepositoryProvider).getAll();
});

/// The selected period's work logs, narrowed to the office being viewed.
///
/// Reports are always produced for one consulting office, so the Dashboard
/// uses the same scope: the totals on the home screen and the numbers in the
/// exported timesheet can never disagree.
final periodLogsProvider = FutureProvider<List<WorkLog>>((ref) async {
  ref.watch(dataVersionProvider);
  final period = ref.watch(selectedPeriodProvider);
  final officeId = ref.watch(reportOfficeProvider);
  final repository = ref.read(workLogRepositoryProvider);
  if (officeId == null) {
    return repository.getForPeriod(period.start, period.end);
  }
  return repository.getForPeriodForOffice(period.start, period.end, officeId);
});

final periodTotalHoursProvider = FutureProvider<double>((ref) async {
  final logs = await ref.watch(periodLogsProvider.future);
  return logs.fold<double>(0, (sum, log) => sum + log.hours);
});

final periodEntryCountProvider = FutureProvider<int>((ref) async {
  final logs = await ref.watch(periodLogsProvider.future);
  return logs.length;
});

final recentEntriesProvider = FutureProvider<List<WorkLogView>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.read(workLogRepositoryProvider).getRecent(limit: 5);
});

final workLogsForPeriodProvider = FutureProvider<List<WorkLog>>((ref) {
  return ref.watch(periodLogsProvider.future);
});

/// Hours per ISO date in the selected period, for the dashboard's day strip.
final periodDailyHoursProvider =
    FutureProvider<Map<String, double>>((ref) async {
  final logs = await ref.watch(periodLogsProvider.future);

  final byDate = <String, double>{};
  for (final log in logs) {
    byDate.update(log.workDate, (value) => value + log.hours,
        ifAbsent: () => log.hours);
  }
  return byDate;
});

/// A project and the hours logged against it in the selected period.
class ProjectHours {
  final String nameAr;
  final String nameEn;
  final double hours;

  const ProjectHours({
    required this.nameAr,
    required this.nameEn,
    required this.hours,
  });

  String displayName(String localeCode) {
    final ar = nameAr.trim();
    final en = nameEn.trim();
    if (localeCode == 'ar') return ar.isNotEmpty ? ar : en;
    return en.isNotEmpty ? en : ar;
  }
}

/// The three projects that took the most hours this period.
final periodTopProjectsProvider =
    FutureProvider<List<ProjectHours>>((ref) async {
  final logs = await ref.watch(periodLogsProvider.future);
  if (logs.isEmpty) return const <ProjectHours>[];

  final totals = <int, double>{};
  for (final log in logs) {
    totals.update(log.projectId, (value) => value + log.hours,
        ifAbsent: () => log.hours);
  }

  final projects = await ref.read(projectRepositoryProvider).getAll();
  final rows = projects
      .where((project) => totals.containsKey(project.id))
      .map((project) => ProjectHours(
            nameAr: project.nameAr,
            nameEn: project.nameEn,
            hours: totals[project.id]!,
          ))
      .toList()
    ..sort((a, b) => b.hours.compareTo(a.hours));

  return rows.take(3).toList();
});

final excelTemplateFileProvider = Provider<File?>((ref) {
  final settings = ref.watch(settingsProvider).value;
  final path = settings?.excelTemplatePath;
  if (path == null || path.isEmpty) return null;
  return File(path);
});
