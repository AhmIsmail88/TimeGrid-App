import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/localization/gen/app_localizations.dart';
import '../../../core/models/office.dart';
import '../../../core/models/reporting_period.dart';
import '../../../core/widgets/office_picker.dart';
import '../../../core/models/export_record.dart';
import '../../../core/providers/providers.dart';
import '../../../core/utils/bidi.dart';
import '../../../core/services/file_sharer.dart';
import '../data/excel_exporter.dart';
import '../data/pdf_timesheet_exporter.dart';
import '../domain/report_calculator.dart';

final _reportDataProvider = FutureProvider<ReportData>((ref) async {
  ref.watch(dataVersionProvider);
  final period = ref.watch(selectedPeriodProvider);
  final officeId = ref.watch(reportOfficeProvider);
  final logs = ref.read(workLogRepositoryProvider);
  final projects = ref.read(projectRepositoryProvider);
  final tasks = ref.read(taskRepositoryProvider);

  // A timesheet is always produced for one consulting office, so both the
  // logs and the project names are scoped to it as soon as one is chosen.
  final logsInPeriod = officeId == null
      ? await logs.getForPeriod(period.start, period.end)
      : await logs.getForPeriodForOffice(period.start, period.end, officeId);
  final allProjects = await projects.getAll(officeId: officeId);
  final allTasks = await tasks.getAll();

  return ReportCalculator().build(
    period: period,
    logsInPeriod: logsInPeriod,
    projectNameAr: {for (final p in allProjects) p.id!: p.nameAr},
    projectNameEn: {for (final p in allProjects) p.id!: p.nameEn},
    taskNameAr: {for (final t in allTasks) t.id!: t.nameAr},
    taskNameEn: {for (final t in allTasks) t.id!: t.nameEn},
  );
});

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  bool _exporting = false;
  bool _exportingPdf = false;

  Future<void> _pickManualRange(ReportingPeriod current) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: current.start, end: current.end),
    );
    if (range != null) {
      ref.read(selectedPeriodProvider.notifier).moveTo(
          ReportingPeriod(start: range.start, end: range.end));
    }
  }

  Future<void> _export(ReportData data) async {
    final l10n = AppLocalizations.of(context)!;
    final templateFile = ref.read(excelTemplateFileProvider);
    final settings = ref.read(settingsProvider).value;
    final locale = Localizations.localeOf(context).languageCode;
    final officeId = ref.read(reportOfficeProvider);
    final officeName = _reportOfficeName(locale) ?? '';

    if (officeId == null) {
      _showMessage(l10n.exportFailedTitle, l10n.selectOfficeToExport);
      return;
    }
    if (templateFile == null) {
      _showMessage(l10n.exportFailedTitle, l10n.selectTemplate);
      return;
    }
    if (data.rows.isEmpty) {
      _showMessage(l10n.exportFailedTitle, l10n.noDataForPeriod);
      return;
    }

    setState(() => _exporting = true);
    final result = await const ExcelExporter().export(
      data: data,
      templateFile: templateFile,
      employeeName: settings?.employeeName ?? '',
      localeCode: locale,
      officeName: officeName,
    );
    setState(() => _exporting = false);

    if (!mounted) return;
    if (result.success && result.file != null) {
      await _rememberExport(
        data: data,
        file: result.file!,
        officeId: officeId,
        officeName: officeName,
      );
      if (!mounted) return;
      _showExportSuccessDialog(result.file!.path.split('/').last, result.file!.path, l10n);
      await _offerToLockPeriod(data.period, l10n);
    } else {
      _showMessage(l10n.exportFailedTitle, _exportErrorMessage(result.errorMessage, l10n));
    }
  }

  /// Turns the exporter's machine-readable failure code into text a user
  /// can act on.
  String _exportErrorMessage(String? code, AppLocalizations l10n) {
    switch (code) {
      case 'template_unsupported_format':
        return l10n.templateUnsupportedFormat;
      case 'template_not_found':
        return l10n.selectTemplate;
      case null:
        return '';
      default:
        return code;
    }
  }

  /// The office this report is about, or null when none is chosen yet.
  String? _reportOfficeName(String locale) {
    final id = ref.watch(reportOfficeProvider);
    if (id == null) return null;
    for (final office in ref.watch(officesProvider).value ?? const <Office>[]) {
      if (office.id == id) return office.displayName(locale);
    }
    return null;
  }

  Future<void> _pickReportOffice(AppLocalizations l10n) async {
    final chosen = await pickOffice(
      context,
      ref,
      l10n,
      current: ref.read(reportOfficeProvider),
    );
    if (chosen == null) return;
    ref.read(reportOfficeProvider.notifier).state = chosen;
  }

  /// After a report has gone out, offer to close the period it covers so the
  /// numbers the office received cannot drift afterwards.
  Future<void> _offerToLockPeriod(
      ReportingPeriod period, AppLocalizations l10n) async {
    final repository = ref.read(periodLockRepositoryProvider);
    if (await repository.isRangeLocked(period.start, period.end)) return;
    if (!mounted) return;

    final lock = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.lockPeriodTitle),
        content: Text(l10n.lockPeriodMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.lockPeriod),
          ),
        ],
      ),
    );
    if (lock != true) return;

    await repository.lock(period.start, period.end);
    ref.read(dataVersionProvider.notifier).state++;
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.periodLocked)));
  }

  TimesheetLabels _pdfLabels(AppLocalizations l10n) => TimesheetLabels(
        title: l10n.timesheetTitle,
        number: l10n.numberColumn,
        task: l10n.task,
        project: l10n.project,
        total: l10n.totalColumn,
        grandTotal: l10n.totalHours,
        employee: l10n.employeeName,
        period: l10n.filterByPeriod,
        generated: l10n.generatedOn,
        noEntries: l10n.noDataForPeriod,
      );

  /// Builds the printable timesheet and hands it to the share sheet, then
  /// offers to lock the period it covers.
  Future<void> _sharePdf(ReportData data) async {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).languageCode;
    final settings = ref.read(settingsProvider).value;

    if (ref.read(reportOfficeProvider) == null) {
      _showMessage(l10n.exportFailedTitle, l10n.selectOfficeToExport);
      return;
    }

    setState(() => _exportingPdf = true);
    final bytes = await const PdfTimesheetExporter().buildPdf(
      data: data,
      labels: _pdfLabels(l10n),
      officeName: _reportOfficeName(locale) ?? '',
      employeeName: settings?.employeeName ?? '',
      periodText: ltrRun('${DateFormat('d MMM yyyy').format(data.period.start)}'
          ' - '
          '${DateFormat('d MMM yyyy').format(data.period.end)}'),
    );
    if (!mounted) return;
    setState(() => _exportingPdf = false);

    if (bytes == null) {
      _showMessage(l10n.exportFailedTitle, l10n.exportFailedPdf);
      return;
    }

    final stamp = DateFormat('yyyy-MM-dd').format(data.period.start);
    final end = DateFormat('yyyy-MM-dd').format(data.period.end);
    final directory = await getApplicationDocumentsDirectory();
    final file = File(
        '${directory.path}/TimeGrid_Timesheet_${stamp}_to_$end.pdf');
    await file.writeAsBytes(bytes, flush: true);
    await _rememberExport(
      data: data,
      file: file,
      officeId: ref.read(reportOfficeProvider),
      officeName: _reportOfficeName(locale) ?? '',
    );
    if (!mounted) return;

    // Shares through the normal Android sheet, so it can go straight to the
    // office by mail or WhatsApp.
    await ref.read(fileSharerProvider).shareFile(
          path: file.path,
          subject: 'TimeGrid ${DateFormat('yyyy-MM-dd').format(data.period.start)}',
        );
    if (!mounted) return;
    await _offerToLockPeriod(data.period, l10n);
  }

  /// Records the file that was just produced, so the Reports screen can show
  /// what has already gone out and for which period.
  Future<void> _rememberExport({
    required ReportData data,
    required File file,
    required int? officeId,
    required String officeName,
  }) async {
    final name = file.path.split('/').last;
    await ref.read(exportRepositoryProvider).record(ExportRecord(
          officeId: officeId,
          officeName: officeName,
          periodStart: data.period.start,
          periodEnd: data.period.end,
          fileName: name,
          filePath: file.path,
          format: name.contains('.')
              ? name.split('.').last.toLowerCase()
              : '',
          exportedAt: DateTime.now().toIso8601String(),
        ));
    ref.read(dataVersionProvider.notifier).state++;
  }

  /// "21 Sep – 20 Oct" for an export record, isolated so the two dates keep
  /// their own direction inside Arabic text.
  String _periodRange(ExportRecord record) => ltrRun(
      '${DateFormat('d MMM').format(record.periodStart)} \u2013 '
      '${DateFormat('d MMM').format(record.periodEnd)}');

  void _showMessage(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  void _showExportSuccessDialog(String fileName, String path, AppLocalizations l10n) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.exportSuccessTitle),
        content: Text(l10n.exportSuccessMessage(fileName)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              OpenFilex.open(path);
            },
            child: Text(l10n.openFile),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              SharePlus.instance.share(ShareParams(files: [XFile(path)]));
            },
            child: Text(l10n.shareFile),
          ),
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).languageCode;
    final period = ref.watch(selectedPeriodProvider);
    final reportAsync = ref.watch(_reportDataProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.reports)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              title: Text(
                  '${l10n.periodStart}: ${ltrRun(DateFormat('d MMM yyyy').format(period.start))}\n'
                  '${l10n.periodEnd}: ${ltrRun(DateFormat('d MMM yyyy').format(period.end))}'),
              isThreeLine: false,
              trailing: TextButton(
                onPressed: () => _pickManualRange(period),
                child: Text(l10n.manualPeriod),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.business_outlined),
              title: Text(l10n.office),
              subtitle: Text(
                  _reportOfficeName(locale) ?? l10n.selectOfficeToExport),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickReportOffice(l10n),
            ),
          ),
          const SizedBox(height: 12),
          if (ref.watch(lockedPeriodsProvider).maybeWhen(
                data: (periods) =>
                    periods.any((p) => p.contains(period.start)),
                orElse: () => false,
              ))
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: ListTile(
                leading: const Icon(Icons.lock_outline),
                title: Text(l10n.periodLocked),
                trailing: TextButton(
                  onPressed: () async {
                    await ref
                        .read(periodLockRepositoryProvider)
                        .unlock(period.start, period.end);
                    ref.read(dataVersionProvider.notifier).state++;
                  },
                  child: Text(l10n.unlockPeriod),
                ),
              ),
            ),
          const SizedBox(height: 12),
          reportAsync.when(
            data: (data) {
              if (data.rows.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: Text(l10n.noDataForPeriod)),
                );
              }
              return Column(
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(children: [
                            Text(data.grandTotal.toStringAsFixed(2),
                                style: Theme.of(context).textTheme.titleLarge),
                            Text(l10n.totalHours),
                          ]),
                          Column(children: [
                            Text(data.entryCount.toString(),
                                style: Theme.of(context).textTheme.titleLarge),
                            Text(l10n.summaryByProjectTask),
                          ]),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...data.rows.map((row) => Card(
                        child: ListTile(
                          title: Text(locale == 'ar'
                              ? (row.taskNameAr.isNotEmpty ? row.taskNameAr : row.taskNameEn)
                              : (row.taskNameEn.isNotEmpty ? row.taskNameEn : row.taskNameAr)),
                          subtitle: Text(locale == 'ar'
                              ? (row.projectNameAr.isNotEmpty ? row.projectNameAr : row.projectNameEn)
                              : (row.projectNameEn.isNotEmpty ? row.projectNameEn : row.projectNameAr)),
                          trailing: Text('${row.rowTotal.toStringAsFixed(2)}h',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      )),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: _exporting
                          ? const SizedBox(
                              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.file_download_outlined),
                      label: Text(l10n.exportExcel),
                      onPressed: _exporting ? null : () => _export(data),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: _exportingPdf
                          ? const SizedBox(
                              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(l10n.exportPdf),
                      onPressed: _exportingPdf ? null : () => _sharePdf(data),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.exportHistory,
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 8),
                          ref.watch(exportHistoryProvider).when(
                                data: (records) => records.isEmpty
                                    ? Text(l10n.noExportsYet,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall)
                                    : Column(
                                        children: [
                                          for (final record in records.take(5))
                                            ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              dense: true,
                                              leading: Icon(
                                                  record.format == 'pdf'
                                                      ? Icons
                                                          .picture_as_pdf_outlined
                                                      : Icons
                                                          .table_chart_outlined),
                                              title: Text(
                                                  '${record.officeName} \u00b7 ${_periodRange(record)}'),
                                              subtitle: Text(ltrRun(record
                                                  .exportedAt
                                                  .split('T')
                                                  .first)),
                                              onTap: () => OpenFilex.open(
                                                  record.filePath),
                                            ),
                                        ],
                                      ),
                                loading: () => const SizedBox(
                                    height: 24,
                                    child: Center(
                                        child: CircularProgressIndicator())),
                                error: (e, _) => Text('$e'),
                              ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
            loading: () => const Padding(
                padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text('$e'),
          ),
        ],
      ),
    );
  }
}
