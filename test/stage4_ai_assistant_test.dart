import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/core/security/secure_storage_service.dart';
import 'package:si_hemat/features/ai_assistant/ai_finance_service.dart';
import 'package:si_hemat/features/ai_assistant/gemini_client.dart';
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

class _FakeGeminiClient extends GeminiInteractionsClient {
  _FakeGeminiClient(this.handler);

  final String Function({
    required String model,
    required Object input,
    String? systemInstruction,
    Map<String, dynamic>? jsonSchema,
    required bool store,
  }) handler;

  @override
  Future<String> createInteraction({
    required String apiKey,
    required String model,
    required Object input,
    String? systemInstruction,
    Map<String, dynamic>? jsonSchema,
    int? maxOutputTokens,
    bool store = false,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const GeminiException('Missing API Key');
    }
    return handler(
      model: model,
      input: input,
      systemInstruction: systemInstruction,
      jsonSchema: jsonSchema,
      store: store,
    );
  }
}

void main() {
  late AppDatabase db;
  late _MemKeyStore keyStore;
  late OnboardingService onboarding;
  late TransactionService txService;
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
    final res = await onboarding.createNewFamily(
      familyName: 'Keluarga Erwin',
      adminName: 'Erwin',
      paydayDay: 31,
      initialCashBalance: 1000000,
      initialBankBalance: 5000000,
    );
    familyId = res.familyId;
    await keyStore.write(SecureStorageKeys.geminiApiKey, 'AIzaTestKey12345');
  });

  tearDown(() async {
    await db.close();
  });

  group('Stage 4: Gemini Interactions API Parsing & AI Workflows', () {
    test('extractOutputText parses Interactions API v1 steps skipping thought steps',
        () {
      final response = {
        'id': 'v1_abc',
        'status': 'completed',
        'steps': [
          {'type': 'thought', 'signature': 'sig', 'summary': 'thinking...'},
          {
            'type': 'model_output',
            'content': [
              {'type': 'text', 'text': '{"reply":"Siap","transactions":[]}'},
            ],
          },
        ],
      };

      expect(
        GeminiInteractionsClient.extractOutputText(response),
        '{"reply":"Siap","transactions":[]}',
      );
    });

    test('parseTransactionsFromChat splits multi-item chat and commits to SQLite',
        () async {
      bool? capturedStore;
      String? capturedModel;

      final fakeClient = _FakeGeminiClient(({
        required model,
        required input,
        systemInstruction,
        jsonSchema,
        required store,
      }) {
        capturedStore = store;
        capturedModel = model;
        expect(jsonSchema, isNotNull);
        return jsonEncode({
          'reply': 'Saya siapkan 2 transaksi dari pesan Anda.',
          'transactions': [
            {
              'type': 'expense',
              'amount': 85000,
              'category_name': 'Anak & Pendidikan',
              'wallet_name': 'Kas Keluarga',
              'merchant': 'Indomaret',
              'date': '2026-11-26',
              'note': 'Susu anak',
            },
            {
              'type': 'expense',
              'amount': 120000,
              'category_name': 'Anak & Pendidikan',
              'wallet_name': 'Kas Keluarga',
              'merchant': 'Indomaret',
              'date': '2026-11-26',
              'note': 'Popok',
            },
          ],
        });
      });

      final aiService = AiFinanceService(
        db: db,
        keyStore: keyStore,
        geminiClient: fakeClient,
        transactionService: txService,
      );

      final parsed = await aiService.parseTransactionsFromChat(
        familyId: familyId,
        userText: 'Beli susu 85rb dan popok 120rb pakai Kas Keluarga',
        now: DateTime(2026, 11, 26),
      );

      expect(capturedStore, isFalse);
      expect(capturedModel, GeminiModels.hydrogen);
      expect(parsed.drafts.length, 2);
      expect(parsed.drafts.first.categoryId, '${familyId}_exp_kids');

      for (final d in parsed.drafts) {
        await aiService.commitDraft(familyId: familyId, draft: d);
      }

      final wallets = await db.getWalletsWithBalance(familyId);
      final cash = wallets.firstWhere((w) => w.wallet.type == WalletType.cash);
      expect(cash.balance, 1000000 - 85000 - 120000);
    });

    test('parseReceiptImage sends inline base64 image block and extracts receipt draft',
        () async {
      Object? capturedInput;
      final fakeClient = _FakeGeminiClient(({
        required model,
        required input,
        systemInstruction,
        jsonSchema,
        required store,
      }) {
        capturedInput = input;
        return jsonEncode({
          'reply': 'Struk Superindo terbaca Rp 245.000.',
          'transactions': [
            {
              'type': 'expense',
              'amount': 245000,
              'category_name': 'Makan & Dapur',
              'wallet_name': 'Rekening Keluarga',
              'merchant': 'Superindo',
              'date': '2026-11-26',
              'note': 'Beras 5kg, Minyak goreng, Telur',
            },
          ],
        });
      });

      final aiService = AiFinanceService(
        db: db,
        keyStore: keyStore,
        geminiClient: fakeClient,
        transactionService: txService,
      );

      final result = await aiService.parseReceiptImage(
        familyId: familyId,
        imageBytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
      );

      expect(capturedInput, isA<List<dynamic>>());
      final blocks = capturedInput as List<dynamic>;
      expect((blocks[1] as Map)['type'], 'image');
      expect((blocks[1] as Map)['mime_type'], 'image/jpeg');
      expect(result.drafts.length, 1);
      expect(result.drafts.first.amount, 245000);
      expect(result.drafts.first.merchant, 'Superindo');
      expect(result.drafts.first.source, TransactionSource.aiReceipt);
    });

    test('askFinancialQuestion injects deterministic SQLite totals and saves local chat history',
        () async {
      final wallets = await db.getWalletsWithBalance(familyId);
      final bank = wallets.firstWhere((w) => w.wallet.type == WalletType.bank).wallet;

      await txService.createTransaction(
        familyId: familyId,
        sourceWallet: bank,
        categoryId: '${familyId}_exp_food',
        type: TransactionType.expense,
        amount: 750000,
        date: DateTime(2026, 11, 10),
        merchant: 'Pasar Minggu',
      );

      String? capturedPrompt;
      final fakeClient = _FakeGeminiClient(({
        required model,
        required input,
        systemInstruction,
        jsonSchema,
        required store,
      }) {
        capturedPrompt = input as String;
        return 'Pengeluaran Makan & Dapur bulan ini sebesar Rp 750.000.';
      });

      final aiService = AiFinanceService(
        db: db,
        keyStore: keyStore,
        geminiClient: fakeClient,
        transactionService: txService,
      );

      final reply = await aiService.askFinancialQuestion(
        familyId: familyId,
        question: 'Pengeluaran makan bulan ini berapa?',
        month: DateTime(2026, 11, 1),
      );

      expect(capturedPrompt, contains('Rp 750.000'));
      expect(capturedPrompt, contains('Makan & Dapur'));
      expect(reply, contains('Rp 750.000'));

      final history = await db.watchAiChatMessages().first;
      expect(history.length, 2);
      expect(history[0].role, 'user');
      expect(history[1].role, 'assistant');
    });
  });
}
