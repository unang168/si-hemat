import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:si_hemat/app/providers.dart';
import 'package:si_hemat/app/theme/app_theme.dart';
import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/core/utils/category_icons.dart';
import 'package:si_hemat/core/utils/currency_formatter.dart';
import 'package:si_hemat/core/utils/date_formatter.dart';
import 'package:si_hemat/core/utils/idr_input_formatter.dart';

class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({
    super.key,
    this.initialType = TransactionType.expense,
    this.existing,
  });

  final String initialType;
  final Transaction? existing;

  @override
  ConsumerState<TransactionFormScreen> createState() =>
      _TransactionFormScreenState();
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountCtrl;
  late final TextEditingController _merchantCtrl;
  late final TextEditingController _noteCtrl;

  late String _type;
  late DateTime _date;
  String? _walletId;
  String? _toWalletId;
  String? _categoryId;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  static const List<int> _quickAmounts = [10000, 25000, 50000, 100000, 500000];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = e?.type ?? widget.initialType;
    _date = e != null
        ? DateTime.fromMillisecondsSinceEpoch(e.date, isUtc: true).toLocal()
        : DateTime.now();
    _walletId = e?.walletId;
    _toWalletId = e?.toWalletId;
    _categoryId = e?.categoryId;
    _amountCtrl = TextEditingController(
      text: e != null ? CurrencyFormatter.formatNumber(e.amount) : '',
    );
    _merchantCtrl = TextEditingController(text: e?.merchant ?? '');
    _noteCtrl = TextEditingController(text: e?.note ?? '');
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _merchantCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _addQuickAmount(int delta) {
    final current = CurrencyFormatter.parseIdr(_amountCtrl.text) ?? 0;
    final next = current + delta;
    setState(() {
      _amountCtrl.text = CurrencyFormatter.formatNumber(next);
      _amountCtrl.selection = TextSelection.collapsed(
        offset: _amountCtrl.text.length,
      );
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _date = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _date.hour,
          _date.minute,
        );
      });
    }
  }

  Future<void> _submit({
    required String familyId,
    required List<WalletWithBalance> wallets,
  }) async {
    if (!_formKey.currentState!.validate()) return;
    final amount = CurrencyFormatter.parseIdr(_amountCtrl.text) ?? 0;
    if (amount <= 0) {
      _showError('Masukkan nominal lebih dari Rp 0.');
      return;
    }

    final sourceWallet =
        wallets.where((w) => w.wallet.id == _walletId).firstOrNull?.wallet;
    if (sourceWallet == null) {
      _showError('Pilih dompet terlebih dahulu.');
      return;
    }

    Wallet? targetWallet;
    if (_type == TransactionType.transfer) {
      targetWallet =
          wallets.where((w) => w.wallet.id == _toWalletId).firstOrNull?.wallet;
      if (targetWallet == null) {
        _showError('Pilih dompet tujuan transfer.');
        return;
      }
      if (targetWallet.id == sourceWallet.id) {
        _showError('Dompet asal dan tujuan tidak boleh sama.');
        return;
      }
    } else if (_categoryId == null) {
      _showError('Pilih kategori terlebih dahulu.');
      return;
    }

    setState(() => _saving = true);
    try {
      final service = ref.read(transactionServiceProvider);
      if (_isEditing) {
        await service.updateTransaction(
          transactionId: widget.existing!.id,
          sourceWallet: sourceWallet,
          targetWallet: targetWallet,
          categoryId: _categoryId,
          type: _type,
          amount: amount,
          date: _date,
          merchant: _merchantCtrl.text,
          note: _noteCtrl.text,
        );
      } else {
        await service.createTransaction(
          familyId: familyId,
          sourceWallet: sourceWallet,
          targetWallet: targetWallet,
          categoryId: _categoryId,
          type: _type,
          amount: amount,
          date: _date,
          merchant: _merchantCtrl.text,
          note: _noteCtrl.text,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showError(e.toString().replaceFirst('Invalid argument(s): ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Transaksi?'),
        content: const Text(
          'Transaksi ini akan dihapus dan saldo dompet otomatis disesuaikan kembali.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.expenseColor,
              minimumSize: const Size(96, 44),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(transactionServiceProvider).deleteTransaction(existing.id);
    if (mounted) Navigator.pop(context);
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final family = ref.watch(activeFamilyProvider).value;
    final wallets = ref.watch(allWalletsWithBalanceProvider).value ?? const [];
    final allCategories = ref.watch(categoriesProvider).value ?? const [];

    final filteredCategories = allCategories
        .where(
          (c) => _type == TransactionType.income
              ? c.type == CategoryType.income
              : c.type == CategoryType.expense,
        )
        .toList();

    // Auto-select sensible defaults on first load
    if (_walletId == null && wallets.isNotEmpty) {
      _walletId = wallets.first.wallet.id;
    }
    if (_type == TransactionType.transfer &&
        _toWalletId == null &&
        wallets.length >= 2) {
      _toWalletId = wallets
          .firstWhere(
            (w) => w.wallet.id != _walletId,
            orElse: () => wallets.last,
          )
          .wallet
          .id;
    }
    if (_type != TransactionType.transfer &&
        filteredCategories.isNotEmpty &&
        !filteredCategories.any((c) => c.id == _categoryId)) {
      _categoryId = filteredCategories.first.id;
    }

    final parsedAmount = CurrencyFormatter.parseIdr(_amountCtrl.text) ?? 0;
    final selectedSourceWallet =
        wallets.where((w) => w.wallet.id == _walletId).firstOrNull?.wallet;
    final selectedTargetWallet =
        wallets.where((w) => w.wallet.id == _toWalletId).firstOrNull?.wallet;
    final mixedVisibilityTransfer = _type == TransactionType.transfer &&
        selectedSourceWallet != null &&
        selectedTargetWallet != null &&
        selectedSourceWallet.visibility != selectedTargetWallet.visibility;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Transaksi' : 'Catat Transaksi'),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Hapus Transaksi',
              onPressed: _saving ? null : _confirmDelete,
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: AppTheme.expenseColor,
              ),
            ),
        ],
      ),
      body: family == null
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  // Step 1: Type Switcher
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: TransactionType.expense,
                        icon: Icon(Icons.arrow_upward_rounded, size: 18),
                        label: Text('Keluar'),
                      ),
                      ButtonSegment(
                        value: TransactionType.income,
                        icon: Icon(Icons.arrow_downward_rounded, size: 18),
                        label: Text('Masuk'),
                      ),
                      ButtonSegment(
                        value: TransactionType.transfer,
                        icon: Icon(Icons.swap_horiz_rounded, size: 18),
                        label: Text('Transfer'),
                      ),
                    ],
                    selected: {_type},
                    onSelectionChanged: (s) {
                      setState(() {
                        _type = s.first;
                        _categoryId = null;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // Step 2: Nominal Input + Quick Shortcut Chips
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nominal (Rp)',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _amountCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: const [IdrInputFormatter()],
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: _type == TransactionType.income
                                  ? AppTheme.incomeOf(context)
                                  : (_type == TransactionType.transfer
                                      ? AppTheme.transferOf(context)
                                      : AppTheme.expenseOf(context)),
                            ),
                            decoration: InputDecoration(
                              prefixText: 'Rp ',
                              hintText: '0',
                              suffixIcon: _amountCtrl.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded),
                                      onPressed: () =>
                                          setState(() => _amountCtrl.clear()),
                                    )
                                  : null,
                            ),
                            onChanged: (_) => setState(() {}),
                            validator: (v) {
                              final n = CurrencyFormatter.parseIdr(v ?? '') ?? 0;
                              if (n <= 0) return 'Nominal wajib > Rp 0';
                              return null;
                            },
                          ),
                          if (parsedAmount > 0) ...[
                            const SizedBox(height: 6),
                            Text(
                              CurrencyFormatter.formatIdr(parsedAmount),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _quickAmounts
                                .map(
                                  (amt) => ActionChip(
                                    label: Text(
                                      '+${CurrencyFormatter.formatCompactIdr(amt).replaceFirst('Rp ', '')}',
                                    ),
                                    onPressed: () => _addQuickAmount(amt),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Step 3: Wallet(s)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: wallets
                                    .any((w) => w.wallet.id == _walletId)
                                ? _walletId
                                : null,
                            decoration: InputDecoration(
                              labelText: _type == TransactionType.transfer
                                  ? 'Dari Dompet'
                                  : 'Dompet',
                              prefixIcon: const Icon(
                                Icons.account_balance_wallet_outlined,
                              ),
                            ),
                            items: wallets
                                .map(
                                  (w) => DropdownMenuItem<String>(
                                    value: w.wallet.id,
                                    child: Text(
                                      '${w.wallet.name} (${CurrencyFormatter.formatCompactIdr(w.balance)})',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() => _walletId = v),
                          ),
                          if (_type == TransactionType.transfer) ...[
                            const SizedBox(height: 14),
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue: wallets
                                      .any((w) => w.wallet.id == _toWalletId)
                                  ? _toWalletId
                                  : null,
                              decoration: const InputDecoration(
                                labelText: 'Ke Dompet Tujuan',
                                prefixIcon: Icon(Icons.arrow_forward_rounded),
                              ),
                              items: wallets
                                  .map(
                                    (w) => DropdownMenuItem<String>(
                                      value: w.wallet.id,
                                      child: Text(
                                        '${w.wallet.name} (${CurrencyFormatter.formatCompactIdr(w.balance)})',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _toWalletId = v),
                            ),
                            if (mixedVisibilityTransfer) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: colors.secondaryContainer
                                      .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Transfer melibatkan dompet Pribadi sehingga hanya disimpan lokal (tidak ikut Wi-Fi Sync) agar dompet pribadi tetap privat.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSecondaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Step 4: Category Picker (hidden for Transfer)
                  if (_type != TransactionType.transfer) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Kategori',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => context.push('/categories'),
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('Kelola'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: filteredCategories.map((cat) {
                        final selected = cat.id == _categoryId;
                        final color = Color(cat.color);
                        return ChoiceChip(
                          selected: selected,
                          avatar: Icon(
                            AppIcons.forCategory(cat.icon),
                            size: 18,
                            color: selected ? colors.onPrimary : color,
                          ),
                          label: Text(cat.name),
                          onSelected: (_) =>
                              setState(() => _categoryId = cat.id),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Step 5: Date, Merchant & Note
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.calendar_today_rounded),
                            title: const Text('Tanggal Transaksi'),
                            subtitle: Text(DateFormatter.formatShortDate(_date)),
                            trailing: const Text('Ubah'),
                            onTap: _pickDate,
                          ),
                          const Divider(height: 16),
                          if (_type != TransactionType.transfer) ...[
                            TextFormField(
                              controller: _merchantCtrl,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Toko / Merchant (opsional)',
                                hintText: 'Contoh: Alfamart, PLN, Warteg',
                                prefixIcon: Icon(Icons.storefront_outlined),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          TextFormField(
                            controller: _noteCtrl,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              labelText: 'Catatan (opsional)',
                              hintText: 'Contoh: Belanja sayur mingguan',
                              prefixIcon: Icon(Icons.notes_rounded),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),

                  FilledButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _submit(familyId: family.id, wallets: wallets),
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
                          : (_isEditing
                              ? 'Simpan Perubahan'
                              : 'Simpan Transaksi'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
