import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/core/security/secure_storage_service.dart';
import 'package:si_hemat/features/budgets/budget_bill_service.dart';
import 'package:si_hemat/features/onboarding/onboarding_service.dart';
import 'package:si_hemat/features/reports/report_export_service.dart';
import 'package:si_hemat/features/transactions/transaction_service.dart';

class _MemKeyStore implements SecureKeyStore {
  final Map<String, String> _map = {};
  @override
  Future<void> delete(String key) async => _map.remove(key);
  @override
  Future<String?> read(String key) async => _map[key];
  @override
  Future<void> write(String key, String value) async => _map[key] = value;
}

void main() {
  late AppDatabase db;
  late _MemKeyStore keyStore;
  late OnboardingService onboarding;
  late TransactionService txService;
  late BudgetBillService budgetBillService;
  late String familyId;

  setUpAll(() async {
    await initializeDateFormatting('id_ID');
  });

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    keyStore = _MemKeyStore();
    onboarding = OnboardingService(db: db, keyStore: keyStore);
    txService = TransactionService(
      db: db,
      keyStore: keyStore,
      onboarding: onboarding,
    );
    budgetBillService = BudgetBillService(
      db: db,
      keyStore: keyStore,
      onboarding: onboarding,
    );

    final res = await onboarding.createNewFamily(
      familyName: 'Keluarga Si-Hemat',
      adminName: 'Erwin',
      paydayDay: 31,
      initialCashBalance: 1000000,
      initialBankBalance: 5000000,
    );
    familyId = res.familyId;
  });

  tearDown(() async {
    await db.close();
  });

  group('Stage 3: Monthly Budgets', () {
    test('tracks spending ratio, warning/over-budget flags, and copies from previous month',
        () async {
      final nov = DateTime(2026, 11, 1);
      final dec = DateTime(2026, 12, 1);
      final foodCatId = '${familyId}_exp_food';
      final leisureCatId = '${familyId}_exp_leisure';

      final wallets = await db.getWalletsWithBalance(familyId);
      final cash = wallets.firstWhere((w) => w.wallet.type == WalletType.cash).wallet;

      await budgetBillService.saveBudget(
        familyId: familyId,
        categoryId: foodCatId,
        month: nov,
        limitAmount: 1000000,
      );
      await budgetBillService.saveBudget(
        familyId: familyId,
        categoryId: leisureCatId,
        month: nov,
        limitAmount: 200000,
      );

      // Spend 850k on food (85% -> warning) & 250k on leisure (125% -> overBudget)
      await txService.createTransaction(
        familyId: familyId,
        sourceWallet: cash,
        categoryId: foodCatId,
        type: TransactionType.expense,
        amount: 850000,
        date: DateTime(2026, 11, 10),
      );
      await txService.createTransaction(
        familyId: familyId,
        sourceWallet: cash,
        categoryId: leisureCatId,
        type: TransactionType.expense,
        amount: 250000,
        date: DateTime(2026, 11, 15),
      );

      final progress = await db.getBudgetsWithProgress(familyId, month: nov);
      expect(progress.length, 2);
      // Sorted highest ratio first -> leisure (125%) then food (85%)
      expect(progress.first.category?.id, leisureCatId);
      expect(progress.first.isOverBudget, isTrue);
      expect(progress.first.remainingAmount, -50000);

      expect(progress.last.category?.id, foodCatId);
      expect(progress.last.isWarning, isTrue);
      expect(progress.last.isOverBudget, isFalse);
      expect(progress.last.remainingAmount, 150000);

      // Copy budgets to December
      final copied = await budgetBillService.copyFromPreviousMonth(
        familyId: familyId,
        targetMonth: dec,
      );
      expect(copied, 2);

      final decBudgets = await db.getBudgetsWithProgress(familyId, month: dec);
      expect(decBudgets.length, 2);
      expect(decBudgets.every((b) => b.spentAmount == 0), isTrue);
    });
  });

  group('Stage 3: Recurring Bills & Atomic Payment', () {
    test('detects due-soon / overdue bills and pays atomically into SQLite transactions',
        () async {
      final nov = DateTime(2026, 11, 1);
      final billsCatId = '${familyId}_exp_bills';
      final wallets = await db.getWalletsWithBalance(familyId);
      final bank = wallets.firstWhere((w) => w.wallet.type == WalletType.bank).wallet;

      await budgetBillService.createBill(
        familyId: familyId,
        walletId: bank.id,
        categoryId: billsCatId,
        name: 'Listrik PLN',
        amount: 450000,
        dueDay: 20,
      );
      await budgetBillService.createBill(
        familyId: familyId,
        walletId: bank.id,
        categoryId: billsCatId,
        name: 'Internet Rumah',
        amount: 350000,
        dueDay: 28,
      );

      // Reference date: 26 Nov 2026 -> PLN (20 Nov) is overdue, Internet (28 Nov) is due soon (2 days)
      final bills = await db.getRecurringBills(
        familyId,
        month: nov,
        referenceNow: DateTime(2026, 11, 26),
      );
      expect(bills.length, 2);
      final pln = bills.firstWhere((b) => b.bill.name == 'Listrik PLN');
      final inet = bills.firstWhere((b) => b.bill.name == 'Internet Rumah');
      expect(pln.isOverdue, isTrue);
      expect(inet.isDueSoon, isTrue);
      expect(inet.daysUntilDue, 2);

      // Pay PLN with actual adjusted amount Rp 475.000
      await budgetBillService.payBill(
        bill: pln.bill,
        wallet: bank,
        month: nov,
        paidAt: DateTime(2026, 11, 26),
        overrideAmount: 475000,
      );

      final afterPay = await db.getRecurringBills(
        familyId,
        month: nov,
        referenceNow: DateTime(2026, 11, 26),
      );
      final plnAfter = afterPay.firstWhere((b) => b.bill.name == 'Listrik PLN');
      expect(plnAfter.isPaidForMonth, isTrue);
      expect(plnAfter.isOverdue, isFalse);

      // Verify Bank wallet dropped from 5.000.000 -> 4.525.000
      final updatedWallets = await db.getWalletsWithBalance(familyId);
      final updatedBank =
          updatedWallets.firstWhere((w) => w.wallet.id == bank.id);
      expect(updatedBank.balance, 4525000);
    });

    test('reactive streams emit immediately on saveBudget, createBill, and payBill (same personal category)',
        () async {
      final dec = DateTime(2026, 12, 1);
      final billsCatId = '${familyId}_exp_bills';
      final wallets = await db.getWalletsWithBalance(familyId);
      final personalWallet = wallets
          .firstWhere((w) => w.wallet.visibility == VisibilityScope.personal)
          .wallet;

      final budgetEmissions = <List<BudgetProgressItem>>[];
      final billEmissions = <List<RecurringBillWithDetails>>[];

      final budgetSub = db
          .watchBudgetsWithProgress(
            familyId,
            month: dec,
            visibilityFilter: VisibilityScope.personal,
          )
          .listen(budgetEmissions.add);
      final billSub = db
          .watchRecurringBills(
            familyId,
            month: dec,
            visibilityFilter: VisibilityScope.personal,
          )
          .listen(billEmissions.add);

      // Wait for initial empty emissions
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(budgetEmissions.length, 1);
      expect(budgetEmissions.last, isEmpty);
      expect(billEmissions.length, 1);
      expect(billEmissions.last, isEmpty);

      // 1. Add personal budget Rp 2.000.000 -> MUST emit immediately without changing month!
      await budgetBillService.saveBudget(
        familyId: familyId,
        categoryId: billsCatId,
        month: dec,
        limitAmount: 2000000,
        visibility: VisibilityScope.personal,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(budgetEmissions.last.length, 1);
      expect(budgetEmissions.last.first.spentAmount, 0);
      expect(budgetEmissions.last.first.budget.limitAmount, 2000000);

      // 2. Add personal bill Rp 500.000 -> MUST emit immediately without changing month!
      await budgetBillService.createBill(
        familyId: familyId,
        walletId: personalWallet.id,
        categoryId: billsCatId,
        name: 'Internet Pribadi',
        amount: 500000,
        dueDay: 15,
        visibility: VisibilityScope.personal,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(billEmissions.last.length, 1);
      expect(billEmissions.last.first.isPaidForMonth, isFalse);

      // 3. Pay personal bill for December (even when DateTime.now() is November!)
      // -> BOTH bill stream AND budget stream MUST emit immediately with spent = 500.000!
      await budgetBillService.payBill(
        bill: billEmissions.last.first.bill,
        wallet: personalWallet,
        month: dec,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(billEmissions.last.first.isPaidForMonth, isTrue);
      expect(budgetEmissions.last.first.spentAmount, 500000);
      expect(budgetEmissions.last.first.remainingAmount, 1500000);

      await budgetSub.cancel();
      await billSub.cancel();
    });

    test('stopping a bill at month 13 preserves paid history for months 1..12 and hides month 13+',
        () async {
      final billsCatId = '${familyId}_exp_debt';
      final wallets = await db.getWalletsWithBalance(familyId);
      final bank = wallets.firstWhere((w) => w.wallet.type == WalletType.bank).wallet;

      // Start credit card installment in Jan 2026 (open-ended initially, or 12 months paid)
      final billId = await budgetBillService.createBill(
        familyId: familyId,
        walletId: bank.id,
        categoryId: billsCatId,
        name: 'Cicilan Kartu Kredit',
        amount: 500000,
        dueDay: 10,
        startMonth: DateTime(2026, 1, 1),
      );

      // Should NOT appear before startMonth (Dec 2025)
      final beforeStart = await db.getRecurringBills(
        familyId,
        month: DateTime(2025, 12, 1),
      );
      expect(beforeStart, isEmpty);

      // Pay all 12 months (Jan 2026 .. Dec 2026)
      for (var m = 1; m <= 12; m++) {
        final month = DateTime(2026, m, 1);
        final list = await db.getRecurringBills(familyId, month: month);
        expect(list.length, 1);
        expect(list.first.isPaidForMonth, isFalse);
        await budgetBillService.payBill(
          bill: list.first.bill,
          wallet: bank,
          month: month,
        );
      }

      // Stop/delete the bill starting at month 13 (Jan 2027)
      await budgetBillService.stopBillFromMonth(
        billId: billId,
        fromMonth: DateTime(2027, 1, 1),
      );

      // Verify months 1..12 STILL exist AND stay marked paid (Lunas) with 1/12..12/12!
      for (var m = 1; m <= 12; m++) {
        final list = await db.getRecurringBills(
          familyId,
          month: DateTime(2026, m, 1),
        );
        expect(list.length, 1, reason: 'Month $m should keep history');
        expect(list.first.isPaidForMonth, isTrue, reason: 'Month $m should stay paid');
        expect(list.first.installmentNumber, m);
        expect(list.first.totalInstallments, 12);
      }

      // Verify month 13 (Jan 2027) and month 14 (Feb 2027) are GONE!
      expect(
        await db.getRecurringBills(familyId, month: DateTime(2027, 1, 1)),
        isEmpty,
      );
      expect(
        await db.getRecurringBills(familyId, month: DateTime(2027, 2, 1)),
        isEmpty,
      );
    });

    test('creating a bill with tenorMonths=12 auto-ends after month 12', () async {
      final billsCatId = '${familyId}_exp_debt';
      await budgetBillService.createBill(
        familyId: familyId,
        categoryId: billsCatId,
        name: 'Cicilan Laptop',
        amount: 750000,
        dueDay: 15,
        startMonth: DateTime(2026, 3, 1),
        tenorMonths: 12,
      );

      // Month 1 (Mar 2026) -> 1/12
      final m1 = await db.getRecurringBills(familyId, month: DateTime(2026, 3, 1));
      expect(m1.length, 1);
      expect(m1.first.installmentNumber, 1);
      expect(m1.first.totalInstallments, 12);

      // Month 12 (Feb 2027) -> 12/12
      final m12 = await db.getRecurringBills(familyId, month: DateTime(2027, 2, 1));
      expect(m12.length, 1);
      expect(m12.first.installmentNumber, 12);
      expect(m12.first.totalInstallments, 12);

      // Month 13 (Mar 2027) -> automatically gone!
      final m13 = await db.getRecurringBills(familyId, month: DateTime(2027, 3, 1));
      expect(m13, isEmpty);
    });
  });

  group('Stage 3: Reports & Export PDF/CSV', () {
    test('computes category breakdown, 6-month trend, CSV and valid PDF bytes',
        () async {
      final nov = DateTime(2026, 11, 1);
      final wallets = await db.getWalletsWithBalance(familyId);
      final bank = wallets.firstWhere((w) => w.wallet.type == WalletType.bank).wallet;

      await txService.createTransaction(
        familyId: familyId,
        sourceWallet: bank,
        categoryId: '${familyId}_inc_salary',
        type: TransactionType.income,
        amount: 10000000,
        date: DateTime(2026, 11, 1),
        merchant: 'Gaji Bulanan',
      );
      await txService.createTransaction(
        familyId: familyId,
        sourceWallet: bank,
        categoryId: '${familyId}_exp_food',
        type: TransactionType.expense,
        amount: 3000000,
        date: DateTime(2026, 11, 5),
        merchant: 'Superindo, Mall',
      );
      await txService.createTransaction(
        familyId: familyId,
        sourceWallet: bank,
        categoryId: '${familyId}_exp_bills',
        type: TransactionType.expense,
        amount: 1000000,
        date: DateTime(2026, 11, 12),
        merchant: 'PLN',
      );

      final report = await db.getMonthlyReport(familyId, month: nov);
      expect(report.summary.totalIncome, 10000000);
      expect(report.summary.totalExpense, 4000000);
      expect(report.summary.savingRatePercent, closeTo(60.0, 0.01));
      expect(report.expenseByCategory.length, 2);
      expect(report.expenseByCategory.first.percentage, closeTo(75.0, 0.01));
      expect(report.trend6Months.length, 6);
      expect(report.trend6Months.last.income, 10000000);
      expect(report.topExpenses.first.transaction.amount, 3000000);

      final txs = await db.getTransactionsDetailed(familyId, month: nov);
      const exporter = ReportExportService();

      final csv = exporter.buildCsvContent(
        txs,
        familyName: 'Keluarga Si-Hemat',
        month: nov,
      );
      expect(csv, contains('"Superindo, Mall"'));
      expect(csv, contains('10000000'));

      final pdfBytes = await exporter.buildPdfBytes(
        familyName: 'Keluarga Si-Hemat',
        report: report,
        transactions: txs,
      );
      expect(pdfBytes.length, greaterThan(500));
      expect(utf8.decode(pdfBytes.sublist(0, 5)), '%PDF-');
    });
  });
}
