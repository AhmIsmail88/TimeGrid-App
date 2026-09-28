import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/localization/gen/app_localizations.dart';
import '../../../core/models/office.dart';
import '../../../core/models/project.dart';
import '../../../core/providers/providers.dart';

class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  String _query = '';
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).languageCode;
    final projectsAsync = ref.watch(projectsProvider);
    final offices = ref.watch(officesProvider).value ?? const <Office>[];
    final officeNames = <int, String>{
      for (final office in offices) office.id!: office.displayName(locale),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.projects),
        actions: [
          IconButton(
            icon: Icon(_showArchived ? Icons.visibility : Icons.visibility_off_outlined),
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
              decoration: InputDecoration(hintText: l10n.search, prefixIcon: const Icon(Icons.search)),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: projectsAsync.when(
              data: (all) {
                final filtered = all.where((p) {
                  if (!_showArchived && p.isArchived) return false;
                  if (_query.isEmpty) return true;
                  final q = _query.toLowerCase();
                  return p.nameAr.toLowerCase().contains(q) || p.nameEn.toLowerCase().contains(q);
                }).toList();

                if (filtered.isEmpty) return Center(child: Text(l10n.noProjectsYet));

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final project = filtered[index];
                    final officeName =
                        project.officeId == null ? null : officeNames[project.officeId!];
                    final status =
                        project.isArchived ? l10n.archived : l10n.active;
                    return Card(
                      child: ListTile(
                        title: Text(project.displayName(locale)),
                        // Which office this project is for, so the list
                        // shows the relationship without opening anything.
                        subtitle: Text(
                          officeName == null ? status : '$officeName \u00b7 $status',
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) => _handleAction(action, project, l10n),
                          itemBuilder: (context) => [
                            PopupMenuItem(value: 'edit', child: Text(l10n.edit)),
                            PopupMenuItem(
                              value: 'archive',
                              child: Text(project.isArchived ? l10n.unarchive : l10n.archive),
                            ),
                          ],
                        ),
                        onTap: () => _showEditDialog(project, l10n),
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
        label: Text(l10n.addProject),
        onPressed: () => _showEditDialog(null, l10n),
      ),
    );
  }

  Future<void> _handleAction(String action, Project project, AppLocalizations l10n) async {
    if (action == 'edit') {
      _showEditDialog(project, l10n);
    } else if (action == 'archive') {
      await ref.read(projectRepositoryProvider).setArchived(project.id!, !project.isArchived);
      ref.read(dataVersionProvider.notifier).state++;
    }
  }

  Future<void> _showEditDialog(Project? existing, AppLocalizations l10n) async {
    final locale = Localizations.localeOf(context).languageCode;
    final arController = TextEditingController(text: existing?.nameAr ?? '');
    final enController = TextEditingController(text: existing?.nameEn ?? '');
    final offices = await ref
        .read(officeRepositoryProvider)
        .getAll(includeArchived: false);
    if (!mounted) return;
    var selectedOfficeId = existing?.officeId;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? l10n.addProject : l10n.edit),
          content: SingleChildScrollView(
            child: Column(
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
                const SizedBox(height: 16),
                // A project is delivered for one consulting office; that is
                // what later scopes the project list and the report.
                DropdownButtonFormField<int?>(
                  initialValue: selectedOfficeId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l10n.office),
                  items: [
                    DropdownMenuItem<int?>(
                      value: null,
                      child: Text(l10n.noOffice),
                    ),
                    for (final office in offices)
                      DropdownMenuItem<int?>(
                        value: office.id,
                        child: Text(office.displayName(locale)),
                      ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => selectedOfficeId = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancel)),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.save)),
          ],
        ),
      ),
    );

    if (result != true) return;
    final ar = arController.text.trim();
    final en = enController.text.trim();
    if (ar.isEmpty && en.isEmpty) return;

    final now = DateTime.now().toIso8601String();
    final repo = ref.read(projectRepositoryProvider);
    if (existing == null) {
      await repo.insert(Project(
        officeId: selectedOfficeId,
        nameAr: ar,
        nameEn: en,
        createdAt: now,
        updatedAt: now,
      ));
    } else {
      // Built by hand rather than copyWith, so clearing the office back to
      // "none" is actually possible.
      await repo.update(Project(
        id: existing.id,
        officeId: selectedOfficeId,
        nameAr: ar,
        nameEn: en,
        isArchived: existing.isArchived,
        createdAt: existing.createdAt,
        updatedAt: now,
      ));
    }
    ref.read(dataVersionProvider.notifier).state++;
  }
}
