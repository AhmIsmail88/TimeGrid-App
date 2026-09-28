import 'dart:io';

import 'package:excel/excel.dart' as xl;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/report_calculator.dart';
import 'spreadsheetml_exporter.dart';

/// Describes WHERE in the company's Excel template each piece of data
/// goes. These coordinates are placeholders and MUST be adjusted to
/// match the real template (PRD A18 Phase 1 — "test the Excel template
/// early" is the highest-priority task before anything else here can
/// be trusted). Row/column numbers are 0-based to match the `excel`
/// package's API.
///
/// Only used for OOXML `.xlsx` templates: a SpreadsheetML `.xls`
/// template is located from its own content instead (see
/// [SpreadsheetMlExporter]).
class ExcelTemplateConfig {
  /// Sheet to write into. If null, the first sheet in the template is used.
  final String? sheetName;

  /// Cell holding the employee's name.
  final int employeeNameRow;
  final int employeeNameCol;

  /// Cells holding the period start / end dates.
  final int periodStartRow;
  final int periodStartCol;
  final int periodEndRow;
  final int periodEndCol;

  /// The row that contains the day-column headers (day 1..N of the
  /// period). [firstDayCol] is the column of the FIRST day; each
  /// subsequent day is one column to the right, in period order —
  /// matching the template's own column order, even if that order
  /// feels unusual relative to the app's UI (PRD A9.2).
  final int dayHeaderRow;
  final int firstDayCol;

  /// Where the data rows (one per Project+Task pair) start, and which
  /// columns hold the project name, task name, and the row total.
  final int firstDataRow;
  final int projectNameCol;
  final int taskNameCol;
  final int rowTotalCol;

  /// Number of pre-formatted data rows already present in the
  /// template. If the report needs more rows than this, the exporter
  /// inserts additional rows copying the format of the last template
  /// row rather than silently dropping data (PRD A9.10).
  final int templateDataRowCount;

  const ExcelTemplateConfig({
    this.sheetName,
    this.employeeNameRow = 1,
    this.employeeNameCol = 1,
    this.periodStartRow = 2,
    this.periodStartCol = 1,
    this.periodEndRow = 2,
    this.periodEndCol = 3,
    this.dayHeaderRow = 4,
    this.firstDayCol = 3,
    this.firstDataRow = 5,
    this.projectNameCol = 0,
    this.taskNameCol = 1,
    this.rowTotalCol = 2,
    this.templateDataRowCount = 20,
  });
}

class ExcelExportResult {
  final bool success;
  final File? file;
  final String? errorMessage;
  const ExcelExportResult.ok(this.file)
      : success = true,
        errorMessage = null;
  const ExcelExportResult.failure(this.errorMessage)
      : success = false,
        file = null;
}

/// Fills a copy of the company's Excel template with a computed
/// [ReportData]. Never rebuilds the report from scratch (PRD A9.1):
/// it opens the existing template, writes only the cells that carry
/// data, and re-saves — preserving every other cell's formatting,
/// merges and labels.
///
/// Two template formats are supported, detected from the file bytes:
///
///  * **OOXML `.xlsx`** (a ZIP container) — handled through
///    `package:excel` with the coordinates in [ExcelTemplateConfig].
///    Note that `package:excel` rebuilds the `.xlsx` package when
///    saving, so exotic template features (embedded charts, some
///    conditional formats) may not survive.
///  * **SpreadsheetML 2003 XML** (commonly saved as `.xls`) — handled
///    by [SpreadsheetMlExporter], which edits the XML in place and
///    therefore keeps the original file's formatting intact.
///
/// Any other format (binary BIFF `.xls`, `.ods`, …) is rejected with
/// `template_unsupported_format` rather than failing obscurely.
class ExcelExporter {
  final ExcelTemplateConfig config;
  const ExcelExporter({this.config = const ExcelTemplateConfig()});

  Future<ExcelExportResult> export({
    required ReportData data,
    required File templateFile,
    required String employeeName,
    required String localeCode,
    String officeName = '',
  }) async {
    try {
      if (!await templateFile.exists()) {
        return const ExcelExportResult.failure('template_not_found');
      }
      final bytes = await templateFile.readAsBytes();

      if (_isZipContainer(bytes)) {
        return await _writeXlsxTemplate(bytes, data, employeeName);
      }
      return await _writeSpreadsheetMlTemplate(
          bytes, data, employeeName, localeCode, officeName);
    } catch (e) {
      return ExcelExportResult.failure(e.toString());
    }
  }

  /// Fills an OOXML `.xlsx` template through `package:excel`.
  Future<ExcelExportResult> _writeXlsxTemplate(
    List<int> bytes,
    ReportData data,
    String employeeName,
  ) async {
    final workbook = xl.Excel.decodeBytes(bytes);
    final sheetName = config.sheetName ?? workbook.sheets.keys.first;
    final sheet = workbook.sheets[sheetName];
    if (sheet == null) {
      return const ExcelExportResult.failure('sheet_not_found');
    }

    _writeHeader(sheet, data, employeeName);
    _writeRows(sheet, data);

    final saved = workbook.encode();
    if (saved == null) {
      return const ExcelExportResult.failure('encode_failed');
    }

    final outFile = await _uniqueOutputFile(_fileNameFor(data, '.xlsx'));
    await outFile.writeAsBytes(saved, flush: true);
    return _verified(outFile);
  }

  /// Fills a SpreadsheetML 2003 XML template in place.
  Future<ExcelExportResult> _writeSpreadsheetMlTemplate(
    List<int> bytes,
    ReportData data,
    String employeeName,
    String localeCode,
    String officeName,
  ) async {
    final templateText = SpreadsheetMlExporter.decode(bytes);
    if (templateText == null ||
        !templateText.contains(SpreadsheetMlExporter.spreadsheetNs)) {
      return const ExcelExportResult.failure('template_unsupported_format');
    }

    final filled = SpreadsheetMlExporter().fill(
      templateXml: templateText,
      data: data,
      employeeName: employeeName,
      localeCode: localeCode,
      officeName: officeName,
    );
    if (filled == null) {
      return const ExcelExportResult.failure('template_unsupported_format');
    }

    final outFile = await _uniqueOutputFile(_fileNameFor(data, '.xls'));
    await outFile.writeAsString(filled, flush: true);
    return _verified(outFile);
  }

  /// Confirms the export really landed on disk before reporting success
  /// (PRD A9.9 / A20 rule 9 — never claim success before the file is
  /// verified to exist).
  Future<ExcelExportResult> _verified(File outFile) async {
    if (!await outFile.exists()) {
      return const ExcelExportResult.failure('file_not_written');
    }
    return ExcelExportResult.ok(outFile);
  }

  bool _isZipContainer(List<int> bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4B &&
      bytes[2] == 0x03 &&
      bytes[3] == 0x04;

  String _fileNameFor(ReportData data, String extension) {
    String iso(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return 'TimeGrid_Timesheet_${iso(data.period.start)}_to_${iso(data.period.end)}$extension';
  }

  /// Never silently overwrite a previous export (PRD A9.8): if the exact
  /// same period was already exported, suffix a counter.
  Future<File> _uniqueOutputFile(String fileName) async {
    final outDir = await getApplicationDocumentsDirectory();
    var outFile = File(p.join(outDir.path, fileName));
    final withoutExt = p.basenameWithoutExtension(fileName);
    final extension = p.extension(fileName);
    var counter = 1;
    while (await outFile.exists()) {
      outFile = File(p.join(outDir.path, '$withoutExt ($counter)$extension'));
      counter++;
    }
    return outFile;
  }

  void _writeHeader(xl.Sheet sheet, ReportData data, String employeeName) {
    sheet
        .cell(xl.CellIndex.indexByColumnRow(
            columnIndex: config.employeeNameCol, rowIndex: config.employeeNameRow))
        .value = xl.TextCellValue(employeeName);

    sheet
        .cell(xl.CellIndex.indexByColumnRow(
            columnIndex: config.periodStartCol, rowIndex: config.periodStartRow))
        .value = xl.TextCellValue(_formatDate(data.period.start));

    sheet
        .cell(xl.CellIndex.indexByColumnRow(
            columnIndex: config.periodEndCol, rowIndex: config.periodEndRow))
        .value = xl.TextCellValue(_formatDate(data.period.end));

    final days = data.period.allDates;
    for (var i = 0; i < days.length; i++) {
      sheet
          .cell(xl.CellIndex.indexByColumnRow(
              columnIndex: config.firstDayCol + i, rowIndex: config.dayHeaderRow))
          .value = xl.IntCellValue(days[i].day);
    }
  }

  void _writeRows(xl.Sheet sheet, ReportData data) {
    final days = data.period.allDates;

    for (var r = 0; r < data.rows.length; r++) {
      final row = data.rows[r];
      final rowIndex = config.firstDataRow + r;

      // If the report needs more rows than the template pre-formatted,
      // copy the row height/format of the last known template row so
      // new rows don't look out of place (best-effort — see class doc).
      if (r >= config.templateDataRowCount) {
        sheet.appendRow(
          List<xl.CellValue?>.filled(config.firstDayCol + days.length, null),
        );
      }

      sheet
          .cell(xl.CellIndex.indexByColumnRow(
              columnIndex: config.projectNameCol, rowIndex: rowIndex))
          .value = xl.TextCellValue(row.projectNameEn.isNotEmpty
              ? row.projectNameEn
              : row.projectNameAr);
      sheet
          .cell(xl.CellIndex.indexByColumnRow(
              columnIndex: config.taskNameCol, rowIndex: rowIndex))
          .value = xl.TextCellValue(
              row.taskNameEn.isNotEmpty ? row.taskNameEn : row.taskNameAr);

      for (var i = 0; i < days.length; i++) {
        final iso = _isoDate(days[i]);
        final hours = row.hoursByDate[iso];
        if (hours != null) {
          sheet
              .cell(xl.CellIndex.indexByColumnRow(
                  columnIndex: config.firstDayCol + i, rowIndex: rowIndex))
              .value = xl.DoubleCellValue(hours);
        }
      }

      sheet
          .cell(xl.CellIndex.indexByColumnRow(
              columnIndex: config.rowTotalCol, rowIndex: rowIndex))
          .value = xl.DoubleCellValue(row.rowTotal);
    }
  }

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-${_monthAbbr(d.month)}-${d.year}';

  String _monthAbbr(int month) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][month - 1];
}
