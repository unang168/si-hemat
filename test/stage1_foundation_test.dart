import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:si_hemat/core/constants/default_categories.dart';
import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/core/security/family_crypto.dart';
import 'package:si_hemat/core/security/secure_storage_service.dart';
import 'package:si_hemat/core/utils/currency_formatter.dart';
import 'package:si_hemat/core/utils/date_formatter.dart';
import 'package:si_hemat/features/onboarding/onboarding_service.dart';

class _InMemoryKeyStore implements SecureKeyStore {
  final Map<String, String> _data = {};

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;
}

void main() {
  group('CurrencyFormatter & DateFormatter', () {
    test('formats Indonesian Rupiah accurately and supports hide mode', () {
      expect(CurrencyFormatter.formatIdr(150000), 'Rp 150.000');
      expect(CurrencyFormatter.formatIdr(150000, hide: true), 'Rp ••••••');
      expect(CurrencyFormatter.parseIdr('Rp 2.500.000'), 2500000);
      expect(CurrencyFormatter.parseIdr(''), isNull);
    });

    test('computes effective payday for end-of-month (31) and weekend shifts to Friday',
        () {
      // 25 Nov 2026 is Wednesday -> stays 25 Nov
      expect(
        DateFormatter.effectivePaydayForMonth(2026, 11, 25),
        DateTime(2026, 11, 25),
      );
      expect(
        DateFormatter.daysUntilNextPayday(DateTime(2026, 11, 20), 25),
        5,
      );
      // 25 Dec 2026 is Friday -> 30 days after 25 Nov
      expect(
        DateFormatter.daysUntilNextPayday(DateTime(2026, 11, 25), 25),
        30,
      );

      // 28 Nov 2026 is Saturday -> shifts to Friday 27 Nov 2026
      expect(
        DateFormatter.effectivePaydayForMonth(2026, 11, 28),
        DateTime(2026, 11, 27),
      );

      // 29 Nov 2026 is Sunday -> shifts to Friday 27 Nov 2026
      expect(
        DateFormatter.effectivePaydayForMonth(2026, 11, 29),
        DateTime(2026, 11, 27),
      );

      // End of month (31) in November 2026 (30 days, Mon 30 Nov) -> 30 Nov 2026
      expect(
        DateFormatter.effectivePaydayForMonth(2026, 11, 31),
        DateTime(2026, 11, 30),
      );

      // End of month (31) in Feb 2026 (28 days, Sat 28 Feb) -> Friday 27 Feb 2026
      expect(
        DateFormatter.effectivePaydayForMonth(2026, 2, 31),
        DateTime(2026, 2, 27),
      );

      // End of month (31) in leap year Feb 2028 (29 days, Tue 29 Feb) -> 29 Feb 2028
      expect(
        DateFormatter.effectivePaydayForMonth(2028, 2, 31),
        DateTime(2028, 2, 29),
      );

      // End of month (31) in Jan 2027 (Sun 31 Jan) -> Friday 29 Jan 2027
      expect(
        DateFormatter.effectivePaydayForMonth(2027, 1, 31),
        DateTime(2027, 1, 29),
      );

      // Edge case: payday 1 Nov 2026 is Sunday -> shifts to Friday 30 Oct 2026!
      // On 29 Oct 2026, next payday is 30 Oct 2026 (1 day left).
      expect(
        DateFormatter.nextPaydayDate(DateTime(2026, 10, 29), 1),
        DateTime(2026, 10, 30),
      );
      // On 31 Oct 2026, 1 Nov's shifted payday (30 Oct) already passed -> next is 1 Dec 2026!
      expect(
        DateFormatter.nextPaydayDate(DateTime(2026, 10, 31), 1),
        DateTime(2026, 12, 1),
      );
    });
  });

  group('FamilyCrypto & QR Pairing Payload', () {
    test('generates 256-bit secret and round-trips QR payload', () async {
      final secret = FamilyCrypto.generateFamilySecret();
      expect(secret.length, greaterThanOrEqualTo(43));

      final hash = await FamilyCrypto.computeFamilyHash('fam-123');
      expect(hash.length, 16);

      final payload = FamilyPairingPayload(
        version: 1,
        familyId: 'fam-123',
        familyName: 'Keluarga Erwin',
        familySecret: secret,
        paydayDay: 25,
      );
      final parsed = FamilyPairingPayload.fromQrString(payload.toQrString());
      expect(parsed.familyId, 'fam-123');
      expect(parsed.familyName, 'Keluarga Erwin');
      expect(parsed.familySecret, secret);
      expect(parsed.paydayDay, 25);
    });

    test('rejects invalid or foreign QR payloads', () {
      expect(
        () => FamilyPairingPayload.fromQrString('not-json'),
        throwsFormatException,
      );
      expect(
        () => FamilyPairingPayload.fromQrString('{"app":"other"}'),
        throwsFormatException,
      );
    });
  });

  group('AppDatabase & OnboardingService (SQLite in-memory)', () {
    late AppDatabase db;
    late _InMemoryKeyStore keyStore;
    late OnboardingService onboarding;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      keyStore = _InMemoryKeyStore();
      onboarding = OnboardingService(db: db, keyStore: keyStore);
    });

    tearDown(() async {
      await db.close();
    });

    test('createNewFamily seeds family, admin, 3 wallets, and 15 categories',
        () async {
      final result = await onboarding.createNewFamily(
        familyName: 'Keluarga Erwin',
        adminName: 'Erwin',
        paydayDay: 25,
        initialCashBalance: 1000000,
        initialBankBalance: 5000000,
      );

      final family = await db.getActiveFamily();
      expect(family, isNotNull);
      expect(family!.id, result.familyId);
      expect(family.name, 'Keluarga Erwin');

      final wallets = await db.getWalletsWithBalance(result.familyId);
      expect(wallets.length, 3);
      expect(
        wallets.fold<int>(0, (sum, w) => sum + w.balance),
        6000000,
      );

      final sharedWallets = await db.getWalletsWithBalance(
        result.familyId,
        visibilityFilter: VisibilityScope.shared,
      );
      expect(sharedWallets.length, 2);

      final cats = await db.watchCategories(result.familyId).first;
      expect(cats.length, kDefaultCategories.length);

      expect(
        await keyStore.read(SecureStorageKeys.familySecret),
        result.familySecret,
      );
    });

    test('calculates deterministic wallet balances across income, expense, transfer, and soft-delete',
        () async {
      final result = await onboarding.createNewFamily(
        familyName: 'Keluarga Test',
        adminName: 'Ayah',
        paydayDay: 25,
        initialCashBalance: 500000,
        initialBankBalance: 2000000,
      );

      final wallets = await db.getWalletsWithBalance(result.familyId);
      final cashWallet = wallets.firstWhere((w) => w.wallet.type == WalletType.cash).wallet;
      final bankWallet = wallets.firstWhere((w) => w.wallet.type == WalletType.bank).wallet;
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;

      // Income +3.000.000 into Bank -> Bank = 5.000.000
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx-1',
              familyId: result.familyId,
              memberId: result.memberId,
              walletId: bankWallet.id,
              type: TransactionType.income,
              amount: 3000000,
              date: now,
              createdAt: now,
              updatedAt: now,
              updatedByDeviceId: result.deviceId,
            ),
          );

      // Transfer 1.000.000 from Bank -> Cash (Bank = 4.000.000, Cash = 1.500.000)
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx-2',
              familyId: result.familyId,
              memberId: result.memberId,
              walletId: bankWallet.id,
              toWalletId: Value(cashWallet.id),
              type: TransactionType.transfer,
              amount: 1000000,
              date: now,
              createdAt: now,
              updatedAt: now,
              updatedByDeviceId: result.deviceId,
            ),
          );

      // Expense 250.000 from Cash -> Cash = 1.250.000
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx-3',
              familyId: result.familyId,
              memberId: result.memberId,
              walletId: cashWallet.id,
              type: TransactionType.expense,
              amount: 250000,
              date: now,
              createdAt: now,
              updatedAt: now,
              updatedByDeviceId: result.deviceId,
            ),
          );

      // Soft-deleted expense 999.000 from Cash -> must NOT affect balance!
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx-4',
              familyId: result.familyId,
              memberId: result.memberId,
              walletId: cashWallet.id,
              type: TransactionType.expense,
              amount: 999000,
              date: now,
              createdAt: now,
              updatedAt: now,
              updatedByDeviceId: result.deviceId,
              isDeleted: const Value(true),
            ),
          );

      final updated = await db.getWalletsWithBalance(result.familyId);
      final updatedCash =
          updated.firstWhere((w) => w.wallet.id == cashWallet.id).balance;
      final updatedBank =
          updated.firstWhere((w) => w.wallet.id == bankWallet.id).balance;

      expect(updatedBank, 4000000);
      expect(updatedCash, 1250000);
    });

    test('joinFamilyFromQr stores shared secret and seeds matching category IDs',
        () async {
      final invite = FamilyPairingPayload(
        version: 1,
        familyId: 'fam-shared-001',
        familyName: 'Keluarga Bahagia',
        familySecret: FamilyCrypto.generateFamilySecret(),
        paydayDay: 28,
      );

      final joined = await onboarding.joinFamilyFromQr(
        qrPayloadRaw: invite.toQrString(),
        memberName: 'Ibu',
      );

      expect(joined.familyId, 'fam-shared-001');
      expect(
        await keyStore.read(SecureStorageKeys.familySecret),
        invite.familySecret,
      );
      final cats = await db.watchCategories('fam-shared-001').first;
      expect(cats.length, kDefaultCategories.length);
      expect(cats.any((c) => c.id == 'fam-shared-001_exp_food'), isTrue);
    });
  });
}
