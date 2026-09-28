import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

/// Wraps the device's biometric prompt.
///
/// It is an interface rather than a direct call so the lock screen can be
/// driven in tests without a fingerprint reader, and so a device that has no
/// biometrics at all degrades to "not available" instead of throwing.
abstract class AppLockAuthenticator {
  /// Whether this device can authenticate the user at all.
  Future<bool> isAvailable();

  /// Prompts the user. Returns true only when the device accepted them.
  Future<bool> authenticate(String reason);
}

class LocalAuthAuthenticator implements AppLockAuthenticator {
  LocalAuthAuthenticator([LocalAuthentication? authentication])
      : _authentication = authentication ?? LocalAuthentication();

  final LocalAuthentication _authentication;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _authentication.isDeviceSupported() ||
          await _authentication.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _authentication.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          // Falls back to the phone's PIN/pattern when no fingerprint is
          // enrolled, which is still better than an open app.
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}

final appLockAuthenticatorProvider =
    Provider<AppLockAuthenticator>((ref) => LocalAuthAuthenticator());
