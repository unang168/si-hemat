import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

class FamilyPairingPayload {
  const FamilyPairingPayload({
    required this.version,
    required this.familyId,
    required this.familyName,
    required this.familySecret,
    required this.paydayDay,
    this.geminiApiKey,
  });

  final int version;
  final String familyId;
  final String familyName;
  final String familySecret;
  final int paydayDay;
  final String? geminiApiKey;

  Map<String, dynamic> toJson() => {
        'v': version,
        'app': 'si_hemat',
        'family_id': familyId,
        'family_name': familyName,
        'family_secret': familySecret,
        'payday_day': paydayDay,
        if (geminiApiKey != null && geminiApiKey!.isNotEmpty)
          'gemini_api_key': geminiApiKey,
      };

  String toQrString() => jsonEncode(toJson());

  factory FamilyPairingPayload.fromQrString(String raw) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(raw.trim());
    } catch (_) {
      throw const FormatException('Kode pairing keluarga tidak valid.');
    }

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Format kode pairing tidak dikenali.');
    }

    if (decoded['app'] != 'si_hemat') {
      throw const FormatException('QR ini bukan kode undangan Si-Hemat.');
    }

    final familyId = decoded['family_id'];
    final familyName = decoded['family_name'];
    final familySecret = decoded['family_secret'];
    final paydayRaw = decoded['payday_day'];
    final versionRaw = decoded['v'];

    if (familyId is! String ||
        familyId.isEmpty ||
        familyName is! String ||
        familyName.isEmpty ||
        familySecret is! String ||
        familySecret.length < 32) {
      throw const FormatException('Data keluarga pada kode pairing tidak lengkap.');
    }

    final payday = (paydayRaw is int ? paydayRaw : 25).clamp(1, 31);
    final version = versionRaw is int ? versionRaw : 1;
    final apiKey = decoded['gemini_api_key'];

    return FamilyPairingPayload(
      version: version,
      familyId: familyId,
      familyName: familyName,
      familySecret: familySecret,
      paydayDay: payday,
      geminiApiKey: apiKey is String && apiKey.isNotEmpty ? apiKey : null,
    );
  }
}

/// Cryptographic primitives for family pairing and privacy-preserving Wi-Fi sync.
class FamilyCrypto {
  FamilyCrypto._();

  static final Sha256 _sha256 = Sha256();

  /// Generates a 256-bit cryptographically secure random key encoded as base64url.
  static String generateFamilySecret() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  /// Computes a privacy-preserving SHA-256 fingerprint of familyId for mDNS discovery
  /// so the raw familyId is never broadcast on local Wi-Fi.
  static Future<String> computeFamilyHash(String familyId) async {
    final hash = await _sha256.hash(utf8.encode('sihemat:$familyId'));
    return hash.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .substring(0, 16);
  }
}
