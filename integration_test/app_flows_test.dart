import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:timegrid/core/database/app_database.dart';
import 'package:timegrid/core/models/reporting_period.dart';
import 'package:timegrid/core/models/project.dart';
import 'package:timegrid/core/repositories/backup_repository.dart';
import 'package:timegrid/core/repositories/period_lock_repository.dart';
import 'package:timegrid/core/repositories/project_repository.dart';
import 'package:timegrid/core/security/app_lock.dart';
import 'package:timegrid/features/reports/data/pdf_timesheet_exporter.dart';
import 'package:timegrid/features/reports/domain/report_calculator.dart';

/// Runs **on the phone**, not in the host test runner.
///
/// The printable timesheet is produced by handing HTML to the platform's own
/// web engine, so whether Arabic comes out shaped correctly can only be
/// answered here. The generated PDF is written to the app's documents
/// directory so it can be pulled off the device and inspected.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const labels = TimesheetLabels(
    title: 'تقرير ساعات العمل',
    number: 'رقم',
    task: 'المهمة',
    project: 'المشروع',
    total: 'الإجمالي',
    grandTotal: 'إجمالي الساعات',
    employee: 'اسم الموظف',
    period: 'الفترة',
    generated: 'تاريخ الإصدار',
    noEntries: 'لا توجد سجلات لهذه الفترة',
  );

  ReportData arabicSample() => ReportData(
        period: ReportingPeriod(
          start: DateTime(2026, 8, 21),
          end: DateTime(2026, 9, 20),
        ),
        rows: [
          ReportRow(
            projectId: 1,
            taskId: 1,
            projectNameAr: 'كفر ابو زهرة',
            projectNameEn: '',
            taskNameAr: 'مراجعة رسومات غرف خط السيب',
            taskNameEn: '',
            hoursByDate: const {'2026-08-23': 3.0, '2026-09-20': 0.5},
          ),
          ReportRow(
            projectId: 2,
            taskId: 2,
            projectNameAr: 'الجبل الأصفر',
            projectNameEn: '',
            taskNameAr: 'تعديل مقايسة أعمال ال SAND CLASSIFIER',
            taskNameEn: '',
            hoursByDate: const {'2026-09-01': 2.0},
          ),
        ],
      );

  testWidgets('the timesheet renders to a real PDF on this device',
      (tester) async {
    final bytes = await const PdfTimesheetExporter().buildPdf(
      data: arabicSample(),
      labels: labels,
      officeName: 'مكتب الاستشاري',
      employeeName: 'أحمد',
      periodText: '21 أغسطس 2026 - 20 سبتمبر 2026',
      generatedAt: DateTime(2026, 9, 28),
    );

    expect(bytes, isNotNull,
        reason: 'the platform web engine returned no PDF at all');
    expect(bytes!.length, greaterThan(2000),
        reason: 'a rendered page should be more than a stub');
    // "%PDF"
    expect(bytes.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]);

    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'integration_test_timesheet.pdf'));
    await file.writeAsBytes(bytes, flush: true);
    expect(await file.exists(), isTrue);

    // ignore: avoid_print
    print('PDF written: ${file.path} (${bytes.length} bytes)');
    // The integration-test runner uninstalls the app afterwards, which takes
    // the file with it, so hand the bytes back over stdout as well.
    // ignore: avoid_print
    print('PDF_BASE64_START');
    // ignore: avoid_print
    print(base64Encode(bytes));
    // ignore: avoid_print
    print('PDF_BASE64_END');
  });

  testWidgets('the app database opens and the lock table is present',
      (tester) async {
    final db = await AppDatabase.instance.database;
    final version =
        (await db.rawQuery('PRAGMA user_version')).first.values.first;
    expect(version, AppDatabase.schemaVersion);

    final tables = (await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table'"))
        .map((r) => r['name'] as String)
        .toList();
    expect(
        tables, containsAll(<String>['offices', 'projects', 'tasks', 'work_logs', 'locked_periods']));

    // The lock rules behave the same on the device as they do in tests.
    final locks = PeriodLockRepository();
    await locks.lock(DateTime(2026, 8, 21), DateTime(2026, 9, 20));
    expect(await locks.isDateLocked(DateTime(2026, 9, 1)), isTrue);
    expect(await locks.isDateLocked(DateTime(2026, 9, 21)), isFalse);
    await locks.unlock(DateTime(2026, 8, 21), DateTime(2026, 9, 20));
    expect(await locks.isDateLocked(DateTime(2026, 9, 1)), isFalse);

    await AppDatabase.instance.close();
  });

  testWidgets('the device says whether it can lock the app', (tester) async {
    // No prompt is shown: this only asks the platform what the phone supports,
    // which is what decides whether the lock setting is offered at all.
    final available = await LocalAuthAuthenticator().isAvailable();
    // ignore: avoid_print
    print('biometric/screen-lock available on this device: $available');
    expect(available, isA<bool>());
  });

  testWidgets('a backup can be written on this device', (tester) async {
    await ProjectRepository().insert(const Project(
      nameAr: 'مشروع نسخة',
      nameEn: '',
      createdAt: '2026-09-01T00:00:00.000',
      updatedAt: '2026-09-01T00:00:00.000',
    ));

    final file = await BackupRepository().createBackup();
    expect(await file.exists(), isTrue);
    expect(file.path, endsWith('.json'));

    final payload = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(payload['format'], 'timegrid_backup');
    expect(payload['projects'], isA<List<dynamic>>());
    expect((payload['projects'] as List), isNotEmpty);

    // ignore: avoid_print
    print('backup written: ${file.path} (${await file.length()} bytes)');
  });
}