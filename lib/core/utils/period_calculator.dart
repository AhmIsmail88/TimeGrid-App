import '../models/reporting_period.dart';

/// Computes reporting periods from a configurable "cycle start day"
/// (1..28), handling short months by clamping to the last day that
/// actually exists in that month (see PRD §6.3).
class PeriodCalculator {
  final int startDay;

  const PeriodCalculator(this.startDay)
      : assert(startDay >= 1 && startDay <= 28,
            'startDay must be between 1 and 28 to avoid ambiguity around February');

  int _lastDayOfMonth(int year, int month) {
    final firstOfNextMonth = (month == 12)
        ? DateTime(year + 1, 1, 1)
        : DateTime(year, month + 1, 1);
    return firstOfNextMonth.subtract(const Duration(days: 1)).day;
  }

  DateTime _clampedStart(int year, int month) {
    final lastDay = _lastDayOfMonth(year, month);
    final day = startDay > lastDay ? lastDay : startDay;
    return DateTime(year, month, day);
  }

  /// Returns the period that contains [date].
  ReportingPeriod periodContaining(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    // Candidate period starting in the same month as `d`.
    var periodStart = _clampedStart(d.year, d.month);

    if (d.isBefore(periodStart)) {
      // `d` falls before this month's start day -> belongs to the
      // period that started the previous month.
      final prevMonth = d.month == 1 ? 12 : d.month - 1;
      final prevYear = d.month == 1 ? d.year - 1 : d.year;
      periodStart = _clampedStart(prevYear, prevMonth);
    }

    final nextMonth = periodStart.month == 12 ? 1 : periodStart.month + 1;
    final nextYear =
        periodStart.month == 12 ? periodStart.year + 1 : periodStart.year;
    final nextStart = _clampedStart(nextYear, nextMonth);
    final periodEnd = nextStart.subtract(const Duration(days: 1));

    return ReportingPeriod(start: periodStart, end: periodEnd);
  }

  /// Returns the current period (containing today).
  ReportingPeriod currentPeriod() => periodContaining(DateTime.now());

  /// Returns the period immediately before [period].
  ReportingPeriod previousPeriod(ReportingPeriod period) {
    final dayBeforeStart = period.start.subtract(const Duration(days: 1));
    return periodContaining(dayBeforeStart);
  }

  /// Returns the period immediately after [period].
  ReportingPeriod nextPeriod(ReportingPeriod period) {
    final dayAfterEnd = period.end.add(const Duration(days: 1));
    return periodContaining(dayAfterEnd);
  }
}
