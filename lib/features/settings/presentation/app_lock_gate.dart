import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/localization/gen/app_localizations.dart';
import '../../../app/theme.dart';
import '../../../core/providers/providers.dart';
import '../../../core/security/app_lock.dart';

/// Sits in front of every screen and keeps the app closed until the device
/// has identified the user, so somebody picking up an unlocked phone cannot
/// read or change the timesheet.
///
/// The lock re-engages whenever the app goes to the background, and it does
/// nothing at all while the setting is off, so enabling it is the only thing
/// that changes the app's behaviour.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  bool _unlocked = false;
  bool _prompting = false;
  bool _promptedOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && mounted && _unlocked) {
      setState(() {
        _unlocked = false;
        _promptedOnce = false;
      });
    }
  }

  Future<void> _unlock(AppLocalizations l10n) async {
    if (_prompting) return;
    setState(() => _prompting = true);
    final accepted = await ref
        .read(appLockAuthenticatorProvider)
        .authenticate(l10n.appLockReason);
    if (!mounted) return;
    setState(() {
      _prompting = false;
      _unlocked = accepted;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    if (settings.isLoading) {
      // Never paint the app before we know whether it should be locked, or
      // the work would flash on screen for a frame at launch.
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final enabled = settings.value?.appLockEnabled ?? false;
    if (!enabled) return widget.child;
    if (_unlocked) return widget.child;

    final l10n = AppLocalizations.of(context)!;

    // Ask once as soon as the lock is shown, rather than making the user tap
    // a button they did not ask for.
    if (!_promptedOnce) {
      _promptedOnce = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_unlocked) _unlock(l10n);
      });
    }

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 56, color: AppColors.primary),
              const SizedBox(height: 16),
              Text(l10n.appLockedTitle,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(l10n.appLockHint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _prompting ? null : () => _unlock(l10n),
                icon: _prompting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.fingerprint),
                label: Text(l10n.unlockAction),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
