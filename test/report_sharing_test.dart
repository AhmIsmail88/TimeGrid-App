import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timegrid/app/localization/gen/app_localizations.dart';
import 'package:timegrid/core/models/office.dart';
import 'package:timegrid/core/models/reporting_period.dart';
import 'package:timegrid/core/providers/providers.dart';
import 'package:timegrid/core/repositories/office_repository.dart';
import 'package:timegrid/core/services/file_sharer.dart';
import 'package:timegrid/core/services/report_sharing.dart';
import 'package:timegrid/features/offices/presentation/offices_screen.dart';
import 'package:timegrid/features/reports/presentation/report_share_sheet.dart';

/// The share sheet that asks where a produced timesheet should go, and the
/// email/message it builds. The platform channel is never available in
/// widget tests, so every direct attempt falls back to the system share
/// sheet — which is exactly the behaviour a missing WhatsApp/Gmail should
/// produce.
void main() {
  final period = ReportingPeriod(
    start: DateTime(2026, 9, 21),
    end: DateTime(2026, 10, 20),
  );

  group('ReportEmail', () {
    test('subject matches the format the office recognises', () {
      expect(ReportEmail.subject(period),
          'Time sheet from (21/09/2026) to (20/10/2026)');
    });

    test('single-digit days and months keep leading zeros', () {
      final p = ReportingPeriod(
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 2, 9),
      );
      expect(ReportEmail.subject(p), 'Time sheet from (01/01/2026) to (09/02/2026)');
    });

    test('body greets the office and signs with the employee name', () {
      final body = ReportEmail.body(
        officeName: 'Seeb office',
        period: period,
        employeeName: 'Ahmed',
      );

      expect(body, startsWith('Dear Seeb office,'));
      expect(body, contains('from 21/09/2026 to 20/10/2026'));
      expect(body, contains('attached my timesheet'));
      expect(body, endsWith('Ahmed'));
    });

    test('body falls back politely without an office or employee name', () {
      final body = ReportEmail.body(
        officeName: '',
        period: period,
        employeeName: '',
      );

      expect(body, startsWith('Dear Sir or Madam,'));
      expect(body, isNot(contains('null')));
      expect(body, endsWith('Best regards,'));
    });

    test('whatsapp message is one line with the period', () {
      expect(ReportEmail.whatsappText(period),
          'Time sheet from 21/09/2026 to 20/10/2026 \u2014 attached.');
    });
  });

  group('ReportShareSheet', () {
    Office office({String email = '', String phone = '', String whatsapp = ''}) =>
        Office(
          id: 1,
          nameAr: 'مكتب السيب',
          nameEn: 'Seeb office',
          email: email,
          phone: phone,
          whatsapp: whatsapp,
          createdAt: '2026-09-01T00:00:00.000',
          updatedAt: '2026-09-01T00:00:00.000',
        );

    late _RecordingFileSharer sharer;

    Widget harness({
      required String filePath,
      required Office? office,
      _RecordingFileSharer? withSharer,
    }) {
      final recorder = withSharer ?? _RecordingFileSharer();
      sharer = recorder;
      return ProviderScope(
        overrides: [
          fileSharerProvider.overrideWithValue(recorder),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showReportShareSheet(
                    context,
                    filePath: filePath,
                    period: period,
                    office: office,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
    }

    setUp(() {
      sharer = _RecordingFileSharer();
    });

    testWidgets('offers WhatsApp, Gmail and other apps', (tester) async {
      await tester.pumpWidget(harness(
        filePath: '/tmp/TimeGrid_Timesheet.pdf',
        office: office(email: 'pm@example.com', whatsapp: '100'),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('WhatsApp'), findsOneWidget);
      expect(find.text('Gmail'), findsOneWidget);
      expect(find.text('Other apps'), findsOneWidget);
      // The office's contacts are shown as context inside the sheet.
      expect(find.text('pm@example.com'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
    });

    testWidgets('Gmail falls back to the system share sheet when the app is '
        'missing, and still sends the file', (tester) async {
      // In a widget test the platform channel never answers on its own, so
      // the platform side is mocked as "Gmail is not installed" - the
      // fallback is what this test verifies.
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.example.timegrid/sharing'),
        (call) async => 'no_app',
      );
      await tester.pumpWidget(harness(
        filePath: '/tmp/TimeGrid_Timesheet.pdf',
        office: office(email: 'pm@example.com'),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Gmail'));
      await tester.pumpAndSettle();

      expect(sharer.paths, ['/tmp/TimeGrid_Timesheet.pdf']);
    });

    testWidgets('Gmail is refused with a hint when the office has no email',
        (tester) async {
      await tester.pumpWidget(harness(
        filePath: '/tmp/TimeGrid_Timesheet.pdf',
        office: office(phone: '100'),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Gmail'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(sharer.paths, isEmpty);
    });

    testWidgets('WhatsApp sends the file; without a number it still opens',
        (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.example.timegrid/sharing'),
        (call) async => 'no_app',
      );
      await tester.pumpWidget(harness(
        filePath: '/tmp/TimeGrid_Timesheet.pdf',
        office: null,
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('WhatsApp'));
      await tester.pumpAndSettle();

      expect(sharer.paths, ['/tmp/TimeGrid_Timesheet.pdf']);
    });

    testWidgets('Other apps always uses the system share sheet',
        (tester) async {
      await tester.pumpWidget(harness(
        filePath: '/tmp/TimeGrid_Timesheet.pdf',
        office: office(email: 'pm@example.com'),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Other apps'));
      await tester.pumpAndSettle();

      expect(sharer.paths, ['/tmp/TimeGrid_Timesheet.pdf']);
    });
  });

  group('office form contact details', () {
    late _FakeOfficeRepository offices;

    Widget harness() {
      offices = _FakeOfficeRepository();
      return ProviderScope(
        overrides: [
          officeRepositoryProvider.overrideWithValue(offices),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: OfficesScreen(),
        ),
      );
    }

    testWidgets('saving an office stores its contacts and mirrors the phone '
        'number into WhatsApp', (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), 'مكتب السيب');
      await tester.enterText(fields.at(1), 'Seeb office');
      await tester.enterText(fields.at(2), 'pm@example.com');
      // Typing the phone number leaves the WhatsApp field mirroring it.
      await tester.enterText(fields.at(3), '+20 100 000 0000');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(offices.inserted, hasLength(1));
      expect(offices.inserted.single.nameEn, 'Seeb office');
      expect(offices.inserted.single.email, 'pm@example.com');
      expect(offices.inserted.single.phone, '+20 100 000 0000');
      expect(offices.inserted.single.whatsapp, '+20 100 000 0000');
    });

    testWidgets('an invalid email keeps the dialog open and saves nothing',
        (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), 'مكتب');
      await tester.enterText(fields.at(1), 'Office');
      await tester.enterText(fields.at(2), 'not-an-email');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget,
          reason: 'the dialog is still open');
      expect(offices.inserted, isEmpty);
    });
  });
}

class _RecordingFileSharer implements FileSharer {
  final List<String> paths = [];

  @override
  Future<void> shareFile({required String path, String? subject}) async {
    paths.add(path);
  }
}

class _FakeOfficeRepository extends OfficeRepository {
  final List<Office> inserted = <Office>[];
  final List<Office> updated = <Office>[];

  @override
  Future<List<Office>> getAll({bool includeArchived = true}) async =>
      const <Office>[];

  @override
  Future<int> insert(Office office) async {
    inserted.add(office);
    return 1;
  }

  @override
  Future<void> update(Office office) async {
    updated.add(office);
  }
}
