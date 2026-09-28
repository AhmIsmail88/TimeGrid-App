import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

/// Exports/imports the full local data set (projects, tasks, work logs,
/// settings) as a single structured JSON file, so a backup can never
/// contain a partial table or orphaned rows (PRD A11).
class BackupRepository {
  static const int backupFormatVersion = 1;

  Future<Database> get _db => AppDatabase.instance.database;

  /// Writes a complete snapshot into the app documents directory.
  ///
  /// [prefix] distinguishes ordinary exports from the automatic safety
  /// copies taken before something destructive happens.
  Future<File> createBackup({String prefix = 'TimeGrid_Backup'}) async {
    final db = await _db;

    final projects = await db.query('projects');
    final tasks = await db.query('tasks');
    final workLogs = await db.query('work_logs');
    final settings = await db.query('settings');

    final payload = {
      'format': 'timegrid_backup',
      'version': backupFormatVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'projects': projects,
      'tasks': tasks,
      'work_logs': workLogs,
      'settings': settings,
    };

    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = File(p.join(dir.path, '${prefix}_$timestamp.json'));
    await file.writeAsString(jsonEncode(payload), flush: true);
    return file;
  }

  /// Validates the file structure before touching the live database.
  /// Throws a [FormatException] with a user-facing-safe code if the file
  /// isn't a recognizable TimeGrid backup, or if it was produced by a
  /// NEWER version of the app than this build can be trusted to read.
  Future<Map<String, dynamic>> _readAndValidate(File file) async {
    final content = await file.readAsString();
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('invalid_backup');
    }
    if (decoded['format'] != 'timegrid_backup' ||
        decoded['projects'] is! List ||
        decoded['tasks'] is! List ||
        decoded['work_logs'] is! List ||
        decoded['settings'] is! List) {
      throw const FormatException('invalid_backup');
    }
    final version = decoded['version'];
    if (version is int && version > backupFormatVersion) {
      throw const FormatException('backup_from_newer_version');
    }
    return decoded;
  }

  /// Restores from [file], replacing all current data.
  ///
  /// Safety guarantees:
  ///  * The file is validated *before* anything is touched.
  ///  * A complete snapshot of the CURRENT data is written out first, so
  ///    an unwanted restore can always be undone. It is returned to the
  ///    caller so the UI can tell the user where it went.
  ///  * The replacement runs inside a single transaction, so a failure
  ///    leaves the existing database untouched (PRD A11).
  Future<File> restoreBackup(File file) async {
    final data = await _readAndValidate(file);
    final db = await _db;

    final safetyCopy =
        await createBackup(prefix: 'TimeGrid_PreRestore_Backup');

    await db.transaction((txn) async {
      await txn.delete('work_logs');
      await txn.delete('tasks');
      await txn.delete('projects');
      await txn.delete('settings');

      final batch = txn.batch();
      for (final row in (data['projects'] as List)) {
        batch.insert('projects', Map<String, Object?>.from(row));
      }
      for (final row in (data['tasks'] as List)) {
        batch.insert('tasks', Map<String, Object?>.from(row));
      }
      for (final row in (data['work_logs'] as List)) {
        batch.insert('work_logs', Map<String, Object?>.from(row));
      }
      for (final row in (data['settings'] as List)) {
        batch.insert('settings', Map<String, Object?>.from(row));
      }
      await batch.commit(noResult: true);
    });

    return safetyCopy;
  }
}
