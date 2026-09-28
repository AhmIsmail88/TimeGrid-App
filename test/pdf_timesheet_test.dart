import 'package:flutter_test/flutter_test.dart';
import 'package:timegrid/core/models/reporting_period.dart';
import 'package:timegrid/features/reports/data/pdf_timesheet_exporter.dart';
import 'package:timegrid/features/reports/domain/report_calculator.dart';

/// The printable timesheet is painted with Flutter's own text engine and
/// embedded in the PDF as an image (see [PdfTimesheetExporter] for why).
/// These tests pin the page down: that a real PDF comes out, and that the
/// page is the expected A4-landscape size.
void main() {
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

  ReportData sampleData({bool empty = false}) => ReportData(
        period: ReportingPeriod(
          start: DateTime(2026, 8, 21),
          end: DateTime(2026, 9, 20),
        ),
        rows: empty
            ? const []
            : [
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
                  taskNameAr: 'تعديل مقايسة و RFQ',
                  taskNameEn: '',
                  hoursByDate: const {'2026-09-01': 2.0},
                ),
              ],
      );

  Future<List<int>?> pdf({bool empty = false}) =>
      const PdfTimesheetExporter().buildPdf(
        data: sampleData(empty: empty),
        labels: labels,
        officeName: 'مكتب الاستشاري',
        employeeName: 'أحمد',
        periodText: '21 أغسطس 2026 - 20 سبتمبر 2026',
        generatedAt: DateTime(2026, 9, 28),
      );

  /// Reads a big-endian 32-bit value out of the PNG header.
  int be32(List<int> bytes, int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];

  test('a real PDF comes out, not an empty stub', () async {
    final bytes = await pdf();

    expect(bytes, isNotNull, reason: 'the page could not be rendered');
    expect(bytes!.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]); // %PDF
    expect(bytes.length, greaterThan(5000));
  });

  test('the page is painted at A4 landscape pixel size', () async {
    final png = await const PdfTimesheetExporter().renderPagePng(
      data: sampleData(),
      labels: labels,
      officeName: 'مكتب الاستشاري',
      employeeName: 'أحمد',
      periodText: '21 أغسطس 2026 - 20 سبتمبر 2026',
      generatedAt: DateTime(2026, 9, 28),
    );

    expect(png, isNotNull);
    expect(png!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]); // PNG magic
    expect(be32(png, 16), 2105, reason: '180 dpi across an A4 landscape page');
    expect(be32(png, 20), 1489);
  });

  test('an empty period still produces a page rather than failing', () async {
    final bytes = await pdf(empty: true);

    expect(bytes, isNotNull);
    expect(bytes!.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]);
  });
}
