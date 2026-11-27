import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:si_hemat/app/providers.dart';
import 'package:si_hemat/app/theme/app_theme.dart';
import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/utils/currency_formatter.dart';
import 'package:si_hemat/core/utils/date_formatter.dart';
import 'package:si_hemat/features/ai_assistant/ai_models.dart';

class AiChatInputScreen extends ConsumerStatefulWidget {
  const AiChatInputScreen({super.key});

  @override
  ConsumerState<AiChatInputScreen> createState() => _AiChatInputScreenState();
}

class _AiChatInputScreenState extends ConsumerState<AiChatInputScreen> {
  final _inputCtrl = TextEditingController();
  bool _analyzing = false;
  bool _saving = false;
  String? _assistantReply;
  String? _errorText;
  List<AiTransactionDraft> _drafts = [];

  static const List<String> _examples = [
    'Beli susu anak 85rb dan popok 120rb pakai Kas Keluarga',
    'Bayar bensin 50rb dan parkir 5rb tunai',
    'Terima gaji 8,5jt masuk Rekening Keluarga',
    'Transfer 1jt dari Rekening Keluarga ke Kas Keluarga',
  ];

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    final text = _inputCtrl.text.trim();
    final family = ref.read(activeFamilyProvider).value;
    if (text.isEmpty || family == null) return;

    setState(() {
      _analyzing = true;
      _errorText = null;
    });

    try {
      final result = await ref
          .read(aiFinanceServiceProvider)
          .parseTransactionsFromChat(familyId: family.id, userText: text);
      if (!mounted) return;
      setState(() {
        _assistantReply = result.assistantMessage;
        _drafts = List<AiTransactionDraft>.from(result.drafts);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = e.toString());
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _commitAllDrafts() async {
    final family = ref.read(activeFamilyProvider).value;
    if (family == null || _drafts.isEmpty) return;

    setState(() => _saving = true);
    try {
      final service = ref.read(aiFinanceServiceProvider);
      var count = 0;
      for (final d in _drafts) {
        await service.commitDraft(familyId: family.id, draft: d);
        count++;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count transaksi berhasil disimpan ke buku!')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final configAsync = ref.watch(aiConfigProvider);
    final wallets = ref.watch(allWalletsWithBalanceProvider).value ?? const [];
    final categories = ref.watch(categoriesProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Catat via Chat AI'),
        actions: [
          IconButton(
            tooltip: 'Pengaturan AI',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/ai-settings'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (configAsync.value?.isConfigured == false) ...[
            Card(
              color: AppTheme.warningColor.withValues(alpha: 0.14),
              child: ListTile(
                leading: const Icon(
                  Icons.key_off_rounded,
                  color: AppTheme.warningColor,
                ),
                title: const Text(
                  'Gemini API Key belum diatur',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'Atur API Key gratis dari Google AI Studio untuk mengaktifkan fitur ini.',
                ),
                trailing: TextButton(
                  onPressed: () => context.push('/ai-settings'),
                  child: const Text('Atur'),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Ceritakan transaksi Anda dengan bahasa sehari-hari',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _inputCtrl,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText:
                          'Contoh: Tadi beli kopi 28rb dan roti 22rb pakai Kas Keluarga',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _examples
                        .map(
                          (ex) => ActionChip(
                            label: Text(
                              ex,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onPressed: () =>
                                setState(() => _inputCtrl.text = ex),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _analyzing ? null : _analyze,
                    icon: _analyzing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome_rounded),
                    label: Text(
                      _analyzing ? 'Menganalisis...' : 'Ubah Jadi Draft Transaksi',
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 12),
            Card(
              color: AppTheme.expenseColor.withValues(alpha: 0.12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _errorText!,
                  style: const TextStyle(color: AppTheme.expenseColor),
                ),
              ),
            ),
          ],
          if (_assistantReply != null) ...[
            const SizedBox(height: 14),
            Card(
              color: colors.primaryContainer.withValues(alpha: 0.45),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: colors.primary),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_assistantReply!)),
                  ],
                ),
              ),
            ),
          ],
          if (_drafts.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Periksa Draft (${_drafts.length} transaksi)',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _drafts.length; i++) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DraftReviewCard(
                  draft: _drafts[i],
                  wallets: wallets.map((w) => w.wallet).toList(),
                  categories: categories,
                  onChanged: (updated) => setState(() => _drafts[i] = updated),
                  onRemove: () => setState(() => _drafts.removeAt(i)),
                ),
              ),
            ],
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _saving ? null : _commitAllDrafts,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(
                _saving
                    ? 'Menyimpan...'
                    : 'Simpan Semua (${_drafts.length} Transaksi)',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DraftReviewCard extends StatelessWidget {
  const _DraftReviewCard({
    required this.draft,
    required this.wallets,
    required this.categories,
    required this.onChanged,
    required this.onRemove,
  });

  final AiTransactionDraft draft;
  final List wallets;
  final List categories;
  final ValueChanged<AiTransactionDraft> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTransfer = draft.type == TransactionType.transfer;
    final isIncome = draft.type == TransactionType.income;
    final matchingCats = categories
        .where(
          (c) => isIncome
              ? c.type == CategoryType.income
              : c.type == CategoryType.expense,
        )
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  label: Text(
                    isTransfer
                        ? 'Transfer'
                        : (isIncome ? 'Pemasukan' : 'Pengeluaran'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    CurrencyFormatter.formatIdr(draft.amount),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: isTransfer
                          ? AppTheme.transferColor
                          : (isIncome
                              ? AppTheme.incomeColor
                              : AppTheme.expenseColor),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Hapus draft',
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: onRemove,
                ),
              ],
            ),
            if (draft.merchant != null && draft.merchant!.isNotEmpty)
              Text(
                'Toko: ${draft.merchant}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            if (draft.note != null && draft.note!.isNotEmpty)
              Text(
                'Catatan: ${draft.note}',
                style: theme.textTheme.bodySmall,
              ),
            Text(
              'Tanggal: ${DateFormatter.formatShortDate(draft.date)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            if (!isTransfer && matchingCats.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: matchingCats.any((c) => c.id == draft.categoryId)
                    ? draft.categoryId
                    : matchingCats.first.id as String,
                decoration: const InputDecoration(
                  labelText: 'Kategori',
                  isDense: true,
                ),
                items: matchingCats
                    .map<DropdownMenuItem<String>>(
                      (c) => DropdownMenuItem<String>(
                        value: c.id as String,
                        child: Text(
                          c.name as String,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val == null) return;
                  final cat = matchingCats.firstWhere((c) => c.id == val);
                  onChanged(
                    draft.copyWith(
                      categoryId: cat.id as String,
                      categoryName: cat.name as String,
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
            ],
            if (wallets.isNotEmpty)
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: wallets.any((w) => w.id == draft.walletId)
                    ? draft.walletId
                    : wallets.first.id as String,
                decoration: InputDecoration(
                  labelText: isTransfer ? 'Dari Dompet' : 'Dompet',
                  isDense: true,
                ),
                items: wallets
                    .map<DropdownMenuItem<String>>(
                      (w) => DropdownMenuItem<String>(
                        value: w.id as String,
                        child: Text(
                          w.name as String,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val == null) return;
                  final w = wallets.firstWhere((x) => x.id == val);
                  onChanged(
                    draft.copyWith(
                      walletId: w.id as String,
                      walletName: w.name as String,
                    ),
                  );
                },
              ),
            if (isTransfer && wallets.length >= 2) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: wallets.any((w) => w.id == draft.toWalletId)
                    ? draft.toWalletId
                    : wallets.last.id as String,
                decoration: const InputDecoration(
                  labelText: 'Ke Dompet Tujuan',
                  isDense: true,
                ),
                items: wallets
                    .map<DropdownMenuItem<String>>(
                      (w) => DropdownMenuItem<String>(
                        value: w.id as String,
                        child: Text(
                          w.name as String,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val == null) return;
                  final w = wallets.firstWhere((x) => x.id == val);
                  onChanged(
                    draft.copyWith(
                      toWalletId: w.id as String,
                      toWalletName: w.name as String,
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
