import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

class SyncAuthException implements Exception {
  const SyncAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Authenticated encryption (AES-256-GCM) and handshake verification (HMAC-SHA256)
/// using the family's 256-bit `family_secret` exchanged once via QR code.
class SyncCrypto {
  SyncCrypto._();

  static final AesGcm _aesGcm = AesGcm.with256bits();
  static final Hmac _hmacSha256 = Hmac.sha256();
  static final Sha256 _sha256 = Sha256();

  static Future<SecretKey> _deriveSecretKey(String familySecret) async {
    List<int> rawBytes;
    try {
      rawBytes = base64Url.decode(base64Url.normalize(familySecret.trim()));
    } catch (_) {
      rawBytes = utf8.encode(familySecret.trim());
    }
    if (rawBytes.length != 32) {
      final digest = await _sha256.hash(rawBytes);
      rawBytes = digest.bytes;
    }
    return SecretKey(rawBytes);
  }

  static String generateNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  static Future<String> computeHandshakeHmac({
    required String familySecret,
    required String deviceId,
    required String nonce,
  }) async {
    final key = await _deriveSecretKey(familySecret);
    final mac = await _hmacSha256.calculateMac(
      utf8.encode('sihemat-sync-v1:$deviceId:$nonce'),
      secretKey: key,
    );
    return base64UrlEncode(mac.bytes);
  }

  static Future<bool> verifyHandshakeHmac({
    required String familySecret,
    required String deviceId,
    required String nonce,
    required String providedHmac,
  }) async {
    final expected = await computeHandshakeHmac(
      familySecret: familySecret,
      deviceId: deviceId,
      nonce: nonce,
    );
    return _constantTimeEquals(expected, providedHmac);
  }

  /// Encrypts a JSON map using AES-256-GCM with a fresh random 96-bit nonce.
  static Future<Map<String, String>> encryptJson({
    required Map<String, dynamic> payload,
    required String familySecret,
  }) async {
    final key = await _deriveSecretKey(familySecret);
    final clearText = utf8.encode(jsonEncode(payload));
    final box = await _aesGcm.encrypt(clearText, secretKey: key);
    return {
      'nonce': base64UrlEncode(box.nonce),
      'ciphertext': base64UrlEncode(box.cipherText),
      'mac': base64UrlEncode(box.mac.bytes),
    };
  }

  /// Decrypts and authenticates an AES-256-GCM envelope. Throws [SyncAuthException]
  /// if the key does not match or the payload was tampered with.
  static Future<Map<String, dynamic>> decryptJson({
    required Map<String, dynamic> envelope,
    required String familySecret,
  }) async {
    try {
      final key = await _deriveSecretKey(familySecret);
      final nonce = base64Url.decode(
        base64Url.normalize(envelope['nonce'] as String),
      );
      final cipherText = base64Url.decode(
        base64Url.normalize(envelope['ciphertext'] as String),
      );
      final macBytes = base64Url.decode(
        base64Url.normalize(envelope['mac'] as String),
      );
      final box = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));
      final clearBytes = await _aesGcm.decrypt(box, secretKey: key);
      final decoded = jsonDecode(utf8.decode(clearBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const SyncAuthException('Payload sync tidak valid.');
      }
      return decoded;
    } on SyncAuthException {
      rethrow;
    } catch (_) {
      throw const SyncAuthException(
        'Gagal mendekripsi data sync. Pastikan kedua HP berasal dari keluarga yang sama.',
      );
    }
  }

  static bool _constantTimeEquals(String a, String b) {
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
