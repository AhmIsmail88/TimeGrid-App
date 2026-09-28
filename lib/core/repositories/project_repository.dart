import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/project.dart';

class ProjectRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  /// Projects, newest-name first. Pass [officeId] to get only the projects
  /// that belong to one consulting office — that is what keeps the entry
  /// form's project list scoped instead of showing every project.
  Future<List<Project>> getAll({
    bool includeArchived = true,
    int? officeId,
  }) async {
    final db = await _db;
    final where = <String>[];
    final args = <Object?>[];
    if (!includeArchived) where.add('is_archived = 0');
    if (officeId != null) {
      where.add('office_id = ?');
      args.add(officeId);
    }

    final rows = await db.query(
      'projects',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'name_en COLLATE NOCASE ASC, name_ar COLLATE NOCASE ASC',
    );
    return rows.map(Project.fromMap).toList();
  }

  Future<Project?> getById(int id) async {
    final db = await _db;
    final rows = await db.query('projects', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Project.fromMap(rows.first);
  }

  Future<int> insert(Project project) async {
    final db = await _db;
    return db.insert('projects', project.toMap()..remove('id'));
  }

  Future<void> update(Project project) async {
    final db = await _db;
    await db.update('projects', project.toMap(),
        where: 'id = ?', whereArgs: [project.id]);
  }

  Future<void> setArchived(int id, bool archived) async {
    final db = await _db;
    await db.update(
      'projects',
      {
        'is_archived': archived ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Hard-delete is only allowed when no work logs reference this
  /// project (PRD A7.7 / A10.5). Returns false (and does nothing) if
  /// the project has history — caller should archive instead.
  Future<bool> deleteIfUnused(int id) async {
    final db = await _db;
    final count = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM work_logs WHERE project_id = ?', [id]));
    if ((count ?? 0) > 0) return false;
    await db.delete('projects', where: 'id = ?', whereArgs: [id]);
    return true;
  }

  Future<double> totalHoursForProject(int projectId,
      {DateTime? start, DateTime? end}) async {
    final db = await _db;
    final where = StringBuffer('project_id = ?');
    final args = <Object?>[projectId];
    if (start != null && end != null) {
      where.write(' AND work_date BETWEEN ? AND ?');
      args.add(_iso(start));
      args.add(_iso(end));
    }
    final rows = await db.rawQuery(
        'SELECT COALESCE(SUM(hours), 0) as total FROM work_logs WHERE $where',
        args);
    return (rows.first['total'] as num).toDouble();
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
