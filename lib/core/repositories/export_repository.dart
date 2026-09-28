import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/export_record.dart';

/// Keeps the list of timesheets that have been produced, newest first.
class ExportRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<int> record(ExportRecord record) async {
    final db = await _db;
    return db.insert('exports', record.toMap()..remove('id'));
  }

  Future<List<ExportRecord>> getRecent({int limit = 20}) async {
    final db = await _db;
    final rows = await db.query(
      'exports',
      orderBy: 'exported_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(ExportRecord.fromMap).toList();
  }

  /// True when this exact period has already been exported for this office,
  /// which is what the Reports screen uses to say "already sent".
  Future<bool> hasExported({
    required int? officeId,
    required DateTime start,
    required DateTime end,
  }) async {
    final db = await _db;
    String iso(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final rows = await db.query(
      'exports',
      where: 'period_start = ? AND period_end = ? AND '
          '(office_id = ? OR (office_id IS NULL AND ? IS NULL))',
      whereArgs: [iso(start), iso(end), officeId, officeId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> deleteAll() async {
    final db = await _db;
    await db.delete('exports');
  }
}
