/// One exported timesheet: which office and period it covered, and where the
/// file went. It is the record that answers "did I already send September?"
/// without hunting through the file system.
class ExportRecord {
  final int? id;
  final int? officeId;
  final String officeName;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String fileName;
  final String filePath;

  /// 'xlsx', 'xls' or 'pdf'.
  final String format;
  final String exportedAt;

  const ExportRecord({
    this.id,
    this.officeId,
    required this.officeName,
    required this.periodStart,
    required this.periodEnd,
    required this.fileName,
    required this.filePath,
    required this.format,
    required this.exportedAt,
  });

  Map<String, Object?> toMap() {
    String iso(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return {
      'id': id,
      'office_id': officeId,
      'office_name': officeName,
      'period_start': iso(periodStart),
      'period_end': iso(periodEnd),
      'file_name': fileName,
      'file_path': filePath,
      'format': format,
      'exported_at': exportedAt,
    };
  }

  factory ExportRecord.fromMap(Map<String, Object?> map) {
    return ExportRecord(
      id: map['id'] as int?,
      officeId: map['office_id'] as int?,
      officeName: (map['office_name'] as String?) ?? '',
      periodStart: DateTime.parse(map['period_start'] as String),
      periodEnd: DateTime.parse(map['period_end'] as String),
      fileName: (map['file_name'] as String?) ?? '',
      filePath: (map['file_path'] as String?) ?? '',
      format: (map['format'] as String?) ?? '',
      exportedAt: (map['exported_at'] as String?) ?? '',
    );
  }
}
