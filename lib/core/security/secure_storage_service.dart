import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Abstraction over secure key-value storage for easy unit testing.
abstract class SecureKeyStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureStorageKeys {
  static const String deviceId = 'sihemat_device_id';
  static const String familyId = 'sihemat_family_id';
  static const String memberId = 'sihemat_member_id';
  static const String familySecret = 'sihemat_family_secret';
  static const String geminiApiKey = 'sihemat_gemini_api_key';
  static const String geminiModel = 'sihemat_gemini_model';
  static const String pinHash = 'sihemat_pin_hash';
  static const String appLockEnabled = 'sihemat_app_lock_enabled';
  static const String biometricEnabled = 'sihemat_biometric_enabled';
  static const String themeMode = 'sihemat_theme_mode';
  static const String autoLockSeconds = 'sihemat_auto_lock_seconds';
}

class FlutterSecureKeyStore implements SecureKeyStore {
  FlutterSecureKeyStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
