import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/core/security/secure_storage_service.dart';
import 'package:si_hemat/core/utils/currency_formatter.dart';
import 'package:si_hemat/core/utils/date_formatter.dart';
import 'package:si_hemat/core/utils/idr_input_formatter.dart';
import 'package:si_hemat/features/categories/category_service.dart';
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
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
  });

  group('UX Polish: IdrInputFormatter & Formatters', () {
    const formatter = IdrInputFormatter();

    test('formats Rupiah live with dot separators and keeps cursor sane', () {
      const empty = TextEditingValue.empty;

      final step1 = formatter.formatEditUpdate(
        empty,
        const TextEditingValue(
          text: '1500000',
          selection: TextSelection.collapsed(offset: 7),
        ),
      );
      expect(step1.text, '1.500.000');
      expect(step1.selection.baseOffset, 9);

      // Non-digits stripped cleanly
      final step2 = formatter.formatEditUpdate(
        step1,
        const TextEditingValue(
          text: 'Rp 250a000',
          selection: TextSelection.collapsed(offset: 10),
        ),
      );
      expect(step2.text, '250.000');

      // Leading zeros normalized
      final step3 = formatter.formatEditUpdate(
        empty,
        const TextEditingValue(
          text: '005000',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      expect(step3.text, '5.000');

      // Empty input stays empty
      final step4 = formatter.formatEditUpdate(
        step3,
        const TextEditingValue(
          text: '',
          selection: TextSelection.collapsed(offset: 0),
        ),
      );
      expect(step4.text, '');
    });

    test('formats short axis labels & relative sync timestamps cleanly', () {
      expect(CurrencyFormatter.formatShortAxisIdr(0), '0');
      expect(CurrencyFormatter.formatShortAxisIdr(500000), '500 rb');
      expect(CurrencyFormatter.formatShortAxisIdr(2500000), '2,5 jt');
      expect(CurrencyFormatter.formatShortAxisIdr(12000000), '12 jt');

      final now = DateTime(2026, 11, 27, 10, 0);
      expect(
        DateFormatter.formatRelativeTime(
          now.subtract(const Duration(seconds: 20)).toUtc().millisecondsSinceEpoch,
          now: now,
        ),
        'Baru saja',
      );
      expect(
        DateFormatter.formatRelativeTime(
          now.subtract(const Duration(minutes: 15)).toUtc().millisecondsSinceEpoch,
          now: now,
        ),
        '15 menit lalu',
      );
      expect(
        DateFormatter.formatRelativeTime(
          now.subtract(const Duration(hours: 3)).toUtc().millisecondsSinceEpoch,
          now: now,
        ),
        '3 jam lalu',
      );
      expect(DateFormatter.isSameMonth(DateTime(2026, 11, 1), now), isTrue);
      expect(DateFormatter.isSameMonth(DateTime(2026, 10, 1), now), isFalse);
    });
  });

  group('UX Polish: Custom Categories, Profile Edit, Undo Delete & Category Filter',
      () {
    late AppDatabase db;
    late _MemKeyStore keys;
    late OnboardingService onboarding;
    late CategoryService categoryService;
    late TransactionService txService;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      keys = _MemKeyStore();
      onboarding = OnboardingService(db: db, keyStore: keys);
      categoryService = CategoryService(db: db, onboarding: onboarding);
      txService = TransactionService(
        db: db,
        keyStore: keys,
        onboarding: onboarding,
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('manages custom categories, blocks deleting defaults, updates family/member names, and restores deleted transaction (Undo)',
        () async {
      final created = await onboarding.createNewFamily(
        familyName: 'Keluarga Lama',
        adminName: 'Ayah',
        paydayDay: 25,
        initialCashBalance: 1000000,
      );

      // Update family name & member name
      final deviceId = await onboarding.getOrCreateDeviceId();
      await db.updateFamilyName(
        familyId: created.familyId,
        name: 'Keluarga Erwin',
        deviceId: deviceId,
      );
      await db.updateMemberName(
        memberId: created.memberId,
        name: 'Erwin',
        deviceId: deviceId,
      );

      final updatedFamily = await db.getActiveFamily();
      expect(updatedFamily!.name, 'Keluarga Erwin');
      final members = await db.getFamilyMembers(created.familyId);
      expect(members.single.name, 'Erwin');

      // Custom Category CRUD
      final customCatId = await categoryService.createCategory(
        familyId: created.familyId,
        name: 'Arisan RT',
        type: CategoryType.expense,
        icon: 'savings',
        color: 0xFF8E44AD,
      );

      var cats = await db.watchCategories(created.familyId).first;
      final arisan = cats.firstWhere((c) => c.id == customCatId);
      expect(arisan.name, 'Arisan RT');
      expect(arisan.isDefault, isFalse);

      await categoryService.updateCategory(
        categoryId: customCatId,
        name: 'Arisan Keluarga',
        icon: 'savings',
        color: 0xFF0E7C66,
      );
      cats = await db.watchCategories(created.familyId).first;
      expect(
        cats.firstWhere((c) => c.id == customCatId).name,
        'Arisan Keluarga',
      );

      // Cannot delete default category
      final defaultCat = cats.firstWhere((c) => c.isDefault);
      await expectLater(
        () => categoryService.deleteCategory(defaultCat),
        throwsStateError,
      );

      // Create transaction on custom category, verify categoryIdFilter + Undo Delete
      final cash = (await db.getWalletsWithBalance(created.familyId))
          .firstWhere((w) => w.wallet.type == WalletType.cash)
          .wallet;

      final txId = await txService.createTransaction(
        familyId: created.familyId,
        sourceWallet: cash,
        categoryId: customCatId,
        type: TransactionType.expense,
        amount: 200000,
        date: DateTime(2026, 11, 20),
        merchant: 'Bu RT',
      );

      final byCat = await db.getTransactionsDetailed(
        created.familyId,
        month: DateTime(2026, 11, 1),
        categoryIdFilter: customCatId,
      );
      expect(byCat.length, 1);
      expect(byCat.first.transaction.id, txId);

      // Soft delete -> balance returns to 1.000.000
      await txService.deleteTransaction(txId);
      var cashBal = (await db.getWalletsWithBalance(created.familyId))
          .firstWhere((w) => w.wallet.id == cash.id)
          .balance;
      expect(cashBal, 1000000);

      // Undo restore -> balance returns to 800.000
      await txService.restoreTransaction(txId);
      cashBal = (await db.getWalletsWithBalance(created.familyId))
          .firstWhere((w) => w.wallet.id == cash.id)
          .balance;
      expect(cashBal, 800000);

      // Soft-delete custom category works cleanly
      await categoryService.deleteCategory(
        cats.firstWhere((c) => c.id == customCatId),
      );
      cats = await db.watchCategories(created.familyId).first;
      expect(cats.any((c) => c.id == customCatId), isFalse);
    });
  });
}
