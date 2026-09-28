import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../app/localization/gen/app_localizations.dart';
import '../../../app/theme.dart';
import '../../../core/models/office.dart';
import '../../../core/providers/providers.dart';
import '../../../core/utils/bidi.dart';
import '../../../core/widgets/office_picker.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).languageCode;
    final period = ref.watch(selectedPeriodProvider);
    final totalHours = ref.watch(periodTotalHoursProvider);
    final entryCount = ref.watch(periodEntryCountProvider);
    final dailyHours = ref.watch(periodDailyHoursProvider);
    final topProjects = ref.watch(periodTopProjectsProvider);
    final recent = ref.watch(recentEntriesProvider);

    final periodLabel = ltrRun(
        '${DateFormat('d MMM').format(period.start)} \u2013 ${DateFormat('d MMM').format(period.end)}');

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.grid_view_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(l10n.appTitle,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.read(dataVersionProvider.notifier).state++,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // --- period, with the headline numbers -----------------------
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(Icons.calendar_month_outlined,
                                  size: 16, color: Theme.of(context).hintColor),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(l10n.currentPeriod,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                              ),
                            ],
                          ),
                        ),
                        // Which consulting office these numbers belong to.
                        // Reports are per office, so the Dashboard follows the
                        // same scope and the two always agree.
                        ActionChip(
                          avatar: const Icon(Icons.business_outlined, size: 16),
                          label: Text(_scopeLabel(context, ref, l10n, locale)),
                          onPressed: () async {
                            final chosen = await pickOffice(
                              context,
                              ref,
                              l10n,
                              current: ref.read(reportOfficeProvider),
                              allowAll: true,
                            );
                            if (chosen == null) return;
                            ref.read(reportOfficeProvider.notifier).state =
                                chosen == allOffices ? null : chosen;
                          },
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            periodLabel,
                            key: const ValueKey('dashboardPeriodLabel'),
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          tooltip: l10n.previousPeriod,
                          onPressed: () => _shiftPeriod(ref, -1),
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_forward),
                          tooltip: l10n.nextPeriod,
                          onPressed: () => _shiftPeriod(ref, 1),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _Stat(
                            icon: Icons.schedule_outlined,
                            label: l10n.totalHours,
                            value: totalHours.when(
                              data: (v) => v.toStringAsFixed(2),
                              loading: () => '\u2026',
                              error: (_, __) => '\u2014',
                            ),
                          ),
                        ),
                        Expanded(
                          child: _Stat(
                            icon: Icons.list_alt_outlined,
                            label: l10n.entriesCount,
                            value: entryCount.when(
                              data: (v) => v.toString(),
                              loading: () => '\u2026',
                              error: (_, __) => '\u2014',
                            ),
                          ),
                        ),
                        Expanded(
                          child: _Stat(
                            icon: Icons.trending_up_outlined,
                            label: l10n.averagePerDay,
                            value: totalHours.when(
                              data: (v) => period.dayCount == 0
                                  ? '0.00'
                                  : (v / period.dayCount).toStringAsFixed(2),
                              loading: () => '\u2026',
                              error: (_, __) => '\u2014',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // --- how the period is spread over its days -------------------
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.dailyHours,
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 14),
                    dailyHours.when(
                      data: (byDate) => _DailyBars(
                        days: period.allDates,
                        hoursByDate: byDate,
                      ),
                      loading: () => const SizedBox(
                          height: 96,
                          child: Center(child: CircularProgressIndicator())),
                      error: (e, _) => Text('$e'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // --- where the hours actually went ----------------------------
            topProjects.maybeWhen(
              data: (projects) => projects.isEmpty
                  ? const SizedBox.shrink()
                  : Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l10n.topProjects,
                                style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 12),
                            for (final project in projects)
                              _ProjectBar(
                                label: project.displayName(locale),
                                hours: project.hours,
                                share: projects.first.hours == 0
                                    ? 0
                                    : project.hours / projects.first.hours,
                              ),
                          ],
                        ),
                      ),
                    ),
              orElse: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: 18),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: Text(l10n.addEntry),
                onPressed: () => context.push('/add-entry'),
              ),
            ),
            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: Text(l10n.recentEntries,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                TextButton(
                  onPressed: () => context.push('/work-logs'),
                  child: Text(l10n.workLogs),
                ),
              ],
            ),
            recent.when(
              data: (items) {
                if (items.isEmpty) {
                  return _EmptyState(
                    title: l10n.noEntriesYet,
                    hint: l10n.noEntriesHint,
                  );
                }
                return Column(
                  children: items.map((view) {
                    final date = DateTime.parse(view.log.workDate);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(view.taskName(locale)),
                        subtitle: Text(
                            '${view.projectName(locale)} \u00b7 ${ltrRun(DateFormat('d MMM').format(date))}'),
                        trailing: Text(
                          '${view.log.hours}h',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onTap: () => context.push('/edit-entry/${view.log.id}'),
                      ),
                    );
                  }).toList(),
                );
              },
              loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Text('$e'),
            ),
            const SizedBox(height: 24),
            _NavRow(l10n: l10n),
          ],
        ),
      ),
    );
  }
}

/// "All offices", or the name of the one the numbers are currently for.
String _scopeLabel(BuildContext context, WidgetRef ref, AppLocalizations l10n,
    String locale) {
  final id = ref.watch(reportOfficeProvider);
  if (id == null) return l10n.allOffices;
  for (final office in ref.watch(officesProvider).value ?? const <Office>[]) {
    if (office.id == id) return office.displayName(locale);
  }
  return l10n.allOffices;
}

/// Moves the period shown on the Dashboard one cycle back or forward, so
/// checking "how am I doing this cycle" does not require a trip through
/// the Reports screen. `Icons.arrow_back` / `arrow_forward` are
/// text-direction aware, so they read correctly in Arabic and English.
void _shiftPeriod(WidgetRef ref, int direction) {
  final calculator = ref.read(periodCalculatorProvider);
  final current = ref.read(selectedPeriodProvider);
  ref.read(selectedPeriodProvider.notifier).moveTo(direction < 0
      ? calculator.previousPeriod(current)
      : calculator.nextPeriod(current));
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 6),
        Text(value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// One bar per day of the period, so busy stretches are obvious at a glance
/// without opening the Reports screen.
class _DailyBars extends StatelessWidget {
  const _DailyBars({required this.days, required this.hoursByDate});

  final List<DateTime> days;
  final Map<String, double> hoursByDate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final peak = hoursByDate.values.isEmpty
        ? 0.0
        : hoursByDate.values.reduce(math.max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 84,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final day in days)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Tooltip(
                      message:
                          '${ltrRun(DateFormat('d MMM').format(day))}: ${(hoursByDate[_isoDate(day)] ?? 0).toStringAsFixed(1)}',
                      child: Container(
                        height: peak == 0
                            ? 3
                            : 4 + 76 * ((hoursByDate[_isoDate(day)] ?? 0) / peak),
                        decoration: BoxDecoration(
                          color: (hoursByDate[_isoDate(day)] ?? 0) == 0
                              ? scheme.outlineVariant
                              : scheme.primary,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(ltrRun(DateFormat('d MMM').format(days.first)),
                style: Theme.of(context).textTheme.bodySmall),
            Text(ltrRun(DateFormat('d MMM').format(days.last)),
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ],
    );
  }
}

class _ProjectBar extends StatelessWidget {
  const _ProjectBar({
    required this.label,
    required this.hours,
    required this.share,
  });

  final String label;
  final double hours;

  /// Fraction of the largest project's hours, 0..1.
  final double share;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
              const SizedBox(width: 8),
              Text('${hours.toStringAsFixed(2)}h',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: share.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: scheme.outlineVariant,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String hint;
  const _EmptyState({required this.title, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const Icon(Icons.inbox_outlined, size: 40, color: AppColors.border),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(hint,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final AppLocalizations l10n;
  const _NavRow({required this.l10n});

  @override
  Widget build(BuildContext context) {
    Widget navCard(String label, IconData icon, String route) {
      final scheme = Theme.of(context).colorScheme;
      return Expanded(
        child: Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.push(route),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Icon(icon, color: scheme.primary),
                  const SizedBox(height: 6),
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            navCard(l10n.offices, Icons.business_outlined, '/offices'),
            const SizedBox(width: 8),
            navCard(l10n.projects, Icons.folder_outlined, '/projects'),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            navCard(l10n.tasks, Icons.task_alt_outlined, '/tasks'),
            const SizedBox(width: 8),
            navCard(l10n.reports, Icons.summarize_outlined, '/reports'),
          ],
        ),
      ],
    );
  }
}
