import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timegrid/app/localization/gen/app_localizations.dart';
import 'package:timegrid/core/models/app_settings.dart';
import 'package:timegrid/core/providers/providers.dart';
import 'package:timegrid/core/security/app_lock.dart';
import 'package:timegrid/features/settings/presentation/app_lock_gate.dart';

/// The lock screen itself is testable even though the fingerprint prompt is
/// not: the gate talks to [AppLockAuthenticator], and these tests supply
/// their own.
class _FakeAuthenticator implements AppLockAuthenticator {
  _FakeAuthenticator({this.accept = true});

  final bool accept;
  int prompts = 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return accept;
  }
}

class _FakeSettings extends SettingsNotifier {
  _FakeSettings(this._value);

  final AppSettings _value;

  @override
  Future<AppSettings> build() async => _value;
}

void main() {
  Widget host({
    required AppSettings settings,
    required AppLockAuthenticator authenticator,
  }) {
    return ProviderScope(
      overrides: [
        settingsProvider.overrideWith(() => _FakeSettings(settings)),
        appLockAuthenticatorProvider.overrideWithValue(authenticator),
      ],
      child: const MaterialApp(
        locale: Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AppLockGate(child: Text('محتوى العمل')),
      ),
    );
  }

  testWidgets('with the lock off the app opens straight away, with no prompt',
      (tester) async {
    final authenticator = _FakeAuthenticator();
    await tester.pumpWidget(host(
      settings: const AppSettings(),
      authenticator: authenticator,
    ));
    await tester.pumpAndSettle();

    expect(find.text('محتوى العمل'), findsOneWidget);
    expect(authenticator.prompts, 0);
  });

  testWidgets('with the lock on the device is asked before anything is shown',
      (tester) async {
    final authenticator = _FakeAuthenticator(accept: true);
    await tester.pumpWidget(host(
      settings: const AppSettings(appLockEnabled: true),
      authenticator: authenticator,
    ));

    // Before the prompt resolves the work is not on screen.
    await tester.pump();
    expect(find.text('محتوى العمل'), findsNothing);

    await tester.pumpAndSettle();
    expect(authenticator.prompts, 1);
    expect(find.text('محتوى العمل'), findsOneWidget);
  });

  testWidgets('a rejected prompt keeps the app closed and offers another try',
      (tester) async {
    final authenticator = _FakeAuthenticator(accept: false);
    await tester.pumpWidget(host(
      settings: const AppSettings(appLockEnabled: true),
      authenticator: authenticator,
    ));
    await tester.pumpAndSettle();

    expect(authenticator.prompts, 1);
    expect(find.text('محتوى العمل'), findsNothing);
    expect(find.text('TimeGrid مقفول'), findsOneWidget);

    // The button is a real retry, and a second refusal still keeps it shut.
    await tester.tap(find.text('افتح'));
    await tester.pumpAndSettle();
    expect(authenticator.prompts, 2);
    expect(find.text('محتوى العمل'), findsNothing);
  });
}
