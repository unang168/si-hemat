import 'dart:convert';
import 'dart:typed_data';

import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/core/security/secure_storage_service.dart';
import 'package:si_hemat/core/utils/currency_formatter.dart';
import 'package:si_hemat/core/utils/date_formatter.dart';
import 'package:si_hemat/features/ai_assistant/ai_models.dart';
import 'package:si_hemat/features/ai_assistant/gemini_client.dart';
import 'package:si_hemat/features/ai_assistant/nine_router_client.dart';
import 'package:si_hemat/features/transactions/transaction_service.dart';
import 'package:uuid/uuid.dart';

class AiFinanceService {
  AiFinanceService({
    required this.db,
    required this.keyStore,
    required this.geminiClient,
    required this.transactionService,
    NineRouterClient? nineRouterClient,
  }) : nineRouterClient = nineRouterClient ?? NineRouterClient();

  final AppDatabase db;
  final SecureKeyStore keyStore;
  final GeminiInteractionsClient geminiClient;
  final NineRouterClient nineRouterClient;
  final TransactionService transactionService;
  static const Uuid _uuid = Uuid();

  Future<AiConfig> loadConfig() async {
    final providerRaw =
        (await keyStore.read(SecureStorageKeys.aiProvider)) ?? '';
    final provider = providerRaw == AiProviderType.nineRouter
        ? AiProviderType.nineRouter
        : AiProviderType.gemini;

    final key = (await keyStore.read(SecureStorageKeys.geminiApiKey)) ?? '';
    final model =
        (await keyStore.read(SecureStorageKeys.geminiModel)) ??
        GeminiModels.hydrogen;
    final nrUrl =
        (await keyStore.read(SecureStorageKeys.nineRouterBaseUrl)) ??
        NineRouterClient.defaultBaseUrl;
    final nrKey =
        (await keyStore.read(SecureStorageKeys.nineRouterApiKey)) ?? '';
    final nrModel =
        (await keyStore.read(SecureStorageKeys.nineRouterModel)) ?? '';

    return AiConfig(
      provider: provider,
      apiKey: key,
      model: model.isEmpty ? GeminiModels.hydrogen : model,
      nineRouterBaseUrl:
          nrUrl.isEmpty ? NineRouterClient.defaultBaseUrl : nrUrl,
      nineRouterApiKey: nrKey,
      nineRouterModel: nrModel,
    );
  }

  Future<void> saveConfig({
    String? provider,
    String? apiKey,
    String? model,
    String? nineRouterBaseUrl,
    String? nineRouterApiKey,
    String? nineRouterModel,
  }) async {
    if (provider != null) {
      await keyStore.write(SecureStorageKeys.aiProvider, provider);
    }
    if (apiKey != null) {
      final trimmed = apiKey.trim();
      if (trimmed.isEmpty) {
        await keyStore.delete(SecureStorageKeys.geminiApiKey);
      } else {
        await keyStore.write(SecureStorageKeys.geminiApiKey, trimmed);
      }
    }
    if (model != null) {
      await keyStore.write(SecureStorageKeys.geminiModel, model.trim());
    }
    if (nineRouterBaseUrl != null) {
      final normalized = NineRouterClient.normalizeBaseUrl(nineRouterBaseUrl);
      if (normalized.isEmpty) {
        await keyStore.delete(SecureStorageKeys.nineRouterBaseUrl);
      } else {
        await keyStore.write(SecureStorageKeys.nineRouterBaseUrl, normalized);
      }
    }
    if (nineRouterApiKey != null) {
      final trimmed = nineRouterApiKey.trim();
      if (trimmed.isEmpty) {
        await keyStore.delete(SecureStorageKeys.nineRouterApiKey);
      } else {
        await keyStore.write(SecureStorageKeys.nineRouterApiKey, trimmed);
      }
    }
    if (nineRouterModel != null) {
      await keyStore.write(
        SecureStorageKeys.nineRouterModel,
        nineRouterModel.trim(),
      );
    }
  }

  Future<String> testApiKey({
    required String apiKey,
    required String model,
  }) {
    return geminiClient.testConnection(apiKey: apiKey, model: model);
  }

  Future<String> testNineRouter({
    required String baseUrl,
    required String apiKey,
    required String model,
  }) {
    return nineRouterClient.testConnection(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
    );
  }

  Future<List<String>> fetchNineRouterModels({
    required String baseUrl,
    required String apiKey,
  }) {
    return nineRouterClient.listModels(baseUrl: baseUrl, apiKey: apiKey);
  }

  Future<String> _runPrompt({
    required AiConfig config,
    required String userText,
    String? systemInstruction,
    Uint8List? imageBytes,
    String imageMimeType = 'image/jpeg',
    Map<String, dynamic>? jsonSchema,
    int? maxOutputTokens,
  }) {
    if (config.isNineRouter) {
      return nineRouterClient.createChatCompletion(
        baseUrl: config.nineRouterBaseUrl,
        apiKey: config.nineRouterApiKey,
        model: config.nineRouterModel,
        userText: userText,
        systemInstruction: systemInstruction,
        imageBytes: imageBytes,
        imageMimeType: imageMimeType,
        jsonSchema: jsonSchema,
        maxTokens: maxOutputTokens,
      );
    }

    final Object geminiInput = imageBytes != null
        ? [
            {'type': 'text', 'text': userText},
            {
              'type': 'image',
              'data': base64Encode(imageBytes),
              'mime_type': imageMimeType,
            },
          ]
        : userText;

    return geminiClient.createInteraction(
      apiKey: config.apiKey,
      model: config.model,
      systemInstruction: systemInstruction,
      input: geminiInput,
      jsonSchema: jsonSchema,
      maxOutputTokens: maxOutputTokens,
      store: false,
    );
  }

  // ---------------------------------------------------------------------------
  // 1. Parse Natural Language Chat into Structured Transaction Drafts
  // ---------------------------------------------------------------------------

  Future<AiParseResult> parseTransactionsFromChat({
    required String familyId,
    required String userText,
    DateTime? now,
  }) async {
    final config = await loadConfig();
    final refNow = now ?? DateTime.now();
    final walletsWithBal = await db.getWalletsWithBalance(familyId);
    final wallets = walletsWithBal.map((e) => e.wallet).toList();
    final categories = await db.watchCategories(familyId).first;

    final expenseCats = categories
        .where((c) => c.type == CategoryType.expense)
        .map((c) => c.name)
        .join(', ');
    final incomeCats = categories
        .where((c) => c.type == CategoryType.income)
        .map((c) => c.name)
        .join(', ');
    final walletNames = wallets.map((w) => w.name).join(', ');
    final todayIso =
        '${refNow.year}-${refNow.month.toString().padLeft(2, '0')}-${refNow.day.toString().padLeft(2, '0')}';

    final systemInstruction = '''
Kamu adalah asisten pencatat keuangan keluarga Si-Hemat berbahasa Indonesia.
Tugasmu: ubah kalimat pengguna menjadi daftar draft transaksi terstruktur JSON.
Hari ini: $todayIso.
Daftar dompet pengguna: [$walletNames].
Kategori pengeluaran: [$expenseCats].
Kategori pemasukan: [$incomeCats].

Aturan ketat:
- Nominal dalam Rupiah bulat (integer). Contoh: "85rb" = 85000, "1,5jt" = 1500000.
- Jika ada beberapa item dalam 1 kalimat (mis. "beli susu 85rb dan popok 120rb"), pisahkan menjadi beberapa object transaksi.
- Gunakan type = "expense", "income", atau "transfer".
- Pilih nama kategori dan dompet yang paling cocok dari daftar di atas.
- Jika pengguna bilang "kemarin", kurangi 1 hari dari $todayIso.
''';

    final schema = <String, dynamic>{
      'type': 'object',
      'properties': {
        'reply': {
          'type': 'string',
          'description': 'Konfirmasi singkat ramah dalam bahasa Indonesia.',
        },
        'transactions': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'type': {
                'type': 'string',
                'enum': ['expense', 'income', 'transfer'],
              },
              'amount': {'type': 'integer'},
              'category_name': {'type': 'string'},
              'wallet_name': {'type': 'string'},
              'to_wallet_name': {'type': 'string'},
              'merchant': {'type': 'string'},
              'date': {'type': 'string', 'description': 'Format YYYY-MM-DD'},
              'note': {'type': 'string'},
            },
            'required': ['type', 'amount'],
          },
        },
      },
      'required': ['reply', 'transactions'],
    };

    final rawJson = await _runPrompt(
      config: config,
      systemInstruction: systemInstruction,
      userText: userText,
      jsonSchema: schema,
    );

    return _decodeDraftResult(
      rawJson: rawJson,
      wallets: wallets,
      categories: categories,
      fallbackDate: refNow,
      source: TransactionSource.aiChat,
    );
  }

  // ---------------------------------------------------------------------------
  // 2. Scan Receipt / QRIS Screenshot via Gemini Multimodal Vision
  // ---------------------------------------------------------------------------

  Future<AiParseResult> parseReceiptImage({
    required String familyId,
    required Uint8List imageBytes,
    String mimeType = 'image/jpeg',
    DateTime? now,
  }) async {
    final config = await loadConfig();
    final refNow = now ?? DateTime.now();
    final walletsWithBal = await db.getWalletsWithBalance(familyId);
    final wallets = walletsWithBal.map((e) => e.wallet).toList();
    final categories = await db.watchCategories(familyId).first;

    final expenseCats = categories
        .where((c) => c.type == CategoryType.expense)
        .map((c) => c.name)
        .join(', ');
    final walletNames = wallets.map((w) => w.name).join(', ');
    final todayIso =
        '${refNow.year}-${refNow.month.toString().padLeft(2, '0')}-${refNow.day.toString().padLeft(2, '0')}';

    final systemInstruction = '''
Kamu adalah asisten OCR struk belanja dan bukti transfer/QRIS aplikasi Si-Hemat.
Hari ini: $todayIso.
Daftar dompet pengguna: [$walletNames].
Kategori pengeluaran: [$expenseCats].

Aturan ketat:
- Ekstrak total pembayaran akhir (integer Rupiah bulat, tanpa titik/koma).
- Identifikasi nama toko/merchant, tanggal struk (format YYYY-MM-DD, gunakan $todayIso jika tidak terbaca), metode pembayaran/dompet yang paling cocok, kategori paling relevan, dan ringkas daftar item utama pada field note.
- Jika gambar adalah bukti transfer masuk/gaji, set type = "income", selain itu "expense".
''';

    final schema = <String, dynamic>{
      'type': 'object',
      'properties': {
        'reply': {
          'type': 'string',
          'description': 'Ringkasan singkat struk yang terbaca dalam bahasa Indonesia.',
        },
        'transactions': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'type': {
                'type': 'string',
                'enum': ['expense', 'income', 'transfer'],
              },
              'amount': {'type': 'integer'},
              'category_name': {'type': 'string'},
              'wallet_name': {'type': 'string'},
              'merchant': {'type': 'string'},
              'date': {'type': 'string', 'description': 'Format YYYY-MM-DD'},
              'note': {'type': 'string'},
            },
            'required': ['type', 'amount'],
          },
        },
      },
      'required': ['reply', 'transactions'],
    };

    final rawJson = await _runPrompt(
      config: config,
      systemInstruction: systemInstruction,
      userText:
          'Baca struk belanja atau screenshot bukti pembayaran/QRIS ini dan ekstrak data transaksinya.',
      imageBytes: imageBytes,
      imageMimeType: mimeType,
      jsonSchema: schema,
    );

    return _decodeDraftResult(
      rawJson: rawJson,
      wallets: wallets,
      categories: categories,
      fallbackDate: refNow,
      source: TransactionSource.aiReceipt,
    );
  }

  /// Persists a confirmed AI transaction draft into SQLite via TransactionService.
  Future<String> commitDraft({
    required String familyId,
    required AiTransactionDraft draft,
  }) async {
    final wallets = (await db.getWalletsWithBalance(familyId))
        .map((w) => w.wallet)
        .toList();
    final sourceWallet = wallets
        .where((w) => w.id == draft.walletId)
        .firstOrNull;
    if (sourceWallet == null) {
      throw ArgumentError('Pilih dompet yang valid sebelum menyimpan.');
    }

    Wallet? targetWallet;
    if (draft.type == TransactionType.transfer) {
      targetWallet = wallets
          .where((w) => w.id == draft.toWalletId)
          .firstOrNull;
    }

    return transactionService.createTransaction(
      familyId: familyId,
      sourceWallet: sourceWallet,
      targetWallet: targetWallet,
      categoryId: draft.categoryId,
      type: draft.type,
      amount: draft.amount,
      date: draft.date,
      merchant: draft.merchant,
      note: draft.note,
      source: draft.source,
    );
  }

  // ---------------------------------------------------------------------------
  // 3. Deterministic Financial Q&A & Monthly Evaluation Coach
  // ---------------------------------------------------------------------------

  Future<String> askFinancialQuestion({
    required String familyId,
    required String question,
    required DateTime month,
    String? visibilityFilter,
  }) async {
    final config = await loadConfig();
    final trimmedQ = question.trim();
    if (trimmedQ.isEmpty) {
      throw ArgumentError('Pertanyaan tidak boleh kosong.');
    }

    await db.insertAiChatMessage(
      id: _uuid.v4(),
      role: 'user',
      content: trimmedQ,
    );

    final contextSnapshot = await buildDeterministicContext(
      familyId: familyId,
      month: month,
      visibilityFilter: visibilityFilter,
    );

    const systemInstruction = '''
Kamu adalah Si-Hemat AI, penasihat keuangan keluarga pribadi yang ramah, jujur, dan praktis dalam bahasa Indonesia.
ATURAN WAJIB:
- Seluruh angka yang kamu sebutkan HARUS berasal persis dari RINGKASAN DATA SQLITE yang diberikan. Dilarang mengarang angka atau membuat asumsi saldo fiktif.
- Gunakan format Rupiah yang mudah dibaca (mis. Rp 1.500.000).
- Berikan jawaban ringkas, terstruktur (poin-poin jika perlu), dan langsung actionable untuk keluarga.
''';

    final prompt = '''
RINGKASAN DATA SQLITE:
$contextSnapshot

PERTANYAAN PENGGUNA:
$trimmedQ
''';

    final answer = await _runPrompt(
      config: config,
      systemInstruction: systemInstruction,
      userText: prompt,
      maxOutputTokens: 1200,
    );

    await db.insertAiChatMessage(
      id: _uuid.v4(),
      role: 'assistant',
      content: answer,
    );
    return answer;
  }

  /// Builds a privacy-safe, 100% deterministic aggregate snapshot from SQLite
  /// (never sends raw account numbers or secrets to the LLM).
  Future<String> buildDeterministicContext({
    required String familyId,
    required DateTime month,
    String? visibilityFilter,
  }) async {
    final family = await db.getActiveFamily();
    final report = await db.getMonthlyReport(
      familyId,
      month: month,
      visibilityFilter: visibilityFilter,
    );
    final prevMonth = DateTime(month.year, month.month - 1, 1);
    final prevSummary = await db.getMonthlySummary(
      familyId,
      month: prevMonth,
      visibilityFilter: visibilityFilter,
    );
    final budgets = await db.getBudgetsWithProgress(
      familyId,
      month: month,
      visibilityFilter: visibilityFilter,
    );
    final bills = await db.getRecurringBills(
      familyId,
      month: month,
      visibilityFilter: visibilityFilter,
    );
    final wallets = await db.getWalletsWithBalance(
      familyId,
      visibilityFilter: visibilityFilter,
    );

    final totalBalance = wallets.fold<int>(0, (s, w) => s + w.balance);
    final scopeLabel = visibilityFilter == VisibilityScope.shared
        ? 'Keluarga (Shared)'
        : visibilityFilter == VisibilityScope.personal
            ? 'Pribadi (Personal)'
            : 'Semua (Keluarga + Pribadi)';

    final buf = StringBuffer();
    buf.writeln('Buku: ${family?.name ?? 'Keluarga'} | Scope: $scopeLabel');
    buf.writeln('Periode: ${DateFormatter.formatMonthYear(month)}');
    buf.writeln('Total Saldo Bersih Saat Ini: ${CurrencyFormatter.formatIdr(totalBalance)}');
    buf.writeln(
      'Arus Kas Bulan Ini: Pemasukan ${CurrencyFormatter.formatIdr(report.summary.totalIncome)}, '
      'Pengeluaran ${CurrencyFormatter.formatIdr(report.summary.totalExpense)}, '
      'Selisih ${CurrencyFormatter.formatIdr(report.summary.netCashflow)}, '
      'Saving Rate ${report.summary.savingRatePercent.toStringAsFixed(1)}%',
    );
    buf.writeln(
      'Arus Kas Bulan Lalu (${DateFormatter.formatMonthYear(prevMonth)}): '
      'Pemasukan ${CurrencyFormatter.formatIdr(prevSummary.totalIncome)}, '
      'Pengeluaran ${CurrencyFormatter.formatIdr(prevSummary.totalExpense)}',
    );

    if (report.expenseByCategory.isNotEmpty) {
      buf.writeln('Pengeluaran per Kategori Bulan Ini:');
      for (final c in report.expenseByCategory) {
        buf.writeln(
          '- ${c.categoryName}: ${CurrencyFormatter.formatIdr(c.amount)} (${c.percentage.toStringAsFixed(1)}%, ${c.transactionCount}x)',
        );
      }
    }

    if (budgets.isNotEmpty) {
      buf.writeln('Status Anggaran Bulan Ini:');
      for (final b in budgets) {
        final status = b.isOverBudget
            ? 'OVER BUDGET'
            : (b.isWarning ? 'HAMPIR HABIS' : 'AMAN');
        buf.writeln(
          '- ${b.category?.name ?? 'Kategori'}: Terpakai ${CurrencyFormatter.formatIdr(b.spentAmount)} / Batas ${CurrencyFormatter.formatIdr(b.budget.limitAmount)} (${(b.ratio * 100).toStringAsFixed(0)}% - $status)',
        );
      }
    }

    if (bills.isNotEmpty) {
      final paidCount = bills.where((b) => b.isPaidForMonth).length;
      final unpaidTotal = bills
          .where((b) => !b.isPaidForMonth)
          .fold<int>(0, (s, b) => s + b.bill.amount);
      buf.writeln(
        'Tagihan Rutin Bulan Ini: $paidCount/${bills.length} lunas, sisa belum dibayar ${CurrencyFormatter.formatIdr(unpaidTotal)}',
      );
      for (final b in bills.where((x) => !x.isPaidForMonth)) {
        buf.writeln(
          '- Belum bayar: ${b.bill.name} ${CurrencyFormatter.formatIdr(b.bill.amount)} (jatuh tempo tgl ${b.bill.dueDay})',
        );
      }
    }

    if (report.topExpenses.isNotEmpty) {
      buf.writeln('Top Pengeluaran Terbesar Bulan Ini:');
      for (final t in report.topExpenses) {
        buf.writeln(
          '- ${t.transaction.merchant ?? t.category?.name ?? 'Pengeluaran'}: ${CurrencyFormatter.formatIdr(t.transaction.amount)} (${t.category?.name ?? '-'})',
        );
      }
    }

    return buf.toString();
  }

  AiParseResult _decodeDraftResult({
    required String rawJson,
    required List<Wallet> wallets,
    required List<Category> categories,
    required DateTime fallbackDate,
    required String source,
  }) {
    final cleaned = _stripCodeFence(rawJson);
    final dynamic parsed;
    try {
      parsed = jsonDecode(cleaned);
    } catch (_) {
      throw const GeminiException(
        'Respons AI tidak berformat JSON valid. Silakan coba kirim ulang.',
      );
    }

    if (parsed is! Map<String, dynamic>) {
      throw const GeminiException('Struktur jawaban AI tidak sesuai.');
    }

    final reply = (parsed['reply'] as String?)?.trim() ??
        'Draft transaksi berhasil disiapkan. Silakan periksa sebelum disimpan.';
    final rawList = parsed['transactions'];
    final drafts = <AiTransactionDraft>[];

    if (rawList is List) {
      for (final entry in rawList) {
        if (entry is! Map) continue;
        final rawType = entry['type']?.toString() ?? TransactionType.expense;
        final type = (rawType == TransactionType.income ||
                rawType == TransactionType.transfer)
            ? rawType
            : TransactionType.expense;

        final rawAmt = entry['amount'];
        final amount = rawAmt is int
            ? rawAmt
            : (rawAmt is num
                ? rawAmt.round()
                : CurrencyFormatter.parseIdr(rawAmt?.toString() ?? '') ?? 0);
        if (amount <= 0) continue;

        final matchedCat = AiEntityMatcher.matchCategory(
          suggestedName: entry['category_name']?.toString(),
          txType: type,
          categories: categories,
        );
        final matchedWallet = AiEntityMatcher.matchWallet(
          suggestedName: entry['wallet_name']?.toString(),
          wallets: wallets,
        );
        final matchedToWallet = type == TransactionType.transfer
            ? AiEntityMatcher.matchWallet(
                suggestedName: entry['to_wallet_name']?.toString(),
                wallets: wallets,
                excludeWalletId: matchedWallet?.id,
              )
            : null;

        final txDate = AiEntityMatcher.parseIsoDateOrFallback(
          entry['date']?.toString(),
          fallbackDate,
        );

        drafts.add(
          AiTransactionDraft(
            type: type,
            amount: amount,
            date: txDate,
            categoryId: matchedCat?.id,
            categoryName: matchedCat?.name,
            walletId: matchedWallet?.id,
            walletName: matchedWallet?.name,
            toWalletId: matchedToWallet?.id,
            toWalletName: matchedToWallet?.name,
            merchant: entry['merchant']?.toString(),
            note: entry['note']?.toString(),
            source: source,
          ),
        );
      }
    }

    return AiParseResult(assistantMessage: reply, drafts: drafts);
  }

  String _stripCodeFence(String raw) {
    var trimmed = NineRouterClient.stripThinkBlocks(raw).trim();
    if (trimmed.startsWith('```')) {
      final lines = trimmed.split('\n');
      if (lines.length >= 3 && lines.last.trim().startsWith('```')) {
        trimmed = lines.sublist(1, lines.length - 1).join('\n').trim();
      }
    }
    // If an LLM wrapped JSON in prose, slice the outermost {...} object safely.
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start > 0 && end > start) {
      trimmed = trimmed.substring(start, end + 1);
    }
    return trimmed;
  }
}
