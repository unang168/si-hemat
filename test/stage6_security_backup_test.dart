import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/core/security/app_lock_service.dart';
import 'package:si_hemat/core/security/secure_storage_service.dart';
import 'package:si_hemat/features/budgets/budget_bill_service.dart';
import 'package:si_hemat/features/onboarding/onboarding_service.dart';
import 'package:si_hemat/features/settings/backup_service.dart';
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
  group('Stage 6: AppLockService (Salted 6-digit PIN)', () {
    late _MemKeyStore keyStore;
    late AppLockService lockService;

    setUp(() {
      keyStore = _MemKeyStore();
      lockService = AppLockService(keyStore: keyStore);
    });

    test('sets salted SHA-256 PIN, verifies valid/invalid PINs, and disables cleanly',
        () async {
      expect(await lockService.isLockEnabled(), isFalse);
      expect(() => lockService.setPin('1234'), throwsArgumentError);
      expect(() => lockService.setPin('abcdef'), throwsArgumentError);

      await lockService.setPin('246810');
      expect(await lockService.isLockEnabled(), isTrue);

      // Must NOT store plaintext PIN!
      final stored = await keyStore.read(SecureStorageKeys.pinHash);
      expect(stored, isNotNull);
      expect(stored!.contains('246810'), isFalse);

      expect(await lockService.verifyPin('246810'), isTrue);
      expect(await lockService.verifyPin('000000'), isFalse);

      await lockService.disableLock();
      expect(await lockService.isLockEnabled(), isFalse);
      expect(await lockService.verifyPin('246810'), isFalse);
    });
  });

  group('Stage 6: BackupService (AES-256-GCM + PBKDF2 Full Encrypted Backup)', () {
    test(
      'exports shared + personal data + family_secret, restores onto fresh device, and rejects wrong password',
      () async {
        final dbSource = AppDatabase(NativeDatabase.memory());
        final keysSource = _MemKeyStore();
        final onboardSource = OnboardingService(
          db: dbSource,
          keyStore: keysSource,
        );
        final txSource = TransactionService(
          db: dbSource,
          keyStore: keysSource,
          onboarding: onboardSource,
        );
        final budgetSource = BudgetBillService(
          db: dbSource,
          keyStore: keysSource,
          onboarding: onboardSource,
        );
        final backupSource = BackupService(
          db: dbSource,
          keyStore: keysSource,
          onboarding: onboardSource,
        );

        final created = await onboardSource.createNewFamily(
          familyName: 'Keluarga Erwin',
          adminName: 'Erwin',
          paydayDay: 31,
          initialCashBalance: 1000000,
          initialBankBalance: 5000000,
        );

        final wallets = await dbSource.getWalletsWithBalance(created.familyId);
        final cash =
            wallets.firstWhere((w) => w.wallet.type == WalletType.cash).wallet;
        final personal = wallets
            .firstWhere((w) => w.wallet.visibility == VisibilityScope.personal)
            .wallet;

        await txSource.createTransaction(
          familyId: created.familyId,
          sourceWallet: cash,
          categoryId: '${created.familyId}_exp_food',
          type: TransactionType.expense,
          amount: 120000,
          date: DateTime(2026, 11, 20),
          merchant: 'Pasar',
        );
        await txSource.createTransaction(
          familyId: created.familyId,
          sourceWallet: personal,
          categoryId: '${created.familyId}_exp_leisure',
          type: TransactionType.expense,
          amount: 45000,
          date: DateTime(2026, 11, 21),
          merchant: 'Kopi Pribadi',
        );
        await budgetSource.saveBudget(
          familyId: created.familyId,
          categoryId: '${created.familyId}_exp_food',
          month: DateTime(2026, 11, 1),
          limitAmount: 1500000,
        );

        // Encrypt full backup
        final encryptedStr = await backupSource.createEncryptedBackupString(
          familyId: created.familyId,
          password: 'SandiKeluarga2026!',
        );
        // Plaintext merchant & secret must NOT appear in encrypted file!
        expect(encryptedStr, isNot(contains('Kopi Pribadi')));
        expect(encryptedStr, isNot(contains(created.familySecret)));

        // Restore onto a brand-new empty SQLite database (new phone!)
        final dbTarget = AppDatabase(NativeDatabase.memory());
        final keysTarget = _MemKeyStore();
        final onboardTarget = OnboardingService(
          db: dbTarget,
          keyStore: keysTarget,
        );
        final backupTarget = BackupService(
          db: dbTarget,
          keyStore: keysTarget,
          onboarding: onboardTarget,
        );

        // Wrong password must fail
        await expectLater(
          () => backupTarget.restoreFromEncryptedBackupString(
            rawBackupContent: encryptedStr,
            password: 'SalahPassword',
          ),
          throwsA(isA<BackupException>()),
        );

        // Correct password restores EVERYTHING including personal wallet & family_secret
        final summary = await backupTarget.restoreFromEncryptedBackupString(
          rawBackupContent: encryptedStr,
          password: 'SandiKeluarga2026!',
        );
        expect(summary.familyName, 'Keluarga Erwin');
        expect(summary.walletsCount, 3);
        expect(summary.transactionsCount, 2);
        expect(summary.budgetsCount, 1);

        final restoredWallets =
            await dbTarget.getWalletsWithBalance(created.familyId);
        expect(
          restoredWallets.firstWhere((w) => w.wallet.id == cash.id).balance,
          880000,
        );
        expect(
          restoredWallets.firstWhere((w) => w.wallet.id == personal.id).balance,
          -45000,
        );
        expect(
          await keysTarget.read(SecureStorageKeys.familySecret),
          created.familySecret,
        );

        await dbSource.close();
        await dbTarget.close();
      },
    );
  });
}
