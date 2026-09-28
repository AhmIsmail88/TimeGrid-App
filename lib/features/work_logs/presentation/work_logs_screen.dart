import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/localization/gen/app_localizations.dart';
import '../../../core/models/locked_period.dart';
import '../../../core/models/work_log.dart';
import '../../../core/providers/providers.dart';
import '../../../core/utils/bidi.dart';
import '../../../core/repositories/work_log_repository.dart';
import '../../../core/widgets/week_strip.dart';
import 'widgets/work_log_card.dart';

final _workLogsFilterProvider = StateProvider<WorkLogFilter>((ref) {
  return const WorkLogFilter();
});

final _filteredWorkLogsProvider = FutureProvider<List<WorkLogView>>((ref) {
  ref.watch(dataVersionProvider);
  final filter = ref.watch(_workLogsFilterProvider);
  return ref.read(workLogRepositoryProvider).getFiltered(filter);
});

class WorkLogsScreen extends ConsumerStatefulWidget {
  const WorkLogsScreen({super.key});

  @override
  ConsumerState<WorkLogsScreen> createState() => _WorkLogsScreenState();
}

class _WorkLogsScreenState extends ConsumerState<WorkLogsScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilter(WorkLogFilter Function(WorkLogFilter) update) {
    final current = ref.read(_workLogsFilterProvider);
    ref.read(_workLogsFilterProvider.notifier).state = update(current);
  }

  /// Tapping the already-selected day clears the day filter again; tapping
  /// any other day narrows the list to just that day.
  void _selectDay(DateTime day) {
    final current = ref.read(_workLogsFilterProvider);
    final start = current.periodStart;
    final alreadyThatDay = start != null &&
        current.periodEnd != null &&
        start.year == day.year &&
        start.month == day.month &&
        start.day == day.day;
    _applyFilter((f) => WorkLogFilter(
          periodStart: alreadyThatDay ? null : day,
          periodEnd: alreadyThatDay ? null : day,
          projectId: f.projectId,
          taskId: f.taskId,
          searchText: f.searchText,
          newestFirst: f.newestFirst,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).languageCode;
    final logs = ref.watch(_filteredWorkLogsProvider);
    final filter = ref.watch(_workLogsFilterProvider);
    // One read for the whole screen: the chip on each card is decided in
    // memory instead of one database call per row.
    final lockedPeriods =
        ref.watch(lockedPeriodsProvider).value ?? const <LockedPeriod>[];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.workLogs)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.search,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: filter.searchText == null && filter.projectId == null && filter.taskId == null
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(_workLogsFilterProvider.notifier).state = const WorkLogFilter();
                        },
                      ),
              ),
              onChanged: (v) => _applyFilter((f) => WorkLogFilter(
                    periodStart: f.periodStart,
                    periodEnd: f.periodEnd,
                    projectId: f.projectId,
                    taskId: f.taskId,
                    searchText: v,
                    newestFirst: f.newestFirst,
                  )),
            ),
          ),
          WeekStrip(
            selectedDate: filter.periodStart,
            onDaySelected: _selectDay,
          ),
          if (filter.periodStart != null || filter.periodEnd != null)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 0),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: ActionChip(
                  label: Text(l10n.allDays),
                  onPressed: () => _applyFilter((f) => WorkLogFilter(
                        projectId: f.projectId,
                        taskId: f.taskId,
                        searchText: f.searchText,
                        newestFirst: f.newestFirst,
                      )),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: TextButton.icon(
                  icon: Icon(filter.newestFirst ? Icons.arrow_downward : Icons.arrow_upward, size: 16),
                  label: Text(filter.newestFirst ? l10n.sortNewestFirst : l10n.sortOldestFirst,
                      overflow: TextOverflow.ellipsis),
                  onPressed: () => _applyFilter((f) => WorkLogFilter(
                        periodStart: f.periodStart,
                        periodEnd: f.periodEnd,
                        projectId: f.projectId,
                        taskId: f.taskId,
                        searchText: f.searchText,
                        newestFirst: !f.newestFirst,
                      )),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: TextButton(
                    onPressed: () {
                      _searchController.clear();
                      ref.read(_workLogsFilterProvider.notifier).state =
                          const WorkLogFilter();
                    },
                    child: Text(l10n.clearFilters,
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: logs.when(
              data: (items) {
                if (items.isEmpty) {
                  return Center(child: Text(l10n.noEntriesYet));
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 88),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final view = items[index];
                    final workDate = DateTime.parse(view.log.workDate);
                    return WorkLogCard(
                      view: view,
                      locale: locale,
                      isLocked: lockedPeriods.any((p) => p.contains(workDate)),
                      onTap: () => context.push('/edit-entry/${view.log.id}'),
                      onDelete: () => _confirmDelete(context, view, l10n, locale),
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
        onPressed: () => context.push('/add-entry'),
        icon: const Icon(Icons.add),
        label: Text(l10n.addEntry),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WorkLogView view, AppLocalizations l10n, String locale) async {
    // A sent report must keep matching what the office received.
    final locked = await ref
        .read(periodLockRepositoryProvider)
        .findForDate(DateTime.parse(view.log.workDate));
    if (locked != null) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.periodLockedTitle),
          content: Text(l10n.periodLockedMessage),
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

    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteEntryTitle),
        content: Text(l10n.deleteEntryMessage(
          view.taskName(locale),
          ltrRun(DateFormat('d MMM yyyy').format(DateTime.parse(view.log.workDate))),
          view.log.hours.toString(),
        )),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final repository = ref.read(workLogRepositoryProvider);
    final deleted = view.log;
    await repository.delete(deleted.id!);
    ref.read(dataVersionProvider.notifier).state++;
    // `context` is the caller's, so it needs its own guard.
    if (!context.mounted) return;

    // Deleting is the one action that removes data for good, so it stays
    // reversible straight from the list instead of relying on the user
    // having taken a backup.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.entryDeleted),
          action: SnackBarAction(
            label: l10n.undo,
            onPressed: () async {
              await repository.restore(deleted);
              if (mounted) {
                ref.read(dataVersionProvider.notifier).state++;
              }
            },
          ),
        ),
      );
  }
}
