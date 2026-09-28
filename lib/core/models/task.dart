class TimeTask {
  final int? id;
  final String nameAr;
  final String nameEn;
  final bool isArchived;
  final String createdAt;
  final String updatedAt;

  const TimeTask({
    this.id,
    required this.nameAr,
    required this.nameEn,
    this.isArchived = false,
    required this.createdAt,
    required this.updatedAt,
  });

  String displayName(String localeCode) {
    final ar = nameAr.trim();
    final en = nameEn.trim();
    if (localeCode == 'ar') {
      return ar.isNotEmpty ? ar : en;
    }
    return en.isNotEmpty ? en : ar;
  }

  TimeTask copyWith({
    int? id,
    String? nameAr,
    String? nameEn,
    bool? isArchived,
    String? createdAt,
    String? updatedAt,
  }) {
    return TimeTask(
      id: id ?? this.id,
      nameAr: nameAr ?? this.nameAr,
      nameEn: nameEn ?? this.nameEn,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name_ar': nameAr,
      'name_en': nameEn,
      'is_archived': isArchived ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory TimeTask.fromMap(Map<String, Object?> map) {
    return TimeTask(
      id: map['id'] as int?,
      nameAr: (map['name_ar'] as String?) ?? '',
      nameEn: (map['name_en'] as String?) ?? '',
      isArchived: (map['is_archived'] as int? ?? 0) == 1,
      createdAt: map['created_at'] as String? ?? '',
      updatedAt: map['updated_at'] as String? ?? '',
    );
  }
}
