import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/localization/gen/app_localizations.dart';
import '../../../core/models/office.dart';
import '../../../core/providers/providers.dart';

/// The consulting offices / clients the user delivers work for.
///
/// Everything downstream hangs off this list: a project belongs to one
/// office, and a timesheet is produced for one office at a time.
class OfficesScreen extends ConsumerStatefulWidget {
  const OfficesScreen({super.key});

  @override
  ConsumerState<OfficesScreen> createState() => _OfficesScreenState();
}

class _OfficesScreenState extends ConsumerState<OfficesScreen> {
  String _query = '';
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).languageCode;
    final officesAsync = ref.watch(officesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.offices),
        actions: [
          IconButton(
            icon: Icon(
                _showArchived ? Icons.visibility : Icons.visibility_off_outlined),
            tooltip: l10n.archived,
            onPressed: () => setState(() => _showArchived = !_showArchived),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: l10n.search,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: officesAsync.when(
              data: (all) {
                final filtered = all.where((office) {
                  if (!_showArchived && office.isArchived) return false;
                  if (_query.isEmpty) return true;
                  final q = _query.toLowerCase();
                  return office.nameAr.toLowerCase().contains(q) ||
                      office.nameEn.toLowerCase().contains(q);
                }).toList();

                if (filtered.isEmpty) {
                  return Center(child: Text(l10n.noOfficesYet));
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final office = filtered[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.business_outlined),
                        title: Text(office.displayName(locale)),
                        subtitle:
                            Text(office.isArchived ? l10n.archived : l10n.active),
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) =>
                              _handleAction(action, office, l10n),
                          itemBuilder: (context) => [
                            PopupMenuItem(value: 'edit', child: Text(l10n.edit)),
                            PopupMenuItem(
                              value: 'archive',
                              child: Text(
                                  office.isArchived ? l10n.unarchive : l10n.archive),
                            ),
                            PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
                          ],
                        ),
                        onTap: () => _showEditDialog(office, l10n),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(l10n.addOffice),
        onPressed: () => _showEditDialog(null, l10n),
      ),
    );
  }

  Future<void> _handleAction(
      String action, Office office, AppLocalizations l10n) async {
    final repository = ref.read(officeRepositoryProvider);

    if (action == 'edit') {
      await _showEditDialog(office, l10n);
      return;
    }
    if (action == 'archive') {
      await repository.setArchived(office.id!, !office.isArchived);
      ref.read(dataVersionProvider.notifier).state++;
      return;
    }
    if (action == 'delete') {
      final removed = await repository.deleteIfUnused(office.id!);
      if (!removed) {
        // Refusing is the safe answer: projects still point at it, and
        // deleting would orphan their report history.
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.confirmDeleteProjectTitle),
            content: Text(l10n.confirmDeleteOfficeMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.confirm),
              ),
            ],
          ),
        );
        return;
      }
      ref.read(dataVersionProvider.notifier).state++;
    }
  }

  Future<void> _showEditDialog(Office? existing, AppLocalizations l10n) async {
    final arController = TextEditingController(text: existing?.nameAr ?? '');
    final enController = TextEditingController(text: existing?.nameEn ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? l10n.addOffice : l10n.edit),
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

    if (result != true) return;
    final ar = arController.text.trim();
    final en = enController.text.trim();
    if (ar.isEmpty && en.isEmpty) return;

    final now = DateTime.now().toIso8601String();
    final repository = ref.read(officeRepositoryProvider);
    if (existing == null) {
      await repository.insert(
          Office(nameAr: ar, nameEn: en, createdAt: now, updatedAt: now));
    } else {
      await repository.update(
          existing.copyWith(nameAr: ar, nameEn: en, updatedAt: now));
    }
    ref.read(dataVersionProvider.notifier).state++;
  }
}
