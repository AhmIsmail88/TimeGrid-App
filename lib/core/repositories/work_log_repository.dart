import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/work_log.dart';

class WorkLogFilter {
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final int? projectId;
  final int? taskId;
  final String? searchText;
  final bool newestFirst;

  /// Optional hard cap on the number of returned rows, applied in SQL so
  /// "recent entries" never has to load the entire table first.
  final int? limit;

  const WorkLogFilter({
    this.periodStart,
    this.periodEnd,
    this.projectId,
    this.taskId,
    this.searchText,
    this.newestFirst = true,
    this.limit,
  });
}

class WorkLogRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Escapes the LIKE wildcards so a literal `%` or `_` typed by the
  /// user matches itself instead of acting as a wildcard.
  String _likePattern(String raw) {
    final escaped = raw
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    return '%$escaped%';
  }

  Future<int> insert(WorkLog log) async {
    final db = await _db;
    return db.insert('work_logs', log.toMap()..remove('id'));
  }

  Future<void> update(WorkLog log) async {
    final db = await _db;
    await db.update('work_logs', log.toMap(),
        where: 'id = ?', whereArgs: [log.id]);
  }

  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete('work_logs', where: 'id = ?', whereArgs: [id]);
  }

  /// Re-inserts a row that was just deleted, keeping its original id, so
  /// the "Undo" action puts back exactly the entry the user removed
  /// instead of a look-alike with a new identity.
  Future<void> restore(WorkLog log) async {
    final db = await _db;
    await db.insert('work_logs', log.toMap());
  }

  Future<WorkLog?> getById(int id) async {
    final db = await _db;
    final rows = await db.query('work_logs', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return WorkLog.fromMap(rows.first);
  }

  /// Joined rows for the Work Logs list screen (project/task names
  /// resolved server-side so the UI doesn't N+1 query).
  Future<List<WorkLogView>> getFiltered(WorkLogFilter filter) async {
    final db = await _db;
    final where = <String>[];
    final args = <Object?>[];

    if (filter.periodStart != null && filter.periodEnd != null) {
      where.add('w.work_date BETWEEN ? AND ?');
      args.add(_iso(filter.periodStart!));
      args.add(_iso(filter.periodEnd!));
    }
    if (filter.projectId != null) {
      where.add('w.project_id = ?');
      args.add(filter.projectId);
    }
    if (filter.taskId != null) {
      where.add('w.task_id = ?');
      args.add(filter.taskId);
    }
    if (filter.searchText != null && filter.searchText!.trim().isNotEmpty) {
      where.add(
          r"(p.name_ar LIKE ? ESCAPE '\' OR p.name_en LIKE ? ESCAPE '\' OR t.name_ar LIKE ? ESCAPE '\' OR t.name_en LIKE ? ESCAPE '\')");
      final like = _likePattern(filter.searchText!.trim());
      args.addAll([like, like, like, like]);
    }

    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final orderSql =
        filter.newestFirst ? 'w.work_date DESC, w.id DESC' : 'w.work_date ASC, w.id ASC';
    final limitSql = filter.limit != null ? 'LIMIT ?' : '';
    if (filter.limit != null) args.add(filter.limit);

    final rows = await db.rawQuery('''
      SELECT w.*, p.name_ar as p_name_ar, p.name_en as p_name_en,
             t.name_ar as t_name_ar, t.name_en as t_name_en
      FROM work_logs w
      JOIN projects p ON p.id = w.project_id
      JOIN tasks t ON t.id = w.task_id
      $whereSql
      ORDER BY $orderSql
      $limitSql
    ''', args);

    return rows.map((row) {
      return WorkLogView(
        log: WorkLog.fromMap(row),
        projectNameAr: row['p_name_ar'] as String? ?? '',
        projectNameEn: row['p_name_en'] as String? ?? '',
        taskNameAr: row['t_name_ar'] as String? ?? '',
        taskNameEn: row['t_name_en'] as String? ?? '',
      );
    }).toList();
  }

  Future<List<WorkLog>> getForPeriod(DateTime start, DateTime end) async {
    final db = await _db;
    final rows = await db.query(
      'work_logs',
      where: 'work_date BETWEEN ? AND ?',
      whereArgs: [_iso(start), _iso(end)],
    );
    return rows.map(WorkLog.fromMap).toList();
  }

  /// Logs in the period whose project belongs to [officeId]. This is what
  /// makes a report about one consulting office instead of a global dump.
  Future<List<WorkLog>> getForPeriodForOffice(
      DateTime start, DateTime end, int officeId) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT w.* FROM work_logs w
      JOIN projects p ON p.id = w.project_id
      WHERE w.work_date BETWEEN ? AND ? AND p.office_id = ?
      ORDER BY w.work_date ASC, w.id ASC
    ''', [_iso(start), _iso(end), officeId]);
    return rows.map(WorkLog.fromMap).toList();
  }

  Future<double> totalHoursForPeriod(DateTime start, DateTime end) async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(hours), 0) as total FROM work_logs WHERE work_date BETWEEN ? AND ?',
      [_iso(start), _iso(end)],
    );
    return (rows.first['total'] as num).toDouble();
  }

  Future<int> countForPeriod(DateTime start, DateTime end) async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) as c FROM work_logs WHERE work_date BETWEEN ? AND ?',
      [_iso(start), _iso(end)],
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<List<WorkLogView>> getRecent({int limit = 5}) async {
    return getFiltered(WorkLogFilter(newestFirst: true, limit: limit));
  }
}
