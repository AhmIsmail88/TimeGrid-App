import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/reporting_period.dart';

/// What a direct share attempt ended with.
enum ShareOutcome {
  /// The target app was launched (or a chooser was offered).
  opened,

  /// The target app is not installed / the channel is unavailable. The
  /// caller should fall back to the system share sheet.
  noApp,

  /// The platform call failed for another reason.
  error,
}

/// Sends a produced timesheet straight to a target app.
///
/// Pre-filling Gmail's recipient and opening WhatsApp with a file need
/// Android intent details the generic share sheet does not expose, so this
/// goes through a small platform channel implemented in `MainActivity.kt`.
class ReportSharer {
  const ReportSharer();

  static const MethodChannel _channel =
      MethodChannel('com.example.timegrid/sharing');

  Future<ShareOutcome> shareViaGmail({
    required String to,
    required String subject,
    required String body,
    required String filePath,
  }) async {
    try {
      final result = await _channel.invokeMethod<String>('shareToGmail', {
        'to': to,
        'subject': subject,
        'body': body,
        'filePath': filePath,
      });
      return _outcomeOf(result);
    } on MissingPluginException {
      // No channel on this runtime (tests, non-Android): the caller falls
      // back to the system share sheet, which is the right answer here too.
      return ShareOutcome.noApp;
    } on PlatformException {
      return ShareOutcome.error;
    }
  }

  Future<ShareOutcome> shareViaWhatsApp({
    required String text,
    required String filePath,
  }) async {
    try {
      final result = await _channel.invokeMethod<String>('shareToWhatsApp', {
        'text': text,
        'filePath': filePath,
      });
      return _outcomeOf(result);
    } on MissingPluginException {
      return ShareOutcome.noApp;
    } on PlatformException {
      return ShareOutcome.error;
    }
  }
}

final reportSharerProvider =
    Provider<ReportSharer>((ref) => const ReportSharer());

/// Maps the platform layer's four possible answers. A missing handler (no
/// result at all) counts as "no app", which is what routes the caller to the
/// system share sheet.
ShareOutcome _outcomeOf(String? result) {
  switch (result) {
    case 'opened':
      return ShareOutcome.opened;
    case 'no_app':
    case null:
      return ShareOutcome.noApp;
    default:
      return ShareOutcome.error;
  }
}

/// Builds the subject, body and message for the report email and WhatsApp.
///
/// Deliberately English: the timesheet goes to the consulting office, and the
/// subject format is the one the client recognises at a glance.
class ReportEmail {
  ReportEmail._();

  /// Exactly `Time sheet from (21/09/2026) to (20/10/2026)`.
  static String subject(ReportingPeriod period) =>
      'Time sheet from (${_d(period.start)}) to (${_d(period.end)})';

  /// One-liner that travels with the file to WhatsApp.
  static String whatsappText(ReportingPeriod period) =>
      'Time sheet from ${_d(period.start)} to ${_d(period.end)} '
      '\u2014 attached.';

  static String body({
    required String officeName,
    required ReportingPeriod period,
    required String employeeName,
  }) {
    final name = officeName.trim();
    final greeting =
        name.isEmpty ? 'Dear Sir or Madam,' : 'Dear $name,';
    final signature = employeeName.trim();

    return [
      greeting,
      '',
      'Please find attached my timesheet for the period from '
          '${_d(period.start)} to ${_d(period.end)}.',
      '',
      'Kindly review it at your convenience and let me know if you need any '
          'clarification or adjustments.',
      '',
      'Best regards,',
      if (signature.isNotEmpty) signature,
    ].join('\n');
  }

  /// DD/MM/YYYY.
  static String _d(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}

/// Light check for the optional office email field: catches obvious typos
/// without rejecting valid addresses.
bool isValidEmail(String value) {
  final v = value.trim();
  if (v.isEmpty) return true;
  final at = v.indexOf('@');
  if (at <= 0 || at == v.length - 1) return false;
  if (v.contains(' ')) return false;
  return v.contains('.', at + 1);
}
