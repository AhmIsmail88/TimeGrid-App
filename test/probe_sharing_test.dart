import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timegrid/core/services/report_sharing.dart';

/// The platform side of the sharing channel (`MainActivity.kt`) answers with
/// `opened`, `no_app` or `error`. This test pins the Dart side's contract for
/// the case that matters most: when there is no platform implementation at
/// all (older device code, tests, desktop), the caller must get `noApp` so it
/// falls back to the system share sheet instead of doing nothing.
void main() {
  testWidgets('a channel with no implementation reports noApp, not an error',
      (tester) async {
    // In a widget test an unhandled platform channel call never answers, so
    // the platform side is mocked explicitly: a handler that answers with
    // nothing is exactly what "no implementation" looks like.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.example.timegrid/sharing'),
      (call) async => null,
    );

    final gmail = await const ReportSharer().shareViaGmail(
      to: 'a@b.com',
      subject: 'Time sheet from (21/09/2026) to (20/10/2026)',
      body: 'body',
      filePath: '/tmp/TimeGrid_Timesheet.pdf',
    );
    expect(gmail, ShareOutcome.noApp);

    final whatsapp = await const ReportSharer().shareViaWhatsApp(
      text: 'Time sheet from 21/09/2026 to 20/10/2026',
      filePath: '/tmp/TimeGrid_Timesheet.pdf',
    );
    expect(whatsapp, ShareOutcome.noApp);
  });

  testWidgets('a platform-reported error reaches the caller as an error',
      (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.example.timegrid/sharing'),
      (call) async => 'error',
    );

    final gmail = await const ReportSharer().shareViaGmail(
      to: 'a@b.com',
      subject: 's',
      body: 'b',
      filePath: '/tmp/missing.pdf',
    );
    expect(gmail, ShareOutcome.error);
  });
}
