import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/localization/gen/app_localizations.dart';
import '../../../core/models/office.dart';
import '../../../core/models/reporting_period.dart';
import '../../../core/providers/providers.dart';
import '../../../core/services/file_sharer.dart';
import '../../../core/services/report_sharing.dart';

/// Asks where a produced timesheet should go: WhatsApp, Gmail (opened with
/// the office's email already in the "to" field) or the system share sheet.
///
/// The office's contact details drive the two direct options, so they are
/// shown in the sheet itself — if something is missing the user is told which
/// detail to add instead of the action failing silently.
Future<void> showReportShareSheet(
  BuildContext context, {
  required String filePath,
  required ReportingPeriod period,
  required Office? office,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => _ReportShareSheet(
      filePath: filePath,
      period: period,
      office: office,
    ),
  );
}

class _ReportShareSheet extends ConsumerWidget {
  const _ReportShareSheet({
    required this.filePath,
    required this.period,
    required this.office,
  });

  final String filePath;
  final ReportingPeriod period;
  final Office? office;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final fileName = filePath.split('/').last;
    final email = office?.email.trim() ?? '';
    final whatsapp = office?.whatsappNumber ?? '';

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 2),
            child: Text(
              l10n.shareReportTitle,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 8),
            child: Text(
              fileName,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.chat_outlined),
            title: Text(l10n.whatsapp),
            subtitle:
                Text(whatsapp.isNotEmpty ? whatsapp : l10n.shareWhatsappHint),
            onTap: () => _shareWhatsApp(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: Text(l10n.shareViaGmail),
            subtitle: Text(
              email.isNotEmpty ? email : l10n.shareMissingEmail,
              style: email.isNotEmpty
                  ? null
                  : TextStyle(color: theme.colorScheme.error),
            ),
            onTap: () => _shareGmail(context, ref, email),
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: Text(l10n.shareOtherApps),
            onTap: () => _shareWithSystemSheet(context, ref),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _shareGmail(
      BuildContext context, WidgetRef ref, String email) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // Gmail is opened with the office address already filled in, so there is
    // nothing to guess: without an address the action is refused with a hint
    // rather than opening Gmail with an empty "to".
    if (email.isEmpty) {
      navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.shareMissingEmail)));
      return;
    }

    // Everything the follow-up needs is read before the sheet is popped:
    // its own ref dies with it.
    final sharer = ref.read(reportSharerProvider);
    final fileSharer = ref.read(fileSharerProvider);
    final subject = ReportEmail.subject(period);
    final body = ReportEmail.body(
      officeName: office?.nameEn.trim().isNotEmpty == true
          ? office!.nameEn
          : (office?.nameAr ?? ''),
      period: period,
      employeeName: ref.read(settingsProvider).value?.employeeName ?? '',
    );

    navigator.pop();
    final outcome = await sharer.shareViaGmail(
      to: email,
      subject: subject,
      body: body,
      filePath: filePath,
    );
    await _finish(fileSharer, outcome, messenger, l10n);
  }

  Future<void> _shareWhatsApp(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final sharer = ref.read(reportSharerProvider);
    final fileSharer = ref.read(fileSharerProvider);

    navigator.pop();
    final outcome = await sharer.shareViaWhatsApp(
      text: ReportEmail.whatsappText(period),
      filePath: filePath,
    );
    await _finish(fileSharer, outcome, messenger, l10n);
  }

  Future<void> _shareWithSystemSheet(
      BuildContext context, WidgetRef ref) async {
    final fileSharer = ref.read(fileSharerProvider);
    Navigator.of(context).pop();
    await fileSharer.shareFile(
          path: filePath,
          subject: ReportEmail.subject(period),
        );
  }

  /// Common ending: the target app is open, or fall back to the system share
  /// sheet, or tell the user it failed.
  Future<void> _finish(
    FileSharer fileSharer,
    ShareOutcome outcome,
    ScaffoldMessengerState messenger,
    AppLocalizations l10n,
  ) async {
    switch (outcome) {
      case ShareOutcome.opened:
        return;
      case ShareOutcome.noApp:
        // No direct target: the generic sheet still gets the file there.
        await fileSharer.shareFile(
          path: filePath,
          subject: ReportEmail.subject(period),
        );
      case ShareOutcome.error:
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(l10n.shareFailed)));
    }
  }
}
