import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/locked_period.dart';

/// Remembers which reporting periods have already been reported to a
/// consulting office, so they can be protected against later edits.
class PeriodLockRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<List<LockedPeriod>> getAll() async {
    final db = await _db;
    final rows = await db.query('locked_periods', orderBy: 'start_date DESC');
    return rows.map(LockedPeriod.fromMap).toList();
  }

  Future<bool> isDateLocked(DateTime date) async {
    final db = await _db;
    final rows = await db.query(
      'locked_periods',
      where: 'start_date <= ? AND end_date >= ?',
      whereArgs: [_iso(date), _iso(date)],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// The locked period containing [date], or null when the date is free.
  Future<LockedPeriod?> findForDate(DateTime date) async {
    final db = await _db;
    final rows = await db.query(
      'locked_periods',
      where: 'start_date <= ? AND end_date >= ?',
      whereArgs: [_iso(date), _iso(date)],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LockedPeriod.fromMap(rows.first);
  }

  /// Locks [start]..[end]. Locking the same period twice is harmless.
  Future<void> lock(DateTime start, DateTime end) async {
    final db = await _db;
    await db.insert(
      'locked_periods',
      {
        'start_date': _iso(start),
        'end_date': _iso(end),
        'locked_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Unlocks a period again. Deliberately explicit and separate from [lock],
  /// so reopening a submitted period is never accidental.
  Future<void> unlock(DateTime start, DateTime end) async {
    final db = await _db;
    await db.delete(
      'locked_periods',
      where: 'start_date = ? AND end_date = ?',
      whereArgs: [_iso(start), _iso(end)],
    );
  }

  Future<bool> isRangeLocked(DateTime start, DateTime end) async {
    final db = await _db;
    final rows = await db.query(
      'locked_periods',
      where: 'start_date = ? AND end_date = ?',
      whereArgs: [_iso(start), _iso(end)],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
}
