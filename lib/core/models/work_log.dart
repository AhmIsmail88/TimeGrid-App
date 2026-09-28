/// A single work-log entry: one project + one task + one date + hours.
/// Multiple entries with the same project/task/date are intentionally
/// allowed to remain as separate rows (they represent separate work
/// sessions); aggregation happens only at summary/export time.
class WorkLog {
  final int? id;
  final int projectId;
  final int taskId;
  final String workDate; // ISO 'YYYY-MM-DD'
  final double hours;
  final String? notes;
  final String createdAt;
  final String updatedAt;

  const WorkLog({
    this.id,
    required this.projectId,
    required this.taskId,
    required this.workDate,
    required this.hours,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  WorkLog copyWith({
    int? id,
    int? projectId,
    int? taskId,
    String? workDate,
    double? hours,
    String? notes,
    String? createdAt,
    String? updatedAt,
  }) {
    return WorkLog(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      taskId: taskId ?? this.taskId,
      workDate: workDate ?? this.workDate,
      hours: hours ?? this.hours,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'project_id': projectId,
      'task_id': taskId,
      'work_date': workDate,
      'hours': hours,
      'notes': notes,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory WorkLog.fromMap(Map<String, Object?> map) {
    return WorkLog(
      id: map['id'] as int?,
      projectId: map['project_id'] as int,
      taskId: map['task_id'] as int,
      workDate: map['work_date'] as String,
      hours: (map['hours'] as num).toDouble(),
      notes: map['notes'] as String?,
      createdAt: map['created_at'] as String? ?? '',
      updatedAt: map['updated_at'] as String? ?? '',
    );
  }
}

/// A joined view row used by the Work Logs list screen, so the UI never
/// has to re-look-up project/task names per row.
class WorkLogView {
  final WorkLog log;
  final String projectNameAr;
  final String projectNameEn;
  final String taskNameAr;
  final String taskNameEn;

  const WorkLogView({
    required this.log,
    required this.projectNameAr,
    required this.projectNameEn,
    required this.taskNameAr,
    required this.taskNameEn,
  });

  String projectName(String localeCode) =>
      localeCode == 'ar'
          ? (projectNameAr.isNotEmpty ? projectNameAr : projectNameEn)
          : (projectNameEn.isNotEmpty ? projectNameEn : projectNameAr);

  String taskName(String localeCode) =>
      localeCode == 'ar'
          ? (taskNameAr.isNotEmpty ? taskNameAr : taskNameEn)
          : (taskNameEn.isNotEmpty ? taskNameEn : taskNameAr);
}
