import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/localization/gen/app_localizations.dart';
import '../../../core/models/task.dart';
import '../../../core/providers/providers.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  String _query = '';
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).languageCode;
    final tasksAsync = ref.watch(tasksProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tasks),
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
            child: tasksAsync.when(
              data: (all) {
                final filtered = all.where((t) {
                  if (!_showArchived && t.isArchived) return false;
                  if (_query.isEmpty) return true;
                  final q = _query.toLowerCase();
                  return t.nameAr.toLowerCase().contains(q) || t.nameEn.toLowerCase().contains(q);
                }).toList();

                if (filtered.isEmpty) return Center(child: Text(l10n.noTasksYet));

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final task = filtered[index];
                    return Card(
                      child: ListTile(
                        title: Text(task.displayName(locale)),
                        subtitle: Text(task.isArchived ? l10n.archived : l10n.active),
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) => _handleAction(action, task, l10n),
                          itemBuilder: (context) => [
                            PopupMenuItem(value: 'edit', child: Text(l10n.edit)),
                            PopupMenuItem(
                              value: 'archive',
                              child: Text(task.isArchived ? l10n.unarchive : l10n.archive),
                            ),
                          ],
                        ),
                        onTap: () => _showEditDialog(task, l10n),
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
        label: Text(l10n.addTask),
        onPressed: () => _showEditDialog(null, l10n),
      ),
    );
  }

  Future<void> _handleAction(String action, TimeTask task, AppLocalizations l10n) async {
    if (action == 'edit') {
      _showEditDialog(task, l10n);
    } else if (action == 'archive') {
      await ref.read(taskRepositoryProvider).setArchived(task.id!, !task.isArchived);
      ref.read(dataVersionProvider.notifier).state++;
    }
  }

  Future<void> _showEditDialog(TimeTask? existing, AppLocalizations l10n) async {
    final arController = TextEditingController(text: existing?.nameAr ?? '');
    final enController = TextEditingController(text: existing?.nameEn ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? l10n.addTask : l10n.edit),
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
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.save)),
        ],
      ),
    );

    if (result != true) return;
    final ar = arController.text.trim();
    final en = enController.text.trim();
    if (ar.isEmpty && en.isEmpty) return;

    final now = DateTime.now().toIso8601String();
    final repo = ref.read(taskRepositoryProvider);
    if (existing == null) {
      await repo.insert(TimeTask(nameAr: ar, nameEn: en, createdAt: now, updatedAt: now));
    } else {
      await repo.update(existing.copyWith(nameAr: ar, nameEn: en, updatedAt: now));
    }
    ref.read(dataVersionProvider.notifier).state++;
  }
}
