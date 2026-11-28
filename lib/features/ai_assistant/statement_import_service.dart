import 'dart:convert';
import 'dart:typed_data';

import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/core/utils/currency_formatter.dart';
import 'package:si_hemat/features/ai_assistant/ai_finance_service.dart';
import 'package:si_hemat/features/ai_assistant/ai_models.dart';
import 'package:si_hemat/features/ai_assistant/gemini_client.dart';
import 'package:si_hemat/features/ai_assistant/nine_router_client.dart';
import 'package:si_hemat/features/transactions/transaction_service.dart';
import 'package:si_hemat/features/wallets/wallet_service.dart';
import 'package:uuid/uuid.dart';

class StatementImportProgress {
  const StatementImportProgress({
    required this.currentPage,
    required this.totalPages,
    required this.foundCount,
    required this.statusText,
  });

  final int currentPage;
  final int totalPages;
  final int foundCount;
  final String statusText;

  double get fraction => totalPages <= 0 ? 0 : currentPage / totalPages;
}

class StatementDraftItem {
  const StatementDraftItem({
    required this.tempId,
    required this.type,
    required this.amount,
    required this.date,
    required this.merchant,
    this.note,
    this.categoryId,
    this.categoryName,
    this.toWalletId,
    this.toWalletName,
    this.pageNumber = 1,
    required this.fingerprint,
    this.isDuplicate = false,
    this.duplicateReason,
    this.selected = true,
  });

  final String tempId;
  final String type; // expense | income | transfer
  final int amount;
  final DateTime date;
  final String merchant;
  final String? note;
  final String? categoryId;
  final String? categoryName;
  final String? toWalletId;
  final String? toWalletName;
  final int pageNumber;
  final String fingerprint;
  final bool isDuplicate;
  final String? duplicateReason;
  final bool selected;

  StatementDraftItem copyWith({
    String? type,
    int? amount,
    DateTime? date,
    String? merchant,
    String? note,
    String? categoryId,
    String? categoryName,
    String? toWalletId,
    String? toWalletName,
    bool clearToWallet = false,
    String? fingerprint,
    bool? isDuplicate,
    String? duplicateReason,
    bool clearDuplicateReason = false,
    bool? selected,
  }) {
    return StatementDraftItem(
      tempId: tempId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      merchant: merchant ?? this.merchant,
      note: note ?? this.note,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      toWalletId: clearToWallet ? null : (toWalletId ?? this.toWalletId),
      toWalletName: clearToWallet ? null : (toWalletName ?? this.toWalletName),
      pageNumber: pageNumber,
      fingerprint: fingerprint ?? this.fingerprint,
      isDuplicate: isDuplicate ?? this.isDuplicate,
      duplicateReason: clearDuplicateReason
          ? null
          : (duplicateReason ?? this.duplicateReason),
      selected: selected ?? this.selected,
    );
  }
}

class StatementImportResult {
  const StatementImportResult({
    required this.items,
    required this.pagesProcessed,
    required this.summaryReply,
    this.detectedBank,
    this.detectedAccountLast4,
    this.detectedAccountHolder,
    this.detectedPeriod,
    this.suggestedWalletId,
  });

  final List<StatementDraftItem> items;
  final int pagesProcessed;
  final String summaryReply;
  final String? detectedBank;
  final String? detectedAccountLast4;
  final String? detectedAccountHolder;
  final String? detectedPeriod;
  final String? suggestedWalletId;

  bool get hasDetectedAccount =>
      (detectedBank != null && detectedBank!.trim().isNotEmpty) ||
      (detectedAccountLast4 != null && detectedAccountLast4!.trim().isNotEmpty);

  String get detectedAccountLabel {
    final bank = detectedBank?.trim() ?? '';
    final last4 = detectedAccountLast4?.trim() ?? '';
    if (bank.isNotEmpty && last4.isNotEmpty) return '$bank ••••$last4';
    if (last4.isNotEmpty) return 'Rekening ••••$last4';
    return bank;
  }
}

/// Parses 1-month PDF bank statements (rendered to page images) and
/// multi-screenshot mobile banking histories into deduplicated batch drafts.
class StatementImportService {
  StatementImportService({
    required this.db,
    required this.aiService,
    required this.transactionService,
    required this.walletService,
  });

  final AppDatabase db;
  final AiFinanceService aiService;
  final TransactionService transactionService;
  final WalletService walletService;
  static const Uuid _uuid = Uuid();

  /// Computes a deterministic fingerprint for deduplication across overlapping
  /// screenshots and existing SQLite records (`Transactions.receiptHash`).
  static String buildFingerprint({
    required String walletId,
    required DateTime date,
    required String type,
    required int amount,
    required String merchant,
  }) {
    final day =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final normMerchant = normalizeMerchant(merchant);
    return 'stmt:$walletId|$day|$type|$amount|$normMerchant';
  }

  static String normalizeMerchant(String raw) {
    final cleaned = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '')
        .trim();
    return cleaned.length > 24 ? cleaned.substring(0, 24) : cleaned;
  }

  /// Parses one or more rendered PDF pages or mobile banking screenshots sequentially,
  /// extracts bank/account metadata (when visible), and runs 2-level deduplication.
  Future<StatementImportResult> parseStatementPages({
    required String familyId,
    required String selectedWalletId,
    required List<Uint8List> pageImages,
    DateTime? now,
    void Function(StatementImportProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (pageImages.isEmpty) {
      throw ArgumentError('Pilih minimal 1 file PDF atau gambar mutasi.');
    }

    final refNow = now ?? DateTime.now();
    final walletsWithBal = await db.getWalletsWithBalance(familyId);
    final wallets = walletsWithBal.map((w) => w.wallet).toList();
    final categories = await db.watchCategories(familyId).first;
    final hints = await walletService.loadBankHints();

    final selectedWallet =
        wallets.where((w) => w.id == selectedWalletId).firstOrNull;
    final otherWalletNames = wallets
        .where((w) => w.id != selectedWalletId)
        .map((w) => w.name)
        .join(', ');
    final expenseCats = categories
        .where((c) => c.type == CategoryType.expense)
        .map((c) => c.name)
        .join(', ');
    final incomeCats = categories
        .where((c) => c.type == CategoryType.income)
        .map((c) => c.name)
        .join(', ');
    final todayIso =
        '${refNow.year}-${refNow.month.toString().padLeft(2, '0')}-${refNow.day.toString().padLeft(2, '0')}';

    final systemInstruction = '''
Kamu adalah asisten OCR mutasi rekening bank & e-wallet Indonesia untuk aplikasi Si-Hemat.
Hari ini: $todayIso (tahun saat ini: ${refNow.year}).
Dompet sumber yang sedang diimpor: ${selectedWallet?.name ?? 'Rekening Bank'}.
Dompet lain milik pengguna (hanya untuk deteksi Transfer antar dompet sendiri): [$otherWalletNames].
Kategori pengeluaran: [$expenseCats].
Kategori pemasukan: [$incomeCats].

ATURAN SANGAT KETAT (WAJIB DIIKUTI):
1. Ekstrak SEMUA baris mutasi uang nyata yang lengkap pada halaman/gambar ini.
2. NOMINAL RUPIAH BULAT (INTEGER) — WASPADAI DESIMAL SEN:
   - Banyak m-banking & PDF memakai ",00", ".00", atau angka kecil superscript "⁰⁰" di belakang nominal (contoh: "- Rp 50.000⁰⁰" = 50000 BUKAN 5000000; "- Rp 115.600⁰⁰" = 115600; "1,250,000.00" = 1250000; "6.000,00" = 6000).
   - Buang 2 digit sen di belakang koma/desimal/superscript.
3. ABAIKAN BARIS TERPOTONG & TEKS NON-TRANSAKSI:
   - Jika ada baris terpotong di tepi paling atas atau paling bawah screenshot yang TIDAK memiliki nominal lengkap, JANGAN diekstrak.
   - Abaikan poin reward (seperti "+ 1 poin", "Livin'poin"), kolom "Saldo Akhir / Balance / Saldo Awal", ringkasan total mutasi, header tabel, dan footer ("Anda telah mencapai akhir mutasi...").
4. ARAH TRANSAKSI (type):
   - Tanda minus "- Rp", "DB", "Debit", "QR Bayar", "Biaya", pembayaran → "expense".
   - Tanda plus "+ Rp", "CR", "Kredit", gaji, bunga, transfer masuk → "income".
   - Jika transaksi adalah Top-up / Transfer ke salah satu dompet di daftar "Dompet lain milik pengguna" (contoh: "Pembayaran OVO" dan ada dompet bernama OVO di daftar tersebut), set type = "transfer" dan isi to_wallet_name dengan nama dompet yang cocok. Jika tidak ada dompet tujuan yang cocok di daftar, gunakan "expense".
5. TANGGAL: Format YYYY-MM-DD. Jika hanya ada tanggal & bulan (mis. "05/11"), gunakan tahun dari header periode mutasi atau ${refNow.year}.
6. METADATA REKENING: Isi detected_bank dan detected_account_last4 (4 digit terakhir saja) HANYA JIKA tertulis jelas di halaman/gambar. Jika tidak tampak (mis. screenshot m-banking polos), isi string kosong "". Dilarang mengarang nomor rekening.
7. MERCHANT & KATEGORI: Bersihkan nama merchant (mis. "Nasi Goreng 76., KLP DUA", "HOLLAND BAKERY BINONG", "Biaya administrasi kartu debit") dan pilih kategori paling relevan dari daftar di atas.
''';

    final schema = <String, dynamic>{
      'type': 'object',
      'properties': {
        'detected_bank': {'type': 'string'},
        'detected_account_last4': {'type': 'string'},
        'detected_account_holder': {'type': 'string'},
        'detected_period': {'type': 'string'},
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
              'date': {'type': 'string', 'description': 'Format YYYY-MM-DD'},
              'merchant': {'type': 'string'},
              'category_name': {'type': 'string'},
              'to_wallet_name': {'type': 'string'},
              'note': {'type': 'string'},
            },
            'required': ['type', 'amount', 'merchant'],
          },
        },
      },
      'required': ['transactions'],
    };

    final collected = <StatementDraftItem>[];
    String? detectedBank;
    String? detectedLast4;
    String? detectedHolder;
    String? detectedPeriod;
    var processedPages = 0;

    for (var i = 0; i < pageImages.length; i++) {
      if (isCancelled?.call() == true) break;
      final pageNum = i + 1;
      onProgress?.call(
        StatementImportProgress(
          currentPage: pageNum,
          totalPages: pageImages.length,
          foundCount: collected.length,
          statusText:
              'AI sedang membaca halaman/gambar $pageNum dari ${pageImages.length}...',
        ),
      );

      final rawJson = await aiService.runMultimodalPrompt(
        systemInstruction: systemInstruction,
        userText:
            'Baca halaman/screenshot mutasi ke-$pageNum dari ${pageImages.length} ini dan ekstrak seluruh baris transaksi lengkap dalam JSON.',
        imageBytes: pageImages[i],
        imageMimeType: 'image/jpeg',
        jsonSchema: schema,
        maxOutputTokens: 4096,
      );

      processedPages++;
      final decoded = _decodePageJson(
        rawJson: rawJson,
        walletId: selectedWalletId,
        wallets: wallets,
        categories: categories,
        fallbackDate: refNow,
        pageNumber: pageNum,
      );

      if ((detectedBank == null || detectedBank.isEmpty) &&
          decoded.detectedBank != null &&
          decoded.detectedBank!.isNotEmpty) {
        detectedBank = decoded.detectedBank;
      }
      if ((detectedLast4 == null || detectedLast4.isEmpty) &&
          decoded.detectedLast4 != null &&
          decoded.detectedLast4!.isNotEmpty) {
        detectedLast4 = decoded.detectedLast4;
      }
      if ((detectedHolder == null || detectedHolder.isEmpty) &&
          decoded.detectedHolder != null &&
          decoded.detectedHolder!.isNotEmpty) {
        detectedHolder = decoded.detectedHolder;
      }
      if ((detectedPeriod == null || detectedPeriod.isEmpty) &&
          decoded.detectedPeriod != null &&
          decoded.detectedPeriod!.isNotEmpty) {
        detectedPeriod = decoded.detectedPeriod;
      }

      collected.addAll(decoded.items);
    }

    final suggestedWalletId = WalletService.findMatchingWalletId(
      wallets: wallets,
      hints: hints,
      detectedBank: detectedBank,
      detectedLast4: detectedLast4,
    );

    final deduped = await applyDeduplication(
      familyId: familyId,
      walletId: selectedWalletId,
      items: collected,
    );

    final dupCount = deduped.where((e) => e.isDuplicate).length;
    final reply = deduped.isEmpty
        ? 'Tidak ditemukan baris transaksi lengkap pada $processedPages halaman/gambar ini.'
        : 'Berhasil membaca ${deduped.length} transaksi dari $processedPages halaman/gambar${dupCount > 0 ? ' ($dupCount terindikasi duplikat & otomatis tidak dicentang)' : ''}.';

    return StatementImportResult(
      items: deduped,
      pagesProcessed: processedPages,
      summaryReply: reply,
      detectedBank: detectedBank,
      detectedAccountLast4: detectedLast4,
      detectedAccountHolder: detectedHolder,
      detectedPeriod: detectedPeriod,
      suggestedWalletId: suggestedWalletId,
    );
  }

  /// Converts drafts from single-receipt scan fallback into batch review items.
  Future<StatementImportResult> fromAiDrafts({
    required String familyId,
    required String walletId,
    required List<AiTransactionDraft> drafts,
  }) async {
    final converted = drafts
        .map(
          (d) => StatementDraftItem(
            tempId: _uuid.v4(),
            type: d.type,
            amount: d.amount,
            date: d.date,
            merchant: (d.merchant != null && d.merchant!.trim().isNotEmpty)
                ? d.merchant!.trim()
                : (d.categoryName ?? 'Transaksi'),
            note: d.note,
            categoryId: d.categoryId,
            categoryName: d.categoryName,
            toWalletId: d.toWalletId,
            toWalletName: d.toWalletName,
            pageNumber: 1,
            fingerprint: buildFingerprint(
              walletId: walletId,
              date: d.date,
              type: d.type,
              amount: d.amount,
              merchant: d.merchant ?? d.categoryName ?? '',
            ),
          ),
        )
        .toList();

    final deduped = await applyDeduplication(
      familyId: familyId,
      walletId: walletId,
      items: converted,
    );

    return StatementImportResult(
      items: deduped,
      pagesProcessed: 1,
      summaryReply:
          '${deduped.length} transaksi siap direview sebelum disimpan.',
    );
  }

  /// Re-evaluates cross-page overlap AND SQLite database duplicates for [walletId].
  /// Safe to call again whenever the user switches the target wallet dropdown.
  Future<List<StatementDraftItem>> applyDeduplication({
    required String familyId,
    required String walletId,
    required List<StatementDraftItem> items,
  }) async {
    if (items.isEmpty) return const [];

    // Compute date range to query existing SQLite transactions efficiently
    var minDate = items.first.date;
    var maxDate = items.first.date;
    for (final item in items) {
      if (item.date.isBefore(minDate)) minDate = item.date;
      if (item.date.isAfter(maxDate)) maxDate = item.date;
    }

    final existingAll = await db.getTransactionsDetailed(
      familyId,
      walletIdFilter: walletId,
    );

    final startDay = DateTime(minDate.year, minDate.month, minDate.day - 1);
    final endDay = DateTime(maxDate.year, maxDate.month, maxDate.day + 2);

    // Build occurrence pools of existing DB transactions in range
    final dbHashCounts = <String, int>{};
    final dbKeyCounts = <String, int>{};

    for (final detailed in existingAll) {
      final tx = detailed.transaction;
      // Only compare outgoing/incoming rows whose primary wallet is this walletId
      if (tx.walletId != walletId) continue;
      final localDate =
          DateTime.fromMillisecondsSinceEpoch(tx.date, isUtc: true).toLocal();
      if (localDate.isBefore(startDay) || localDate.isAfter(endDay)) continue;

      if (tx.receiptHash != null && tx.receiptHash!.isNotEmpty) {
        dbHashCounts[tx.receiptHash!] =
            (dbHashCounts[tx.receiptHash!] ?? 0) + 1;
      }
      final softKey = _softDayAmountKey(localDate, tx.type, tx.amount);
      dbKeyCounts[softKey] = (dbKeyCounts[softKey] ?? 0) + 1;
    }

    // Track items seen on EARLIER pages to catch scrolling screenshot overlaps
    // without flagging two legitimate identical transactions on the SAME page.
    final seenByPage = <String, int>{};
    final output = <StatementDraftItem>[];

    for (final rawItem in items) {
      final fp = buildFingerprint(
        walletId: walletId,
        date: rawItem.date,
        type: rawItem.type,
        amount: rawItem.amount,
        merchant: rawItem.merchant,
      );
      final softKey = _softDayAmountKey(
        rawItem.date,
        rawItem.type,
        rawItem.amount,
      );

      var isDup = false;
      String? reason;

      // 1. Exact receiptHash match in DB
      if ((dbHashCounts[fp] ?? 0) > 0) {
        dbHashCounts[fp] = dbHashCounts[fp]! - 1;
        if ((dbKeyCounts[softKey] ?? 0) > 0) {
          dbKeyCounts[softKey] = dbKeyCounts[softKey]! - 1;
        }
        isDup = true;
        reason = 'Sudah pernah diimpor ke dompet ini';
      }
      // 2. Soft DB match (same wallet + calendar day + type + exact amount)
      else if ((dbKeyCounts[softKey] ?? 0) > 0) {
        dbKeyCounts[softKey] = dbKeyCounts[softKey]! - 1;
        isDup = true;
        reason = 'Kemungkinan sudah tercatat di buku keuangan';
      }
      // 3. Cross-page screenshot overlap (same fingerprint seen on an earlier page)
      else if (seenByPage.containsKey(fp) &&
          seenByPage[fp]! < rawItem.pageNumber) {
        isDup = true;
        reason = 'Overlap dengan gambar/halaman sebelumnya';
      }
      // Always record earliest page seen so overlapping copies on later pages
      // are caught even when earlier pages already matched DB records.
      seenByPage.putIfAbsent(fp, () => rawItem.pageNumber);

      // If switching targetWallet made a transfer's toWallet == sourceWallet, revert to expense
      final invalidSelfTransfer = rawItem.type == TransactionType.transfer &&
          rawItem.toWalletId == walletId;

      output.add(
        rawItem.copyWith(
          type: invalidSelfTransfer ? TransactionType.expense : rawItem.type,
          clearToWallet: invalidSelfTransfer,
          fingerprint: fp,
          isDuplicate: isDup,
          duplicateReason: reason,
          clearDuplicateReason: !isDup,
          selected: !isDup,
        ),
      );
    }

    return output;
  }

  /// Batch-commits all selected [items] into SQLite and optionally remembers
  /// the detected bank/last4 hint on [targetWallet].
  Future<int> commitSelectedItems({
    required String familyId,
    required Wallet targetWallet,
    required List<Wallet> allWallets,
    required List<Category> allCategories,
    required List<StatementDraftItem> items,
    bool rememberAccountHint = false,
    String? detectedBank,
    String? detectedAccountLast4,
  }) async {
    final chosen = items.where((i) => i.selected && i.amount > 0).toList();
    if (chosen.isEmpty) {
      throw ArgumentError('Pilih minimal 1 transaksi untuk disimpan.');
    }

    final walletMap = {for (final w in allWallets) w.id: w};
    var savedCount = 0;

    for (final item in chosen) {
      Wallet? toWallet;
      var effectiveType = item.type;
      String? effectiveCategoryId = item.categoryId;

      if (effectiveType == TransactionType.transfer) {
        toWallet =
            item.toWalletId != null ? walletMap[item.toWalletId!] : null;
        if (toWallet == null || toWallet.id == targetWallet.id) {
          effectiveType = TransactionType.expense;
          toWallet = null;
        }
      }

      if (effectiveType != TransactionType.transfer &&
          (effectiveCategoryId == null || effectiveCategoryId.isEmpty)) {
        final fallbackCat = AiEntityMatcher.matchCategory(
          suggestedName: item.categoryName ?? item.merchant,
          txType: effectiveType,
          categories: allCategories,
        );
        effectiveCategoryId = fallbackCat?.id;
      }

      final fp = buildFingerprint(
        walletId: targetWallet.id,
        date: item.date,
        type: effectiveType,
        amount: item.amount,
        merchant: item.merchant,
      );

      await transactionService.createTransaction(
        familyId: familyId,
        sourceWallet: targetWallet,
        targetWallet: toWallet,
        categoryId: effectiveCategoryId,
        type: effectiveType,
        amount: item.amount,
        date: item.date,
        merchant: item.merchant,
        note: item.note,
        receiptHash: fp,
        source: TransactionSource.aiStatement,
      );
      savedCount++;
    }

    if (rememberAccountHint &&
        ((detectedBank != null && detectedBank.trim().isNotEmpty) ||
            (detectedAccountLast4 != null &&
                detectedAccountLast4.trim().isNotEmpty))) {
      await walletService.setBankHint(
        walletId: targetWallet.id,
        bankName: detectedBank,
        last4: detectedAccountLast4,
      );
    }

    return savedCount;
  }

  String _softDayAmountKey(DateTime date, String type, int amount) {
    final day =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return '$day|$type|$amount';
  }

  ({
    List<StatementDraftItem> items,
    String? detectedBank,
    String? detectedLast4,
    String? detectedHolder,
    String? detectedPeriod,
  }) _decodePageJson({
    required String rawJson,
    required String walletId,
    required List<Wallet> wallets,
    required List<Category> categories,
    required DateTime fallbackDate,
    required int pageNumber,
  }) {
    final cleaned = _stripCodeFence(rawJson);
    final dynamic parsed;
    try {
      parsed = jsonDecode(cleaned);
    } catch (_) {
      throw GeminiException(
        'Respons AI pada halaman $pageNumber tidak berformat JSON valid. Coba ulangi atau gunakan model vision lain.',
      );
    }
    if (parsed is! Map<String, dynamic>) {
      throw GeminiException(
        'Struktur jawaban AI pada halaman $pageNumber tidak sesuai.',
      );
    }

    final bank = (parsed['detected_bank'] as String?)?.trim();
    final last4Raw = (parsed['detected_account_last4'] as String?)?.trim();
    final last4 =
        last4Raw != null ? WalletBankHint.normalizeLast4(last4Raw) : '';
    final holder = (parsed['detected_account_holder'] as String?)?.trim();
    final period = (parsed['detected_period'] as String?)?.trim();

    final rawList = parsed['transactions'];
    final items = <StatementDraftItem>[];

    if (rawList is List) {
      for (final entry in rawList) {
        if (entry is! Map) continue;
        final rawType = entry['type']?.toString() ?? TransactionType.expense;
        var type = (rawType == TransactionType.income ||
                rawType == TransactionType.transfer)
            ? rawType
            : TransactionType.expense;

        final rawAmt = entry['amount'];
        final amount = _parseStatementAmount(rawAmt);
        if (amount <= 0) continue;

        final merchantRaw = entry['merchant']?.toString().trim() ?? '';
        final noteRaw = entry['note']?.toString().trim();
        final merchant = merchantRaw.isNotEmpty
            ? merchantRaw
            : (noteRaw != null && noteRaw.isNotEmpty ? noteRaw : 'Mutasi');

        Wallet? matchedToWallet;
        if (type == TransactionType.transfer) {
          final suggestedTo = entry['to_wallet_name']?.toString().trim();
          if (suggestedTo != null && suggestedTo.isNotEmpty) {
            matchedToWallet = _matchExplicitTargetWallet(
              suggestedName: suggestedTo,
              wallets: wallets,
              excludeWalletId: walletId,
            );
          }
          if (matchedToWallet == null) {
            // Do not guess an unrelated target wallet for transfers; fall back safely to expense.
            type = TransactionType.expense;
          }
        }

        final matchedCat = type == TransactionType.transfer
            ? null
            : AiEntityMatcher.matchCategory(
                suggestedName: entry['category_name']?.toString(),
                txType: type,
                categories: categories,
              );

        final txDate = AiEntityMatcher.parseIsoDateOrFallback(
          entry['date']?.toString(),
          fallbackDate,
        );

        final fp = buildFingerprint(
          walletId: walletId,
          date: txDate,
          type: type,
          amount: amount,
          merchant: merchant,
        );

        items.add(
          StatementDraftItem(
            tempId: _uuid.v4(),
            type: type,
            amount: amount,
            date: txDate,
            merchant: merchant,
            note: (noteRaw != null && noteRaw.isNotEmpty) ? noteRaw : null,
            categoryId: matchedCat?.id,
            categoryName: matchedCat?.name,
            toWalletId: matchedToWallet?.id,
            toWalletName: matchedToWallet?.name,
            pageNumber: pageNumber,
            fingerprint: fp,
          ),
        );
      }
    }

    return (
      items: items,
      detectedBank: (bank != null && bank.isNotEmpty) ? bank : null,
      detectedLast4: last4.isNotEmpty ? last4 : null,
      detectedHolder: (holder != null && holder.isNotEmpty) ? holder : null,
      detectedPeriod: (period != null && period.isNotEmpty) ? period : null,
    );
  }

  /// Parses Rupiah integers safely even if an LLM returns a string with decimal cents
  /// like `"50.000,00"`, `"115600.00"`, or `"- Rp 30.000"`.
  static int parseStatementAmount(dynamic raw) => _parseStatementAmount(raw);

  static int _parseStatementAmount(dynamic raw) {
    if (raw is int) return raw.abs();
    if (raw is num) return raw.round().abs();
    var text = raw?.toString().trim() ?? '';
    if (text.isEmpty) return 0;
    // Strip superscript zeros like ⁰⁰ or trailing ,00 / .00 decimal cents
    text = text.replaceAll(RegExp(r'[⁰¹²³⁴⁵⁶⁷⁸⁹]+$'), '');
    text = text.replaceAll(RegExp(r'[,\.]\d{2}$'), '');
    return (CurrencyFormatter.parseIdr(text) ?? 0).abs();
  }

  Wallet? _matchExplicitTargetWallet({
    required String suggestedName,
    required List<Wallet> wallets,
    required String excludeWalletId,
  }) {
    final needle = suggestedName.trim().toLowerCase();
    if (needle.isEmpty) return null;
    final pool = wallets.where((w) => w.id != excludeWalletId).toList();
    final exact = pool.where((w) => w.name.toLowerCase() == needle).firstOrNull;
    if (exact != null) return exact;
    return pool
        .where(
          (w) =>
              w.name.toLowerCase().contains(needle) ||
              needle.contains(w.name.toLowerCase()),
        )
        .firstOrNull;
  }

  String _stripCodeFence(String raw) {
    var trimmed = NineRouterClient.stripThinkBlocks(raw).trim();
    if (trimmed.startsWith('```')) {
      final lines = trimmed.split('\n');
      if (lines.length >= 3 && lines.last.trim().startsWith('```')) {
        trimmed = lines.sublist(1, lines.length - 1).join('\n').trim();
      }
    }
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start > 0 && end > start) {
      trimmed = trimmed.substring(start, end + 1);
    }
    return trimmed;
  }
}
