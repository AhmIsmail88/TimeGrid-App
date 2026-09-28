// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// One-off inspection helper for a legacy TimeGrid database that was pulled
/// off a device with `adb exec-out run-as`. It only runs when
/// TIMEGRID_LEGACY_DB points at such a file, so it stays out of the way of
/// the normal suite.
void main() {
  final path = Platform.environment['TIMEGRID_LEGACY_DB'] ?? '';

  test('inspect a legacy database', () async {
    final file = File(path);
    if (path.isEmpty || !file.existsSync()) {
      markTestSkipped('TIMEGRID_LEGACY_DB not set');
      return;
    }

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Open a throwaway copy read-write so SQLite can recover the write-ahead
    // log into the main file without touching anything else.
    final work = Directory.systemTemp.createTempSync('legacy_db');
    final copy = File('${work.path}/legacy.db');
    file.copySync(copy.path);
    for (final suffix in ['-wal', '-shm']) {
      final side = File('$path$suffix');
      if (side.existsSync()) side.copySync('${copy.path}$suffix');
    }

    final db = await databaseFactory.openDatabase(copy.path);
    await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');

    final objects = await db.rawQuery(
        "SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type DESC, name");

    print('=== SCHEMA ===');
    for (final row in objects) {
      print('--- ${row['type']}: ${row['name']}');
      print(row['sql']);
    }

    print('=== ROW COUNTS ===');
    for (final row in objects.where((r) => r['type'] == 'table')) {
      final name = row['name'];
      final count = await db.rawQuery('SELECT COUNT(*) AS c FROM "$name"');
      print('$name :: ${count.first['c']}');
    }

    print('=== SAMPLE ROWS ===');
    for (final row in objects.where((r) => r['type'] == 'table')) {
      final name = row['name'];
      final rows = await db.rawQuery('SELECT * FROM "$name" LIMIT 3');
      print('--- $name');
      for (final r in rows) {
        print(r);
      }
    }

    await db.close();
  });
}
