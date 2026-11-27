import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:local_auth/local_auth.dart';
import 'package:si_hemat/core/security/secure_storage_service.dart';

class AppLockStatus {
  const AppLockStatus({
    required this.lockEnabled,
    required this.biometricEnabled,
    required this.biometricAvailable,
  });

  final bool lockEnabled;
  final bool biometricEnabled;
  final bool biometricAvailable;
}

/// Manages 6-digit salted SHA-256 PIN lock and Android Biometric unlock.
class AppLockService {
  AppLockService({
    required this.keyStore,
    LocalAuthentication? localAuth,
  }) : _localAuth = localAuth ?? LocalAuthentication();

  final SecureKeyStore keyStore;
  final LocalAuthentication _localAuth;
  static final Sha256 _sha256 = Sha256();

  Future<bool> isLockEnabled() async {
    final enabled = await keyStore.read(SecureStorageKeys.appLockEnabled);
    final hash = await keyStore.read(SecureStorageKeys.pinHash);
    return enabled == 'true' && hash != null && hash.contains(':');
  }

  Future<bool> isBiometricEnabled() async {
    final flag = await keyStore.read(SecureStorageKeys.biometricEnabled);
    return flag == 'true';
  }

  Future<bool> isBiometricAvailable() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      return supported && canCheck;
    } catch (_) {
      return false;
    }
  }

  Future<AppLockStatus> loadStatus() async {
    final locked = await isLockEnabled();
    final bioEnabled = await isBiometricEnabled();
    final bioAvailable = await isBiometricAvailable();
    return AppLockStatus(
      lockEnabled: locked,
      biometricEnabled: locked && bioEnabled && bioAvailable,
      biometricAvailable: bioAvailable,
    );
  }

  Future<void> setPin(String pin) async {
    final cleaned = pin.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(cleaned)) {
      throw ArgumentError('PIN harus terdiri dari tepat 6 angka.');
    }

    final rng = Random.secure();
    final saltBytes = List<int>.generate(16, (_) => rng.nextInt(256));
    final salt = base64UrlEncode(saltBytes);
    final digest = await _hashPin(salt: salt, pin: cleaned);

    await keyStore.write(SecureStorageKeys.pinHash, '$salt:$digest');
    await keyStore.write(SecureStorageKeys.appLockEnabled, 'true');
  }

  Future<bool> verifyPin(String candidate) async {
    final stored = await keyStore.read(SecureStorageKeys.pinHash);
    if (stored == null || !stored.contains(':')) return false;
    final parts = stored.split(':');
    if (parts.length != 2) return false;
    final salt = parts[0];
    final expectedHash = parts[1];
    final actualHash = await _hashPin(salt: salt, pin: candidate.trim());
    return _constantTimeEquals(expectedHash, actualHash);
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await keyStore.write(
      SecureStorageKeys.biometricEnabled,
      enabled ? 'true' : 'false',
    );
  }

  Future<void> disableLock() async {
    await keyStore.delete(SecureStorageKeys.pinHash);
    await keyStore.write(SecureStorageKeys.appLockEnabled, 'false');
    await keyStore.write(SecureStorageKeys.biometricEnabled, 'false');
  }

  Future<bool> authenticateWithBiometrics() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Buka kunci Si-Hemat menggunakan biometrik',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  Future<String> _hashPin({
    required String salt,
    required String pin,
  }) async {
    final digest = await _sha256.hash(utf8.encode('sihemat-pin:$salt:$pin'));
    return base64UrlEncode(digest.bytes);
  }

  bool _constantTimeEquals(String a, String b) {
    final ab = utf8.encode(a);
    final bb = utf8.encode(b);
    if (ab.length != bb.length) return false;
    var diff = 0;
    for (var i = 0; i < ab.length; i++) {
      diff |= ab[i] ^ bb[i];
    }
    return diff == 0;
  }
}
