import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/localization/gen/app_localizations.dart';
import '../../../../app/theme.dart';
import '../../../../core/models/work_log.dart';
import '../../../../core/utils/bidi.dart';
import '../../../../core/utils/project_accent.dart';

/// One work-log entry as a list card: a project-coloured bar on the leading
/// edge, the task as the headline, the project and date underneath, and the
/// hours with the delete action on the trailing side.
///
/// Shared so the list and any other place that shows an entry (the dashboard's
/// recent entries) stay visually identical.
class WorkLogCard extends StatelessWidget {
  const WorkLogCard({
    super.key,
    required this.view,
    required this.locale,
    required this.isLocked,
    required this.onTap,
    required this.onDelete,
  });

  /// The joined row: entry plus resolved project/task names.
  final WorkLogView view;

  /// Language code the project and task names are rendered in.
  final String locale;

  /// True when the entry's date falls inside a period that has already been
  /// reported. Shown as a chip, so the refusal to delete the entry is
  /// explained before the user tries it.
  final bool isLocked;

  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final accent = ProjectAccent.of(view.log.projectId, theme.brightness);
    final date = DateTime.parse(view.log.workDate);

    return Card(
      // The accent bar is a child of the card, so it has to be clipped to
      // follow the rounded corner instead of poking out of it.
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The first child of a Row is the leading edge, which is the
              // right-hand side in RTL without any special casing.
              Container(
                key: const Key('work-log-accent'),
                width: 4,
                color: accent,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 6, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              view.taskName(locale),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyLarge
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${view.projectName(locale)} \u00b7 '
                              '${ltrRun(DateFormat('d MMM yyyy').format(date))}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            if (isLocked) ...[
                              const SizedBox(height: 6),
                              _LockedChip(label: l10n.periodLocked),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${view.log.hours}h',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        tooltip: l10n.delete,
                        icon: const Icon(Icons.delete_outline),
                        onPressed: onDelete,
                      ),
                    ],
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

/// Marks an entry whose period has already been reported to the office.
class _LockedChip extends StatelessWidget {
  const _LockedChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final foreground = AppColors.onChip(brightness);

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(8, 3, 8, 3),
        decoration: BoxDecoration(
          color: AppColors.chipBackground(brightness),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 12, color: foreground),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
