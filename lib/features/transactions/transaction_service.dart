import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/core/security/secure_storage_service.dart';
import 'package:si_hemat/features/onboarding/onboarding_service.dart';
import 'package:uuid/uuid.dart';

class TransactionService {
  TransactionService({
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

  /// Determines sync visibility safely:
  /// If any involved wallet is personal, the transaction stays personal so
  /// personal wallet foreign keys never leak into shared Wi-Fi sync.
  String resolveVisibility({
    required Wallet sourceWallet,
    Wallet? targetWallet,
  }) {
    if (sourceWallet.visibility == VisibilityScope.personal) {
      return VisibilityScope.personal;
    }
    if (targetWallet != null &&
        targetWallet.visibility == VisibilityScope.personal) {
      return VisibilityScope.personal;
    }
    return VisibilityScope.shared;
  }

  Future<String> createTransaction({
    required String familyId,
    required Wallet sourceWallet,
    Wallet? targetWallet,
    String? categoryId,
    required String type,
    required int amount,
    required DateTime date,
    String? merchant,
    String? note,
    String? receiptHash,
    String source = TransactionSource.manual,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('Nominal harus lebih dari Rp 0.');
    }
    if (type == TransactionType.transfer) {
      if (targetWallet == null) {
        throw ArgumentError('Dompet tujuan transfer wajib dipilih.');
      }
      if (targetWallet.id == sourceWallet.id) {
        throw ArgumentError('Dompet asal dan tujuan tidak boleh sama.');
      }
    } else if (categoryId == null || categoryId.isEmpty) {
      throw ArgumentError('Kategori wajib dipilih.');
    }

    final deviceId = await onboarding.getOrCreateDeviceId();
    final memberId = await _resolveMemberId(familyId);
    final visibility = resolveVisibility(
      sourceWallet: sourceWallet,
      targetWallet: targetWallet,
    );

    return db.insertTransaction(
      id: _uuid.v4(),
      familyId: familyId,
      memberId: memberId,
      walletId: sourceWallet.id,
      toWalletId: type == TransactionType.transfer ? targetWallet?.id : null,
      categoryId: type == TransactionType.transfer ? null : categoryId,
      type: type,
      amount: amount,
      date: date,
      merchant: merchant,
      note: note,
      receiptHash: receiptHash,
      source: source,
      visibility: visibility,
      deviceId: deviceId,
    );
  }

  Future<void> updateTransaction({
    required String transactionId,
    required Wallet sourceWallet,
    Wallet? targetWallet,
    String? categoryId,
    required String type,
    required int amount,
    required DateTime date,
    String? merchant,
    String? note,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('Nominal harus lebih dari Rp 0.');
    }
    if (type == TransactionType.transfer) {
      if (targetWallet == null) {
        throw ArgumentError('Dompet tujuan transfer wajib dipilih.');
      }
      if (targetWallet.id == sourceWallet.id) {
        throw ArgumentError('Dompet asal dan tujuan tidak boleh sama.');
      }
    } else if (categoryId == null || categoryId.isEmpty) {
      throw ArgumentError('Kategori wajib dipilih.');
    }

    final deviceId = await onboarding.getOrCreateDeviceId();
    final visibility = resolveVisibility(
      sourceWallet: sourceWallet,
      targetWallet: targetWallet,
    );

    await db.updateTransactionRow(
      id: transactionId,
      walletId: sourceWallet.id,
      toWalletId: type == TransactionType.transfer ? targetWallet?.id : null,
      categoryId: type == TransactionType.transfer ? null : categoryId,
      type: type,
      amount: amount,
      date: date,
      merchant: merchant,
      note: note,
      visibility: visibility,
      deviceId: deviceId,
    );
  }

  Future<void> deleteTransaction(String transactionId) async {
    final deviceId = await onboarding.getOrCreateDeviceId();
    await db.softDeleteTransaction(id: transactionId, deviceId: deviceId);
  }

  Future<void> restoreTransaction(String transactionId) async {
    final deviceId = await onboarding.getOrCreateDeviceId();
    await db.restoreTransaction(id: transactionId, deviceId: deviceId);
  }
}
