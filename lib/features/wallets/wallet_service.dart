import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/core/security/secure_storage_service.dart';
import 'package:si_hemat/features/onboarding/onboarding_service.dart';
import 'package:uuid/uuid.dart';

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
