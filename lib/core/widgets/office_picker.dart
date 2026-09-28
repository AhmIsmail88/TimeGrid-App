import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/localization/gen/app_localizations.dart';
import '../models/office.dart';
import '../providers/providers.dart';
import 'searchable_picker.dart';

/// Asks which consulting office the numbers on screen should be about.
///
/// Returns the chosen office id. A returned value of [allOffices] means "every
/// office", and `null` means the user dismissed the sheet without choosing.
///
/// [allowAll] adds that "all offices" row; Reports always needs one office
/// (a timesheet goes to exactly one of them), while the Dashboard is happy to
/// show everything.
Future<int?> pickOffice(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n, {
  int? current,
  bool allowAll = false,
}) async {
  final locale = Localizations.localeOf(context).languageCode;
  final offices = await ref
      .read(officeRepositoryProvider)
      .getAll(includeArchived: false);
  if (!context.mounted) return null;

  final items = <SearchablePickerItem>[
    if (allowAll)
      SearchablePickerItem(id: allOffices, label: l10n.allOffices),
    for (final office in offices)
      SearchablePickerItem(
          id: office.id!, label: office.displayName(locale)),
  ];

  final result = await showSearchablePicker(
    context: context,
    title: l10n.office,
    items: items,
    addNewLabel: l10n.addOffice,
    searchHint: l10n.search,
    emptyLabel: l10n.noOfficesYet,
  );
  if (result == null) return null;

  if (result.isNew) {
    if (!context.mounted) return null;
    final arController = TextEditingController(text: result.query);
    final enController = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.addOffice),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: arController,
              decoration: InputDecoration(labelText: l10n.arabicName),
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: enController,
              decoration: InputDecoration(labelText: l10n.englishName),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (created != true) return null;

    final ar = arController.text.trim();
    final en = enController.text.trim();
    if (ar.isEmpty && en.isEmpty) return null;

    final now = DateTime.now().toIso8601String();
    final id = await ref.read(officeRepositoryProvider).insert(
        Office(nameAr: ar, nameEn: en, createdAt: now, updatedAt: now));
    ref.read(dataVersionProvider.notifier).state++;
    return id;
  }

  return result.id;
}

/// Sentinel used by [pickOffice] for "all offices". It cannot collide with a
/// real row id, which is always positive.
const int allOffices = -2;
