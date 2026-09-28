class AppSettings {
  final String languageCode; // 'ar' or 'en'
  final String employeeName;
  final int reportingCycleStartDay; // 1..28
  final String? excelTemplatePath;

  /// When true, opening the app asks for the device's biometric or screen
  /// lock before showing any of the stored work.
  final bool appLockEnabled;

  const AppSettings({
    this.languageCode = 'ar',
    this.employeeName = '',
    this.reportingCycleStartDay = 1,
    this.excelTemplatePath,
    this.appLockEnabled = false,
  });

  AppSettings copyWith({
    String? languageCode,
    String? employeeName,
    int? reportingCycleStartDay,
    String? excelTemplatePath,
    bool? appLockEnabled,
  }) {
    return AppSettings(
      languageCode: languageCode ?? this.languageCode,
      employeeName: employeeName ?? this.employeeName,
      reportingCycleStartDay:
          reportingCycleStartDay ?? this.reportingCycleStartDay,
      excelTemplatePath: excelTemplatePath ?? this.excelTemplatePath,
      appLockEnabled: appLockEnabled ?? this.appLockEnabled,
    );
  }

  Map<String, String> toKeyValueMap() {
    return {
      'language_code': languageCode,
      'employee_name': employeeName,
      'reporting_cycle_start_day': reportingCycleStartDay.toString(),
      if (excelTemplatePath != null) 'excel_template_path': excelTemplatePath!,
      'app_lock_enabled': appLockEnabled ? '1' : '0',
    };
  }

  factory AppSettings.fromKeyValueMap(Map<String, String> map) {
    return AppSettings(
      languageCode: map['language_code'] ?? 'ar',
      employeeName: map['employee_name'] ?? '',
      reportingCycleStartDay:
          int.tryParse(map['reporting_cycle_start_day'] ?? '') ?? 1,
      excelTemplatePath: map['excel_template_path'],
      // Absent on databases written before the lock existed, which is
      // exactly the "off" default.
      appLockEnabled: map['app_lock_enabled'] == '1',
    );
  }
}
