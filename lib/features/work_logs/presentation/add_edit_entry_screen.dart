import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../app/localization/gen/app_localizations.dart';
import '../../../core/models/office.dart';
import '../../../core/models/project.dart';
import '../../../core/models/task.dart';
import '../../../core/models/work_log.dart';
import '../../../core/providers/providers.dart';
import '../../../core/utils/bidi.dart';
import '../../../core/repositories/work_log_repository.dart';
import '../../../core/widgets/searchable_picker.dart';
import '../../../core/widgets/week_strip.dart';

/// PRD §7.3 / §7.5 — same form for Add and Edit. If [entryId] is null
/// this is Add Entry (date defaults to today); otherwise it loads and
/// edits that existing log in place.
class AddEditEntryScreen extends ConsumerStatefulWidget {
  final int? entryId;
  const AddEditEntryScreen({super.key, this.entryId});

  @override
  ConsumerState<AddEditEntryScreen> createState() => _AddEditEntryScreenState();
}

class _AddEditEntryScreenState extends ConsumerState<AddEditEntryScreen> {
  DateTime _date = DateTime.now();
  int? _officeId;
  String? _officeLabel;
  int? _projectId;
  String? _projectLabel;
  int? _taskId;
  String? _taskLabel;
  final _hoursController = TextEditingController();
  String? _hoursError;
  bool _saving = false;
  bool _loaded = false;

  /// Preserved across edits so updating an entry never overwrites the
  /// original creation timestamp.
  String? _originalCreatedAt;

  static const double _highHoursThreshold = 16;

  @override
  void initState() {
    super.initState();
    if (widget.entryId != null) {
      _loadExisting();
    } else {
      _loaded = true;
    }
  }

  Future<void> _loadExisting() async {
    final log = await ref.read(workLogRepositoryProvider).getById(widget.entryId!);
    if (log == null || !mounted) return;
    final project = await ref.read(projectRepositoryProvider).getById(log.projectId);
    final task = await ref.read(taskRepositoryProvider).getById(log.taskId);
    final office = project?.officeId == null
        ? null
        : await ref.read(officeRepositoryProvider).getById(project!.officeId!);
    if (!mounted) return;
    final locale = Localizations.localeOf(context).languageCode;
    setState(() {
      _originalCreatedAt = log.createdAt;
      _officeId = project?.officeId;
      _officeLabel = office?.displayName(locale);
      _date = DateTime.parse(log.workDate);
      _projectId = log.projectId;
      _projectLabel = project?.displayName(locale);
      _taskId = log.taskId;
      _taskLabel = task?.displayName(locale);
      _hoursController.text = _formatHours(log.hours);
      _loaded = true;
    });
  }

  String _formatHours(double h) =>
      h == h.roundToDouble() ? h.toInt().toString() : h.toString();

  @override
  void dispose() {
    _hoursController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  /// Picks the consulting office first; the project list then narrows to the
  /// projects attached to it, which is what keeps the entry form scoped.
  Future<void> _pickOffice() async {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).languageCode;
    final offices = await ref
        .read(officeRepositoryProvider)
        .getAll(includeArchived: false);
    if (!mounted) return;

    final result = await showSearchablePicker(
      context: context,
      title: l10n.office,
      items: offices
          .map((office) =>
              SearchablePickerItem(id: office.id!, label: office.displayName(locale)))
          .toList(),
      addNewLabel: l10n.addOffice,
      searchHint: l10n.search,
      emptyLabel: l10n.noOfficesYet,
    );
    if (result == null) return;

    if (result.isNew) {
      if (!mounted) return;
      final created = await showDialog<Office>(
        context: context,
        builder: (context) => _QuickAddDialog(
          title: l10n.addOffice,
          initialAr: result.query,
          arabicLabel: l10n.arabicName,
          englishLabel: l10n.englishName,
          onSubmit: (ar, en) {
            final now = DateTime.now().toIso8601String();
            return Office(nameAr: ar, nameEn: en, createdAt: now, updatedAt: now);
          },
        ),
      );
      if (created == null) return;
      final id = await ref.read(officeRepositoryProvider).insert(created);
      ref.read(dataVersionProvider.notifier).state++;
      setState(() {
        _officeId = id;
        _officeLabel = created.displayName(locale);
        _projectId = null;
        _projectLabel = null;
        _taskId = null;
        _taskLabel = null;
      });
      return;
    }

    final chosen = offices.firstWhere((office) => office.id == result.id);
    setState(() {
      _officeId = chosen.id;
      _officeLabel = chosen.displayName(locale);
      // The project list is scoped by office, so the old choice no longer
      // necessarily belongs here.
      _projectId = null;
      _projectLabel = null;
      _taskId = null;
      _taskLabel = null;
    });
  }

  Future<void> _pickProject() async {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).languageCode;
    // Scope the list to the chosen office instead of showing everything.
    final projects = await ref
        .read(projectRepositoryProvider)
        .getAll(includeArchived: false, officeId: _officeId);
    final items = projects
        .map((p) => SearchablePickerItem(id: p.id!, label: p.displayName(locale)))
        .toList();

    if (!mounted) return;
    final result = await showSearchablePicker(
      context: context,
      title: l10n.project,
      items: items,
      addNewLabel: l10n.addProject,
      searchHint: l10n.search,
      emptyLabel: l10n.noProjectsYet,
    );
    if (result == null) return;

    if (result.isNew) {
      // "Add new" flow keeps whatever the user typed as the new
      // project's name in the current UI language (PRD §7.3 — adding
      // a project must not lose the rest of the form).
      await _createProjectFlow(initialName: result.query);
      return;
    }
    final chosen = projects.firstWhere((p) => p.id == result.id);
    setState(() {
      _projectId = chosen.id;
      _projectLabel = chosen.displayName(locale);
      // Changing the project resets the task selection since the
      // "recently used" ordering depends on it.
      _taskId = null;
      _taskLabel = null;
    });
  }

  Future<void> _createProjectFlow({String initialName = ''}) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<Project>(
      context: context,
      builder: (context) => _QuickAddDialog(
        title: l10n.addProject,
        initialAr: initialName,
        arabicLabel: l10n.arabicName,
        englishLabel: l10n.englishName,
        onSubmit: (ar, en) {
          final now = DateTime.now().toIso8601String();
          return Project(
            officeId: _officeId,
            nameAr: ar,
            nameEn: en,
            createdAt: now,
            updatedAt: now,
          );
        },
      ),
    );
    if (result == null) return;
    final id = await ref.read(projectRepositoryProvider).insert(result);
    ref.read(dataVersionProvider.notifier).state++;
    if (!mounted) return;
    final locale = Localizations.localeOf(context).languageCode;
    setState(() {
      _projectId = id;
      _projectLabel = result.displayName(locale);
      _taskId = null;
      _taskLabel = null;
    });
  }

  Future<void> _pickTask() async {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).languageCode;
    final allTasks = await ref.read(taskRepositoryProvider).getAll(includeArchived: false);

    // Tasks already used on this project surface first, without
    // excluding tasks used elsewhere (PRD §7.3).
    List<TimeTask> ordered = allTasks;
    if (_projectId != null) {
      final recent = await ref
          .read(taskRepositoryProvider)
          .getRecentlyUsedForProject(_projectId!);
      final recentIds = recent.map((t) => t.id).toSet();
      ordered = [...recent, ...allTasks.where((t) => !recentIds.contains(t.id))];
    }

    final items = ordered
        .map((t) => SearchablePickerItem(id: t.id!, label: t.displayName(locale)))
        .toList();

    if (!mounted) return;
    final result = await showSearchablePicker(
      context: context,
      title: l10n.task,
      items: items,
      addNewLabel: l10n.addTask,
      searchHint: l10n.search,
      emptyLabel: l10n.noTasksYet,
    );
    if (result == null) return;

    if (result.isNew) {
      await _createTaskFlow(initialName: result.query);
      return;
    }
    final chosen = ordered.firstWhere((t) => t.id == result.id);
    setState(() {
      _taskId = chosen.id;
      _taskLabel = chosen.displayName(locale);
    });
  }

  Future<void> _createTaskFlow({String initialName = ''}) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<TimeTask>(
      context: context,
      builder: (context) => _QuickAddDialog(
        title: l10n.addTask,
        initialAr: initialName,
        arabicLabel: l10n.arabicName,
        englishLabel: l10n.englishName,
        onSubmit: (ar, en) {
          final now = DateTime.now().toIso8601String();
          return TimeTask(nameAr: ar, nameEn: en, createdAt: now, updatedAt: now);
        },
      ),
    );
    if (result == null) return;
    final id = await ref.read(taskRepositoryProvider).insert(result);
    ref.read(dataVersionProvider.notifier).state++;
    if (!mounted) return;
    final locale = Localizations.localeOf(context).languageCode;
    setState(() {
      _taskId = id;
      _taskLabel = result.displayName(locale);
    });
  }

  bool _validate(AppLocalizations l10n) {
    var valid = true;
    if (_projectId == null || _taskId == null) valid = false;

    final hoursText = _hoursController.text.trim().replaceAll(',', '.');
    final hours = double.tryParse(hoursText);
    if (hours == null || hours <= 0) {
      setState(() => _hoursError = l10n.validationHoursPositive);
      valid = false;
    } else {
      setState(() => _hoursError = null);
    }
    return valid;
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_validate(l10n)) return;

    final hours = double.parse(_hoursController.text.trim().replaceAll(',', '.'));

    if (hours >= _highHoursThreshold) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.highHoursWarningTitle),
          content: Text(l10n.highHoursWarningMessage(_formatHours(hours))),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.confirm),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    if (_saving) return; // guards against double-tap duplicate saves (PRD §12.11)
    // A soft nudge, not a block: logging the same work twice can be
    // deliberate, but a silent duplicate is usually a mistake. This catches
    // the case the double-tap guard cannot see: the same entry typed in
    // twice by hand.
    if (widget.entryId == null && await _isDuplicateOfExisting(hours)) {
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.duplicateWarningTitle),
          content: Text(l10n.duplicateWarningMessage(_formatHours(hours))),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.addAnyway),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    // A period whose report has already been sent is closed to changes.
    final lockedPeriod =
        await ref.read(periodLockRepositoryProvider).findForDate(_date);
    if (lockedPeriod != null) {
      if (!mounted) return;
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

    // Dates in a period that was already reported to a consulting office are
    // an easy mistake to make, so say so before the entry is stored.
    final currentPeriod = ref.read(periodCalculatorProvider).currentPeriod();
    if (_date.isBefore(currentPeriod.start)) {
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.pastPeriodWarningTitle),
          content: Text(
              l10n.pastPeriodWarningMessage(ltrRun(DateFormat.yMMMd().format(_date)))),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.confirm),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _saving = true);

    final now = DateTime.now().toIso8601String();
    final iso =
        '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

    final repo = ref.read(workLogRepositoryProvider);
    if (widget.entryId == null) {
      await repo.insert(WorkLog(
        projectId: _projectId!,
        taskId: _taskId!,
        workDate: iso,
        hours: hours,
        createdAt: now,
        updatedAt: now,
      ));
    } else {
      await repo.update(WorkLog(
        id: widget.entryId,
        projectId: _projectId!,
        taskId: _taskId!,
        workDate: iso,
        hours: hours,
        createdAt: _originalCreatedAt ?? now,
        updatedAt: now,
      ));
    }

    ref.read(dataVersionProvider.notifier).state++;
    if (mounted) context.pop();
  }

  /// True when this exact project + task + date + hours combination is
  /// already recorded, so the user can confirm before a double entry is
  /// stored. Only used when adding, never when editing.
  Future<bool> _isDuplicateOfExisting(double hours) async {
    final existing = await ref.read(workLogRepositoryProvider).getFiltered(
          WorkLogFilter(
            periodStart: _date,
            periodEnd: _date,
            projectId: _projectId,
            taskId: _taskId,
          ),
        );
    return existing.any((view) => (view.log.hours - hours).abs() < 0.001);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (!_loaded) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.entryId == null ? l10n.addEntry : l10n.edit)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _FieldLabel(l10n.date),
          // The week strip is the fast path: one tap instead of opening the
          // full date picker. The picker below still covers far-away dates.
          WeekStrip(
            selectedDate: _date,
            onDaySelected: (day) => setState(() => _date = day),
          ),
          const SizedBox(height: 8),
          InkWell(
            key: const Key('entry-date-field'),
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(),
              child: Text(ltrRun(DateFormat('EEE, d MMM yyyy').format(_date))),
            ),
          ),
          const SizedBox(height: 16),
          _FieldLabel(l10n.office),
          InkWell(
            onTap: _pickOffice,
            child: InputDecorator(
              decoration: const InputDecoration(),
              child: Text(_officeLabel ?? l10n.selectOffice,
                  style: TextStyle(
                      color: _officeLabel == null ? Colors.grey : null)),
            ),
          ),
          const SizedBox(height: 16),
          _FieldLabel(l10n.project),
          InkWell(
            onTap: _pickProject,
            child: InputDecorator(
              decoration: InputDecoration(
                errorText: _projectId == null && _hoursError != null ? l10n.validationRequired : null,
              ),
              child: Text(_projectLabel ?? l10n.project,
                  style: TextStyle(color: _projectLabel == null ? Colors.grey : null)),
            ),
          ),
          const SizedBox(height: 16),
          _FieldLabel(l10n.task),
          InkWell(
            onTap: _projectId == null ? null : _pickTask,
            child: InputDecorator(
              decoration: InputDecoration(
                errorText: _taskId == null && _hoursError != null ? l10n.validationRequired : null,
              ),
              child: Text(_taskLabel ?? l10n.task,
                  style: TextStyle(color: _taskLabel == null ? Colors.grey : null)),
            ),
          ),
          const SizedBox(height: 16),
          _FieldLabel(l10n.hours),
          TextField(
            controller: _hoursController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(errorText: _hoursError, hintText: '0.5, 1.25, 2.5'),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.pop(),
                  child: Text(l10n.cancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l10n.save),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge),
      );
}

class _QuickAddDialog<T> extends StatefulWidget {
  final String title;
  final String arabicLabel;
  final String englishLabel;

  /// Whatever the user had already typed in the search box, so creating the
  /// item does not make them type the name a second time.
  final String initialAr;
  final T Function(String ar, String en) onSubmit;

  const _QuickAddDialog({
    required this.title,
    required this.arabicLabel,
    required this.englishLabel,
    this.initialAr = '',
    required this.onSubmit,
  });

  @override
  State<_QuickAddDialog<T>> createState() => _QuickAddDialogState<T>();
}

class _QuickAddDialogState<T> extends State<_QuickAddDialog<T>> {
  late final TextEditingController _arController =
      TextEditingController(text: widget.initialAr);
  final _enController = TextEditingController();

  @override
  void dispose() {
    _arController.dispose();
    _enController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _arController,
            decoration: InputDecoration(labelText: widget.arabicLabel),
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _enController,
            decoration: InputDecoration(labelText: widget.englishLabel),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancel)),
        FilledButton(
          onPressed: () {
            final ar = _arController.text.trim();
            final en = _enController.text.trim();
            if (ar.isEmpty && en.isEmpty) return;
            Navigator.of(context).pop(widget.onSubmit(ar, en));
          },
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
