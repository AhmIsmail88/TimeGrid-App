import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/app_settings.dart';

class SettingsRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<AppSettings> load() async {
    final db = await _db;
    final rows = await db.query('settings');
    final map = <String, String>{
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
    return AppSettings.fromKeyValueMap(map);
  }

  Future<void> save(AppSettings settings) async {
    final db = await _db;
    final batch = db.batch();
    settings.toKeyValueMap().forEach((key, value) {
      batch.insert(
        'settings',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    await batch.commit(noResult: true);
  }
}
