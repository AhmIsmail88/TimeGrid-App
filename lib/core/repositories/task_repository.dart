import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/task.dart';

class TaskRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<TimeTask>> getAll({bool includeArchived = true}) async {
    final db = await _db;
    final rows = await db.query(
      'tasks',
      where: includeArchived ? null : 'is_archived = 0',
      orderBy: 'name_en COLLATE NOCASE ASC, name_ar COLLATE NOCASE ASC',
    );
    return rows.map(TimeTask.fromMap).toList();
  }

  /// Tasks used at least once within [projectId], most-recently-used
  /// first — used to sort the task picker so tasks already used on
  /// this project surface first (PRD §7.3), without excluding tasks
  /// used elsewhere.
  Future<List<TimeTask>> getRecentlyUsedForProject(int projectId) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT t.*, MAX(w.work_date) as last_used
      FROM tasks t
      JOIN work_logs w ON w.task_id = t.id
      WHERE w.project_id = ? AND t.is_archived = 0
      GROUP BY t.id
      ORDER BY last_used DESC
    ''', [projectId]);
    return rows.map(TimeTask.fromMap).toList();
  }

  Future<TimeTask?> getById(int id) async {
    final db = await _db;
    final rows = await db.query('tasks', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return TimeTask.fromMap(rows.first);
  }

  Future<int> insert(TimeTask task) async {
    final db = await _db;
    return db.insert('tasks', task.toMap()..remove('id'));
  }

  Future<void> update(TimeTask task) async {
    final db = await _db;
    await db.update('tasks', task.toMap(),
        where: 'id = ?', whereArgs: [task.id]);
  }

  Future<void> setArchived(int id, bool archived) async {
    final db = await _db;
    await db.update(
      'tasks',
      {
        'is_archived': archived ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<bool> deleteIfUnused(int id) async {
    final db = await _db;
    final count = Sqflite.firstIntValue(await db
        .rawQuery('SELECT COUNT(*) FROM work_logs WHERE task_id = ?', [id]));
    if ((count ?? 0) > 0) return false;
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
    return true;
  }
}
