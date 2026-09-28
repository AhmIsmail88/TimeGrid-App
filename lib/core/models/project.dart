class Project {
  final int? id;

  /// The consulting office / client this project is delivered for. Nullable
  /// because projects created before the office feature existed have none.
  final int? officeId;

  final String nameAr;
  final String nameEn;
  final bool isArchived;
  final String createdAt;
  final String updatedAt;

  const Project({
    this.id,
    this.officeId,
    required this.nameAr,
    required this.nameEn,
    this.isArchived = false,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Returns the name for the given locale, falling back to whichever
  /// name is available if the preferred one is empty.
  String displayName(String localeCode) {
    final ar = nameAr.trim();
    final en = nameEn.trim();
    if (localeCode == 'ar') {
      return ar.isNotEmpty ? ar : en;
    }
    return en.isNotEmpty ? en : ar;
  }

  Project copyWith({
    int? id,
    int? officeId,
    String? nameAr,
    String? nameEn,
    bool? isArchived,
    String? createdAt,
    String? updatedAt,
  }) {
    return Project(
      id: id ?? this.id,
      officeId: officeId ?? this.officeId,
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
      'office_id': officeId,
      'name_ar': nameAr,
      'name_en': nameEn,
      'is_archived': isArchived ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory Project.fromMap(Map<String, Object?> map) {
    return Project(
      id: map['id'] as int?,
      officeId: map['office_id'] as int?,
      nameAr: (map['name_ar'] as String?) ?? '',
      nameEn: (map['name_en'] as String?) ?? '',
      isArchived: (map['is_archived'] as int? ?? 0) == 1,
      createdAt: map['created_at'] as String? ?? '',
      updatedAt: map['updated_at'] as String? ?? '',
    );
  }
}
