import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/office.dart';

class OfficeRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<Office>> getAll({bool includeArchived = true}) async {
    final db = await _db;
    final rows = await db.query(
      'offices',
      where: includeArchived ? null : 'is_archived = 0',
      orderBy: 'name_en COLLATE NOCASE ASC, name_ar COLLATE NOCASE ASC',
    );
    return rows.map(Office.fromMap).toList();
  }

  Future<Office?> getById(int id) async {
    final db = await _db;
    final rows = await db.query('offices', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Office.fromMap(rows.first);
  }

  Future<int> insert(Office office) async {
    final db = await _db;
    return db.insert('offices', office.toMap()..remove('id'));
  }

  Future<void> update(Office office) async {
    final db = await _db;
    await db.update('offices', office.toMap(),
        where: 'id = ?', whereArgs: [office.id]);
  }

  Future<void> setArchived(int id, bool archived) async {
    final db = await _db;
    await db.update(
      'offices',
      {
        'is_archived': archived ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// How many projects are attached to this office, archived ones included.
  Future<int> projectCount(int officeId) async {
    final db = await _db;
    final rows = await db.rawQuery(
        'SELECT COUNT(*) FROM projects WHERE office_id = ?', [officeId]);
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// Hard-delete is only allowed while no project points at this office.
  /// Returns false (and does nothing) when the office is in use — the caller
  /// should archive it instead, so existing reports keep their meaning.
  Future<bool> deleteIfUnused(int id) async {
    if (await projectCount(id) > 0) return false;
    final db = await _db;
    await db.delete('offices', where: 'id = ?', whereArgs: [id]);
    return true;
  }
}
