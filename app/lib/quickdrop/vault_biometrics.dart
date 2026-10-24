import 'dart:io';

import 'package:local_auth/local_auth.dart';

/// An additional device-authentication gate. The PIN still derives the encryption key;
/// biometrics do not recover, replace, or persist that key.
class VaultBiometrics {
  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> available() async {
    if (!(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) return false;
    try {
      return await _auth.canCheckBiometrics && (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate() => _auth.authenticate(
    localizedReason: 'Confirm your identity to access QuickVault. Your vault PIN is also required.',
    biometricOnly: true,
    persistAcrossBackgrounding: false,
  );
}
