/// An inclusive date range representing one reporting period, e.g.
/// 21 May .. 20 Jun. Both [start] and [end] are inclusive.
class ReportingPeriod {
  final DateTime start;
  final DateTime end;

  const ReportingPeriod({required this.start, required this.end});

  bool contains(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }

  /// All calendar dates in the period, inclusive, in order.
  List<DateTime> get allDates {
    final days = <DateTime>[];
    var cursor = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
    while (!cursor.isAfter(last)) {
      days.add(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }
    return days;
  }

  int get dayCount => allDates.length;
}
