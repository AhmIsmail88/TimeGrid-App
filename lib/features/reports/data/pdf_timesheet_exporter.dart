import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/report_calculator.dart';

/// The strings the printable timesheet needs, taken from AppLocalizations at
/// the call site so this file stays free of any UI dependency.
class TimesheetLabels {
  final String title;
  final String number;
  final String task;
  final String project;
  final String total;
  final String grandTotal;
  final String employee;
  final String period;
  final String generated;
  final String noEntries;

  const TimesheetLabels({
    required this.title,
    required this.number,
    required this.task,
    required this.project,
    required this.total,
    required this.grandTotal,
    required this.employee,
    required this.period,
    required this.generated,
    required this.noEntries,
  });
}

/// Turns a report into a timesheet a consulting office can be handed.
///
/// Why this draws the page with Flutter and embeds it as an image:
///
/// * A PDF text library paints glyphs one by one and has no Arabic shaping,
///   so "مشروع" comes out as isolated letters in the wrong order.
/// * Rendering HTML through the platform's web engine (the obvious fix) was
///   measured on a real device: `Printing.convertHtml` never returns, so the
///   export simply hung.
///
/// Flutter's own text engine does shape Arabic correctly, and it is already
/// in the app, so the page is painted to an image and that image becomes the
/// PDF page. The trade-off is a PDF whose text is not selectable — acceptable
/// for a timesheet, and it is guaranteed to look right.
///
/// The layout follows the company sheet: number, task and project columns,
/// then one column per day of the period **counting backwards from the last
/// day**, which is the order the company template uses.
class PdfTimesheetExporter {
  const PdfTimesheetExporter();

  /// A4 landscape at 180 dpi: crisp when printed, and small enough to share.
  static const double _pageWidth = 2105;
  static const double _pageHeight = 1489;
  static const double _margin = 44;

  Future<Uint8List?> buildPdf({
    required ReportData data,
    required TimesheetLabels labels,
    required String officeName,
    required String employeeName,
    required String periodText,
    DateTime? generatedAt,
  }) async {
    try {
      final png = await renderPagePng(
        data: data,
        labels: labels,
        officeName: officeName,
        employeeName: employeeName,
        periodText: periodText,
        generatedAt: generatedAt ?? DateTime.now(),
      );
      if (png == null) return null;

      final document = pw.Document();
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: pw.EdgeInsets.zero,
          build: (context) => pw.Image(
            pw.MemoryImage(png),
            fit: pw.BoxFit.contain,
          ),
        ),
      );
      return await document.save();
    } catch (_) {
      return null;
    }
  }

  /// Paints the whole timesheet and returns it as PNG bytes.
  Future<Uint8List?> renderPagePng({
    required ReportData data,
    required TimesheetLabels labels,
    required String officeName,
    required String employeeName,
    required String periodText,
    required DateTime generatedAt,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      const Rect.fromLTWH(0, 0, _pageWidth, _pageHeight),
    );

    const ink = Color(0xFF111827);
    const muted = Color(0xFF64748B);
    const brand = Color(0xFF1565C0);
    const line = Color(0xFFB0BEC5);
    const headerFill = Color(0xFFE0F7FA);
    const totalsFill = Color(0xFFF1F5F9);

    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _pageWidth, _pageHeight),
      Paint()..color = Colors.white,
    );

    var y = _margin;
    const contentWidth = _pageWidth - _margin * 2;

    // --- heading ---------------------------------------------------------
    if (officeName.trim().isNotEmpty) {
      _paint(
        canvas,
        officeName,
        left: _margin,
        top: y,
        width: contentWidth,
        size: 34,
        bold: true,
        color: brand,
      );
      y += 46;
    }
    _paint(canvas, labels.title,
        left: _margin, top: y, width: contentWidth, size: 22, color: ink);
    y += 34;
    _paint(
      canvas,
      '${labels.employee}: $employeeName    '
      '${labels.period}: $periodText    '
      '${labels.generated}: ${_stamp(generatedAt)}',
      left: _margin,
      top: y,
      width: contentWidth,
      size: 18,
      color: muted,
    );
    y += 30;

    canvas.drawRect(
      Rect.fromLTWH(_margin, y, contentWidth, 3),
      Paint()..color = brand,
    );
    y += 18;

    if (data.rows.isEmpty) {
      _paint(canvas, labels.noEntries,
          left: _margin, top: y + 60, width: contentWidth, size: 24, color: muted);
      return _toPng(recorder);
    }

    // --- table geometry ---------------------------------------------------
    final days = data.period.allDates.reversed.toList();
    const numberWidth = 54.0;
    const nameWidth = 250.0;
    const totalWidth = 74.0;

    // Day columns take whatever is left, so a 31-day period still fits.
    final dayWidth =
        ((contentWidth - numberWidth - nameWidth * 2 - totalWidth) / days.length)
            .clamp(26.0, 54.0);

    final rowCount = data.rows.length + 3; // header + rows + totals + summary
    final available = _pageHeight - _margin - y;
    final rowHeight = (available / rowCount).clamp(18.0, 34.0);

    var x = _margin;
    final columns = <double>[numberWidth, nameWidth, nameWidth];
    for (var i = 0; i < days.length; i++) {
      columns.add(dayWidth);
    }
    columns.add(totalWidth);
    final tableWidth = columns.fold<double>(0, (a, b) => a + b);

    // Header row: number, task, project, the days, then the total.
    final headers = <String>[
      labels.number,
      labels.task,
      labels.project,
      ...days.map((day) => day.day.toString()),
      labels.total,
    ];
    _paintRow(
      canvas,
      headers,
      columns,
      left: x,
      top: y,
      height: rowHeight,
      size: 15,
      fill: headerFill,
      bold: true,
      color: ink,
      border: line,
      alignRightUpTo: 3,
    );
    y += rowHeight;

    // Data rows.
    final perDay = <int, double>{};
    var grandTotal = 0.0;
    for (var i = 0; i < data.rows.length; i++) {
      final row = data.rows[i];
      final cells = <String>[('${i + 1}'), _name(row.taskNameAr, row.taskNameEn), _name(row.projectNameAr, row.projectNameEn)];
      for (var d = 0; d < days.length; d++) {
        final hours = row.hoursByDate[_isoDate(days[d])];
        if (hours != null) {
          perDay.update(d, (v) => v + hours, ifAbsent: () => hours);
          cells.add(_number(hours));
        } else {
          cells.add('');
        }
      }
      cells.add(_number(row.rowTotal));
      _paintRow(
        canvas,
        cells,
        columns,
        left: x,
        top: y,
        height: rowHeight,
        size: 14,
        color: ink,
        border: line,
        alignRightUpTo: 3,
      );
      y += rowHeight;
      grandTotal += row.rowTotal;
    }

    // Totals row.
    final totals = <String>[labels.total, '', ''];
    for (var d = 0; d < days.length; d++) {
      totals.add(_number(perDay[d] ?? 0));
    }
    totals.add(_number(grandTotal));
    _paintRow(
      canvas,
      totals,
      columns,
      left: x,
      top: y,
      height: rowHeight,
      size: 14,
      bold: true,
      fill: totalsFill,
      color: ink,
      border: line,
      alignRightUpTo: 3,
    );
    y += rowHeight;

    // Summary row: the period total, spanning everything but the last column.
    canvas.drawRect(
      Rect.fromLTWH(x, y, tableWidth - totalWidth, rowHeight),
      Paint()..color = headerFill,
    );
    canvas.drawRect(
      Rect.fromLTWH(x + tableWidth - totalWidth, y, totalWidth, rowHeight),
      Paint()..color = headerFill,
    );
    canvas.drawRect(
      Rect.fromLTWH(x, y, tableWidth, rowHeight),
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    _paint(canvas, labels.grandTotal,
        left: x + 12,
        top: y + (rowHeight - 19) / 2,
        width: tableWidth - totalWidth - 24,
        size: 15,
        bold: true,
        color: ink);
    _paint(canvas, _number(grandTotal),
        left: x + tableWidth - totalWidth,
        top: y + (rowHeight - 19) / 2,
        width: totalWidth,
        size: 15,
        bold: true,
        color: ink,
        align: TextAlign.center);

    return _toPng(recorder);
  }

  Future<Uint8List?> _toPng(ui.PictureRecorder recorder) async {
    final picture = recorder.endRecording();
    final image = await picture.toImage(_pageWidth.toInt(), _pageHeight.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }

  /// Draws one row of the table. The first [alignRightUpTo] cells are the
  /// text columns and read right-to-left; the rest are numbers, centred.
  void _paintRow(
    Canvas canvas,
    List<String> cells,
    List<double> widths, {
    required double left,
    required double top,
    required double height,
    required double size,
    required Color color,
    required Color border,
    int alignRightUpTo = 0,
    Color? fill,
    bool bold = false,
  }) {
    var x = left;
    for (var i = 0; i < cells.length; i++) {
      final width = widths[i];
      final rect = Rect.fromLTWH(x, top, width, height);
      if (fill != null) {
        canvas.drawRect(rect, Paint()..color = fill);
      }
      canvas.drawRect(
        rect,
        Paint()
          ..color = border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      if (cells[i].isNotEmpty) {
        _paint(
          canvas,
          cells[i],
          left: x + (i < alignRightUpTo ? 8 : 0),
          top: top + (height - (size + 4)) / 2,
          width: i < alignRightUpTo ? width - 16 : width,
          size: size,
          bold: bold,
          color: color,
          align: i < alignRightUpTo ? TextAlign.right : TextAlign.center,
        );
      }
      x += width;
    }
  }

  /// Lays a single line of text out with Flutter's own text engine, which is
  /// what gets Arabic shaping and bidi right.
  void _paint(
    Canvas canvas,
    String text, {
    required double left,
    required double top,
    required double width,
    required double size,
    required Color color,
    bool bold = false,
    TextAlign align = TextAlign.right,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.rtl,
      textAlign: align,
      maxLines: 1,
      ellipsis: '\u2026',
    )..layout(maxWidth: width);

    var dx = left;
    if (align == TextAlign.right) {
      dx = left + width - painter.width;
    } else if (align == TextAlign.center) {
      dx = left + (width - painter.width) / 2;
    }
    painter.paint(canvas, Offset(dx, top));
  }

  String _name(String ar, String en) => ar.trim().isNotEmpty ? ar : en;

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _number(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

  String _stamp(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
