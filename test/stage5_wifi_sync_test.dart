import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/core/security/family_crypto.dart';
import 'package:si_hemat/core/security/secure_storage_service.dart';
import 'package:si_hemat/features/budgets/budget_bill_service.dart';
import 'package:si_hemat/features/family_sync/sync_crypto.dart';
import 'package:si_hemat/features/family_sync/sync_transport.dart';
import 'package:si_hemat/features/family_sync/wifi_lan_sync_service.dart';
import 'package:si_hemat/features/onboarding/onboarding_service.dart';
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
  group('Stage 5: SyncCrypto (AES-256-GCM & HMAC-SHA256)', () {
    test('encrypts/decrypts JSON payloads and rejects wrong key or tampering',
        () async {
      final secret = FamilyCrypto.generateFamilySecret();
      final wrongSecret = FamilyCrypto.generateFamilySecret();

      final envelope = await SyncCrypto.encryptJson(
        payload: {'family_id': 'fam-1', 'amount': 125000},
        familySecret: secret,
      );

      final decrypted = await SyncCrypto.decryptJson(
        envelope: envelope,
        familySecret: secret,
      );
      expect(decrypted['amount'], 125000);

      expect(
        () => SyncCrypto.decryptJson(
          envelope: envelope,
          familySecret: wrongSecret,
        ),
        throwsA(isA<SyncAuthException>()),
      );

      final tampered = Map<String, dynamic>.from(envelope);
      tampered['ciphertext'] = '${envelope['ciphertext']}A';
      expect(
        () => SyncCrypto.decryptJson(
          envelope: tampered,
          familySecret: secret,
        ),
        throwsA(isA<SyncAuthException>()),
      );
    });
  });

  group('Stage 5: End-to-End 2-Device Encrypted Wi-Fi Sync (Loopback HTTP)', () {
    late AppDatabase dbA;
    late AppDatabase dbB;
    late _MemKeyStore keysA;
    late _MemKeyStore keysB;
    late OnboardingService onboardA;
    late OnboardingService onboardB;
    late TransactionService txA;
    late TransactionService txB;
    late BudgetBillService budgetA;
    late BudgetBillService budgetB;
    late WifiLanSyncService syncA;
    late WifiLanSyncService syncB;

    setUp(() {
      dbA = AppDatabase(NativeDatabase.memory());
      dbB = AppDatabase(NativeDatabase.memory());
      keysA = _MemKeyStore();
      keysB = _MemKeyStore();
      onboardA = OnboardingService(db: dbA, keyStore: keysA);
      onboardB = OnboardingService(db: dbB, keyStore: keysB);
      txA = TransactionService(db: dbA, keyStore: keysA, onboarding: onboardA);
      txB = TransactionService(db: dbB, keyStore: keysB, onboarding: onboardB);
      budgetA =
          BudgetBillService(db: dbA, keyStore: keysA, onboarding: onboardA);
      budgetB =
          BudgetBillService(db: dbB, keyStore: keysB, onboarding: onboardB);
      syncA = WifiLanSyncService(
        db: dbA,
        keyStore: keysA,
        onboarding: onboardA,
      );
      syncB = WifiLanSyncService(
        db: dbB,
        keyStore: keysB,
        onboarding: onboardB,
      );
    });

    tearDown(() async {
      await syncA.dispose();
      await syncB.dispose();
      await dbA.close();
      await dbB.close();
    });

    test(
      'syncs shared wallets/transactions/budgets/bills, isolates personal data, merges paidMonths union, propagates soft-delete, is idempotent, and rejects rogue peers',
      () async {
        // 1. Device A (Suami) creates Family + shared & personal transactions + shared bill paid Nov
        final famA = await onboardA.createNewFamily(
          familyName: 'Keluarga Erwin',
          adminName: 'Erwin',
          paydayDay: 31,
          initialCashBalance: 1000000,
          initialBankBalance: 5000000,
        );

        final walletsA = await dbA.getWalletsWithBalance(famA.familyId);
        final cashA =
            walletsA.firstWhere((w) => w.wallet.type == WalletType.cash).wallet;
        final personalA = walletsA
            .firstWhere((w) => w.wallet.visibility == VisibilityScope.personal)
            .wallet;

        final sharedExpA = await txA.createTransaction(
          familyId: famA.familyId,
          sourceWallet: cashA,
          categoryId: '${famA.familyId}_exp_food',
          type: TransactionType.expense,
          amount: 150000,
          date: DateTime(2026, 11, 10),
          merchant: 'Pasar Pagi',
        );

        // Personal expense on Device A -> MUST NEVER sync to Device B!
        await txA.createTransaction(
          familyId: famA.familyId,
          sourceWallet: personalA,
          categoryId: '${famA.familyId}_exp_leisure',
          type: TransactionType.expense,
          amount: 777000,
          date: DateTime(2026, 11, 11),
          merchant: 'Kado Rahasia',
        );

        // Shared budget & shared bill paid Nov on Device A
        await budgetA.saveBudget(
          familyId: famA.familyId,
          categoryId: '${famA.familyId}_exp_food',
          month: DateTime(2026, 11, 1),
          limitAmount: 2000000,
        );
        final billId = await budgetA.createBill(
          familyId: famA.familyId,
          walletId: cashA.id,
          categoryId: '${famA.familyId}_exp_bills',
          name: 'Internet Rumah',
          amount: 350000,
          dueDay: 15,
          startMonth: DateTime(2026, 11, 1),
        );
        final billNovA = (await dbA.getRecurringBills(
          famA.familyId,
          month: DateTime(2026, 11, 1),
        ))
            .first;
        await budgetA.payBill(
          bill: billNovA.bill,
          wallet: cashA,
          month: DateTime(2026, 11, 1),
        );

        // 2. Device B (Istri) joins via QR payload from Device A
        final invite = await onboardA.buildInvitePayload();
        expect(invite, isNotNull);
        await onboardB.joinFamilyFromQr(
          qrPayloadRaw: invite!.toQrString(),
          memberName: 'Pasangan',
        );

        // Start Device A local HTTP sync server on loopback 127.0.0.1
        final portA = await syncA.startServerOnly(
          bindAddress: InternetAddress.loopbackIPv4,
        );

        // Device B probes & syncs with Device A over encrypted HTTP
        final peerA = await syncB.probeManualPeer(
          host: '127.0.0.1',
          port: portA,
        );
        expect(peerA.name, 'Erwin');

        final sync1 = await syncB.syncWithPeer(peerA);
        expect(sync1.receivedApplied, greaterThan(0));

        // Verify Device B now sees BOTH members, shared wallets, shared budget, shared bill (paid Nov)
        final membersB = await dbB.getFamilyMembers(famA.familyId);
        expect(membersB.length, 2);

        final walletsB = await dbB.getWalletsWithBalance(famA.familyId);
        // Device B has: its own personal wallet + 2 shared wallets from A = 3 wallets (NOT Erwin's personal wallet!)
        expect(walletsB.length, 3);
        expect(
          walletsB.any((w) => w.wallet.name == personalA.name),
          isFalse,
        );
        final cashB = walletsB.firstWhere((w) => w.wallet.id == cashA.id);
        // Cash = 1.000.000 - 150.000 (Pasar Pagi) - 350.000 (Internet Nov) = 500.000
        expect(cashB.balance, 500000);

        // Verify Erwin's personal "Kado Rahasia" transaction did NOT leak to Device B
        final allTxB = await dbB.getTransactionsDetailed(famA.familyId);
        expect(
          allTxB.any((t) => t.transaction.merchant == 'Kado Rahasia'),
          isFalse,
        );

        // 3. Offline concurrent changes on BOTH phones:
        // - Device B records a shared expense Rp 100.000 on Kas Keluarga & pays Dec bill
        // - Device A soft-deletes sharedExpA (Rp 150.000)
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await txB.createTransaction(
          familyId: famA.familyId,
          sourceWallet: cashB.wallet,
          categoryId: '${famA.familyId}_exp_food',
          type: TransactionType.expense,
          amount: 100000,
          date: DateTime(2026, 11, 20),
          merchant: 'Sayur Ibu',
        );
        final billDecB = (await dbB.getRecurringBills(
          famA.familyId,
          month: DateTime(2026, 12, 1),
        ))
            .first;
        await budgetB.payBill(
          bill: billDecB.bill,
          wallet: cashB.wallet,
          month: DateTime(2026, 12, 1),
        );

        await txA.deleteTransaction(sharedExpA);

        // 4. Second sync + Third idempotent sync
        await syncB.syncWithPeer(peerA);
        await syncB.syncWithPeer(peerA);

        // Expected Cash balance on BOTH Device A and Device B:
        // 1.000.000 - 350.000 (Nov bill) - 100.000 (Sayur Ibu) - 350.000 (Dec bill) = 200.000
        // (sharedExpA 150.000 was soft-deleted on A and propagated to B!)
        final finalCashA = (await dbA.getWalletsWithBalance(famA.familyId))
            .firstWhere((w) => w.wallet.id == cashA.id)
            .balance;
        final finalCashB = (await dbB.getWalletsWithBalance(famA.familyId))
            .firstWhere((w) => w.wallet.id == cashA.id)
            .balance;
        expect(finalCashA, 200000);
        expect(finalCashB, 200000);

        // Verify union merge of paidMonths on BOTH devices (Nov AND Dec both paid!)
        final billRowA = await (dbA.select(dbA.recurringBills)
              ..where((b) => b.id.equals(billId)))
            .getSingle();
        final billRowB = await (dbB.select(dbB.recurringBills)
              ..where((b) => b.id.equals(billId)))
            .getSingle();
        expect(
          AppDatabase.parsePaidMonths(billRowA),
          containsAll(['2026-11', '2026-12']),
        );
        expect(
          AppDatabase.parsePaidMonths(billRowB),
          containsAll(['2026-11', '2026-12']),
        );

        // 5. Rogue Device C with wrong family_secret must be rejected (HTTP 403)
        final dbC = AppDatabase(NativeDatabase.memory());
        final keysC = _MemKeyStore();
        final onboardC = OnboardingService(db: dbC, keyStore: keysC);
        await onboardC.createNewFamily(
          familyName: 'Orang Asing',
          adminName: 'Asing',
          paydayDay: 25,
        );
        final syncC = WifiLanSyncService(
          db: dbC,
          keyStore: keysC,
          onboarding: onboardC,
        );
        await expectLater(
          () => syncC.syncWithPeer(
            SyncPeerInfo(
              deviceId: peerA.deviceId,
              name: peerA.name,
              host: '127.0.0.1',
              port: portA,
              familyHash: peerA.familyHash,
            ),
          ),
          throwsA(isA<SyncAuthException>()),
        );
        await syncC.dispose();
        await dbC.close();
      },
    );
  });
}
