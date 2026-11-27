import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/database/app_database.dart';

class AiTransactionDraft {
  const AiTransactionDraft({
    required this.type,
    required this.amount,
    required this.date,
    this.categoryId,
    this.categoryName,
    this.walletId,
    this.walletName,
    this.toWalletId,
    this.toWalletName,
    this.merchant,
    this.note,
    this.source = TransactionSource.aiChat,
  });

  final String type; // expense | income | transfer
  final int amount;
  final DateTime date;
  final String? categoryId;
  final String? categoryName;
  final String? walletId;
  final String? walletName;
  final String? toWalletId;
  final String? toWalletName;
  final String? merchant;
  final String? note;
  final String source;

  AiTransactionDraft copyWith({
    String? type,
    int? amount,
    DateTime? date,
    String? categoryId,
    String? categoryName,
    String? walletId,
    String? walletName,
    String? toWalletId,
    String? toWalletName,
    String? merchant,
    String? note,
  }) {
    return AiTransactionDraft(
      type: type ?? this.type,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      walletId: walletId ?? this.walletId,
      walletName: walletName ?? this.walletName,
      toWalletId: toWalletId ?? this.toWalletId,
      toWalletName: toWalletName ?? this.toWalletName,
      merchant: merchant ?? this.merchant,
      note: note ?? this.note,
      source: source,
    );
  }
}

class AiParseResult {
  const AiParseResult({
    required this.assistantMessage,
    required this.drafts,
  });

  final String assistantMessage;
  final List<AiTransactionDraft> drafts;
}

class AiConfig {
  const AiConfig({
    required this.apiKey,
    required this.model,
  });

  final String apiKey;
  final String model;

  bool get isConfigured => apiKey.trim().isNotEmpty;
}

/// Deterministic matchers that map Gemini's suggested category/wallet labels
/// onto the user's real SQLite IDs.
class AiEntityMatcher {
  AiEntityMatcher._();

  static Category? matchCategory({
    required String? suggestedName,
    required String txType,
    required List<Category> categories,
  }) {
    if (txType == TransactionType.transfer) return null;
    final desiredType = txType == TransactionType.income
        ? CategoryType.income
        : CategoryType.expense;
    final pool = categories.where((c) => c.type == desiredType).toList();
    if (pool.isEmpty) return null;

    if (suggestedName != null && suggestedName.trim().isNotEmpty) {
      final needle = suggestedName.trim().toLowerCase();
      final exact = pool
          .where((c) => c.name.toLowerCase() == needle)
          .firstOrNull;
      if (exact != null) return exact;

      final contains = pool
          .where(
            (c) =>
                c.name.toLowerCase().contains(needle) ||
                needle.contains(c.name.toLowerCase()),
          )
          .firstOrNull;
      if (contains != null) return contains;
    }

    // Fallback to "Lainnya" category if present, else first category of matching type
    return pool
            .where((c) => c.id.endsWith('_other'))
            .firstOrNull ??
        pool.first;
  }

  static Wallet? matchWallet({
    required String? suggestedName,
    required List<Wallet> wallets,
    String? excludeWalletId,
  }) {
    final pool = excludeWalletId == null
        ? wallets
        : wallets.where((w) => w.id != excludeWalletId).toList();
    if (pool.isEmpty) return null;

    if (suggestedName != null && suggestedName.trim().isNotEmpty) {
      final needle = suggestedName.trim().toLowerCase();
      final exact = pool
          .where((w) => w.name.toLowerCase() == needle)
          .firstOrNull;
      if (exact != null) return exact;

      final contains = pool
          .where(
            (w) =>
                w.name.toLowerCase().contains(needle) ||
                needle.contains(w.name.toLowerCase()),
          )
          .firstOrNull;
      if (contains != null) return contains;

      // Keyword hints for common Indonesian payment methods
      if (needle.contains('tunai') || needle.contains('cash')) {
        final cash = pool.where((w) => w.type == WalletType.cash).firstOrNull;
        if (cash != null) return cash;
      }
      if (needle.contains('bank') ||
          needle.contains('bca') ||
          needle.contains('mandiri') ||
          needle.contains('bri') ||
          needle.contains('bni') ||
          needle.contains('transfer') ||
          needle.contains('debit')) {
        final bank = pool.where((w) => w.type == WalletType.bank).firstOrNull;
        if (bank != null) return bank;
      }
      if (needle.contains('qris') ||
          needle.contains('gopay') ||
          needle.contains('ovo') ||
          needle.contains('dana') ||
          needle.contains('shopee')) {
        final ew = pool.where((w) => w.type == WalletType.ewallet).firstOrNull;
        if (ew != null) return ew;
      }
    }

    return pool.first;
  }

  static DateTime parseIsoDateOrFallback(String? isoDate, DateTime fallback) {
    if (isoDate == null || isoDate.trim().isEmpty) return fallback;
    final parsed = DateTime.tryParse(isoDate.trim());
    if (parsed == null) return fallback;
    return DateTime(
      parsed.year,
      parsed.month,
      parsed.day,
      fallback.hour,
      fallback.minute,
    );
  }
}
