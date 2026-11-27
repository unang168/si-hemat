import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/core/security/family_crypto.dart';
import 'package:si_hemat/core/security/secure_storage_service.dart';
import 'package:si_hemat/features/ai_assistant/ai_finance_service.dart';
import 'package:si_hemat/features/ai_assistant/ai_models.dart';
import 'package:si_hemat/features/ai_assistant/gemini_client.dart';
import 'package:si_hemat/features/ai_assistant/nine_router_client.dart';
import 'package:si_hemat/features/budgets/bill_notification_service.dart';
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

class _MockNineRouterAdapter implements HttpClientAdapter {
  _MockNineRouterAdapter(this.handler);

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

  group('v1.1: 9Router OpenAI-Compatible BYOK AI', () {
    test('normalizes base URLs and strips <think> blocks cleanly', () {
      expect(
        NineRouterClient.normalizeBaseUrl('http://192.168.1.10:20128'),
        'http://192.168.1.10:20128/v1',
      );
      expect(
        NineRouterClient.normalizeBaseUrl('http://192.168.1.10:20128/v1/'),
        'http://192.168.1.10:20128/v1',
      );
      expect(
        NineRouterClient.normalizeBaseUrl(
          'https://9router.my.id/v1/chat/completions',
        ),
        'https://9router.my.id/v1',
      );
      expect(
        NineRouterClient.normalizeBaseUrl('192.168.1.10:20128'),
        'http://192.168.1.10:20128/v1',
      );

      final extracted = NineRouterClient.extractCompletionText({
        'choices': [
          {
            'message': {
              'content': '<think>internal reasoning</think>\n{"reply":"OK","transactions":[]}',
            },
          },
        ],
      });
      expect(extracted, '{"reply":"OK","transactions":[]}');
    });

    test(
      'supports 9Router /v1/models, chat parsing with 400 response_format fallback, receipt vision, and preserves Gemini config independently',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        final keys = _MemKeyStore();
        final onboarding = OnboardingService(db: db, keyStore: keys);
        final txService = TransactionService(
          db: db,
          keyStore: keys,
          onboarding: onboarding,
        );

        final capturedRequests = <RequestOptions>[];
        var chatCallCount = 0;

        final dio = Dio();
        dio.httpClientAdapter = _MockNineRouterAdapter((options) async {
          capturedRequests.add(options);
          if (options.method == 'GET' && options.path.endsWith('/v1/models')) {
            return ResponseBody.fromString(
              jsonEncode({
                'data': [
                  {'id': 'gemini/gemini-2.5-flash'},
                  {'id': 'my-free-combo'},
                ],
              }),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }

          chatCallCount++;
          final body = jsonDecode(options.data as String) as Map<String, dynamic>;
          // Simulate upstream rejecting response_format on first chat call -> verify automatic fallback retry!
          if (chatCallCount == 1 && body.containsKey('response_format')) {
            return ResponseBody.fromString(
              jsonEncode({
                'error': {'message': 'response_format unsupported by model'},
              }),
              400,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }

          // Receipt vision request check
          final messages = body['messages'] as List;
          final userMsg = messages.last as Map<String, dynamic>;
          if (userMsg['content'] is List) {
            return ResponseBody.fromString(
              jsonEncode({
                'choices': [
                  {
                    'message': {
                      'content': jsonEncode({
                        'reply': 'Struk Alfamart terbaca lewat 9Router.',
                        'transactions': [
                          {
                            'type': 'expense',
                            'amount': 65000,
                            'category_name': 'Makan & Dapur',
                            'wallet_name': 'Kas Keluarga',
                            'merchant': 'Alfamart',
                            'date': '2026-11-27',
                          },
                        ],
                      }),
                    },
                  },
                ],
              }),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }

          return ResponseBody.fromString(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content':
                        '<think>parsing</think>```json\n${jsonEncode({
                          'reply': '2 transaksi dicatat via 9Router.',
                          'transactions': [
                            {
                              'type': 'expense',
                              'amount': 45000,
                              'category_name': 'Transportasi',
                              'wallet_name': 'Kas Keluarga',
                              'merchant': 'Pertamina',
                              'date': '2026-11-27',
                            },
                            {
                              'type': 'expense',
                              'amount': 15000,
                              'category_name': 'Hiburan & Jajan',
                              'wallet_name': 'Kas Keluarga',
                              'merchant': 'Kopi Kenangan',
                              'date': '2026-11-27',
                            },
                          ],
                        })}\n```',
                  },
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

        final created = await onboarding.createNewFamily(
          familyName: 'Keluarga Erwin',
          adminName: 'Erwin',
          paydayDay: 25,
          initialCashBalance: 1000000,
        );

        // Save Gemini first, then switch to 9Router -> Gemini key must remain preserved
        await aiService.saveConfig(
          provider: AiProviderType.gemini,
          apiKey: 'AIza-test-key',
          model: GeminiModels.hydrogen,
        );
        await aiService.saveConfig(
          provider: AiProviderType.nineRouter,
          nineRouterBaseUrl: 'http://192.168.1.25:20128',
          nineRouterApiKey: 'sk-9router-secret',
          nineRouterModel: 'my-free-combo',
        );

        final cfg = await aiService.loadConfig();
        expect(cfg.isNineRouter, isTrue);
        expect(cfg.isConfigured, isTrue);
        expect(cfg.apiKey, 'AIza-test-key');
        expect(cfg.nineRouterBaseUrl, 'http://192.168.1.25:20128/v1');
        expect(cfg.nineRouterModel, 'my-free-combo');

        // 1. Fetch models
        final models = await aiService.fetchNineRouterModels(
          baseUrl: cfg.nineRouterBaseUrl,
          apiKey: cfg.nineRouterApiKey,
        );
        expect(models, ['gemini/gemini-2.5-flash', 'my-free-combo']);
        expect(
          capturedRequests.last.headers['Authorization'],
          'Bearer sk-9router-secret',
        );

        // 2. Chat parse (verifies automatic retry without response_format + <think> stripping)
        final parsed = await aiService.parseTransactionsFromChat(
          familyId: created.familyId,
          userText: 'Beli bensin 45rb dan kopi 15rb pakai kas',
          now: DateTime(2026, 11, 27),
        );
        expect(parsed.drafts.length, 2);
        expect(parsed.drafts[0].amount, 45000);
        expect(parsed.drafts[1].amount, 15000);

        // 3. Receipt vision via OpenAI image_url data URI
        final receipt = await aiService.parseReceiptImage(
          familyId: created.familyId,
          imageBytes: Uint8List.fromList([1, 2, 3, 4]),
          now: DateTime(2026, 11, 27),
        );
        expect(receipt.drafts.length, 1);
        expect(receipt.drafts.first.merchant, 'Alfamart');
        expect(receipt.drafts.first.amount, 65000);

        final visionBody =
            jsonDecode(capturedRequests.last.data as String) as Map<String, dynamic>;
        final userContent = (visionBody['messages'] as List).last['content'] as List;
        expect(userContent[1]['type'], 'image_url');
        expect(
          (userContent[1]['image_url']['url'] as String)
              .startsWith('data:image/jpeg;base64,'),
          isTrue,
        );

        await db.close();
      },
    );
  });

  group('v1.1: BillNotificationPlanner (H-2 & Hari-H Scheduled Reminders)', () {
    RecurringBill makeBill({
      required String id,
      required String name,
      required int dueDay,
      int amount = 500000,
      String? startMonth,
      String? endMonth,
      String paidMonths = '',
      bool isActive = true,
      bool isDeleted = false,
    }) {
      return RecurringBill(
        id: id,
        familyId: 'fam-1',
        walletId: null,
        categoryId: 'cat-1',
        name: name,
        amount: amount,
        dueDay: dueDay,
        startMonth: startMonth,
        endMonth: endMonth,
        lastPaidMonth: null,
        paidMonths: paidMonths,
        isActive: isActive,
        visibility: VisibilityScope.shared,
        createdAt: 1,
        updatedAt: 1,
        updatedByDeviceId: 'dev-1',
        isDeleted: isDeleted,
      );
    }

    test('schedules both H-2 and Hari-H at configured hour and skips paid/stopped bills',
        () {
      final now = DateTime(2026, 11, 10, 7, 0);
      final bills = [
        // Active unpaid bill due 15th -> should schedule Nov 13 (H-2), Nov 15 (Hari-H), Dec 13 (H-2), Dec 15 (Hari-H)
        makeBill(id: 'b-pln', name: 'Listrik PLN', dueDay: 15, amount: 450000),
        // Paid in Nov -> only Dec H-2 & Hari-H scheduled!
        makeBill(
          id: 'b-net',
          name: 'Internet',
          dueDay: 20,
          paidMonths: '2026-11',
        ),
        // Stopped after Nov -> only Nov H-2 & Hari-H scheduled!
        makeBill(
          id: 'b-cc',
          name: 'Cicilan HP',
          dueDay: 12,
          startMonth: '2026-01',
          endMonth: '2026-11',
        ),
        // Deleted bill -> never scheduled
        makeBill(id: 'b-del', name: 'Lama', dueDay: 18, isDeleted: true),
      ];

      final planned = BillNotificationPlanner.planReminders(
        bills: bills,
        now: now,
        reminderHour: 8,
      );

      // Listrik PLN: 4 reminders (Nov 13, Nov 15, Dec 13, Dec 15)
      final pln = planned.where((r) => r.billId == 'b-pln').toList();
      expect(pln.length, 4);
      expect(pln[0].kind, BillReminderKind.twoDaysBefore);
      expect(pln[0].scheduledAt, DateTime(2026, 11, 13, 8, 0));
      expect(pln[1].kind, BillReminderKind.dueToday);
      expect(pln[1].scheduledAt, DateTime(2026, 11, 15, 8, 0));
      expect(pln[2].scheduledAt, DateTime(2026, 12, 13, 8, 0));
      expect(pln[3].scheduledAt, DateTime(2026, 12, 15, 8, 0));

      // Internet (paid Nov): only Dec 18 & Dec 20
      final net = planned.where((r) => r.billId == 'b-net').toList();
      expect(net.length, 2);
      expect(net.every((r) => r.monthKey == '2026-12'), isTrue);

      // Cicilan HP (ends Nov, due Nov 12, today is Nov 10 07:00 -> Nov 10 08:00 H-2 + Nov 12 08:00 Hari-H; NO Dec!)
      final cc = planned.where((r) => r.billId == 'b-cc').toList();
      expect(cc.length, 2);
      expect(cc[0].scheduledAt, DateTime(2026, 11, 10, 8, 0));
      expect(cc[1].scheduledAt, DateTime(2026, 11, 12, 8, 0));

      // Deleted bill excluded
      expect(planned.where((r) => r.billId == 'b-del'), isEmpty);
    });

    test('handles cross-month H-2 boundary and end-of-month clamping (dueDay 31)',
        () {
      // Jan 29 07:00 -> Feb 2026 has 28 days, dueDay 31 clamps to Feb 28 (H-2 = Feb 26)
      // Also a bill due on the 1st of Feb has H-2 on Jan 30!
      final now = DateTime(2026, 1, 29, 7, 0);
      final bills = [
        makeBill(id: 'b-end', name: 'Sewa', dueDay: 31),
        makeBill(id: 'b-first', name: 'SPP', dueDay: 1),
      ];

      final planned = BillNotificationPlanner.planReminders(
        bills: bills,
        now: now,
        reminderHour: 8,
      );

      final sewa = planned.where((r) => r.billId == 'b-end').toList();
      // Jan 29 08:00 (H-2 for Jan 31), Jan 31 08:00, Feb 26 08:00 (H-2 for Feb 28), Feb 28 08:00
      expect(sewa.map((e) => e.scheduledAt).toList(), [
        DateTime(2026, 1, 29, 8, 0),
        DateTime(2026, 1, 31, 8, 0),
        DateTime(2026, 2, 26, 8, 0),
        DateTime(2026, 2, 28, 8, 0),
      ]);

      final spp = planned.where((r) => r.billId == 'b-first').toList();
      // Jan 1 is in the past; Feb 1 has H-2 = Jan 30 08:00 and Hari-H = Feb 1 08:00!
      expect(spp.map((e) => e.scheduledAt).toList(), [
        DateTime(2026, 1, 30, 8, 0),
        DateTime(2026, 2, 1, 8, 0),
      ]);
    });
  });

  group('v1.1.3: Family Invite QR AI Config Sharing (9Router & Gemini)', () {
    test('bundles 9Router config into QR and restores it automatically on member join',
        () async {
      final adminDb = AppDatabase(NativeDatabase.memory());
      final adminKeys = _MemKeyStore();
      final adminOnboarding =
          OnboardingService(db: adminDb, keyStore: adminKeys);
      final adminTx = TransactionService(
        db: adminDb,
        keyStore: adminKeys,
        onboarding: adminOnboarding,
      );
      final adminAi = AiFinanceService(
        db: adminDb,
        keyStore: adminKeys,
        geminiClient: GeminiInteractionsClient(),
        nineRouterClient: NineRouterClient(),
        transactionService: adminTx,
      );

      await adminOnboarding.createNewFamily(
        familyName: 'Keluarga Erwin',
        adminName: 'Erwin',
        paydayDay: 25,
      );
      await adminAi.saveConfig(
        provider: AiProviderType.nineRouter,
        nineRouterBaseUrl: 'http://192.168.1.50:20128',
        nineRouterApiKey: 'sk-9router-fam',
        nineRouterModel: 'free-combo',
      );

      // Toggle OFF -> no AI credentials included
      final privateInvite =
          await adminOnboarding.buildInvitePayload(includeAiConfig: false);
      expect(privateInvite, isNotNull);
      expect(privateInvite!.hasAiConfig, isFalse);
      expect(privateInvite.toQrString().contains('sk-9router-fam'), isFalse);

      // Toggle ON -> 9Router config bundled into QR
      final inviteWithAi =
          await adminOnboarding.buildInvitePayload(includeAiConfig: true);
      expect(inviteWithAi, isNotNull);
      expect(inviteWithAi!.hasAiConfig, isTrue);
      expect(inviteWithAi.aiProvider, AiProviderType.nineRouter);
      expect(inviteWithAi.nineRouterBaseUrl, 'http://192.168.1.50:20128/v1');
      expect(inviteWithAi.nineRouterApiKey, 'sk-9router-fam');
      expect(inviteWithAi.nineRouterModel, 'free-combo');

      // Spouse joins using QR string on a fresh device
      final spouseDb = AppDatabase(NativeDatabase.memory());
      final spouseKeys = _MemKeyStore();
      final spouseOnboarding =
          OnboardingService(db: spouseDb, keyStore: spouseKeys);
      final spouseTx = TransactionService(
        db: spouseDb,
        keyStore: spouseKeys,
        onboarding: spouseOnboarding,
      );
      final spouseAi = AiFinanceService(
        db: spouseDb,
        keyStore: spouseKeys,
        geminiClient: GeminiInteractionsClient(),
        nineRouterClient: NineRouterClient(),
        transactionService: spouseTx,
      );

      await spouseOnboarding.joinFamilyFromQr(
        qrPayloadRaw: inviteWithAi.toQrString(),
        memberName: 'Pasangan',
      );

      final spouseCfg = await spouseAi.loadConfig();
      expect(spouseCfg.isNineRouter, isTrue);
      expect(spouseCfg.isConfigured, isTrue);
      expect(spouseCfg.nineRouterBaseUrl, 'http://192.168.1.50:20128/v1');
      expect(spouseCfg.nineRouterApiKey, 'sk-9router-fam');
      expect(spouseCfg.nineRouterModel, 'free-combo');

      await adminDb.close();
      await spouseDb.close();
    });

    test('bundles Gemini config & stays backwards-compatible with legacy v1.0 QR',
        () async {
      final adminDb = AppDatabase(NativeDatabase.memory());
      final adminKeys = _MemKeyStore();
      final adminOnboarding =
          OnboardingService(db: adminDb, keyStore: adminKeys);
      final adminTx = TransactionService(
        db: adminDb,
        keyStore: adminKeys,
        onboarding: adminOnboarding,
      );
      final adminAi = AiFinanceService(
        db: adminDb,
        keyStore: adminKeys,
        geminiClient: GeminiInteractionsClient(),
        nineRouterClient: NineRouterClient(),
        transactionService: adminTx,
      );

      await adminOnboarding.createNewFamily(
        familyName: 'Keluarga Gemini',
        adminName: 'Admin',
        paydayDay: 28,
      );
      await adminAi.saveConfig(
        provider: AiProviderType.gemini,
        apiKey: 'AIza-family-key',
        model: GeminiModels.hydrogen,
      );

      final invite =
          await adminOnboarding.buildInvitePayload(includeAiConfig: true);
      expect(invite!.aiProvider, AiProviderType.gemini);
      expect(invite.geminiApiKey, 'AIza-family-key');
      expect(invite.geminiModel, GeminiModels.hydrogen);

      // Simulate legacy v1.0 QR JSON (only gemini_api_key, no ai_provider)
      final legacyQr = jsonEncode({
        'v': 1,
        'app': 'si_hemat',
        'family_id': invite.familyId,
        'family_name': invite.familyName,
        'family_secret': FamilyCrypto.generateFamilySecret(),
        'payday_day': 28,
        'gemini_api_key': 'AIza-legacy-key',
      });

      final spouseDb = AppDatabase(NativeDatabase.memory());
      final spouseKeys = _MemKeyStore();
      final spouseOnboarding =
          OnboardingService(db: spouseDb, keyStore: spouseKeys);
      final spouseTx = TransactionService(
        db: spouseDb,
        keyStore: spouseKeys,
        onboarding: spouseOnboarding,
      );
      final spouseAi = AiFinanceService(
        db: spouseDb,
        keyStore: spouseKeys,
        geminiClient: GeminiInteractionsClient(),
        nineRouterClient: NineRouterClient(),
        transactionService: spouseTx,
      );

      await spouseOnboarding.joinFamilyFromQr(
        qrPayloadRaw: legacyQr,
        memberName: 'Pasangan',
      );

      final spouseCfg = await spouseAi.loadConfig();
      expect(spouseCfg.isNineRouter, isFalse);
      expect(spouseCfg.isConfigured, isTrue);
      expect(spouseCfg.apiKey, 'AIza-legacy-key');

      await adminDb.close();
      await spouseDb.close();
    });
  });
}
