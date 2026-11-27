import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:si_hemat/app/providers.dart';
import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/features/ai_assistant/ai_chat_input_screen.dart';
import 'package:si_hemat/features/ai_assistant/ai_receipt_scan_screen.dart';
import 'package:si_hemat/features/ai_assistant/ai_report_chat_screen.dart';
import 'package:si_hemat/features/categories/categories_screen.dart';
import 'package:si_hemat/features/family_sync/family_qr_screen.dart';
import 'package:si_hemat/features/family_sync/qr_scanner_screen.dart';
import 'package:si_hemat/features/family_sync/wifi_sync_screen.dart';
import 'package:si_hemat/features/home/home_shell_screen.dart';
import 'package:si_hemat/features/onboarding/onboarding_screen.dart';
import 'package:si_hemat/features/settings/ai_settings_screen.dart';
import 'package:si_hemat/features/settings/lock_screen.dart';
import 'package:si_hemat/features/settings/security_backup_screen.dart';
import 'package:si_hemat/features/transactions/transaction_form_screen.dart';
import 'package:si_hemat/features/wallets/wallets_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const _AppRootGate(),
      ),
      GoRoute(
        path: '/family-qr',
        builder: (context, state) => const FamilyQrScreen(),
      ),
      GoRoute(
        path: '/wifi-sync',
        builder: (context, state) => const WifiSyncScreen(),
      ),
      GoRoute(
        path: '/qr-scanner',
        builder: (context, state) => const QrScannerScreen(),
      ),
      GoRoute(
        path: '/wallets',
        builder: (context, state) => const WalletsScreen(),
      ),
      GoRoute(
        path: '/categories',
        builder: (context, state) => const CategoriesScreen(),
      ),
      GoRoute(
        path: '/transaction/new',
        builder: (context, state) {
          final type =
              state.uri.queryParameters['type'] ?? TransactionType.expense;
          return TransactionFormScreen(initialType: type);
        },
      ),
      GoRoute(
        path: '/transaction/edit',
        builder: (context, state) {
          final tx = state.extra as Transaction?;
          return TransactionFormScreen(existing: tx);
        },
      ),
      GoRoute(
        path: '/ai-settings',
        builder: (context, state) => const AiSettingsScreen(),
      ),
      GoRoute(
        path: '/security-backup',
        builder: (context, state) => const SecurityBackupScreen(),
      ),
      GoRoute(
        path: '/ai-chat-input',
        builder: (context, state) => const AiChatInputScreen(),
      ),
      GoRoute(
        path: '/ai-receipt-scan',
        builder: (context, state) => const AiReceiptScanScreen(),
      ),
      GoRoute(
        path: '/ai-report-chat',
        builder: (context, state) {
          final prompt = state.uri.queryParameters['prompt'];
          return AiReportChatScreen(initialPrompt: prompt);
        },
      ),
    ],
  );
});

class _AppRootGate extends ConsumerStatefulWidget {
  const _AppRootGate();

  @override
  ConsumerState<_AppRootGate> createState() => _AppRootGateState();
}

class _AppRootGateState extends ConsumerState<_AppRootGate>
    with WidgetsBindingObserver {
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (!ref.read(suppressAutoLockProvider)) {
        _backgroundedAt ??= DateTime.now();
      }
    } else if (state == AppLifecycleState.resumed) {
      final awaySince = _backgroundedAt;
      _backgroundedAt = null;
      if (awaySince == null || ref.read(suppressAutoLockProvider)) return;

      final lockStatus = ref.read(appLockStatusProvider).value;
      final timeoutSec = ref.read(autoLockSecondsProvider);
      if (lockStatus != null &&
          lockStatus.lockEnabled &&
          timeoutSec >= 0 &&
          DateTime.now().difference(awaySince).inSeconds >= timeoutSec) {
        ref.read(isAppUnlockedProvider.notifier).lock();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final familyAsync = ref.watch(activeFamilyProvider);
    final lockStatusAsync = ref.watch(appLockStatusProvider);
    final isUnlocked = ref.watch(isAppUnlockedProvider);

    return familyAsync.when(
      loading: () => const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      ),
      error: (err, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Gagal membuka database lokal: $err'),
          ),
        ),
      ),
      data: (family) {
        if (family == null) {
          return const OnboardingScreen();
        }
        if (lockStatusAsync.isLoading && !isUnlocked) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }
        final lockStatus = lockStatusAsync.value;
        if (lockStatus != null && lockStatus.lockEnabled && !isUnlocked) {
          return PinLockScreen(
            biometricEnabled: lockStatus.biometricEnabled,
            onUnlocked: () => ref.read(isAppUnlockedProvider.notifier).unlock(),
          );
        }
        return const HomeShellScreen();
      },
    );
  }
}
