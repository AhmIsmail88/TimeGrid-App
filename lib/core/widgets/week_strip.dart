import 'package:flutter/material.dart';

import '../../app/localization/gen/app_localizations.dart';
import '../../app/theme.dart';

/// One row of seven day cells covering a single week, with the selected day
/// marked by a filled circle.
///
/// It is the quick way to answer "which day?" in this app: the work-log list
/// filters to a tapped day, and the entry form uses it to set the work date
/// without opening the full date picker. The week starts on the locale's
/// first day (Saturday in Arabic) and the row mirrors on its own in RTL.
class WeekStrip extends StatefulWidget {
  const WeekStrip({
    super.key,
    required this.selectedDate,
    required this.onDaySelected,
  });

  /// The day to highlight, or null when no day is selected.
  final DateTime? selectedDate;

  /// Called with the day the user tapped.
  final ValueChanged<DateTime> onDaySelected;

  @override
  State<WeekStrip> createState() => _WeekStripState();
}

class _WeekStripState extends State<WeekStrip> {
  /// A day inside the week currently on screen. Kept apart from
  /// [WeekStrip.selectedDate] so browsing to another week does not move the
  /// selection.
  late DateTime _anchor;

  @override
  void initState() {
    super.initState();
    _anchor = _dayOnly(widget.selectedDate ?? DateTime.now());
  }

  @override
  void didUpdateWidget(covariant WeekStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A date chosen elsewhere (the full date picker, a filter reset) has to
    // bring its own week into view, but a cleared selection must not jump.
    final selected = widget.selectedDate;
    if (selected != null &&
        !_sameWeek(_dayOnly(selected), _anchor, context)) {
      _anchor = _dayOnly(selected);
    }
  }

  static DateTime _dayOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  /// Day arithmetic through the constructor rather than [Duration], so a
  /// daylight-saving change can never land the result at 23:00 of the day
  /// before.
  static DateTime _addDays(DateTime date, int days) =>
      DateTime(date.year, date.month, date.day + days);

  /// The locale's first day of the week, as an index into
  /// `MaterialLocalizations.narrowWeekdays` (0 = Sunday).
  static int _firstDayIndex(BuildContext context) =>
      MaterialLocalizations.of(context).firstDayOfWeekIndex;

  /// A date's index in that same 0 = Sunday scheme.
  static int _weekdayIndex(DateTime date) => date.weekday % 7;

  static DateTime _weekStart(DateTime date, int firstDayIndex) =>
      _addDays(date, -((_weekdayIndex(date) - firstDayIndex + 7) % 7));

  bool _sameWeek(DateTime a, DateTime b, BuildContext context) =>
      _weekStart(a, _firstDayIndex(context)) ==
      _weekStart(b, _firstDayIndex(context));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final localizations = MaterialLocalizations.of(context);
    final labels = localizations.narrowWeekdays;
    final firstDayIndex = localizations.firstDayOfWeekIndex;
    final start = _weekStart(_anchor, firstDayIndex);
    final days = List<DateTime>.generate(7, (i) => _addDays(start, i));
    final selected =
        widget.selectedDate == null ? null : _dayOnly(widget.selectedDate!);
    final today = _dayOnly(DateTime.now());
    final rtl = Directionality.of(context) == TextDirection.rtl;

    return Row(
      children: [
        IconButton(
          tooltip: l10n.previousWeek,
          visualDensity: VisualDensity.compact,
          icon: Icon(rtl ? Icons.chevron_right : Icons.chevron_left),
          onPressed: () => setState(() => _anchor = _addDays(_anchor, -7)),
        ),
        Expanded(
          child: Row(
            children: [
              for (final day in days)
                Expanded(
                  child: _DayCell(
                    key: ValueKey<String>('week-day-${day.toIso8601String()}'),
                    label: labels[_weekdayIndex(day)],
                    day: day,
                    isSelected: selected != null && day == selected,
                    isToday: day == today,
                    onTap: () => widget.onDaySelected(day),
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          tooltip: l10n.nextWeek,
          visualDensity: VisualDensity.compact,
          icon: Icon(rtl ? Icons.chevron_left : Icons.chevron_right),
          onPressed: () => setState(() => _anchor = _addDays(_anchor, 7)),
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    super.key,
    required this.label,
    required this.day,
    required this.isSelected,
    required this.isToday,
    required this.onTap,
  });

  final String label;
  final DateTime day;
  final bool isSelected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final Color numberColor;
    final Color background;
    final Border? border;
    if (isSelected) {
      numberColor = scheme.onPrimary;
      background = scheme.primary;
      border = null;
    } else if (isToday) {
      numberColor = scheme.primary;
      background = Colors.transparent;
      border = Border.all(color: scheme.primary, width: 1.5);
    } else {
      numberColor = AppColors.onChip(theme.brightness);
      background = AppColors.chipBackground(theme.brightness);
      border = null;
    }

    return Semantics(
      button: true,
      selected: isSelected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: background,
                  shape: BoxShape.circle,
                  border: border,
                ),
                child: Text(
                  '${day.day}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: numberColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
