import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../app/localization/gen/app_localizations.dart';
import '../../../core/providers/providers.dart';
import '../../../core/security/app_lock.dart';
import '../../../core/services/file_sharer.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _version = '';

  /// Captured once in [initState] so it can still be used while the
  /// widget is being disposed (see [_flushEmployeeName]). The notifier
  /// lives for the whole app lifetime, so this is safe.
  late final SettingsNotifier _settingsNotifier;

  Timer? _employeeNameDebounce;
  String? _pendingEmployeeName;

  @override
  void initState() {
    super.initState();
    _settingsNotifier = ref.read(settingsProvider.notifier);
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = '${info.version} (${info.buildNumber})');
    });
  }

  @override
  void dispose() {
    // Typing a name and leaving the screen must not lose it.
    _flushEmployeeName();
    super.dispose();
  }

  /// Persists the employee name while the user types, without a database
  /// write on every keystroke.
  void _onEmployeeNameChanged(String value) {
    _pendingEmployeeName = value;
    _employeeNameDebounce?.cancel();
    _employeeNameDebounce =
        Timer(const Duration(milliseconds: 500), _flushEmployeeName);
  }

  void _flushEmployeeName() {
    _employeeNameDebounce?.cancel();
    _employeeNameDebounce = null;
    final pending = _pendingEmployeeName;
    _pendingEmployeeName = null;
    if (pending == null) return;
    _settingsNotifier
        .updateSettings((current) => current.copyWith(employeeName: pending));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: settingsAsync.when(
        data: (settings) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SectionTitle(l10n.language),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'ar', label: Text(l10n.arabic)),
                ButtonSegment(value: 'en', label: Text(l10n.english)),
              ],
              selected: {settings.languageCode},
              onSelectionChanged: (selection) {
                _settingsNotifier.updateSettings(
                    (c) => c.copyWith(languageCode: selection.first));
              },
            ),
            const SizedBox(height: 24),
            _SectionTitle(l10n.employeeName),
            TextFormField(
              initialValue: settings.employeeName,
              decoration: const InputDecoration(),
              onChanged: _onEmployeeNameChanged,
              onFieldSubmitted: (v) {
                _pendingEmployeeName = v;
                _flushEmployeeName();
              },
            ),
            const SizedBox(height: 24),
            _SectionTitle(l10n.reportingCycleStartDay),
            DropdownButtonFormField<int>(
              initialValue: settings.reportingCycleStartDay,
              items: [
                for (var d = 1; d <= 28; d++) DropdownMenuItem(value: d, child: Text('$d')),
              ],
              onChanged: (v) {
                if (v == null) return;
                _settingsNotifier
                    .updateSettings((c) => c.copyWith(reportingCycleStartDay: v));
              },
            ),
            const SizedBox(height: 24),
            _SectionTitle(l10n.selectTemplate),
            ListTile(
              tileColor: Theme.of(context).cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Text(settings.excelTemplatePath?.split('/').last ?? l10n.selectTemplate),
              trailing: const Icon(Icons.upload_file_outlined),
              onTap: () async {
                final picked = await FilePicker.pickFile(
                  type: FileType.custom,
                  allowedExtensions: ['xlsx', 'xls'],
                );
                final path = picked?.path;
                if (path == null) return;
                // Keep our own stable copy: the path returned by the
                // picker can point into a cache directory that Android
                // is free to clear later, which would silently lose the
                // selected template.
                final stablePath = await _copyTemplateToAppStorage(path);
                await _settingsNotifier.updateSettings(
                    (c) => c.copyWith(excelTemplatePath: stablePath));
              },
            ),
            const SizedBox(height: 24),
            _SectionTitle(l10n.appLock),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.appLock),
              subtitle: Text(l10n.appLockHint),
              value: settings.appLockEnabled,
              onChanged: _toggleAppLock,
            ),
            const SizedBox(height: 24),
            _SectionTitle('${l10n.backupData} / ${l10n.restoreData}'),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.backup_outlined),
                    label: Text(l10n.backupData),
                    onPressed: () => _backup(l10n),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.restore_outlined),
                    label: Text(l10n.restoreData),
                    onPressed: () => _restore(l10n),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Center(
              child: Text('${l10n.appVersion}: $_version',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }

  /// Copies the picked workbook into the app documents directory.
  /// Returns the original path if the copy could not be made.
  Future<String> _copyTemplateToAppStorage(String sourcePath) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final extension =
          p.extension(sourcePath).isEmpty ? '.xlsx' : p.extension(sourcePath);
      final target = File(p.join(dir.path, 'TimeGrid_Template$extension'));
      if (p.equals(sourcePath, target.path)) return sourcePath;
      await File(sourcePath).copy(target.path);
      return target.path;
    } catch (_) {
      return sourcePath;
    }
  }

  /// Turning the lock on is only useful if the device can actually identify
  /// the user, so check first and say so instead of silently doing nothing.
  Future<void> _toggleAppLock(bool value) async {
    final l10n = AppLocalizations.of(context)!;
    if (value) {
      final available =
          await ref.read(appLockAuthenticatorProvider).isAvailable();
      if (!available) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.appLockUnavailable)));
        return;
      }
    }
    await _settingsNotifier
        .updateSettings((current) => current.copyWith(appLockEnabled: value));
  }

  Future<void> _backup(AppLocalizations l10n) async {
    final file = await ref.read(backupRepositoryProvider).createBackup();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${l10n.backupSuccess}\n${file.path}'),
        action: SnackBarAction(
          // The file used to be reachable only from inside the app's own
          // storage, which is no use if the phone is what gets lost.
          label: l10n.shareBackup,
          onPressed: () => ref
              .read(fileSharerProvider)
              .shareFile(path: file.path, subject: l10n.backupData),
        ),
      ),
    );
  }

  Future<void> _restore(AppLocalizations l10n) async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = picked?.path;
    if (path == null) return;

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.restoreConfirmTitle),
        content: Text(l10n.restoreConfirmMessage),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      // A snapshot of the current data is written before anything is
      // replaced, so this restore is itself reversible.
      final safetyCopy =
          await ref.read(backupRepositoryProvider).restoreBackup(File(path));
      ref.read(dataVersionProvider.notifier).state++;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text('${l10n.restoreSuccess}\n${l10n.previousDataSavedAs}: ${safetyCopy.path}'),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.restoreInvalidFile)));
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}
