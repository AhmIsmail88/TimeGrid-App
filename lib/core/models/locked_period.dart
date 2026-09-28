/// A reporting period whose timesheet has already been sent to a consulting
/// office. Locking it keeps later edits out of a file that has already been
/// submitted, which is what stops an accidental (or deliberate) change to
/// numbers somebody else has already seen.
class LockedPeriod {
  final DateTime start;
  final DateTime end;
  final String lockedAt;

  const LockedPeriod({
    required this.start,
    required this.end,
    required this.lockedAt,
  });

  bool contains(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }

  factory LockedPeriod.fromMap(Map<String, Object?> map) {
    return LockedPeriod(
      start: DateTime.parse(map['start_date'] as String),
      end: DateTime.parse(map['end_date'] as String),
      lockedAt: map['locked_at'] as String? ?? '',
    );
  }
}
