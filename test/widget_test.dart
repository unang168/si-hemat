import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:si_hemat/app/providers.dart';
import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/core/security/app_lock_service.dart';
import 'package:si_hemat/core/security/secure_storage_service.dart';
import 'package:si_hemat/main.dart';

class _TestKeyStore implements SecureKeyStore {
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

  testWidgets('Shows Si-Hemat onboarding screen when no family exists',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureKeyStoreProvider.overrideWithValue(_TestKeyStore()),
          activeFamilyProvider.overrideWith((ref) => Stream.value(null)),
          appLockStatusProvider.overrideWith(
            (ref) async => const AppLockStatus(
              lockEnabled: false,
              biometricEnabled: false,
              biometricAvailable: false,
            ),
          ),
        ],
        child: const SiHematApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Si-Hemat'), findsOneWidget);
    expect(find.text('Siapkan Buku Keluarga'), findsOneWidget);
    expect(find.text('Gabung Keluarga'), findsOneWidget);
  });

  testWidgets('Shows Dashboard with Hide Balance toggle when family exists',
      (WidgetTester tester) async {
    const now = 1764000000000;
    const mockFamily = Family(
      id: 'fam-1',
      name: 'Keluarga Erwin',
      paydayDay: 25,
      currency: 'IDR',
      createdAt: now,
      updatedAt: now,
      updatedByDeviceId: 'dev-1',
      isDeleted: false,
    );
    const mockWallet = Wallet(
      id: 'w-1',
      familyId: 'fam-1',
      ownerMemberId: 'm-1',
      name: 'Kas Keluarga',
      type: WalletType.cash,
      visibility: VisibilityScope.shared,
      initialBalance: 1500000,
      icon: 'payments',
      color: 0xFF0E7C66,
      createdAt: now,
      updatedAt: now,
      updatedByDeviceId: 'dev-1',
      isDeleted: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureKeyStoreProvider.overrideWithValue(_TestKeyStore()),
          activeFamilyProvider.overrideWith((ref) => Stream.value(mockFamily)),
          syncPeersProvider.overrideWith((ref) => Stream.value(const [])),
          familyMembersProvider.overrideWith((ref) => Stream.value(const [])),
          walletsWithBalanceProvider.overrideWith(
            (ref) => Stream.value(
              const [WalletWithBalance(wallet: mockWallet, balance: 1500000)],
            ),
          ),
          allWalletsWithBalanceProvider.overrideWith(
            (ref) => Stream.value(
              const [WalletWithBalance(wallet: mockWallet, balance: 1500000)],
            ),
          ),
          currentMonthSummaryProvider.overrideWith(
            (ref) => Stream.value(
              const MonthlyCashflowSummary(
                totalIncome: 5000000,
                totalExpense: 1200000,
                transactionCount: 4,
              ),
            ),
          ),
          selectedMonthSummaryProvider.overrideWith(
            (ref) => Stream.value(
              const MonthlyCashflowSummary(
                totalIncome: 5000000,
                totalExpense: 1200000,
                transactionCount: 4,
              ),
            ),
          ),
          recentTransactionsProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          filteredTransactionsProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          dueBillsAlertProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          budgetsProgressProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          recurringBillsProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          monthlyReportProvider.overrideWith(
            (ref) => Stream.value(null),
          ),
          reportTransactionsProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          appLockStatusProvider.overrideWith(
            (ref) async => const AppLockStatus(
              lockEnabled: false,
              biometricEnabled: false,
              biometricAvailable: false,
            ),
          ),
        ],
        child: const SiHematApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Keluarga Erwin'), findsOneWidget);
    expect(find.text('Rp 1.500.000'), findsWidgets);
    expect(find.text('Chat AI'), findsOneWidget);
    expect(find.text('Scan Struk'), findsOneWidget);
    expect(find.text('Sync Wi-Fi'), findsOneWidget);

    // Toggle Hide Balance
    await tester.tap(find.byTooltip('Sembunyikan Saldo'));
    await tester.pumpAndSettle();

    expect(find.text('Rp ••••••'), findsWidgets);
  });
}
