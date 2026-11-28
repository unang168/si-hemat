import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:si_hemat/core/constants/default_categories.dart';
import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/database/tables.dart';
import 'package:uuid/uuid.dart';

part 'app_database.g.dart';

class WalletWithBalance {
  const WalletWithBalance({
    required this.wallet,
    required this.balance,
  });

  final Wallet wallet;
  final int balance;
}

class TransactionWithDetails {
  const TransactionWithDetails({
    required this.transaction,
    this.wallet,
    this.toWallet,
    this.category,
    this.member,
  });

  final Transaction transaction;
  final Wallet? wallet;
  final Wallet? toWallet;
  final Category? category;
  final Member? member;
}

class MonthlyCashflowSummary {
  const MonthlyCashflowSummary({
    required this.totalIncome,
    required this.totalExpense,
    required this.transactionCount,
  });

  final int totalIncome;
  final int totalExpense;
  final int transactionCount;

  int get netCashflow => totalIncome - totalExpense;

  double get savingRatePercent {
    if (totalIncome <= 0) return 0;
    return ((totalIncome - totalExpense) / totalIncome) * 100;
  }
}

class BudgetProgressItem {
  const BudgetProgressItem({
    required this.budget,
    required this.spentAmount,
    this.category,
  });

  final Budget budget;
  final int spentAmount;
  final Category? category;

  double get ratio =>
      budget.limitAmount <= 0 ? 0 : spentAmount / budget.limitAmount;

  int get remainingAmount => budget.limitAmount - spentAmount;

  bool get isOverBudget => budget.limitAmount > 0 && spentAmount > budget.limitAmount;

  bool get isWarning =>
      budget.limitAmount > 0 && ratio >= 0.8 && !isOverBudget;
}

class RecurringBillWithDetails {
  const RecurringBillWithDetails({
    required this.bill,
    required this.isPaidForMonth,
    required this.dueDateForMonth,
    required this.daysUntilDue,
    this.category,
    this.wallet,
    this.installmentNumber,
    this.totalInstallments,
  });

  final RecurringBill bill;
  final bool isPaidForMonth;
  final DateTime dueDateForMonth;
  final int daysUntilDue;
  final Category? category;
  final Wallet? wallet;
  final int? installmentNumber;
  final int? totalInstallments;

  bool get isOverdue => !isPaidForMonth && daysUntilDue < 0;
  bool get isDueSoon => !isPaidForMonth && daysUntilDue >= 0 && daysUntilDue <= 3;
  bool get hasInstallmentPlan =>
      installmentNumber != null &&
      totalInstallments != null &&
      totalInstallments! > 0;
}

class CategorySpendItem {
  const CategorySpendItem({
    required this.categoryId,
    required this.categoryName,
    required this.icon,
    required this.color,
    required this.amount,
    required this.percentage,
    required this.transactionCount,
  });

  final String categoryId;
  final String categoryName;
  final String icon;
  final int color;
  final int amount;
  final double percentage;
  final int transactionCount;
}

class MonthlyTrendPoint {
  const MonthlyTrendPoint({
    required this.month,
    required this.income,
    required this.expense,
  });

  final DateTime month;
  final int income;
  final int expense;
}

class MonthlyReportData {
  const MonthlyReportData({
    required this.month,
    required this.summary,
    required this.expenseByCategory,
    required this.incomeByCategory,
    required this.trend6Months,
    required this.topExpenses,
  });

  final DateTime month;
  final MonthlyCashflowSummary summary;
  final List<CategorySpendItem> expenseByCategory;
  final List<CategorySpendItem> incomeByCategory;
  final List<MonthlyTrendPoint> trend6Months;
  final List<TransactionWithDetails> topExpenses;
}

@DriftDatabase(
  tables: [
    Families,
    Members,
    Wallets,
    Categories,
    Transactions,
    Budgets,
    RecurringBills,
    SyncPeers,
    AiChatMessages,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'si_hemat_db'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await m.addColumn(recurringBills, recurringBills.startMonth);
            await m.addColumn(recurringBills, recurringBills.endMonth);
            await m.addColumn(recurringBills, recurringBills.paidMonths);
            await customStatement(
              "UPDATE recurring_bills SET paid_months = COALESCE(last_paid_month, '') WHERE paid_months = ''",
            );
          }
        },
      );

  /// Emits [loader] immediately on listen, then re-emits whenever any table in [tables] changes.
  /// Uses a managed StreamController + `tableUpdates` so each query tracks its own exact
  /// table set independently and cancels instantaneously on unsubscribe.
  Stream<T> _watchTables<T>(
    Set<TableInfo<Table, dynamic>> tables,
    Future<T> Function() loader,
  ) {
    late StreamController<T> controller;
    StreamSubscription<Set<TableUpdate>>? sub;

    Future<void> emit() async {
      try {
        final data = await loader();
        if (!controller.isClosed) {
          controller.add(data);
        }
      } catch (e, st) {
        if (!controller.isClosed) {
          controller.addError(e, st);
        }
      }
    }

    controller = StreamController<T>(
      onListen: () {
        emit();
        sub = tableUpdates(TableUpdateQuery.onAllTables(tables)).listen((_) {
          emit();
        });
      },
      onCancel: () async {
        await sub?.cancel();
        sub = null;
      },
    );
    return controller.stream;
  }

  /// Watches the active (non-deleted) family workspace if already set up.
  Stream<Family?> watchActiveFamily() {
    return (select(families)
          ..where((t) => t.isDeleted.equals(false))
          ..limit(1))
        .watchSingleOrNull();
  }

  Future<Family?> getActiveFamily() {
    return (select(families)
          ..where((t) => t.isDeleted.equals(false))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<void> updateFamilyPayday({
    required String familyId,
    required int paydayDay,
    required String deviceId,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (update(families)..where((t) => t.id.equals(familyId))).write(
      FamiliesCompanion(
        paydayDay: Value(paydayDay.clamp(1, 31)),
        updatedAt: Value(now),
        updatedByDeviceId: Value(deviceId),
      ),
    );
  }

  Future<void> updateFamilyName({
    required String familyId,
    required String name,
    required String deviceId,
  }) async {
    final cleaned = name.trim();
    if (cleaned.isEmpty) {
      throw ArgumentError('Nama buku keluarga wajib diisi.');
    }
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (update(families)..where((t) => t.id.equals(familyId))).write(
      FamiliesCompanion(
        name: Value(cleaned),
        updatedAt: Value(now),
        updatedByDeviceId: Value(deviceId),
      ),
    );
  }

  Future<void> updateMemberName({
    required String memberId,
    required String name,
    required String deviceId,
  }) async {
    final cleaned = name.trim();
    if (cleaned.isEmpty) {
      throw ArgumentError('Nama panggilan wajib diisi.');
    }
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (update(members)..where((t) => t.id.equals(memberId))).write(
      MembersCompanion(
        name: Value(cleaned),
        updatedAt: Value(now),
        updatedByDeviceId: Value(deviceId),
      ),
    );
  }

  Future<String> insertCategory({
    required String id,
    required String familyId,
    required String name,
    required String type,
    required String icon,
    required int color,
    required String deviceId,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await into(categories).insert(
      CategoriesCompanion.insert(
        id: id,
        familyId: familyId,
        name: name.trim(),
        type: type,
        icon: icon,
        color: color,
        isDefault: const Value(false),
        createdAt: now,
        updatedAt: now,
        updatedByDeviceId: deviceId,
      ),
    );
    return id;
  }

  Future<void> updateCategoryRow({
    required String id,
    required String name,
    required String icon,
    required int color,
    required String deviceId,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (update(categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(
        name: Value(name.trim()),
        icon: Value(icon),
        color: Value(color),
        updatedAt: Value(now),
        updatedByDeviceId: Value(deviceId),
      ),
    );
  }

  Future<void> softDeleteCategory({
    required String id,
    required String deviceId,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (update(categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(now),
        updatedByDeviceId: Value(deviceId),
      ),
    );
  }

  Future<int> countActiveTransactionsForCategory(String categoryId) async {
    final rows = await (select(transactions)
          ..where(
            (t) => t.isDeleted.equals(false) & t.categoryId.equals(categoryId),
          ))
        .get();
    return rows.length;
  }

  Stream<List<Member>> watchFamilyMembers(String familyId) {
    return (select(members)
          ..where(
            (t) => t.familyId.equals(familyId) & t.isDeleted.equals(false),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }

  Future<List<Member>> getFamilyMembers(String familyId) {
    return (select(members)
          ..where(
            (t) => t.familyId.equals(familyId) & t.isDeleted.equals(false),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Stream<List<Category>> watchCategories(String familyId, {String? type}) {
    final query = select(categories)
      ..where((t) {
        final base = t.familyId.equals(familyId) & t.isDeleted.equals(false);
        if (type == null) return base;
        return base & t.type.equals(type);
      })
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    return query.watch();
  }

  /// Deterministically computes each wallet's balance from initialBalance + non-deleted transactions.
  /// Reactive across BOTH `wallets` and `transactions` tables so balances update instantly.
  Stream<List<WalletWithBalance>> watchWalletsWithBalance(
    String familyId, {
    String? visibilityFilter,
  }) {
    return _watchTables(
      {wallets, transactions},
      () => getWalletsWithBalance(
        familyId,
        visibilityFilter: visibilityFilter,
      ),
    );
  }

  Future<List<WalletWithBalance>> getWalletsWithBalance(
    String familyId, {
    String? visibilityFilter,
  }) async {
    final walletsQuery = select(wallets)
      ..where((w) {
        final base = w.familyId.equals(familyId) & w.isDeleted.equals(false);
        if (visibilityFilter == null || visibilityFilter == 'all') return base;
        return base & w.visibility.equals(visibilityFilter);
      })
      ..orderBy([(w) => OrderingTerm.asc(w.createdAt)]);

    final walletList = await walletsQuery.get();
    final allTx = await (select(transactions)
          ..where(
            (t) => t.familyId.equals(familyId) & t.isDeleted.equals(false),
          ))
        .get();
    return _combineWalletBalances(walletList, allTx);
  }

  List<WalletWithBalance> _combineWalletBalances(
    List<Wallet> walletList,
    List<Transaction> txList,
  ) {
    final deltas = <String, int>{};
    for (final tx in txList) {
      if (tx.type == TransactionType.income) {
        deltas[tx.walletId] = (deltas[tx.walletId] ?? 0) + tx.amount;
      } else if (tx.type == TransactionType.expense) {
        deltas[tx.walletId] = (deltas[tx.walletId] ?? 0) - tx.amount;
      } else if (tx.type == TransactionType.transfer) {
        deltas[tx.walletId] = (deltas[tx.walletId] ?? 0) - tx.amount;
        if (tx.toWalletId != null) {
          deltas[tx.toWalletId!] = (deltas[tx.toWalletId!] ?? 0) + tx.amount;
        }
      }
    }

    return walletList
        .map(
          (w) => WalletWithBalance(
            wallet: w,
            balance: w.initialBalance + (deltas[w.id] ?? 0),
          ),
        )
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Wallet CRUD
  // ---------------------------------------------------------------------------

  Future<String> insertWallet({
    required String id,
    required String familyId,
    required String ownerMemberId,
    required String name,
    required String type,
    required String visibility,
    required int initialBalance,
    required int color,
    required String deviceId,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await into(wallets).insert(
      WalletsCompanion.insert(
        id: id,
        familyId: familyId,
        ownerMemberId: Value(ownerMemberId),
        name: name.trim(),
        type: type,
        visibility: Value(visibility),
        initialBalance: Value(initialBalance),
        color: Value(color),
        createdAt: now,
        updatedAt: now,
        updatedByDeviceId: deviceId,
      ),
    );
    return id;
  }

  Future<void> updateWalletRow({
    required String id,
    required String name,
    required String type,
    required String visibility,
    required int initialBalance,
    required int color,
    required String deviceId,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (update(wallets)..where((w) => w.id.equals(id))).write(
      WalletsCompanion(
        name: Value(name.trim()),
        type: Value(type),
        visibility: Value(visibility),
        initialBalance: Value(initialBalance),
        color: Value(color),
        updatedAt: Value(now),
        updatedByDeviceId: Value(deviceId),
      ),
    );
  }

  Future<void> softDeleteWallet({
    required String id,
    required String deviceId,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (update(wallets)..where((w) => w.id.equals(id))).write(
      WalletsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(now),
        updatedByDeviceId: Value(deviceId),
      ),
    );
  }

  Future<int> countActiveTransactionsForWallet(String walletId) async {
    final rows = await (select(transactions)
          ..where(
            (t) =>
                t.isDeleted.equals(false) &
                (t.walletId.equals(walletId) | t.toWalletId.equals(walletId)),
          ))
        .get();
    return rows.length;
  }

  // ---------------------------------------------------------------------------
  // Transaction CRUD & Reactive Queries
  // ---------------------------------------------------------------------------

  Future<String> insertTransaction({
    required String id,
    required String familyId,
    required String memberId,
    required String walletId,
    String? toWalletId,
    String? categoryId,
    required String type,
    required int amount,
    required DateTime date,
    String? merchant,
    String? note,
    String? receiptHash,
    String source = TransactionSource.manual,
    required String visibility,
    required String deviceId,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await into(transactions).insert(
      TransactionsCompanion.insert(
        id: id,
        familyId: familyId,
        memberId: memberId,
        walletId: walletId,
        toWalletId: Value(toWalletId),
        categoryId: Value(categoryId),
        type: type,
        amount: amount,
        date: date.toUtc().millisecondsSinceEpoch,
        merchant: Value(_cleanOptional(merchant)),
        note: Value(_cleanOptional(note)),
        receiptHash: Value(_cleanOptional(receiptHash)),
        source: Value(source),
        visibility: Value(visibility),
        createdAt: now,
        updatedAt: now,
        updatedByDeviceId: deviceId,
      ),
    );
    return id;
  }

  Future<void> updateTransactionRow({
    required String id,
    required String walletId,
    String? toWalletId,
    String? categoryId,
    required String type,
    required int amount,
    required DateTime date,
    String? merchant,
    String? note,
    required String visibility,
    required String deviceId,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (update(transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        walletId: Value(walletId),
        toWalletId: Value(toWalletId),
        categoryId: Value(categoryId),
        type: Value(type),
        amount: Value(amount),
        date: Value(date.toUtc().millisecondsSinceEpoch),
        merchant: Value(_cleanOptional(merchant)),
        note: Value(_cleanOptional(note)),
        visibility: Value(visibility),
        updatedAt: Value(now),
        updatedByDeviceId: Value(deviceId),
      ),
    );
  }

  Future<void> softDeleteTransaction({
    required String id,
    required String deviceId,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (update(transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(now),
        updatedByDeviceId: Value(deviceId),
      ),
    );
  }

  Future<void> restoreTransaction({
    required String id,
    required String deviceId,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (update(transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        isDeleted: const Value(false),
        updatedAt: Value(now),
        updatedByDeviceId: Value(deviceId),
      ),
    );
  }

  Stream<List<TransactionWithDetails>> watchTransactionsDetailed(
    String familyId, {
    DateTime? month,
    String? visibilityFilter,
    String? typeFilter,
    String? memberIdFilter,
    String? walletIdFilter,
    String? categoryIdFilter,
    String? searchQuery,
    int? limit,
  }) {
    return _watchTables(
      {transactions, wallets, categories, members},
      () => getTransactionsDetailed(
        familyId,
        month: month,
        visibilityFilter: visibilityFilter,
        typeFilter: typeFilter,
        memberIdFilter: memberIdFilter,
        walletIdFilter: walletIdFilter,
        categoryIdFilter: categoryIdFilter,
        searchQuery: searchQuery,
        limit: limit,
      ),
    );
  }

  Future<List<TransactionWithDetails>> getTransactionsDetailed(
    String familyId, {
    DateTime? month,
    String? visibilityFilter,
    String? typeFilter,
    String? memberIdFilter,
    String? walletIdFilter,
    String? categoryIdFilter,
    String? searchQuery,
    int? limit,
  }) async {
    final query = select(transactions)
      ..where((t) {
        var expr = t.familyId.equals(familyId) & t.isDeleted.equals(false);
        if (visibilityFilter != null && visibilityFilter != 'all') {
          expr = expr & t.visibility.equals(visibilityFilter);
        }
        if (typeFilter != null && typeFilter != 'all') {
          expr = expr & t.type.equals(typeFilter);
        }
        if (memberIdFilter != null && memberIdFilter.isNotEmpty) {
          expr = expr & t.memberId.equals(memberIdFilter);
        }
        if (walletIdFilter != null && walletIdFilter.isNotEmpty) {
          expr = expr &
              (t.walletId.equals(walletIdFilter) |
                  t.toWalletId.equals(walletIdFilter));
        }
        if (categoryIdFilter != null && categoryIdFilter.isNotEmpty) {
          expr = expr & t.categoryId.equals(categoryIdFilter);
        }
        if (month != null) {
          final startMs =
              DateTime(month.year, month.month, 1).toUtc().millisecondsSinceEpoch;
          final endMs = DateTime(month.year, month.month + 1, 1)
              .toUtc()
              .millisecondsSinceEpoch;
          expr = expr &
              t.date.isBiggerOrEqualValue(startMs) &
              t.date.isSmallerThanValue(endMs);
        }
        return expr;
      })
      ..orderBy([
        (t) => OrderingTerm.desc(t.date),
        (t) => OrderingTerm.desc(t.createdAt),
      ]);

    final txList = await query.get();
    final walletList = await (select(wallets)
          ..where((w) => w.familyId.equals(familyId)))
        .get();
    final categoryList = await (select(categories)
          ..where((c) => c.familyId.equals(familyId)))
        .get();
    final memberList = await (select(members)
          ..where((m) => m.familyId.equals(familyId)))
        .get();

    final walletMap = {for (final w in walletList) w.id: w};
    final categoryMap = {for (final c in categoryList) c.id: c};
    final memberMap = {for (final m in memberList) m.id: m};

    final needle = searchQuery?.trim().toLowerCase() ?? '';
    final detailed = <TransactionWithDetails>[];

    for (final tx in txList) {
      final w = walletMap[tx.walletId];
      final toW = tx.toWalletId != null ? walletMap[tx.toWalletId!] : null;
      final c = tx.categoryId != null ? categoryMap[tx.categoryId!] : null;
      final m = memberMap[tx.memberId];

      if (needle.isNotEmpty) {
        final haystack = [
          tx.merchant ?? '',
          tx.note ?? '',
          c?.name ?? '',
          w?.name ?? '',
          toW?.name ?? '',
          m?.name ?? '',
        ].join(' ').toLowerCase();
        if (!haystack.contains(needle)) continue;
      }

      detailed.add(
        TransactionWithDetails(
          transaction: tx,
          wallet: w,
          toWallet: toW,
          category: c,
          member: m,
        ),
      );
      if (limit != null && detailed.length >= limit) break;
    }

    return detailed;
  }

  /// Computes deterministic monthly income & expense summary.
  /// Transfers and soft-deleted transactions are strictly excluded from income/expense totals.
  Stream<MonthlyCashflowSummary> watchMonthlySummary(
    String familyId, {
    required DateTime month,
    String? visibilityFilter,
  }) {
    return _watchTables(
      {transactions},
      () => getMonthlySummary(
        familyId,
        month: month,
        visibilityFilter: visibilityFilter,
      ),
    );
  }

  Future<MonthlyCashflowSummary> getMonthlySummary(
    String familyId, {
    required DateTime month,
    String? visibilityFilter,
  }) async {
    final startMs =
        DateTime(month.year, month.month, 1).toUtc().millisecondsSinceEpoch;
    final endMs =
        DateTime(month.year, month.month + 1, 1).toUtc().millisecondsSinceEpoch;

    final txList = await (select(transactions)
          ..where((t) {
            var expr = t.familyId.equals(familyId) &
                t.isDeleted.equals(false) &
                t.date.isBiggerOrEqualValue(startMs) &
                t.date.isSmallerThanValue(endMs);
            if (visibilityFilter != null && visibilityFilter != 'all') {
              expr = expr & t.visibility.equals(visibilityFilter);
            }
            return expr;
          }))
        .get();

    var income = 0;
    var expense = 0;
    for (final tx in txList) {
      if (tx.type == TransactionType.income) {
        income += tx.amount;
      } else if (tx.type == TransactionType.expense) {
        expense += tx.amount;
      }
    }

    return MonthlyCashflowSummary(
      totalIncome: income,
      totalExpense: expense,
      transactionCount: txList.length,
    );
  }

  String? _cleanOptional(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  // ---------------------------------------------------------------------------
  // Monthly Budgets CRUD & Progress
  // ---------------------------------------------------------------------------

  Future<String> upsertBudget({
    required String id,
    required String familyId,
    required String categoryId,
    required String monthKey,
    required int limitAmount,
    required String visibility,
    required String deviceId,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final existing = await (select(budgets)
          ..where(
            (b) =>
                b.familyId.equals(familyId) &
                b.categoryId.equals(categoryId) &
                b.monthKey.equals(monthKey) &
                b.visibility.equals(visibility) &
                b.isDeleted.equals(false),
          )
          ..limit(1))
        .getSingleOrNull();

    if (existing != null) {
      await (update(budgets)..where((b) => b.id.equals(existing.id))).write(
        BudgetsCompanion(
          limitAmount: Value(limitAmount),
          updatedAt: Value(now),
          updatedByDeviceId: Value(deviceId),
        ),
      );
      return existing.id;
    }

    await into(budgets).insert(
      BudgetsCompanion.insert(
        id: id,
        familyId: familyId,
        categoryId: categoryId,
        monthKey: monthKey,
        limitAmount: limitAmount,
        visibility: Value(visibility),
        createdAt: now,
        updatedAt: now,
        updatedByDeviceId: deviceId,
      ),
    );
    return id;
  }

  Future<void> softDeleteBudget({
    required String id,
    required String deviceId,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (update(budgets)..where((b) => b.id.equals(id))).write(
      BudgetsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(now),
        updatedByDeviceId: Value(deviceId),
      ),
    );
  }

  /// Copies active budgets from [sourceMonthKey] to [targetMonthKey] if not already set.
  Future<int> copyBudgetsFromMonth({
    required String familyId,
    required String sourceMonthKey,
    required String targetMonthKey,
    required String deviceId,
  }) async {
    const uuid = Uuid();
    final sourceBudgets = await (select(budgets)
          ..where(
            (b) =>
                b.familyId.equals(familyId) &
                b.monthKey.equals(sourceMonthKey) &
                b.isDeleted.equals(false),
          ))
        .get();

    var copied = 0;
    for (final src in sourceBudgets) {
      final exists = await (select(budgets)
            ..where(
              (b) =>
                  b.familyId.equals(familyId) &
                  b.categoryId.equals(src.categoryId) &
                  b.monthKey.equals(targetMonthKey) &
                  b.visibility.equals(src.visibility) &
                  b.isDeleted.equals(false),
            )
            ..limit(1))
          .getSingleOrNull();
      if (exists != null) continue;

      await upsertBudget(
        id: uuid.v4(),
        familyId: familyId,
        categoryId: src.categoryId,
        monthKey: targetMonthKey,
        limitAmount: src.limitAmount,
        visibility: src.visibility,
        deviceId: deviceId,
      );
      copied++;
    }
    return copied;
  }

  Stream<List<BudgetProgressItem>> watchBudgetsWithProgress(
    String familyId, {
    required DateTime month,
    String? visibilityFilter,
  }) {
    return _watchTables(
      {budgets, categories, transactions},
      () => getBudgetsWithProgress(
        familyId,
        month: month,
        visibilityFilter: visibilityFilter,
      ),
    );
  }

  Future<List<BudgetProgressItem>> getBudgetsWithProgress(
    String familyId, {
    required DateTime month,
    String? visibilityFilter,
  }) async {
    final monthKey =
        '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';
    final budgetList = await (select(budgets)
          ..where((b) {
            var expr = b.familyId.equals(familyId) &
                b.monthKey.equals(monthKey) &
                b.isDeleted.equals(false);
            if (visibilityFilter != null && visibilityFilter != 'all') {
              expr = expr & b.visibility.equals(visibilityFilter);
            }
            return expr;
          })
          ..orderBy([(b) => OrderingTerm.asc(b.createdAt)]))
        .get();

    final startMs =
        DateTime(month.year, month.month, 1).toUtc().millisecondsSinceEpoch;
    final endMs =
        DateTime(month.year, month.month + 1, 1).toUtc().millisecondsSinceEpoch;

    final expenses = await (select(transactions)
          ..where((t) {
            var expr = t.familyId.equals(familyId) &
                t.isDeleted.equals(false) &
                t.type.equals(TransactionType.expense) &
                t.date.isBiggerOrEqualValue(startMs) &
                t.date.isSmallerThanValue(endMs);
            if (visibilityFilter != null && visibilityFilter != 'all') {
              expr = expr & t.visibility.equals(visibilityFilter);
            }
            return expr;
          }))
        .get();

    final categoryList = await (select(categories)
          ..where((c) => c.familyId.equals(familyId)))
        .get();
    final categoryMap = {for (final c in categoryList) c.id: c};

    final spentByKey = <String, int>{};
    for (final tx in expenses) {
      if (tx.categoryId == null) continue;
      final scopeKey = '${tx.categoryId}|${tx.visibility}';
      spentByKey[scopeKey] = (spentByKey[scopeKey] ?? 0) + tx.amount;
      final allKey = '${tx.categoryId}|all';
      spentByKey[allKey] = (spentByKey[allKey] ?? 0) + tx.amount;
    }

    final items = budgetList.map((b) {
      final spent = spentByKey['${b.categoryId}|${b.visibility}'] ?? 0;
      return BudgetProgressItem(
        budget: b,
        spentAmount: spent,
        category: categoryMap[b.categoryId],
      );
    }).toList();

    // Sort highest usage ratio first so over-budget items stay visible at top
    items.sort((a, b) => b.ratio.compareTo(a.ratio));
    return items;
  }

  // ---------------------------------------------------------------------------
  // Recurring Bills CRUD & Payment (History-Preserving & Tenor-Aware)
  // ---------------------------------------------------------------------------

  Future<String> insertRecurringBill({
    required String id,
    required String familyId,
    String? walletId,
    required String categoryId,
    required String name,
    required int amount,
    required int dueDay,
    String? startMonth,
    String? endMonth,
    required String visibility,
    required String deviceId,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await into(recurringBills).insert(
      RecurringBillsCompanion.insert(
        id: id,
        familyId: familyId,
        walletId: Value(walletId),
        categoryId: categoryId,
        name: name.trim(),
        amount: amount,
        dueDay: dueDay.clamp(1, 31),
        startMonth: Value(startMonth),
        endMonth: Value(endMonth),
        visibility: Value(visibility),
        createdAt: now,
        updatedAt: now,
        updatedByDeviceId: deviceId,
      ),
    );
    return id;
  }

  Future<void> updateRecurringBillRow({
    required String id,
    String? walletId,
    required String categoryId,
    required String name,
    required int amount,
    required int dueDay,
    String? startMonth,
    String? endMonth,
    required String visibility,
    required String deviceId,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (update(recurringBills)..where((b) => b.id.equals(id))).write(
      RecurringBillsCompanion(
        walletId: Value(walletId),
        categoryId: Value(categoryId),
        name: Value(name.trim()),
        amount: Value(amount),
        dueDay: Value(dueDay.clamp(1, 31)),
        startMonth: Value(startMonth),
        endMonth: Value(endMonth),
        visibility: Value(visibility),
        updatedAt: Value(now),
        updatedByDeviceId: Value(deviceId),
      ),
    );
  }

  /// Stops a recurring bill from [fromMonth] onward while preserving all earlier months'
  /// history (e.g. months 1..12 stay intact when stopping at month 13).
  /// If the bill has no active months before [fromMonth], it soft-deletes completely.
  Future<void> stopRecurringBillFromMonth({
    required String id,
    required DateTime fromMonth,
    required String deviceId,
  }) async {
    final existing = await (select(recurringBills)
          ..where((b) => b.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
    if (existing == null) return;

    final prevMonth = DateTime(fromMonth.year, fromMonth.month - 1, 1);
    final prevKey = _toMonthKey(prevMonth);
    final paidSet = parsePaidMonths(existing);
    final hasHistoryBefore = paidSet.any((m) => m.compareTo(prevKey) <= 0) ||
        (existing.startMonth != null &&
            existing.startMonth!.compareTo(prevKey) <= 0);

    if (!hasHistoryBefore && existing.startMonth != null) {
      await softDeleteRecurringBill(id: id, deviceId: deviceId);
      return;
    }

    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (update(recurringBills)..where((b) => b.id.equals(id))).write(
      RecurringBillsCompanion(
        endMonth: Value(prevKey),
        updatedAt: Value(now),
        updatedByDeviceId: Value(deviceId),
      ),
    );
  }

  Future<void> softDeleteRecurringBill({
    required String id,
    required String deviceId,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await (update(recurringBills)..where((b) => b.id.equals(id))).write(
      RecurringBillsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(now),
        updatedByDeviceId: Value(deviceId),
      ),
    );
  }

  /// Atomically marks a recurring bill paid for [monthKey] (appending to `paidMonths` so
  /// all previously paid months remain recorded) AND records the expense transaction.
  Future<String> payRecurringBillAtomically({
    required RecurringBill bill,
    required String transactionId,
    required String memberId,
    required String walletId,
    required String visibility,
    required String monthKey,
    required DateTime paidAt,
    required String deviceId,
    int? overrideAmount,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final actualAmount = overrideAmount ?? bill.amount;

    await transaction(() async {
      final latest = await (select(recurringBills)
            ..where((b) => b.id.equals(bill.id))
            ..limit(1))
          .getSingleOrNull();
      final paidSet = parsePaidMonths(latest ?? bill)..add(monthKey);
      final sortedPaid = paidSet.toList()..sort();

      await (update(recurringBills)..where((b) => b.id.equals(bill.id))).write(
        RecurringBillsCompanion(
          lastPaidMonth: Value(sortedPaid.last),
          paidMonths: Value(sortedPaid.join(',')),
          walletId: Value(walletId),
          updatedAt: Value(now),
          updatedByDeviceId: Value(deviceId),
        ),
      );

      await into(transactions).insert(
        TransactionsCompanion.insert(
          id: transactionId,
          familyId: bill.familyId,
          memberId: memberId,
          walletId: walletId,
          categoryId: Value(bill.categoryId),
          type: TransactionType.expense,
          amount: actualAmount,
          date: paidAt.toUtc().millisecondsSinceEpoch,
          merchant: Value(bill.name),
          note: Value('Tagihan rutin $monthKey'),
          source: const Value(TransactionSource.recurring),
          visibility: Value(visibility),
          createdAt: now,
          updatedAt: now,
          updatedByDeviceId: deviceId,
        ),
      );
    });

    return transactionId;
  }

  static Set<String> parsePaidMonths(RecurringBill bill) {
    final set = <String>{};
    if (bill.paidMonths.isNotEmpty) {
      for (final part in bill.paidMonths.split(',')) {
        final trimmed = part.trim();
        if (trimmed.isNotEmpty) set.add(trimmed);
      }
    }
    if (bill.lastPaidMonth != null && bill.lastPaidMonth!.isNotEmpty) {
      set.add(bill.lastPaidMonth!);
    }
    return set;
  }

  static String _toMonthKey(DateTime month) =>
      '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';

  static int? _monthDiff(String startKey, String endKey) {
    final sParts = startKey.split('-');
    final eParts = endKey.split('-');
    if (sParts.length != 2 || eParts.length != 2) return null;
    final sy = int.tryParse(sParts[0]);
    final sm = int.tryParse(sParts[1]);
    final ey = int.tryParse(eParts[0]);
    final em = int.tryParse(eParts[1]);
    if (sy == null || sm == null || ey == null || em == null) return null;
    return (ey - sy) * 12 + (em - sm);
  }

  Stream<List<RecurringBillWithDetails>> watchRecurringBills(
    String familyId, {
    required DateTime month,
    String? visibilityFilter,
  }) {
    return _watchTables(
      {recurringBills, categories, wallets},
      () => getRecurringBills(
        familyId,
        month: month,
        visibilityFilter: visibilityFilter,
      ),
    );
  }

  Future<List<RecurringBillWithDetails>> getRecurringBills(
    String familyId, {
    required DateTime month,
    String? visibilityFilter,
    DateTime? referenceNow,
  }) async {
    final monthKey = _toMonthKey(month);
    final bills = await (select(recurringBills)
          ..where((b) {
            var expr = b.familyId.equals(familyId) &
                b.isDeleted.equals(false) &
                b.isActive.equals(true);
            if (visibilityFilter != null && visibilityFilter != 'all') {
              expr = expr & b.visibility.equals(visibilityFilter);
            }
            return expr;
          })
          ..orderBy([(b) => OrderingTerm.asc(b.dueDay)]))
        .get();

    final categoryList = await (select(categories)
          ..where((c) => c.familyId.equals(familyId)))
        .get();
    final walletList = await (select(wallets)
          ..where((w) => w.familyId.equals(familyId)))
        .get();
    final categoryMap = {for (final c in categoryList) c.id: c};
    final walletMap = {for (final w in walletList) w.id: w};

    final now = referenceNow ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastDayOfMonth = DateTime(month.year, month.month + 1, 0).day;

    final result = <RecurringBillWithDetails>[];
    for (final bill in bills) {
      // Respect startMonth & endMonth lifecycle window
      if (bill.startMonth != null &&
          bill.startMonth!.isNotEmpty &&
          monthKey.compareTo(bill.startMonth!) < 0) {
        continue;
      }
      if (bill.endMonth != null &&
          bill.endMonth!.isNotEmpty &&
          monthKey.compareTo(bill.endMonth!) > 0) {
        continue;
      }

      final dueDay = bill.dueDay.clamp(1, lastDayOfMonth);
      final dueDate = DateTime(month.year, month.month, dueDay);
      final paidSet = parsePaidMonths(bill);
      final isPaid = paidSet.contains(monthKey);
      final daysUntil = dueDate.difference(today).inDays;

      int? installmentNumber;
      int? totalInstallments;
      if (bill.startMonth != null && bill.endMonth != null) {
        final totalDiff = _monthDiff(bill.startMonth!, bill.endMonth!);
        final curDiff = _monthDiff(bill.startMonth!, monthKey);
        if (totalDiff != null && curDiff != null && totalDiff >= 0) {
          totalInstallments = totalDiff + 1;
          installmentNumber = curDiff + 1;
        }
      }

      result.add(
        RecurringBillWithDetails(
          bill: bill,
          isPaidForMonth: isPaid,
          dueDateForMonth: dueDate,
          daysUntilDue: daysUntil,
          category: categoryMap[bill.categoryId],
          wallet: bill.walletId != null ? walletMap[bill.walletId!] : null,
          installmentNumber: installmentNumber,
          totalInstallments: totalInstallments,
        ),
      );
    }

    // Unpaid bills sorted by closest due date first, paid bills below
    result.sort((a, b) {
      if (a.isPaidForMonth != b.isPaidForMonth) {
        return a.isPaidForMonth ? 1 : -1;
      }
      return a.dueDateForMonth.compareTo(b.dueDateForMonth);
    });
    return result;
  }

  // ---------------------------------------------------------------------------
  // Monthly Reports & 6-Month Trends (Deterministic SQLite Analytics)
  // ---------------------------------------------------------------------------

  Stream<MonthlyReportData> watchMonthlyReport(
    String familyId, {
    required DateTime month,
    String? visibilityFilter,
  }) {
    return _watchTables(
      {transactions, categories, wallets, members},
      () => getMonthlyReport(
        familyId,
        month: month,
        visibilityFilter: visibilityFilter,
      ),
    );
  }

  Future<MonthlyReportData> getMonthlyReport(
    String familyId, {
    required DateTime month,
    String? visibilityFilter,
  }) async {
    final normalizedMonth = DateTime(month.year, month.month, 1);
    final summary = await getMonthlySummary(
      familyId,
      month: normalizedMonth,
      visibilityFilter: visibilityFilter,
    );

    final monthTxs = await getTransactionsDetailed(
      familyId,
      month: normalizedMonth,
      visibilityFilter: visibilityFilter,
    );

    final expBreakdown = _aggregateByCategory(
      monthTxs.where((t) => t.transaction.type == TransactionType.expense),
      summary.totalExpense,
    );
    final incBreakdown = _aggregateByCategory(
      monthTxs.where((t) => t.transaction.type == TransactionType.income),
      summary.totalIncome,
    );

    final topExpenses = monthTxs
        .where((t) => t.transaction.type == TransactionType.expense)
        .toList()
      ..sort((a, b) => b.transaction.amount.compareTo(a.transaction.amount));

    final trend = <MonthlyTrendPoint>[];
    for (var offset = 5; offset >= 0; offset--) {
      final m = DateTime(normalizedMonth.year, normalizedMonth.month - offset, 1);
      final s = await getMonthlySummary(
        familyId,
        month: m,
        visibilityFilter: visibilityFilter,
      );
      trend.add(
        MonthlyTrendPoint(
          month: m,
          income: s.totalIncome,
          expense: s.totalExpense,
        ),
      );
    }

    return MonthlyReportData(
      month: normalizedMonth,
      summary: summary,
      expenseByCategory: expBreakdown,
      incomeByCategory: incBreakdown,
      trend6Months: trend,
      topExpenses: topExpenses.take(5).toList(),
    );
  }

  List<CategorySpendItem> _aggregateByCategory(
    Iterable<TransactionWithDetails> items,
    int totalAmount,
  ) {
    final amounts = <String, int>{};
    final counts = <String, int>{};
    final meta = <String, Category?>{};

    for (final item in items) {
      final catId = item.category?.id ?? 'uncategorized';
      amounts[catId] = (amounts[catId] ?? 0) + item.transaction.amount;
      counts[catId] = (counts[catId] ?? 0) + 1;
      meta[catId] = item.category;
    }

    final result = amounts.entries.map((entry) {
      final cat = meta[entry.key];
      final pct = totalAmount <= 0 ? 0.0 : (entry.value / totalAmount) * 100;
      return CategorySpendItem(
        categoryId: entry.key,
        categoryName: cat?.name ?? 'Lainnya',
        icon: cat?.icon ?? 'more_horiz',
        color: cat?.color ?? 0xFF7F8C8D,
        amount: entry.value,
        percentage: pct,
        transactionCount: counts[entry.key] ?? 0,
      );
    }).toList();

    result.sort((a, b) => b.amount.compareTo(a.amount));
    return result;
  }

  // ---------------------------------------------------------------------------
  // AI Chat Messages (Local-only history)
  // ---------------------------------------------------------------------------

  Stream<List<AiChatMessage>> watchAiChatMessages() {
    return (select(aiChatMessages)
          ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]))
        .watch();
  }

  Future<void> insertAiChatMessage({
    required String id,
    required String role,
    required String content,
    String? draftJson,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await into(aiChatMessages).insert(
      AiChatMessagesCompanion.insert(
        id: id,
        role: role,
        content: content,
        draftJson: Value(draftJson),
        createdAt: now,
      ),
    );
  }

  Future<void> clearAiChatMessages() async {
    await delete(aiChatMessages).go();
  }

  // ---------------------------------------------------------------------------
  // Local Sync Peers Metadata (not synced)
  // ---------------------------------------------------------------------------

  Stream<List<SyncPeer>> watchSyncPeers() {
    return (select(syncPeers)
          ..orderBy([(p) => OrderingTerm.desc(p.lastSyncedAt)]))
        .watch();
  }

  Future<SyncPeer?> getSyncPeer(String peerDeviceId) {
    return (select(syncPeers)
          ..where((p) => p.peerDeviceId.equals(peerDeviceId))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<void> upsertSyncPeer({
    required String peerDeviceId,
    required String peerName,
    required int lastSyncedAt,
    String? lastIp,
  }) async {
    await into(syncPeers).insertOnConflictUpdate(
      SyncPeersCompanion.insert(
        peerDeviceId: peerDeviceId,
        peerName: peerName,
        lastSyncedAt: Value(lastSyncedAt),
        lastIp: Value(lastIp),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Family Seeding (Onboarding)
  // ---------------------------------------------------------------------------

  Future<void> seedNewFamilyWorkspace({
    required String familyId,
    required String familyName,
    required int paydayDay,
    required String adminMemberId,
    required String adminName,
    required String deviceId,
    int initialCashBalance = 0,
    int initialBankBalance = 0,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    const uuid = Uuid();

    await transaction(() async {
      await into(families).insert(
        FamiliesCompanion.insert(
          id: familyId,
          name: familyName,
          paydayDay: Value(paydayDay),
          createdAt: now,
          updatedAt: now,
          updatedByDeviceId: deviceId,
        ),
      );

      await into(members).insert(
        MembersCompanion.insert(
          id: adminMemberId,
          familyId: familyId,
          deviceId: deviceId,
          name: adminName,
          role: const Value(MemberRole.admin),
          avatarColor: const Value(0xFF0E7C66),
          createdAt: now,
          updatedAt: now,
          updatedByDeviceId: deviceId,
        ),
      );

      await into(wallets).insert(
        WalletsCompanion.insert(
          id: uuid.v4(),
          familyId: familyId,
          ownerMemberId: Value(adminMemberId),
          name: 'Kas Keluarga',
          type: WalletType.cash,
          visibility: const Value(VisibilityScope.shared),
          initialBalance: Value(initialCashBalance),
          icon: const Value('payments'),
          color: const Value(0xFF0E7C66),
          createdAt: now,
          updatedAt: now,
          updatedByDeviceId: deviceId,
        ),
      );

      await into(wallets).insert(
        WalletsCompanion.insert(
          id: uuid.v4(),
          familyId: familyId,
          ownerMemberId: Value(adminMemberId),
          name: 'Rekening Keluarga',
          type: WalletType.bank,
          visibility: const Value(VisibilityScope.shared),
          initialBalance: Value(initialBankBalance),
          icon: const Value('account_balance'),
          color: const Value(0xFF1565C0),
          createdAt: now + 1,
          updatedAt: now + 1,
          updatedByDeviceId: deviceId,
        ),
      );

      await into(wallets).insert(
        WalletsCompanion.insert(
          id: uuid.v4(),
          familyId: familyId,
          ownerMemberId: Value(adminMemberId),
          name: 'Dompet Pribadi $adminName',
          type: WalletType.ewallet,
          visibility: const Value(VisibilityScope.personal),
          initialBalance: const Value(0),
          icon: const Value('account_balance_wallet'),
          color: const Value(0xFF6A1B9A),
          createdAt: now + 2,
          updatedAt: now + 2,
          updatedByDeviceId: deviceId,
        ),
      );

      await _seedDefaultCategories(
        familyId: familyId,
        deviceId: deviceId,
        timestamp: now,
      );
    });
  }

  Future<void> seedJoinedFamilyWorkspace({
    required String familyId,
    required String familyName,
    required int paydayDay,
    required String memberId,
    required String memberName,
    required String deviceId,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    const uuid = Uuid();

    await transaction(() async {
      await into(families).insertOnConflictUpdate(
        FamiliesCompanion.insert(
          id: familyId,
          name: familyName,
          paydayDay: Value(paydayDay),
          createdAt: now,
          updatedAt: now,
          updatedByDeviceId: deviceId,
        ),
      );

      await into(members).insertOnConflictUpdate(
        MembersCompanion.insert(
          id: memberId,
          familyId: familyId,
          deviceId: deviceId,
          name: memberName,
          role: const Value(MemberRole.member),
          avatarColor: const Value(0xFF2563EB),
          createdAt: now,
          updatedAt: now,
          updatedByDeviceId: deviceId,
        ),
      );

      await into(wallets).insert(
        WalletsCompanion.insert(
          id: uuid.v4(),
          familyId: familyId,
          ownerMemberId: Value(memberId),
          name: 'Dompet Pribadi $memberName',
          type: WalletType.cash,
          visibility: const Value(VisibilityScope.personal),
          initialBalance: const Value(0),
          icon: const Value('account_balance_wallet'),
          color: const Value(0xFF2563EB),
          createdAt: now,
          updatedAt: now,
          updatedByDeviceId: deviceId,
        ),
      );

      await _seedDefaultCategories(
        familyId: familyId,
        deviceId: deviceId,
        timestamp: now,
      );
    });
  }

  Future<void> _seedDefaultCategories({
    required String familyId,
    required String deviceId,
    required int timestamp,
  }) async {
    await batch((b) {
      b.insertAll(
        categories,
        kDefaultCategories.map(
          (seed) => CategoriesCompanion.insert(
            id: '${familyId}_${seed.key}',
            familyId: familyId,
            name: seed.name,
            type: seed.type,
            icon: seed.iconName,
            color: seed.colorValue,
            isDefault: const Value(true),
            createdAt: timestamp,
            updatedAt: timestamp,
            updatedByDeviceId: deviceId,
          ),
        ),
        mode: InsertMode.insertOrIgnore,
      );
    });
  }
}
