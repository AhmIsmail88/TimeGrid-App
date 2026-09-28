import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timegrid/core/models/reporting_period.dart';
import 'package:timegrid/features/reports/data/spreadsheetml_exporter.dart';
import 'package:timegrid/features/reports/domain/report_calculator.dart';
import 'package:xml/xml.dart';

/// Exercises the real company timesheet that ships in the repository root.
/// Every test is skipped when that file is absent, so the suite still runs
/// on a machine that only has the source code.
void main() {
  final template = File('Time Sheet.xls');

  ReportData sampleData() {
    final period = ReportingPeriod(
      start: DateTime(2026, 8, 21),
      end: DateTime(2026, 9, 20),
    );
    return ReportData(period: period, rows: [
      ReportRow(
        projectId: 1,
        taskId: 1,
        projectNameAr: 'مشروع ألف',
        projectNameEn: 'Project A',
        taskNameAr: 'مهمة ألف',
        taskNameEn: 'Task A',
        hoursByDate: {'2026-08-23': 3.0, '2026-09-20': 0.5},
      ),
      ReportRow(
        projectId: 2,
        taskId: 2,
        projectNameAr: 'مشروع باء',
        projectNameEn: 'Project B',
        taskNameAr: 'مهمة باء',
        taskNameEn: 'Task B',
        hoursByDate: {'2026-09-01': 2.0},
      ),
    ]);
  }

  String? fill(ReportData data, {String employeeName = 'موظف تجريبي'}) {
    final xml = template.readAsStringSync(encoding: utf8);
    return SpreadsheetMlExporter().fill(
      templateXml: xml,
      data: data,
      employeeName: employeeName,
      localeCode: 'ar',
    );
  }

  test('fills the company SpreadsheetML template in place', () {
    if (!template.existsSync()) {
      markTestSkipped('Company template not present in the repository root');
      return;
    }

    final filled = fill(sampleData());
    expect(filled, isNotNull, reason: 'template should be recognised');

    // Excel only treats the file as a spreadsheet when the XML
    // declaration and the mso-application processing instruction
    // survive serialization.
    expect(filled, startsWith('<?xml'));
    expect(filled, contains('<?mso-application'));
    expect(filled, contains('urn:schemas-microsoft-com:office:spreadsheet'));

    // Still exactly one worksheet.
    expect(
      XmlDocument.parse(filled!)
          .descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'Worksheet')
          .length,
      1,
    );

    // Header block updated.
    expect(filled, contains('موظف تجريبي'));
    expect(filled, contains('2026/08/21'));
    expect(filled, contains('2026/09/20'));

    // The rows the report produced are present...
    expect(filled, contains('مشروع ألف'));
    expect(filled, contains('مهمة باء'));
    expect(filled, contains('5.5'));

    // ...and the sample data that was inside the template is gone.
    expect(filled, isNot(contains('كفر ابو زهرة')));
    expect(filled, isNot(contains('الجبل الأصفر')));
  });

  test('writes the right hours into the right day columns', () {
    if (!template.existsSync()) {
      markTestSkipped('Company template not present in the repository root');
      return;
    }

    final rows = gridOf(fill(sampleData())!);

    // The template starts its day columns at column 4 and counts down
    // from the last day of the period: 20, 19, ... 1, 31, ... 21.
    final header = rows[3];
    expect(header[4], '20');
    expect(header[23], '1');
    expect(header[24], '31');
    expect(header[34], '21');
    expect(header[35], 'الإجمالي');

    // First data row: 3 h on 2026-08-23 -> column 32, 0.5 h on
    // 2026-09-20 -> column 4, row total 3.5.
    final first = rows[4];
    expect(first[1], '1');
    expect(first[2], 'مهمة ألف');
    expect(first[3], 'مشروع ألف');
    expect(first[4], '0.5');
    expect(first[32], '3');
    expect(first[35], '3.5');

    // Second data row: 2 h on 2026-09-01 -> column 23.
    final second = rows[5];
    expect(second[1], '2');
    expect(second[23], '2');
    expect(second[35], '2');

    // The data block shrank from the template's 9 sample rows to 2, so
    // the totals row follows immediately after them.
    final totals = rows[6];
    expect(totals[1], 'الإجمالي');
    expect(totals[4], '0.5');
    expect(totals[35], '5.5');

    // The last summary line carries the period total.
    expect(rows.last[35], '5.5');
  });

  test('the consulting office name heads the sheet', () {
    if (!template.existsSync()) {
      markTestSkipped('Company template not present in the repository root');
      return;
    }
    final original = template.readAsStringSync(encoding: utf8);
    final filled = SpreadsheetMlExporter().fill(
      templateXml: original,
      data: sampleData(),
      employeeName: 'موظف تجريبي',
      localeCode: 'ar',
      officeName: 'مكتب الاستشاري',
    );
    expect(filled, isNotNull);

    final rows = gridOf(filled!);
    expect(rows[0][1], 'مكتب الاستشاري');
    expect(rows[0][2], 'مكتب الاستشاري');
    expect(filled, isNot(contains('INTEGRATED CONSULTING ENGINEERING')));
  });

  test('refuses a period that cannot fit the template grid', () {
    if (!template.existsSync()) {
      markTestSkipped('Company template not present in the repository root');
      return;
    }
    final tooLong = ReportData(
      period: ReportingPeriod(
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 3, 15),
      ),
      rows: [],
    );
    expect(fill(tooLong), isNull);
  });

  // The strongest check available without Excel: feed the template's OWN
  // data back through the exporter and require the result to be identical
  // cell for cell. A wrong column, a lost value or a stale row would all
  // show up here.
  test('re-exporting the template\'s own data reproduces it exactly', () {
    if (!template.existsSync()) {
      markTestSkipped('Company template not present in the repository root');
      return;
    }

    final original = template.readAsStringSync(encoding: utf8);
    final data = spreadsheetMlDataFrom(original);
    expect(data.rows, isNotEmpty);

    final filled = SpreadsheetMlExporter().fill(
      templateXml: original,
      data: data,
      employeeName: '',
      localeCode: 'ar',
    );
    expect(filled, isNotNull);

    final before = gridOf(original);
    final after = gridOf(filled!);
    expect(after.length, before.length, reason: 'row count must be preserved');

    for (var r = 0; r < before.length; r++) {
      for (var c = 1; c <= 35; c++) {
        expect(
          after[r][c] ?? '',
          before[r][c] ?? '',
          reason: 'cell R${r + 1}C$c changed',
        );
      }
    }
  });

  // Dev aid: set TIMEGRID_SAMPLE_OUT to a file path to also write the
  // filled workbook there, so the produced layout can be opened in Excel
  // and inspected without installing the app.
  test('optionally writes a filled sample for manual inspection', () {
    final out = Platform.environment['TIMEGRID_SAMPLE_OUT'];
    if (out == null || out.isEmpty) {
      markTestSkipped('TIMEGRID_SAMPLE_OUT not set');
      return;
    }
    if (!template.existsSync()) {
      markTestSkipped('Company template not present in the repository root');
      return;
    }
    final original = template.readAsStringSync(encoding: utf8);
    final filled = SpreadsheetMlExporter().fill(
      templateXml: original,
      data: spreadsheetMlDataFrom(original),
      employeeName: 'موظف تجريبي',
      localeCode: 'ar',
    );
    expect(filled, isNotNull);
    File(out).writeAsStringSync(filled!, flush: true);
    expect(File(out).existsSync(), isTrue);
  });

  test('decodes UTF-8, UTF-16LE and UTF-16BE template bytes', () {
    const xml =
        '<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"><Worksheet/></Workbook>';

    expect(SpreadsheetMlExporter.decode(utf8.encode(xml)), xml);
    expect(
      SpreadsheetMlExporter.decode(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode(xml)]),
      xml,
    );

    final littleEndian = <int>[0xFF, 0xFE];
    for (final unit in xml.codeUnits) {
      littleEndian
        ..add(unit & 0xFF)
        ..add((unit >> 8) & 0xFF);
    }
    expect(SpreadsheetMlExporter.decode(littleEndian), xml);

    final bigEndian = <int>[0xFE, 0xFF];
    for (final unit in xml.codeUnits) {
      bigEndian
        ..add((unit >> 8) & 0xFF)
        ..add(unit & 0xFF);
    }
    expect(SpreadsheetMlExporter.decode(bigEndian), xml);
  });

  test('tolerates a byte-order mark in the template text', () {
    if (!template.existsSync()) {
      markTestSkipped('Company template not present in the repository root');
      return;
    }
    final original = template.readAsStringSync(encoding: utf8);
    final filled = SpreadsheetMlExporter().fill(
      templateXml: '\uFEFF$original',
      data: sampleData(),
      employeeName: 'موظف تجريبي',
      localeCode: 'ar',
    );
    expect(filled, isNotNull);
    expect(filled, contains('موظف تجريبي'));
  });
}

/// Rebuilds the sheet as `row -> column -> cell text`, honouring the
/// SpreadsheetML `ss:Index` / `ss:MergeAcross` attributes.
List<Map<int, String?>> gridOf(String xml) {
  final document = XmlDocument.parse(xml);
  final table = document.descendants
      .whereType<XmlElement>()
      .firstWhere((e) => e.name.local == 'Table');
  return table.children
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'Row')
      .map(_cellsOf)
      .toList();
}

/// Reads a filled SpreadsheetML timesheet back into the app's own
/// [ReportData] shape: the period comes from the banner line, the day
/// numbers from the header row, and every data row from its cells.
ReportData spreadsheetMlDataFrom(String xml) {
  final grid = gridOf(xml);
  final header = grid[3];

  final dayColumns = <int>[];
  for (var c = 4; c <= 35; c++) {
    final text = header[c];
    if (text != null && int.tryParse(text) != null) dayColumns.add(c);
  }

  final dates = RegExp(r'\d{4}/\d{2}/\d{2}')
      .allMatches(grid[1][1] ?? '')
      .map((m) => m.group(0)!)
      .toList();
  final period = ReportingPeriod(
    start: _parseSlashDate(dates[0]),
    end: _parseSlashDate(dates[1]),
  );
  final reversedDays = period.allDates.reversed.toList();

  final rows = <ReportRow>[];
  for (var r = 4; r < grid.length; r++) {
    final cells = grid[r];
    final sequence = cells[1];
    if (sequence == null || int.tryParse(sequence) == null) break;
    final hoursByDate = <String, double>{};
    for (var i = 0; i < dayColumns.length && i < reversedDays.length; i++) {
      final hours = double.tryParse(cells[dayColumns[i]] ?? '');
      if (hours != null && hours != 0) {
        hoursByDate[_isoDate(reversedDays[i])] = hours;
      }
    }
    rows.add(ReportRow(
      projectId: r,
      taskId: r,
      projectNameAr: cells[3] ?? '',
      projectNameEn: '',
      taskNameAr: cells[2] ?? '',
      taskNameEn: '',
      hoursByDate: hoursByDate,
    ));
  }
  return ReportData(period: period, rows: rows);
}

DateTime _parseSlashDate(String value) {
  final parts = value.split('/').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Map<int, String?> _cellsOf(XmlElement row) {
  final cells = <int, String?>{};
  var col = 0;
  for (final node in row.children.whereType<XmlElement>()) {
    if (node.name.local != 'Cell') continue;
    final index = _attr(node, 'Index');
    col = index != null ? int.parse(index) : col + 1;
    final data = node.children
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'Data');
    cells[col] = data.isEmpty ? null : data.first.innerText;
    final merge = _attr(node, 'MergeAcross');
    if (merge != null) col += int.parse(merge);
  }
  return cells;
}

String? _attr(XmlElement element, String local) {
  for (final attribute in element.attributes) {
    if (attribute.name.local == local) return attribute.value;
  }
  return null;
}
