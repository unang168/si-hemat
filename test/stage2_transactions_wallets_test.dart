import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/core/security/secure_storage_service.dart';
import 'package:si_hemat/features/onboarding/onboarding_service.dart';
import 'package:si_hemat/features/transactions/transaction_service.dart';
import 'package:si_hemat/features/wallets/wallet_service.dart';

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
  late WalletService walletService;
  late TransactionService txService;
  late String familyId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    keyStore = _MemKeyStore();
    onboarding = OnboardingService(db: db, keyStore: keyStore);
    walletService = WalletService(
      db: db,
      keyStore: keyStore,
      onboarding: onboarding,
    );
    txService = TransactionService(
      db: db,
      keyStore: keyStore,
      onboarding: onboarding,
    );

    final res = await onboarding.createNewFamily(
      familyName: 'Keluarga Si-Hemat',
      adminName: 'Erwin',
      paydayDay: 31,
      initialCashBalance: 500000,
      initialBankBalance: 3000000,
    );
    familyId = res.familyId;
  });

  tearDown(() async {
    await db.close();
  });

  group('Stage 2: WalletService CRUD', () {
    test('creates, updates, and soft-deletes wallets', () async {
      final newId = await walletService.createWallet(
        familyId: familyId,
        name: 'GoPay Keluarga',
        type: WalletType.ewallet,
        visibility: VisibilityScope.shared,
        initialBalance: 250000,
        color: 0xFF00838F,
      );

      var wallets = await db.getWalletsWithBalance(familyId);
      expect(wallets.length, 4);
      final created = wallets.firstWhere((w) => w.wallet.id == newId);
      expect(created.wallet.name, 'GoPay Keluarga');
      expect(created.balance, 250000);

      await walletService.updateWallet(
        walletId: newId,
        name: 'GoPay Belanja',
        type: WalletType.ewallet,
        visibility: VisibilityScope.shared,
        initialBalance: 400000,
        color: 0xFF00838F,
      );

      wallets = await db.getWalletsWithBalance(familyId);
      final updated = wallets.firstWhere((w) => w.wallet.id == newId);
      expect(updated.wallet.name, 'GoPay Belanja');
      expect(updated.balance, 400000);

      await walletService.deleteWallet(newId);
      wallets = await db.getWalletsWithBalance(familyId);
      expect(wallets.any((w) => w.wallet.id == newId), isFalse);
    });
  });

  group('Stage 2: TransactionService, Reactive Balances & Monthly Summary', () {
    test('handles income, expense, transfer, edit, soft-delete and reactive stream',
        () async {
      final wallets = await db.getWalletsWithBalance(familyId);
      final cash = wallets.firstWhere((w) => w.wallet.type == WalletType.cash).wallet;
      final bank = wallets.firstWhere((w) => w.wallet.type == WalletType.bank).wallet;
      final personal = wallets
          .firstWhere((w) => w.wallet.visibility == VisibilityScope.personal)
          .wallet;

      final foodCatId = '${familyId}_exp_food';
      final salaryCatId = '${familyId}_inc_salary';
      final novDate = DateTime(2026, 11, 26, 10, 0);

      // Listen reactively to wallet balances
      final balanceEmissions = <int>[];
      final sub = db.watchWalletsWithBalance(familyId).listen((list) {
        balanceEmissions.add(
          list.fold<int>(0, (sum, w) => sum + w.balance),
        );
      });

      // 1. Income Rp 5.000.000 to Bank
      await txService.createTransaction(
        familyId: familyId,
        sourceWallet: bank,
        categoryId: salaryCatId,
        type: TransactionType.income,
        amount: 5000000,
        date: novDate,
        merchant: 'Kantor',
      );

      // 2. Expense Rp 150.000 from Cash
      final expId = await txService.createTransaction(
        familyId: familyId,
        sourceWallet: cash,
        categoryId: foodCatId,
        type: TransactionType.expense,
        amount: 150000,
        date: novDate,
        merchant: 'Superindo',
        note: 'Belanja sayur',
      );

      // 3. Transfer Rp 1.000.000 from Bank -> Cash (must NOT count in income/expense!)
      await txService.createTransaction(
        familyId: familyId,
        sourceWallet: bank,
        targetWallet: cash,
        type: TransactionType.transfer,
        amount: 1000000,
        date: novDate,
        note: 'Tarik tunai ATM',
      );

      // 4. Transfer involving Personal wallet -> visibility stays personal!
      final mixedTxId = await txService.createTransaction(
        familyId: familyId,
        sourceWallet: bank,
        targetWallet: personal,
        type: TransactionType.transfer,
        amount: 300000,
        date: novDate,
      );

      final mixedTx = await (db.select(db.transactions)
            ..where((t) => t.id.equals(mixedTxId)))
          .getSingle();
      expect(mixedTx.visibility, VisibilityScope.personal);

      // Verify Monthly Summary excludes transfers
      final summary = await db.getMonthlySummary(
        familyId,
        month: DateTime(2026, 11, 1),
        visibilityFilter: VisibilityScope.shared,
      );
      expect(summary.totalIncome, 5000000);
      expect(summary.totalExpense, 150000);
      expect(summary.netCashflow, 4850000);
      expect(summary.savingRatePercent, closeTo(97.0, 0.01));

      // Edit expense 150.000 -> 200.000
      await txService.updateTransaction(
        transactionId: expId,
        sourceWallet: cash,
        categoryId: foodCatId,
        type: TransactionType.expense,
        amount: 200000,
        date: novDate,
        merchant: 'Superindo',
        note: 'Belanja sayur + buah',
      );

      // Check search query filter
      final found = await db.getTransactionsDetailed(
        familyId,
        month: DateTime(2026, 11, 1),
        searchQuery: 'superindo',
      );
      expect(found.length, 1);
      expect(found.first.transaction.amount, 200000);
      expect(found.first.member?.name, 'Erwin');

      // Soft-delete expense -> cash balance restores
      await txService.deleteTransaction(expId);

      // Expected balances after deleting expense:
      // Bank: 3.000.000 + 5.000.000 - 1.000.000 - 300.000 = 6.700.000
      // Cash: 500.000 + 1.000.000 = 1.500.000
      // Personal: 0 + 300.000 = 300.000
      // Total: 8.500.000
      final finalWallets = await db.getWalletsWithBalance(familyId);
      expect(
        finalWallets.firstWhere((w) => w.wallet.id == bank.id).balance,
        6700000,
      );
      expect(
        finalWallets.firstWhere((w) => w.wallet.id == cash.id).balance,
        1500000,
      );
      expect(
        finalWallets.firstWhere((w) => w.wallet.id == personal.id).balance,
        300000,
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(balanceEmissions.last, 8500000);
      await sub.cancel();
    });
  });
}
