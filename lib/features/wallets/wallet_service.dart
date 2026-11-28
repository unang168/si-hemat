import 'dart:convert';

import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/core/security/secure_storage_service.dart';
import 'package:si_hemat/features/onboarding/onboarding_service.dart';
import 'package:uuid/uuid.dart';

/// Optional, encrypted-at-rest account hint (bank name + last 4 digits only)
/// used to auto-match uploaded bank statement PDFs/screenshots to the right wallet.
class WalletBankHint {
  const WalletBankHint({
    this.bankName = '',
    this.last4 = '',
  });

  final String bankName;
  final String last4;

  bool get isEmpty => bankName.trim().isEmpty && last4.trim().isEmpty;

  String get displayLabel {
    final b = bankName.trim();
    final l = last4.trim();
    if (b.isNotEmpty && l.isNotEmpty) return '$b ••••$l';
    if (l.isNotEmpty) return '••••$l';
    return b;
  }

  Map<String, dynamic> toJson() => {
        if (bankName.trim().isNotEmpty) 'bank': bankName.trim(),
        if (last4.trim().isNotEmpty) 'last4': last4.trim(),
      };

  factory WalletBankHint.fromJson(Map<String, dynamic> json) {
    return WalletBankHint(
      bankName: (json['bank'] as String?)?.trim() ?? '',
      last4: normalizeLast4((json['last4'] as String?) ?? ''),
    );
  }

  static String normalizeLast4(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length <= 4) return digits;
    return digits.substring(digits.length - 4);
  }

  static String normalizeBank(String raw) {
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r'\b(pt|tbk|bank|livin|by|mobile|indonesia)\b'), '')
        .replaceAll(RegExp(r'[^a-z0-9]'), '')
        .trim();
  }
}

class WalletService {
  WalletService({
    required this.db,
    required this.keyStore,
    required this.onboarding,
  });

  final AppDatabase db;
  final SecureKeyStore keyStore;
  final OnboardingService onboarding;
  static const Uuid _uuid = Uuid();

  Future<Map<String, WalletBankHint>> loadBankHints() async {
    final raw = await keyStore.read(SecureStorageKeys.walletBankHints);
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final result = <String, WalletBankHint>{};
      for (final entry in decoded.entries) {
        if (entry.key is String && entry.value is Map) {
          final hint = WalletBankHint.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
          if (!hint.isEmpty) {
            result[entry.key as String] = hint;
          }
        }
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  Future<void> setBankHint({
    required String walletId,
    String? bankName,
    String? last4,
  }) async {
    final current = Map<String, WalletBankHint>.from(await loadBankHints());
    final cleanedBank = (bankName ?? '').trim();
    final cleanedLast4 = WalletBankHint.normalizeLast4(last4 ?? '');
    if (cleanedBank.isEmpty && cleanedLast4.isEmpty) {
      current.remove(walletId);
    } else {
      current[walletId] = WalletBankHint(
        bankName: cleanedBank,
        last4: cleanedLast4,
      );
    }
    final encoded = {
      for (final e in current.entries) e.key: e.value.toJson(),
    };
    await keyStore.write(
      SecureStorageKeys.walletBankHints,
      jsonEncode(encoded),
    );
  }

  /// Attempts safe, conservative matching from AI-detected statement metadata
  /// (`detectedBank`, `detectedLast4`) to one of the user's [wallets].
  /// Returns `null` when ambiguous (e.g., user has two Mandiri wallets and no last4).
  static String? findMatchingWalletId({
    required List<Wallet> wallets,
    required Map<String, WalletBankHint> hints,
    String? detectedBank,
    String? detectedLast4,
  }) {
    final last4 = WalletBankHint.normalizeLast4(detectedLast4 ?? '');
    final bankNorm = WalletBankHint.normalizeBank(detectedBank ?? '');
    final activeIds = wallets.map((w) => w.id).toSet();

    // Priority 1: Exact last-4 digits match (prefer matching bank too if provided)
    if (last4.length == 4) {
      final exactLast4 = <String>[];
      final exactBoth = <String>[];
      for (final w in wallets) {
        final h = hints[w.id];
        if (h == null || h.last4 != last4) continue;
        exactLast4.add(w.id);
        final hBank = WalletBankHint.normalizeBank(h.bankName);
        if (bankNorm.isNotEmpty &&
            hBank.isNotEmpty &&
            (hBank.contains(bankNorm) || bankNorm.contains(hBank))) {
          exactBoth.add(w.id);
        }
      }
      if (exactBoth.length == 1) return exactBoth.first;
      if (exactLast4.length == 1) return exactLast4.first;
    }

    // Priority 2: Unique bank-name match (ONLY if unambiguous — exactly 1 wallet matches!)
    if (bankNorm.length >= 3) {
      final matchedByBank = <String>{};
      for (final w in wallets) {
        final h = hints[w.id];
        final hBank = h != null ? WalletBankHint.normalizeBank(h.bankName) : '';
        final wName = WalletBankHint.normalizeBank(w.name);
        if ((hBank.isNotEmpty &&
                (hBank.contains(bankNorm) || bankNorm.contains(hBank))) ||
            (wName.isNotEmpty &&
                (wName.contains(bankNorm) || bankNorm.contains(wName)))) {
          if (activeIds.contains(w.id)) matchedByBank.add(w.id);
        }
      }
      if (matchedByBank.length == 1) return matchedByBank.first;
    }

    return null;
  }

  Future<String> _resolveMemberId(String familyId) async {
    final stored = await keyStore.read(SecureStorageKeys.memberId);
    if (stored != null && stored.isNotEmpty) return stored;
    final members = await db.getFamilyMembers(familyId);
    if (members.isEmpty) {
      throw StateError('Belum ada anggota keluarga terdaftar.');
    }
    return members.first.id;
  }

  Future<String> createWallet({
    required String familyId,
    required String name,
    required String type,
    required String visibility,
    required int initialBalance,
    required int color,
  }) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('Nama dompet wajib diisi.');
    }
    final deviceId = await onboarding.getOrCreateDeviceId();
    final memberId = await _resolveMemberId(familyId);
    return db.insertWallet(
      id: _uuid.v4(),
      familyId: familyId,
      ownerMemberId: memberId,
      name: name,
      type: type,
      visibility: visibility,
      initialBalance: initialBalance,
      color: color,
      deviceId: deviceId,
    );
  }

  Future<void> updateWallet({
    required String walletId,
    required String name,
    required String type,
    required String visibility,
    required int initialBalance,
    required int color,
  }) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('Nama dompet wajib diisi.');
    }
    final deviceId = await onboarding.getOrCreateDeviceId();
    await db.updateWalletRow(
      id: walletId,
      name: name,
      type: type,
      visibility: visibility,
      initialBalance: initialBalance,
      color: color,
      deviceId: deviceId,
    );
  }

  Future<void> deleteWallet(String walletId) async {
    final deviceId = await onboarding.getOrCreateDeviceId();
    await db.softDeleteWallet(id: walletId, deviceId: deviceId);
  }
}
