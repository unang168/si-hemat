import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/core/security/secure_storage_service.dart';
import 'package:si_hemat/features/ai_assistant/ai_finance_service.dart';
import 'package:si_hemat/features/ai_assistant/ai_models.dart';
import 'package:si_hemat/features/ai_assistant/gemini_client.dart';
import 'package:si_hemat/features/ai_assistant/nine_router_client.dart';
import 'package:si_hemat/features/ai_assistant/statement_import_service.dart';
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

class _MockAdapter implements HttpClientAdapter {
  _MockAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
  });

  group('v1.2: WalletBankHint & Safe Account Auto-Matching', () {
    test('normalizes last4/bank, persists encrypted hints, and avoids ambiguous guesses',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      final keys = _MemKeyStore();
      final onboarding = OnboardingService(db: db, keyStore: keys);
      final walletService = WalletService(
        db: db,
        keyStore: keys,
        onboarding: onboarding,
      );

      final created = await onboarding.createNewFamily(
        familyName: 'Keluarga Erwin',
        adminName: 'Erwin',
        paydayDay: 25,
      );

      final mandiriFamId = await walletService.createWallet(
        familyId: created.familyId,
        name: 'Mandiri Keluarga',
        type: WalletType.bank,
        visibility: VisibilityScope.shared,
        initialBalance: 2000000,
        color: 0xFF0E7C66,
      );
      final mandiriPrivId = await walletService.createWallet(
        familyId: created.familyId,
        name: 'Mandiri Pribadi',
        type: WalletType.bank,
        visibility: VisibilityScope.personal,
        initialBalance: 1000000,
        color: 0xFF6A1B9A,
      );
      final bcaFamId = await walletService.createWallet(
        familyId: created.familyId,
        name: 'BCA Keluarga',
        type: WalletType.bank,
        visibility: VisibilityScope.shared,
        initialBalance: 5000000,
        color: 0xFF1565C0,
      );

      await walletService.setBankHint(
        walletId: mandiriFamId,
        bankName: 'Bank Mandiri',
        last4: '1300012345678', // trims to last 4 -> 5678
      );
      await walletService.setBankHint(
        walletId: mandiriPrivId,
        bankName: 'Mandiri',
        last4: '9012',
      );
      await walletService.setBankHint(
        walletId: bcaFamId,
        bankName: 'BCA',
        last4: '7890',
      );

      final hints = await walletService.loadBankHints();
      expect(hints[mandiriFamId]?.last4, '5678');
      expect(hints[mandiriPrivId]?.displayLabel, 'Mandiri ••••9012');

      final wallets = (await db.getWalletsWithBalance(created.familyId))
          .map((w) => w.wallet)
          .toList();

      // Exact last4 match resolves Personal vs Shared Mandiri accurately
      expect(
        WalletService.findMatchingWalletId(
          wallets: wallets,
          hints: hints,
          detectedBank: 'PT Bank Mandiri Tbk',
          detectedLast4: '9012',
        ),
        mandiriPrivId,
      );
      expect(
        WalletService.findMatchingWalletId(
          wallets: wallets,
          hints: hints,
          detectedBank: 'Mandiri',
          detectedLast4: '5678',
        ),
        mandiriFamId,
      );

      // Ambiguous bank-only ("Mandiri" with NO last4 when 2 Mandiri wallets exist) MUST return null!
      expect(
        WalletService.findMatchingWalletId(
          wallets: wallets,
          hints: hints,
          detectedBank: 'Mandiri',
          detectedLast4: '',
        ),
        isNull,
      );

      // Unique bank-only ("BCA" with only 1 BCA wallet) matches safely
      expect(
        WalletService.findMatchingWalletId(
          wallets: wallets,
          hints: hints,
          detectedBank: 'Bank Central Asia BCA',
          detectedLast4: '',
        ),
        bcaFamId,
      );

      await db.close();
    });
  });

  group('v1.2: StatementImportService (PDF/Multi-Screenshot + 2-Level Dedupe + Batch Commit)',
      () {
    test('strips Rupiah cents/superscripts cleanly in parseStatementAmount', () {
      expect(StatementImportService.parseStatementAmount(50000), 50000);
      expect(StatementImportService.parseStatementAmount('- Rp 50.000⁰⁰'), 50000);
      expect(StatementImportService.parseStatementAmount('- Rp 115.600⁰⁰'), 115600);
      expect(StatementImportService.parseStatementAmount('1.250.000,00'), 1250000);
      expect(StatementImportService.parseStatementAmount('6000.00'), 6000);
    });

    test(
      'parses multi-page statements (9Router), catches cross-page overlap & SQLite duplicates, preserves same-page duplicates, and batch-commits cleanly',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        final keys = _MemKeyStore();
        final onboarding = OnboardingService(db: db, keyStore: keys);
        final walletService = WalletService(
          db: db,
          keyStore: keys,
          onboarding: onboarding,
        );
        final txService = TransactionService(
          db: db,
          keyStore: keys,
          onboarding: onboarding,
        );

        final created = await onboarding.createNewFamily(
          familyName: 'Keluarga Erwin',
          adminName: 'Erwin',
          paydayDay: 25,
        );

        final mandiriPrivId = await walletService.createWallet(
          familyId: created.familyId,
          name: 'Mandiri Pribadi',
          type: WalletType.bank,
          visibility: VisibilityScope.personal,
          initialBalance: 1000000,
          color: 0xFF6A1B9A,
        );
        final ovoPrivId = await walletService.createWallet(
          familyId: created.familyId,
          name: 'OVO Pribadi',
          type: WalletType.ewallet,
          visibility: VisibilityScope.personal,
          initialBalance: 0,
          color: 0xFF4A148C,
        );

        final allWallets = (await db.getWalletsWithBalance(created.familyId))
            .map((e) => e.wallet)
            .toList();
        final mandiriWallet =
            allWallets.firstWhere((w) => w.id == mandiriPrivId);
        final allCats = await db.watchCategories(created.familyId).first;
        final foodCat =
            allCats.firstWhere((c) => c.type == CategoryType.expense);

        // Pre-seed 1 existing transaction in SQLite so DB deduplication catches it
        await txService.createTransaction(
          familyId: created.familyId,
          sourceWallet: mandiriWallet,
          categoryId: foodCat.id,
          type: TransactionType.expense,
          amount: 30000,
          date: DateTime(2026, 11, 4, 12, 0),
          merchant: 'Nasi Goreng 76., KLP DUA',
          source: TransactionSource.manual,
        );

        // Simulate 2 scrolling screenshots (page 1 & page 2 with 1 overlapping transaction!)
        var pageCall = 0;
        final dio = Dio();
        dio.httpClientAdapter = _MockAdapter((options) async {
          pageCall++;
          final Map<String, dynamic> payload;
          if (pageCall == 1) {
            payload = {
              'detected_bank': 'Mandiri',
              'detected_account_last4': '4521',
              'detected_period': 'November 2026',
              'transactions': [
                // Top-up OVO -> matches OVO Pribadi wallet -> transfer!
                {
                  'type': 'transfer',
                  'amount': 50000,
                  'date': '2026-11-05',
                  'merchant': 'Pembayaran OVO 081291719080',
                  'to_wallet_name': 'OVO Pribadi',
                },
                // Already exists in DB -> DB duplicate!
                {
                  'type': 'expense',
                  'amount': 30000,
                  'date': '2026-11-04',
                  'merchant': 'Nasi Goreng 76., KLP DUA',
                  'category_name': 'Makan & Dapur',
                },
                // Two legitimate identical parking fees on the SAME page -> BOTH kept!
                {
                  'type': 'expense',
                  'amount': 5000,
                  'date': '2026-11-03',
                  'merchant': 'Parkir Mall',
                  'category_name': 'Transportasi',
                },
                {
                  'type': 'expense',
                  'amount': 5000,
                  'date': '2026-11-03',
                  'merchant': 'Parkir Mall',
                  'category_name': 'Transportasi',
                },
              ],
            };
          } else {
            payload = {
              'detected_bank': '',
              'detected_account_last4': '',
              'transactions': [
                // Overlapping row from page 1 bottom -> cross-page overlap duplicate!
                {
                  'type': 'expense',
                  'amount': 5000,
                  'date': '2026-11-03',
                  'merchant': 'Parkir Mall',
                  'category_name': 'Transportasi',
                },
                // Brand new transaction on page 2
                {
                  'type': 'expense',
                  'amount': 115600,
                  'date': '2026-11-01',
                  'merchant': 'HOLLAND BAKERY BINONG',
                  'category_name': 'Makan & Dapur',
                },
                // Admin fee
                {
                  'type': 'expense',
                  'amount': 6000,
                  'date': '2026-11-03',
                  'merchant': 'Biaya administrasi kartu debit',
                  'category_name': 'Lainnya',
                },
              ],
            };
          }

          return ResponseBody.fromString(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': jsonEncode(payload)},
                },
              ],
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });

        final aiService = AiFinanceService(
          db: db,
          keyStore: keys,
          geminiClient: GeminiInteractionsClient(),
          nineRouterClient: NineRouterClient(dio: dio),
          transactionService: txService,
        );
        await aiService.saveConfig(
          provider: AiProviderType.nineRouter,
          nineRouterBaseUrl: 'http://192.168.1.10:20128',
          nineRouterModel: 'vision-combo',
        );

        final importService = StatementImportService(
          db: db,
          aiService: aiService,
          transactionService: txService,
          walletService: walletService,
        );

        final progressSteps = <int>[];
        final result = await importService.parseStatementPages(
          familyId: created.familyId,
          selectedWalletId: mandiriPrivId,
          pageImages: [
            Uint8List.fromList([1, 2, 3]),
            Uint8List.fromList([4, 5, 6]),
          ],
          now: DateTime(2026, 11, 28),
          onProgress: (p) => progressSteps.add(p.currentPage),
        );

        expect(progressSteps, [1, 2]);
        expect(result.pagesProcessed, 2);
        expect(result.detectedBank, 'Mandiri');
        expect(result.detectedAccountLast4, '4521');
        expect(result.items.length, 7);

        // Verify Transfer detected to OVO Pribadi
        final ovoTx = result.items.first;
        expect(ovoTx.type, TransactionType.transfer);
        expect(ovoTx.toWalletId, ovoPrivId);
        expect(ovoTx.selected, isTrue);

        // Verify Nasi Goreng (in DB) flagged as duplicate & unchecked
        final nasgor = result.items
            .firstWhere((i) => i.merchant.contains('Nasi Goreng'));
        expect(nasgor.isDuplicate, isTrue);
        expect(nasgor.selected, isFalse);

        // Verify 2 same-page Parkir Mall rows are BOTH selected, while page-2 overlap is duplicate!
        final parkirRows =
            result.items.where((i) => i.merchant == 'Parkir Mall').toList();
        expect(parkirRows.length, 3);
        expect(parkirRows[0].pageNumber, 1);
        expect(parkirRows[0].selected, isTrue);
        expect(parkirRows[1].pageNumber, 1);
        expect(parkirRows[1].selected, isTrue);
        expect(parkirRows[2].pageNumber, 2);
        expect(parkirRows[2].isDuplicate, isTrue);
        expect(parkirRows[2].selected, isFalse);

        // Commit selected items (5 new rows: OVO 50k + 2x Parkir 5k + Holland Bakery 115.6k + Admin 6k)
        final saved = await importService.commitSelectedItems(
          familyId: created.familyId,
          targetWallet: mandiriWallet,
          allWallets: allWallets,
          allCategories: allCats,
          items: result.items,
          rememberAccountHint: true,
          detectedBank: result.detectedBank,
          detectedAccountLast4: result.detectedAccountLast4,
        );
        expect(saved, 5);

        // Verify bank hint remembered on Mandiri Pribadi
        final savedHints = await walletService.loadBankHints();
        expect(savedHints[mandiriPrivId]?.bankName, 'Mandiri');
        expect(savedHints[mandiriPrivId]?.last4, '4521');

        // Verify deterministic wallet balances!
        // Mandiri Pribadi: 1,000,000 - 30,000 (seeded) - 50,000 (transfer) - 10,000 (2x parkir) - 115,600 - 6,000 = 788,400
        // OVO Pribadi: 0 + 50,000 (transfer) = 50,000
        final afterWallets = await db.getWalletsWithBalance(created.familyId);
        final afterMandiri =
            afterWallets.firstWhere((w) => w.wallet.id == mandiriPrivId);
        final afterOvo =
            afterWallets.firstWhere((w) => w.wallet.id == ovoPrivId);
        expect(afterMandiri.balance, 788400);
        expect(afterOvo.balance, 50000);

        // Verify visibility stayed PERSONAL (never leaked to shared sync) and source == ai_statement
        final importedRows = await db.getTransactionsDetailed(
          created.familyId,
          walletIdFilter: mandiriPrivId,
        );
        final aiRows = importedRows
            .where((t) => t.transaction.source == TransactionSource.aiStatement)
            .toList();
        expect(aiRows.length, 5);
        expect(
          aiRows.every(
            (t) => t.transaction.visibility == VisibilityScope.personal,
          ),
          isTrue,
        );
        expect(
          aiRows.every(
            (t) =>
                t.transaction.receiptHash != null &&
                t.transaction.receiptHash!.startsWith('stmt:'),
          ),
          isTrue,
        );

        // Re-running deduplication on the same batch now marks ALL 7 as duplicates!
        final secondPass = await importService.applyDeduplication(
          familyId: created.familyId,
          walletId: mandiriPrivId,
          items: result.items,
        );
        expect(secondPass.every((i) => i.isDuplicate && !i.selected), isTrue);

        await db.close();
      },
    );
  });
}
