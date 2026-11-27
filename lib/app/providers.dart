import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/core/security/app_lock_service.dart';
import 'package:si_hemat/core/security/family_crypto.dart';
import 'package:si_hemat/core/security/secure_storage_service.dart';
import 'package:si_hemat/features/ai_assistant/ai_finance_service.dart';
import 'package:si_hemat/features/ai_assistant/ai_models.dart';
import 'package:si_hemat/features/ai_assistant/gemini_client.dart';
import 'package:si_hemat/features/ai_assistant/nine_router_client.dart';
import 'package:si_hemat/features/budgets/bill_notification_service.dart';
import 'package:si_hemat/features/budgets/budget_bill_service.dart';
import 'package:si_hemat/features/categories/category_service.dart';
import 'package:si_hemat/features/family_sync/wifi_lan_sync_service.dart';
import 'package:si_hemat/features/onboarding/onboarding_service.dart';
import 'package:si_hemat/features/reports/report_export_service.dart';
import 'package:si_hemat/features/settings/backup_service.dart';
import 'package:si_hemat/features/transactions/transaction_service.dart';
import 'package:si_hemat/features/wallets/wallet_service.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final secureKeyStoreProvider = Provider<SecureKeyStore>((ref) {
  return FlutterSecureKeyStore();
});

final onboardingServiceProvider = Provider<OnboardingService>((ref) {
  return OnboardingService(
    db: ref.watch(databaseProvider),
    keyStore: ref.watch(secureKeyStoreProvider),
  );
});

final walletServiceProvider = Provider<WalletService>((ref) {
  return WalletService(
    db: ref.watch(databaseProvider),
    keyStore: ref.watch(secureKeyStoreProvider),
    onboarding: ref.watch(onboardingServiceProvider),
  );
});

final transactionServiceProvider = Provider<TransactionService>((ref) {
  return TransactionService(
    db: ref.watch(databaseProvider),
    keyStore: ref.watch(secureKeyStoreProvider),
    onboarding: ref.watch(onboardingServiceProvider),
  );
});

final billNotificationServiceProvider = Provider<BillNotificationService>((ref) {
  return BillNotificationService(
    db: ref.watch(databaseProvider),
    keyStore: ref.watch(secureKeyStoreProvider),
  );
});

final billNotificationSettingsProvider =
    FutureProvider<BillNotificationSettings>((ref) {
  return ref.watch(billNotificationServiceProvider).loadSettings();
});

final budgetBillServiceProvider = Provider<BudgetBillService>((ref) {
  return BudgetBillService(
    db: ref.watch(databaseProvider),
    keyStore: ref.watch(secureKeyStoreProvider),
    onboarding: ref.watch(onboardingServiceProvider),
    notifications: ref.watch(billNotificationServiceProvider),
  );
});

final reportExportServiceProvider = Provider<ReportExportService>((ref) {
  return const ReportExportService();
});

final geminiClientProvider = Provider<GeminiInteractionsClient>((ref) {
  return GeminiInteractionsClient();
});

final nineRouterClientProvider = Provider<NineRouterClient>((ref) {
  return NineRouterClient();
});

final aiFinanceServiceProvider = Provider<AiFinanceService>((ref) {
  return AiFinanceService(
    db: ref.watch(databaseProvider),
    keyStore: ref.watch(secureKeyStoreProvider),
    geminiClient: ref.watch(geminiClientProvider),
    nineRouterClient: ref.watch(nineRouterClientProvider),
    transactionService: ref.watch(transactionServiceProvider),
  );
});

final aiConfigProvider = FutureProvider<AiConfig>((ref) {
  return ref.watch(aiFinanceServiceProvider).loadConfig();
});

final aiChatMessagesProvider = StreamProvider<List<AiChatMessage>>((ref) {
  return ref.watch(databaseProvider).watchAiChatMessages();
});

final wifiLanSyncServiceProvider = Provider<WifiLanSyncService>((ref) {
  final service = WifiLanSyncService(
    db: ref.watch(databaseProvider),
    keyStore: ref.watch(secureKeyStoreProvider),
    onboarding: ref.watch(onboardingServiceProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final syncPeersProvider = StreamProvider<List<SyncPeer>>((ref) {
  return ref.watch(databaseProvider).watchSyncPeers();
});

final appLockServiceProvider = Provider<AppLockService>((ref) {
  return AppLockService(keyStore: ref.watch(secureKeyStoreProvider));
});

final appLockStatusProvider = FutureProvider<AppLockStatus>((ref) {
  return ref.watch(appLockServiceProvider).loadStatus();
});

class AppUnlockedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void unlock() => state = true;
  void lock() => state = false;
}

final isAppUnlockedProvider = NotifierProvider<AppUnlockedNotifier, bool>(
  AppUnlockedNotifier.new,
);

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(
    db: ref.watch(databaseProvider),
    keyStore: ref.watch(secureKeyStoreProvider),
    onboarding: ref.watch(onboardingServiceProvider),
  );
});

final categoryServiceProvider = Provider<CategoryService>((ref) {
  return CategoryService(
    db: ref.watch(databaseProvider),
    onboarding: ref.watch(onboardingServiceProvider),
  );
});

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _hydrate();
    return ThemeMode.system;
  }

  Future<void> _hydrate() async {
    try {
      final saved =
          await ref.read(secureKeyStoreProvider).read(SecureStorageKeys.themeMode);
      final parsed = _fromString(saved);
      if (parsed != state) state = parsed;
    } catch (_) {}
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    try {
      await ref
          .read(secureKeyStoreProvider)
          .write(SecureStorageKeys.themeMode, _toString(mode));
    } catch (_) {}
  }

  static ThemeMode _fromString(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _toString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

/// Auto-lock timeout in seconds after app moves to background:
/// `0` = Segera, `30` = 30 detik (default), `60` = 1 menit, `-1` = Hanya saat buka awal.
class AutoLockSecondsNotifier extends Notifier<int> {
  @override
  int build() {
    _hydrate();
    return 30;
  }

  Future<void> _hydrate() async {
    try {
      final saved = await ref
          .read(secureKeyStoreProvider)
          .read(SecureStorageKeys.autoLockSeconds);
      final parsed = int.tryParse(saved ?? '');
      if (parsed != null && parsed != state) state = parsed;
    } catch (_) {}
  }

  Future<void> setSeconds(int seconds) async {
    state = seconds;
    try {
      await ref.read(secureKeyStoreProvider).write(
            SecureStorageKeys.autoLockSeconds,
            seconds.toString(),
          );
    } catch (_) {}
  }
}

final autoLockSecondsProvider = NotifierProvider<AutoLockSecondsNotifier, int>(
  AutoLockSecondsNotifier.new,
);

class SuppressAutoLockNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setSuppressed(bool value) => state = value;
}

final suppressAutoLockProvider = NotifierProvider<SuppressAutoLockNotifier, bool>(
  SuppressAutoLockNotifier.new,
);

final activeFamilyProvider = StreamProvider<Family?>((ref) {
  return ref.watch(databaseProvider).watchActiveFamily();
});

final familyMembersProvider = StreamProvider<List<Member>>((ref) {
  final family = ref.watch(activeFamilyProvider).value;
  if (family == null) return Stream.value(const []);
  return ref.watch(databaseProvider).watchFamilyMembers(family.id);
});

class HideBalanceNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final hideBalanceProvider = NotifierProvider<HideBalanceNotifier, bool>(
  HideBalanceNotifier.new,
);

/// Scope filter: 'all' | 'shared' | 'personal'
class ScopeFilterNotifier extends Notifier<String> {
  @override
  String build() => 'all';

  void setScope(String scope) => state = scope;
}

final scopeFilterProvider = NotifierProvider<ScopeFilterNotifier, String>(
  ScopeFilterNotifier.new,
);

final walletsWithBalanceProvider =
    StreamProvider<List<WalletWithBalance>>((ref) {
  final family = ref.watch(activeFamilyProvider).value;
  final scope = ref.watch(scopeFilterProvider);
  if (family == null) return Stream.value(const []);
  return ref.watch(databaseProvider).watchWalletsWithBalance(
        family.id,
        visibilityFilter: scope,
      );
});

/// Always watches ALL active wallets (both shared & personal) regardless of dashboard filter.
final allWalletsWithBalanceProvider =
    StreamProvider<List<WalletWithBalance>>((ref) {
  final family = ref.watch(activeFamilyProvider).value;
  if (family == null) return Stream.value(const []);
  return ref.watch(databaseProvider).watchWalletsWithBalance(family.id);
});

final categoriesProvider = StreamProvider<List<Category>>((ref) {
  final family = ref.watch(activeFamilyProvider).value;
  if (family == null) return Stream.value(const []);
  return ref.watch(databaseProvider).watchCategories(family.id);
});

final currentMonthSummaryProvider =
    StreamProvider<MonthlyCashflowSummary>((ref) {
  final family = ref.watch(activeFamilyProvider).value;
  final scope = ref.watch(scopeFilterProvider);
  if (family == null) {
    return Stream.value(
      const MonthlyCashflowSummary(
        totalIncome: 0,
        totalExpense: 0,
        transactionCount: 0,
      ),
    );
  }
  return ref.watch(databaseProvider).watchMonthlySummary(
        family.id,
        month: DateTime.now(),
        visibilityFilter: scope,
      );
});

final recentTransactionsProvider =
    StreamProvider<List<TransactionWithDetails>>((ref) {
  final family = ref.watch(activeFamilyProvider).value;
  final scope = ref.watch(scopeFilterProvider);
  if (family == null) return Stream.value(const []);
  return ref.watch(databaseProvider).watchTransactionsDetailed(
        family.id,
        visibilityFilter: scope,
        limit: 5,
      );
});

class TransactionFilterState {
  const TransactionFilterState({
    required this.month,
    this.type = 'all',
    this.memberId,
    this.walletId,
    this.categoryId,
    this.searchQuery = '',
  });

  final DateTime month;
  final String type; // all | expense | income | transfer
  final String? memberId;
  final String? walletId;
  final String? categoryId;
  final String searchQuery;

  TransactionFilterState copyWith({
    DateTime? month,
    String? type,
    String? memberId,
    bool clearMember = false,
    String? walletId,
    bool clearWallet = false,
    String? categoryId,
    bool clearCategory = false,
    String? searchQuery,
  }) {
    return TransactionFilterState(
      month: month ?? this.month,
      type: type ?? this.type,
      memberId: clearMember ? null : (memberId ?? this.memberId),
      walletId: clearWallet ? null : (walletId ?? this.walletId),
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

class TransactionFilterNotifier extends Notifier<TransactionFilterState> {
  @override
  TransactionFilterState build() {
    final now = DateTime.now();
    return TransactionFilterState(month: DateTime(now.year, now.month, 1));
  }

  void prevMonth() {
    state = state.copyWith(
      month: DateTime(state.month.year, state.month.month - 1, 1),
    );
  }

  void nextMonth() {
    state = state.copyWith(
      month: DateTime(state.month.year, state.month.month + 1, 1),
    );
  }

  void goToCurrentMonth() {
    final now = DateTime.now();
    state = state.copyWith(month: DateTime(now.year, now.month, 1));
  }

  void setType(String type) => state = state.copyWith(type: type);

  void setMember(String? memberId) => state = memberId == null
      ? state.copyWith(clearMember: true)
      : state.copyWith(memberId: memberId);

  void setWallet(String? walletId) => state = walletId == null
      ? state.copyWith(clearWallet: true)
      : state.copyWith(walletId: walletId);

  void setCategory(String? categoryId) => state = categoryId == null
      ? state.copyWith(clearCategory: true)
      : state.copyWith(categoryId: categoryId);

  void setSearch(String query) => state = state.copyWith(searchQuery: query);

  void clearFilters() {
    state = state.copyWith(
      type: 'all',
      clearMember: true,
      clearWallet: true,
      clearCategory: true,
      searchQuery: '',
    );
  }
}

final transactionFilterProvider =
    NotifierProvider<TransactionFilterNotifier, TransactionFilterState>(
  TransactionFilterNotifier.new,
);

final filteredTransactionsProvider =
    StreamProvider<List<TransactionWithDetails>>((ref) {
  final family = ref.watch(activeFamilyProvider).value;
  final scope = ref.watch(scopeFilterProvider);
  final filter = ref.watch(transactionFilterProvider);
  if (family == null) return Stream.value(const []);
  return ref.watch(databaseProvider).watchTransactionsDetailed(
        family.id,
        month: filter.month,
        visibilityFilter: scope,
        typeFilter: filter.type,
        memberIdFilter: filter.memberId,
        walletIdFilter: filter.walletId,
        categoryIdFilter: filter.categoryId,
        searchQuery: filter.searchQuery,
      );
});

final selectedMonthSummaryProvider =
    StreamProvider<MonthlyCashflowSummary>((ref) {
  final family = ref.watch(activeFamilyProvider).value;
  final scope = ref.watch(scopeFilterProvider);
  final filter = ref.watch(transactionFilterProvider);
  if (family == null) {
    return Stream.value(
      const MonthlyCashflowSummary(
        totalIncome: 0,
        totalExpense: 0,
        transactionCount: 0,
      ),
    );
  }
  return ref.watch(databaseProvider).watchMonthlySummary(
        family.id,
        month: filter.month,
        visibilityFilter: scope,
      );
});

// ---------------------------------------------------------------------------
// Stage 3: Budgets, Recurring Bills & Reports Providers
// ---------------------------------------------------------------------------

class MonthCursorNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }

  void prevMonth() => state = DateTime(state.year, state.month - 1, 1);
  void nextMonth() => state = DateTime(state.year, state.month + 1, 1);
  void goToCurrentMonth() {
    final now = DateTime.now();
    state = DateTime(now.year, now.month, 1);
  }
}

final budgetMonthProvider = NotifierProvider<MonthCursorNotifier, DateTime>(
  MonthCursorNotifier.new,
);

final budgetsProgressProvider =
    StreamProvider<List<BudgetProgressItem>>((ref) {
  final family = ref.watch(activeFamilyProvider).value;
  final scope = ref.watch(scopeFilterProvider);
  final month = ref.watch(budgetMonthProvider);
  if (family == null) return Stream.value(const []);
  return ref.watch(databaseProvider).watchBudgetsWithProgress(
        family.id,
        month: month,
        visibilityFilter: scope,
      );
});

final recurringBillsProvider =
    StreamProvider<List<RecurringBillWithDetails>>((ref) {
  final family = ref.watch(activeFamilyProvider).value;
  final scope = ref.watch(scopeFilterProvider);
  final month = ref.watch(budgetMonthProvider);
  if (family == null) return Stream.value(const []);
  return ref.watch(databaseProvider).watchRecurringBills(
        family.id,
        month: month,
        visibilityFilter: scope,
      );
});

/// Watches unpaid overdue or due-soon (<= 3 days) bills for the current month on Dashboard.
final dueBillsAlertProvider =
    StreamProvider<List<RecurringBillWithDetails>>((ref) {
  final family = ref.watch(activeFamilyProvider).value;
  final scope = ref.watch(scopeFilterProvider);
  if (family == null) return Stream.value(const []);
  return ref
      .watch(databaseProvider)
      .watchRecurringBills(
        family.id,
        month: DateTime.now(),
        visibilityFilter: scope,
      )
      .map(
        (list) => list.where((b) => b.isOverdue || b.isDueSoon).toList(),
      );
});

final reportMonthProvider = NotifierProvider<MonthCursorNotifier, DateTime>(
  MonthCursorNotifier.new,
);

final monthlyReportProvider = StreamProvider<MonthlyReportData?>((ref) {
  final family = ref.watch(activeFamilyProvider).value;
  final scope = ref.watch(scopeFilterProvider);
  final month = ref.watch(reportMonthProvider);
  if (family == null) return Stream.value(null);
  return ref.watch(databaseProvider).watchMonthlyReport(
        family.id,
        month: month,
        visibilityFilter: scope,
      );
});

final reportTransactionsProvider =
    StreamProvider<List<TransactionWithDetails>>((ref) {
  final family = ref.watch(activeFamilyProvider).value;
  final scope = ref.watch(scopeFilterProvider);
  final month = ref.watch(reportMonthProvider);
  if (family == null) return Stream.value(const []);
  return ref.watch(databaseProvider).watchTransactionsDetailed(
        family.id,
        month: month,
        visibilityFilter: scope,
      );
});

final familyInvitePayloadProvider =
    FutureProvider.family<FamilyPairingPayload?, bool>((ref, includeKey) async {
  ref.watch(activeFamilyProvider);
  return ref
      .read(onboardingServiceProvider)
      .buildInvitePayload(includeGeminiApiKey: includeKey);
});

final familyHashProvider = FutureProvider<String?>((ref) async {
  final family = ref.watch(activeFamilyProvider).value;
  if (family == null) return null;
  return FamilyCrypto.computeFamilyHash(family.id);
});
