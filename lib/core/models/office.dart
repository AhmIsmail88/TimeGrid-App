/// A consulting office (or client) the user delivers work for.
///
/// Projects are attached to exactly one office, and timesheets are produced
/// per office rather than as one global report, because each office wants to
/// see only its own work.
class Office {
  final int? id;
  final String nameAr;
  final String nameEn;

  /// Where the produced timesheet is sent. All three are optional: an office
  /// that is only used for reporting does not need any of them, and rows
  /// written before they existed simply have none.
  final String email;
  final String phone;

  /// The number WhatsApp should be used for. Empty means "same as [phone]",
  /// which is what the form fills in for the common case.
  final String whatsapp;

  final bool isArchived;
  final String createdAt;
  final String updatedAt;

  const Office({
    this.id,
    required this.nameAr,
    required this.nameEn,
    this.email = '',
    this.phone = '',
    this.whatsapp = '',
    this.isArchived = false,
    required this.createdAt,
    required this.updatedAt,
  });

  /// The name for the given locale, falling back to whichever name exists.
  String displayName(String localeCode) {
    final ar = nameAr.trim();
    final en = nameEn.trim();
    if (localeCode == 'ar') {
      return ar.isNotEmpty ? ar : en;
    }
    return en.isNotEmpty ? en : ar;
  }

  /// The number to send WhatsApp to: the dedicated one when it is set,
  /// otherwise the office's phone number.
  String get whatsappNumber => whatsapp.trim().isNotEmpty ? whatsapp.trim() : phone.trim();

  /// One-line contact summary for the list, or an empty string when the
  /// office has no contact details yet.
  String get contactSummary {
    final parts = <String>[
      if (email.trim().isNotEmpty) email.trim(),
      if (whatsappNumber.isNotEmpty) whatsappNumber,
    ];
    return parts.join(' \u00b7 ');
  }

  Office copyWith({
    int? id,
    String? nameAr,
    String? nameEn,
    String? email,
    String? phone,
    String? whatsapp,
    bool? isArchived,
    String? createdAt,
    String? updatedAt,
  }) {
    return Office(
      id: id ?? this.id,
      nameAr: nameAr ?? this.nameAr,
      nameEn: nameEn ?? this.nameEn,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      whatsapp: whatsapp ?? this.whatsapp,
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
      // Stored as NULL rather than '' when unused, so "no value" has one
      // representation in the file.
      'email': email.trim().isEmpty ? null : email.trim(),
      'phone': phone.trim().isEmpty ? null : phone.trim(),
      'whatsapp': whatsapp.trim().isEmpty ? null : whatsapp.trim(),
      'is_archived': isArchived ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory Office.fromMap(Map<String, Object?> map) {
    return Office(
      id: map['id'] as int?,
      nameAr: (map['name_ar'] as String?) ?? '',
      nameEn: (map['name_en'] as String?) ?? '',
      // Absent in databases and backups written before the columns existed,
      // which is exactly the empty default.
      email: (map['email'] as String?) ?? '',
      phone: (map['phone'] as String?) ?? '',
      whatsapp: (map['whatsapp'] as String?) ?? '',
      isArchived: (map['is_archived'] as int? ?? 0) == 1,
      createdAt: map['created_at'] as String? ?? '',
      updatedAt: map['updated_at'] as String? ?? '',
    );
  }
}
