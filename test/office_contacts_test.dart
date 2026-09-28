import 'package:flutter_test/flutter_test.dart';
import 'package:timegrid/core/models/office.dart';
import 'package:timegrid/core/services/report_sharing.dart';

/// The contact details an office is sent its timesheet through: they have to
/// survive a save/load round-trip, stay optional, and not break rows that
/// were written before they existed.
void main() {
  Office office({
    String email = '',
    String phone = '',
    String whatsapp = '',
  }) =>
      Office(
        id: 3,
        nameAr: 'مكتب السيب',
        nameEn: 'Seeb office',
        email: email,
        phone: phone,
        whatsapp: whatsapp,
        createdAt: '2026-09-01T00:00:00.000',
        updatedAt: '2026-09-01T00:00:00.000',
      );

  test('contact details survive a map round-trip', () {
    final restored = Office.fromMap(office(
      email: 'pm@example.com',
      phone: '+20 100 000 0000',
      whatsapp: '+20 111 111 1111',
    ).toMap());

    expect(restored.email, 'pm@example.com');
    expect(restored.phone, '+20 100 000 0000');
    expect(restored.whatsapp, '+20 111 111 1111');
    expect(restored.whatsappNumber, '+20 111 111 1111');
    expect(restored.nameAr, 'مكتب السيب');
  });

  test('empty contact details are stored as NULL and read back empty', () {
    final map = office().toMap();
    expect(map['email'], isNull);
    expect(map['phone'], isNull);
    expect(map['whatsapp'], isNull);

    final restored = Office.fromMap(map);
    expect(restored.email, '');
    expect(restored.phone, '');
    expect(restored.whatsapp, '');
  });

  test('a row written before the columns existed still loads', () {
    final restored = Office.fromMap(<String, Object?>{
      'id': 1,
      'name_ar': 'مكتب قديم',
      'name_en': 'Legacy office',
      'is_archived': 0,
      'created_at': '2026-08-01T00:00:00.000',
      'updated_at': '2026-08-01T00:00:00.000',
    });

    expect(restored.email, '');
    expect(restored.phone, '');
    expect(restored.whatsapp, '');
    expect(restored.whatsappNumber, '');
    expect(restored.contactSummary, '');
  });

  test('whatsapp falls back to the phone number', () {
    expect(office(phone: '100200').whatsappNumber, '100200');
    expect(office(phone: '100200', whatsapp: '999').whatsappNumber, '999');
  });

  test('contact summary lists what is there', () {
    expect(office(email: 'a@b.com').contactSummary, 'a@b.com');
    expect(office(email: 'a@b.com', phone: '100').contactSummary,
        'a@b.com \u00b7 100');
    expect(office().contactSummary, '');
  });

  group('isValidEmail', () {
    test('accepts empty (the field is optional) and real addresses', () {
      expect(isValidEmail(''), isTrue);
      expect(isValidEmail('  '), isTrue);
      expect(isValidEmail('pm@example.com'), isTrue);
      expect(isValidEmail(' first.last@sub.example.co.uk '), isTrue);
    });

    test('rejects obvious typos', () {
      expect(isValidEmail('not-an-email'), isFalse);
      expect(isValidEmail('@example.com'), isFalse);
      expect(isValidEmail('user@'), isFalse);
      expect(isValidEmail('user@example'), isFalse);
      expect(isValidEmail('user name@example.com'), isFalse);
    });
  });
}
