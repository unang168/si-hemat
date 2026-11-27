import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/core/security/secure_storage_service.dart';
import 'package:si_hemat/core/utils/date_formatter.dart';
import 'package:si_hemat/features/onboarding/onboarding_service.dart';
import 'package:uuid/uuid.dart';

class BudgetBillService {
  BudgetBillService({
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

  Future<String> saveBudget({
    required String familyId,
    required String categoryId,
    required DateTime month,
    required int limitAmount,
    String visibility = VisibilityScope.shared,
  }) async {
    if (limitAmount <= 0) {
      throw ArgumentError('Batas anggaran harus lebih dari Rp 0.');
    }
    final deviceId = await onboarding.getOrCreateDeviceId();
    return db.upsertBudget(
      id: _uuid.v4(),
      familyId: familyId,
      categoryId: categoryId,
      monthKey: DateFormatter.monthKey(month),
      limitAmount: limitAmount,
      visibility: visibility,
      deviceId: deviceId,
    );
  }

  Future<void> deleteBudget(String budgetId) async {
    final deviceId = await onboarding.getOrCreateDeviceId();
    await db.softDeleteBudget(id: budgetId, deviceId: deviceId);
  }

  Future<int> copyFromPreviousMonth({
    required String familyId,
    required DateTime targetMonth,
  }) async {
    final prevMonth = DateTime(targetMonth.year, targetMonth.month - 1, 1);
    final deviceId = await onboarding.getOrCreateDeviceId();
    return db.copyBudgetsFromMonth(
      familyId: familyId,
      sourceMonthKey: DateFormatter.monthKey(prevMonth),
      targetMonthKey: DateFormatter.monthKey(targetMonth),
      deviceId: deviceId,
    );
  }

  Future<String> createBill({
    required String familyId,
    String? walletId,
    required String categoryId,
    required String name,
    required int amount,
    required int dueDay,
    DateTime? startMonth,
    int? tenorMonths,
    String visibility = VisibilityScope.shared,
  }) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('Nama tagihan wajib diisi.');
    }
    if (amount <= 0) {
      throw ArgumentError('Nominal tagihan harus lebih dari Rp 0.');
    }
    final deviceId = await onboarding.getOrCreateDeviceId();
    final effectiveStart = startMonth != null
        ? DateTime(startMonth.year, startMonth.month, 1)
        : null;
    final startKey =
        effectiveStart != null ? DateFormatter.monthKey(effectiveStart) : null;
    String? endKey;
    if (tenorMonths != null && tenorMonths > 0) {
      final anchor = effectiveStart ??
          DateTime(DateTime.now().year, DateTime.now().month, 1);
      final endDate = DateTime(anchor.year, anchor.month + tenorMonths - 1, 1);
      endKey = DateFormatter.monthKey(endDate);
    }

    return db.insertRecurringBill(
      id: _uuid.v4(),
      familyId: familyId,
      walletId: walletId,
      categoryId: categoryId,
      name: name,
      amount: amount,
      dueDay: dueDay,
      startMonth: startKey,
      endMonth: endKey,
      visibility: visibility,
      deviceId: deviceId,
    );
  }

  Future<void> updateBill({
    required String billId,
    String? walletId,
    required String categoryId,
    required String name,
    required int amount,
    required int dueDay,
    String? startMonth,
    int? tenorMonths,
    String? existingEndMonth,
    bool clearTenor = false,
    required String visibility,
  }) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('Nama tagihan wajib diisi.');
    }
    if (amount <= 0) {
      throw ArgumentError('Nominal tagihan harus lebih dari Rp 0.');
    }
    final deviceId = await onboarding.getOrCreateDeviceId();

    String? endKey = clearTenor ? null : existingEndMonth;
    if (!clearTenor && tenorMonths != null && tenorMonths > 0) {
      final anchor = _parseMonthKey(startMonth) ??
          DateTime(DateTime.now().year, DateTime.now().month, 1);
      final endDate = DateTime(anchor.year, anchor.month + tenorMonths - 1, 1);
      endKey = DateFormatter.monthKey(endDate);
    }

    await db.updateRecurringBillRow(
      id: billId,
      walletId: walletId,
      categoryId: categoryId,
      name: name,
      amount: amount,
      dueDay: dueDay,
      startMonth: startMonth,
      endMonth: endKey,
      visibility: visibility,
      deviceId: deviceId,
    );
  }

  /// Stops the bill starting from [fromMonth] onward while preserving earlier paid months.
  Future<void> stopBillFromMonth({
    required String billId,
    required DateTime fromMonth,
  }) async {
    final deviceId = await onboarding.getOrCreateDeviceId();
    await db.stopRecurringBillFromMonth(
      id: billId,
      fromMonth: fromMonth,
      deviceId: deviceId,
    );
  }

  /// Soft-deletes the entire recurring bill schedule (already-recorded transactions stay intact).
  Future<void> deleteBill(String billId) async {
    final deviceId = await onboarding.getOrCreateDeviceId();
    await db.softDeleteRecurringBill(id: billId, deviceId: deviceId);
  }

  DateTime? _parseMonthKey(String? key) {
    if (key == null || !key.contains('-')) return null;
    final parts = key.split('-');
    if (parts.length != 2) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (y == null || m == null) return null;
    return DateTime(y, m, 1);
  }

  /// Marks bill paid for [month] and automatically records the expense transaction
  /// anchored inside [month] so that month's budget & report immediately reflect it.
  Future<String> payBill({
    required RecurringBill bill,
    required Wallet wallet,
    required DateTime month,
    DateTime? paidAt,
    int? overrideAmount,
  }) async {
    final deviceId = await onboarding.getOrCreateDeviceId();
    final memberId = await _resolveMemberId(bill.familyId);
    final txVisibility = wallet.visibility == VisibilityScope.personal
        ? VisibilityScope.personal
        : bill.visibility;

    final now = DateTime.now();
    final DateTime effectivePaidAt;
    if (paidAt != null) {
      effectivePaidAt = paidAt;
    } else if (month.year == now.year && month.month == now.month) {
      effectivePaidAt = now;
    } else {
      final lastDay = DateTime(month.year, month.month + 1, 0).day;
      effectivePaidAt = DateTime(
        month.year,
        month.month,
        bill.dueDay.clamp(1, lastDay),
        12,
      );
    }

    return db.payRecurringBillAtomically(
      bill: bill,
      transactionId: _uuid.v4(),
      memberId: memberId,
      walletId: wallet.id,
      visibility: txVisibility,
      monthKey: DateFormatter.monthKey(month),
      paidAt: effectivePaidAt,
      deviceId: deviceId,
      overrideAmount: overrideAmount,
    );
  }
}
