import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:xml/xml.dart';

import '../domain/report_calculator.dart';

/// Fills the company's timesheet when it is stored in the legacy
/// **SpreadsheetML 2003** XML format (`<?mso-application progid="Excel.Sheet"?>`,
/// usually saved with a `.xls` extension).
///
/// `package:excel` cannot read this format: it only understands OOXML
/// `.xlsx` packages (ZIP containers). The company template is however a
/// plain XML document, so it can be filled in place — every style,
/// merged cell, column width and label the original file already has is
/// preserved because only `<Data>` values are touched.
///
/// The layout is discovered from the document itself rather than being
/// hard-coded:
///  * the header row is the row directly above the first data row;
///  * the day columns are the run of numeric cells in that header row,
///    written in the template's own (reverse chronological) order;
///  * the task and project columns are found by their header labels;
///  * the totals row is the first row after the data block whose day
///    cells hold numbers, and the summary lines below it carry the
///    period total.
///
/// `null` is returned when the document does not look like a timesheet
/// this exporter understands, so the caller can report a clear error
/// instead of writing a broken file.
class SpreadsheetMlExporter {
  static const String spreadsheetNs =
      'urn:schemas-microsoft-com:office:spreadsheet';

  static const String _projectHeaderAr = 'المشروع';
  static const String _taskHeaderAr = 'المهمة';
  static const String _nameHeaderAr = 'الاسم';

  /// Two `yyyy/MM/dd` dates in the banner line.
  static final RegExp _dateInBanner = RegExp(r'\d{4}/\d{2}/\d{2}');

  /// Decodes a template file into text.
  ///
  /// Excel writes XML Spreadsheet 2003 as UTF-8, UTF-16LE or UTF-16BE
  /// depending on version and locale, and any leftover byte-order mark
  /// would otherwise make XML parsing fail with an opaque error.
  static String? decode(List<int> bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _decodeUtf16(bytes, littleEndian: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _decodeUtf16(bytes, littleEndian: false);
    }
    return _withoutBom(utf8.decode(bytes, allowMalformed: true));
  }

  static String _decodeUtf16(List<int> bytes, {required bool littleEndian}) {
    final codeUnits = <int>[];
    for (var i = 2; i + 1 < bytes.length; i += 2) {
      codeUnits.add(littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1]);
    }
    return String.fromCharCodes(codeUnits);
  }

  static String _withoutBom(String text) {
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      return text.substring(1);
    }
    return text;
  }

  XmlDocument? _document;
  XmlElement? _dataPrototype;

  String? fill({
    required String templateXml,
    required ReportData data,
    required String employeeName,
    required String localeCode,
    String officeName = '',
  }) {
    final days = data.period.allDates;
    if (days.isEmpty) return null;

    final document = XmlDocument.parse(_withoutBom(templateXml));
    _document = document;

    final prototype = document.descendants
        .whereType<XmlElement>()
        .firstWhereOrNull((e) => e.name.local == 'Data');
    if (prototype == null) return null;
    _dataPrototype = prototype;

    final table = document.descendants
        .whereType<XmlElement>()
        .firstWhereOrNull((e) => e.name.local == 'Table');
    if (table == null) return null;

    var rows = _rowsOf(table);
    if (rows.isEmpty) return null;
    var rowCells = rows.map(_cellsOf).toList();

    // --- Locate the data block -------------------------------------------
    final firstDataIdx = rowCells.indexWhere((cells) {
      final first = _textOf(cells[1]);
      return first != null && int.tryParse(first) != null;
    });
    if (firstDataIdx < 1) return null;
    final headerIdx = firstDataIdx - 1;

    var lastDataIdx = firstDataIdx;
    while (lastDataIdx + 1 < rowCells.length &&
        int.tryParse(_textOf(rowCells[lastDataIdx + 1][1]) ?? '') != null) {
      lastDataIdx++;
    }

    // --- Day columns ------------------------------------------------------
    final headerCells = rowCells[headerIdx];
    final dayColumns = headerCells.keys
        .where(
            (c) => c >= 2 && int.tryParse(_textOf(headerCells[c]) ?? '') != null)
        .toList()
      ..sort();
    if (dayColumns.length < 28) return null;

    // Nothing may be silently dropped: the template grid is fixed.
    if (days.length > dayColumns.length) return null;

    final totalCol = dayColumns.last + 1;

    // --- Name the special columns ----------------------------------------
    var taskCol = 2;
    var projectCol = 3;
    for (final c in [2, 3]) {
      final label = _textOf(headerCells[c])?.trim();
      if (label == null) continue;
      if (label.contains(_projectHeaderAr)) projectCol = c;
      if (label.contains(_taskHeaderAr)) taskCol = c;
    }

    // --- Period banner ----------------------------------------------------
    for (final cells in rowCells) {
      for (final cell in cells.values) {
        final text = _textOf(cell);
        if (text == null) continue;
        final matches = _dateInBanner.allMatches(text).toList();
        if (matches.length < 2) continue;
        var updated = text.replaceRange(
            matches[0].start, matches[0].end, _slashDate(data.period.start));
        final second = _dateInBanner.allMatches(updated).toList()[1];
        updated = updated.replaceRange(
            second.start, second.end, _slashDate(data.period.end));
        _setCell(cell, updated, isNumber: false);
      }
    }

    // --- Consulting office -------------------------------------------------
    // The sheet is submitted to one office, so its name heads the document
    // in place of whatever banner the template shipped with.
    if (officeName.trim().isNotEmpty && rowCells.isNotEmpty) {
      final titleCells = rowCells.first;
      _setCell(titleCells[1], officeName, isNumber: false);
      if (titleCells[2] != null) {
        _setCell(titleCells[2], officeName, isNumber: false);
      }
    }

    // --- Employee name ----------------------------------------------------
    for (var r = 0; r < rows.length; r++) {
      final first = _textOf(rowCells[r][1]);
      if (first != null && first.contains(_nameHeaderAr)) {
        _setCell(rowCells[r][2] ?? rowCells[r][1]!, employeeName,
            isNumber: false);
        break;
      }
    }

    // --- Day header numbers, in the template's own (reverse) order --------
    // The company sheet puts the LAST day of the period in the first day
    // column and counts backwards to the first day.
    final reversedDays = days.reversed.toList();
    final dayToColumn = <String, int>{};
    for (var i = 0; i < dayColumns.length; i++) {
      final cell = headerCells[dayColumns[i]];
      if (i < reversedDays.length) {
        final day = reversedDays[i];
        _setCell(cell, day.day.toString(), isNumber: true);
        dayToColumn[_isoDate(day)] = dayColumns[i];
      } else {
        _clearCell(cell);
      }
    }

    // --- Resize the data block to exactly the number of report rows -------
    final existingDataRows = lastDataIdx - firstDataIdx + 1;
    final needed = data.rows.isEmpty ? 1 : data.rows.length;
    final lastTemplateRow = rows[lastDataIdx];
    if (needed > existingDataRows) {
      var insertAt = table.children.indexOf(lastTemplateRow) + 1;
      for (var i = existingDataRows; i < needed; i++) {
        table.children.insert(insertAt++, lastTemplateRow.copy());
      }
    } else if (needed < existingDataRows) {
      for (var i = needed; i < existingDataRows; i++) {
        rows[firstDataIdx + i].remove();
      }
    }

    // Re-read after the resize so the write pass sees the final shape.
    rows = _rowsOf(table);
    rowCells = rows.map(_cellsOf).toList();
    final dataRowCount = data.rows.isEmpty ? 1 : data.rows.length;
    final newLastDataIdx = firstDataIdx + dataRowCount - 1;
    if (newLastDataIdx >= rowCells.length) return null;

    return _writeRows(
      table: table,
      rowCells: rowCells,
      firstDataIdx: firstDataIdx,
      lastDataIdx: newLastDataIdx,
      data: data,
      dayToColumn: dayToColumn,
      dayColumns: dayColumns,
      projectCol: projectCol,
      taskCol: taskCol,
      totalCol: totalCol,
      localeCode: localeCode,
    );
  }

  String? _writeRows({
    required XmlElement table,
    required List<Map<int, XmlElement>> rowCells,
    required int firstDataIdx,
    required int lastDataIdx,
    required ReportData data,
    required Map<String, int> dayToColumn,
    required List<int> dayColumns,
    required int projectCol,
    required int taskCol,
    required int totalCol,
    required String localeCode,
  }) {
    // Blank every surviving data row so stale values never leak through.
    for (var r = firstDataIdx; r <= lastDataIdx; r++) {
      for (final col in <int>[1, taskCol, projectCol, ...dayColumns, totalCol]) {
        _clearCell(rowCells[r][col]);
      }
    }

    final perDayTotals = <int, double>{};
    var grandTotal = 0.0;
    for (var i = 0; i < data.rows.length; i++) {
      final row = data.rows[i];
      final cells = rowCells[firstDataIdx + i];
      _setCell(cells[1], (i + 1).toString(), isNumber: true);
      _setCell(cells[taskCol], _name(localeCode, row.taskNameAr, row.taskNameEn),
          isNumber: false);
      _setCell(
          cells[projectCol], _name(localeCode, row.projectNameAr, row.projectNameEn),
          isNumber: false);
      row.hoursByDate.forEach((iso, hours) {
        final col = dayToColumn[iso];
        if (col == null) return;
        _setCell(cells[col], _number(hours), isNumber: true);
        perDayTotals.update(col, (v) => v + hours, ifAbsent: () => hours);
      });
      _setCell(cells[totalCol], _number(row.rowTotal), isNumber: true);
      grandTotal += row.rowTotal;
    }

    // Totals row: first row after the data block with numbers on the days.
    var totalsIdx = -1;
    for (var r = lastDataIdx + 1; r < rowCells.length; r++) {
      if (dayColumns.any((c) => _textOf(rowCells[r][c]) != null)) {
        totalsIdx = r;
        break;
      }
    }
    if (totalsIdx >= 0) {
      for (final col in dayColumns) {
        _setCell(rowCells[totalsIdx][col], _number(perDayTotals[col] ?? 0),
            isNumber: true);
      }
      _setCell(rowCells[totalsIdx][totalCol], _number(grandTotal),
          isNumber: true);
    }

    // Summary lines below the totals row. This app tracks total hours
    // only, so the last summary line carries the period total and any
    // earlier category line is zeroed rather than left stale.
    final summaryIdxs = <int>[];
    for (var r = totalsIdx + 1; r < rowCells.length; r++) {
      if (_textOf(rowCells[r][totalCol]) != null) summaryIdxs.add(r);
    }
    for (var i = 0; i < summaryIdxs.length; i++) {
      _setCell(
        rowCells[summaryIdxs[i]][totalCol],
        _number(i == summaryIdxs.length - 1 ? grandTotal : 0),
        isNumber: true,
      );
    }

    // Keep the row-count hint in sync with what the table now holds.
    _setAttr(table, 'ExpandedRowCount', _rowsOf(table).length.toString());

    return _document!.toXmlString();
  }

  List<XmlElement> _rowsOf(XmlElement table) => table.children
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'Row')
      .toList();

  String _name(String localeCode, String ar, String en) {
    if (localeCode == 'ar') return ar.isNotEmpty ? ar : en;
    return en.isNotEmpty ? en : ar;
  }

  Map<int, XmlElement> _cellsOf(XmlElement row) {
    final cells = <int, XmlElement>{};
    var col = 0;
    for (final node in row.children.whereType<XmlElement>()) {
      if (node.name.local != 'Cell') continue;
      final index = _attr(node, 'Index');
      col = index != null ? int.parse(index) : col + 1;
      cells[col] = node;
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

  void _setAttr(XmlElement element, String local, String value) {
    for (final attribute in element.attributes) {
      if (attribute.name.local == local) {
        attribute.value = value;
        return;
      }
    }
  }

  XmlElement? _dataOf(XmlElement? cell) => cell?.children
      .whereType<XmlElement>()
      .firstWhereOrNull((e) => e.name.local == 'Data');

  String? _textOf(XmlElement? cell) {
    final text = _dataOf(cell)?.innerText;
    if (text == null || text.isEmpty) return null;
    return text;
  }

  void _clearCell(XmlElement? cell) => _dataOf(cell)?.remove();

  void _setCell(XmlElement? cell, String value, {required bool isNumber}) {
    if (cell == null) return;
    final data = _dataOf(cell) ?? _newData();
    if (data.parent != cell) cell.children.add(data);
    data.children.clear();
    data.children.add(XmlText(value));
    _setAttr(data, 'Type', isNumber ? 'Number' : 'String');
  }

  /// Clones a `<Data>` element that already exists in the document, so the
  /// right namespace prefix is reused without hand-building names.
  XmlElement _newData() => _dataPrototype!.copy();

  String _number(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _slashDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}
