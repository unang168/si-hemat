import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:si_hemat/app/providers.dart';
import 'package:si_hemat/app/theme/app_theme.dart';
import 'package:si_hemat/app/widgets/scope_indicator_bar.dart';
import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/core/utils/currency_formatter.dart';
import 'package:si_hemat/core/utils/date_formatter.dart';
import 'package:si_hemat/features/transactions/transaction_list_tile.dart';

class TransactionsTab extends ConsumerStatefulWidget {
  const TransactionsTab({super.key});

  @override
  ConsumerState<TransactionsTab> createState() => _TransactionsTabState();
}

class _TransactionsTabState extends ConsumerState<TransactionsTab> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _deleteWithUndo(TransactionWithDetails item) async {
    final service = ref.read(transactionServiceProvider);
    await service.deleteTransaction(item.transaction.id);
    if (!mounted) return;

    final title = item.transaction.merchant?.isNotEmpty == true
        ? item.transaction.merchant!
        : (item.category?.name ?? 'Transaksi');

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '"$title" (${CurrencyFormatter.formatIdr(item.transaction.amount)}) dihapus.',
          ),
          action: SnackBarAction(
            label: 'Urungkan',
            onPressed: () {
              service.restoreTransaction(item.transaction.id);
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final incomeColor = AppTheme.incomeOf(context);
    final expenseColor = AppTheme.expenseOf(context);

    final filter = ref.watch(transactionFilterProvider);
    final filterNotifier = ref.read(transactionFilterProvider.notifier);
    final txAsync = ref.watch(filteredTransactionsProvider);
    final summaryAsync = ref.watch(selectedMonthSummaryProvider);
    final members = ref.watch(familyMembersProvider).value ?? const [];
    final wallets = ref.watch(walletsWithBalanceProvider).value ?? const [];
    final hideBalance = ref.watch(hideBalanceProvider);

    final isCurrentMonth = DateFormatter.isSameMonth(
      filter.month,
      DateTime.now(),
    );
    final hasExtraFilter = filter.type != 'all' ||
        filter.memberId != null ||
        filter.walletId != null ||
        filter.categoryId != null ||
        filter.searchQuery.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Transaksi'),
        actions: [
          if (hasExtraFilter)
            TextButton(
              onPressed: () {
                _searchCtrl.clear();
                filterNotifier.clearFilters();
              },
              child: const Text('Reset Filter'),
            ),
          IconButton(
            tooltip: hideBalance ? 'Tampilkan Saldo' : 'Sembunyikan Saldo',
            icon: Icon(
              hideBalance
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
            onPressed: () => ref.read(hideBalanceProvider.notifier).toggle(),
          ),
        ],
      ),
      body: Column(
        children: [
          const ScopeIndicatorBar(),

          // Month Selector + Monthly Totals Strip
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Card(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left_rounded),
                          onPressed: filterNotifier.prevMonth,
                        ),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  DateFormatter.formatMonthYear(filter.month),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (!isCurrentMonth) ...[
                                const SizedBox(width: 8),
                                ActionChip(
                                  visualDensity: VisualDensity.compact,
                                  label: const Text('Bulan Ini'),
                                  onPressed: filterNotifier.goToCurrentMonth,
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right_rounded),
                          onPressed: filterNotifier.nextMonth,
                        ),
                      ],
                    ),
                    const Divider(height: 12),
                    summaryAsync.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (_, _) => const SizedBox.shrink(),
                      data: (s) => Row(
                        children: [
                          Expanded(
                            child: _MiniStat(
                              label: 'Masuk',
                              value: CurrencyFormatter.formatCompactIdr(
                                s.totalIncome,
                                hide: hideBalance,
                              ),
                              color: incomeColor,
                            ),
                          ),
                          Expanded(
                            child: _MiniStat(
                              label: 'Keluar',
                              value: CurrencyFormatter.formatCompactIdr(
                                s.totalExpense,
                                hide: hideBalance,
                              ),
                              color: expenseColor,
                            ),
                          ),
                          Expanded(
                            child: _MiniStat(
                              label: 'Selisih',
                              value: CurrencyFormatter.formatCompactIdr(
                                s.netCashflow,
                                hide: hideBalance,
                              ),
                              color: s.netCashflow >= 0
                                  ? incomeColor
                                  : expenseColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Search Box
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Cari toko, catatan, kategori, dompet...',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                suffixIcon: filter.searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchCtrl.clear();
                          filterNotifier.setSearch('');
                        },
                      )
                    : null,
              ),
              onChanged: filterNotifier.setSearch,
            ),
          ),
          const SizedBox(height: 8),

          // Type + Wallet + Member Filter Chips
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _FilterChip(
                  label: 'Semua',
                  selected: filter.type == 'all',
                  onTap: () => filterNotifier.setType('all'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Pengeluaran',
                  selected: filter.type == TransactionType.expense,
                  onTap: () => filterNotifier.setType(TransactionType.expense),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Pemasukan',
                  selected: filter.type == TransactionType.income,
                  onTap: () => filterNotifier.setType(TransactionType.income),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Transfer',
                  selected: filter.type == TransactionType.transfer,
                  onTap: () => filterNotifier.setType(TransactionType.transfer),
                ),
                if (wallets.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  ...wallets.map(
                    (w) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        avatar: const Icon(
                          Icons.account_balance_wallet_outlined,
                          size: 16,
                        ),
                        label: Text(w.wallet.name),
                        selected: filter.walletId == w.wallet.id,
                        onSelected: (selected) => filterNotifier.setWallet(
                          selected ? w.wallet.id : null,
                        ),
                      ),
                    ),
                  ),
                ],
                if (members.length > 1) ...[
                  const SizedBox(width: 4),
                  ...members.map(
                    (m) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        avatar: const Icon(Icons.person_outline, size: 16),
                        label: Text(m.name),
                        selected: filter.memberId == m.id,
                        onSelected: (selected) => filterNotifier.setMember(
                          selected ? m.id : null,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Grouped Transaction List with Daily Subtotals & Swipe-to-Delete Undo
          Expanded(
            child: txAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Gagal memuat: $e')),
              data: (items) {
                if (items.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 52,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Belum ada transaksi',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            hasExtraFilter
                                ? 'Tidak ada transaksi yang cocok dengan filter aktif. Coba reset filter atau geser bulan.'
                                : 'Catat pengeluaran, pemasukan, atau transfer pertama Anda dengan tombol "+ Catat".',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (hasExtraFilter)
                            OutlinedButton.icon(
                              onPressed: () {
                                _searchCtrl.clear();
                                filterNotifier.clearFilters();
                              },
                              icon: const Icon(Icons.filter_alt_off_outlined),
                              label: const Text('Reset Semua Filter'),
                            )
                          else
                            FilledButton.icon(
                              onPressed: () => context.push('/transaction/new'),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Catat Transaksi Pertama'),
                            ),
                        ],
                      ),
                    ),
                  );
                }

                final grouped = _groupByDay(items);
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: grouped.length,
                  itemBuilder: (context, index) {
                    final group = grouped[index];
                    final netFlow = group.dailyNetFlow;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    DateFormatter.formatDayHeader(group.day),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: colors.onSurfaceVariant,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (group.hasCashflow)
                                  Text(
                                    CurrencyFormatter.formatSignedIdr(
                                      netFlow,
                                      hide: hideBalance,
                                    ),
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: netFlow >= 0
                                          ? incomeColor
                                          : expenseColor,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Card(
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              children: [
                                for (var i = 0;
                                    i < group.items.length;
                                    i++) ...[
                                  if (i > 0) const Divider(height: 1),
                                  Dismissible(
                                    key: ValueKey(
                                      group.items[i].transaction.id,
                                    ),
                                    direction: DismissDirection.endToStart,
                                    background: Container(
                                      color: AppTheme.expenseColor,
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'Hapus',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          SizedBox(width: 6),
                                          Icon(
                                            Icons.delete_outline_rounded,
                                            color: Colors.white,
                                          ),
                                        ],
                                      ),
                                    ),
                                    onDismissed: (_) =>
                                        _deleteWithUndo(group.items[i]),
                                    child: TransactionListTile(
                                      item: group.items[i],
                                      hideBalance: hideBalance,
                                      onTap: () => context.push(
                                        '/transaction/edit',
                                        extra: group.items[i].transaction,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<_DayGroup> _groupByDay(List<TransactionWithDetails> items) {
    final map = <DateTime, List<TransactionWithDetails>>{};
    for (final item in items) {
      final dt = DateTime.fromMillisecondsSinceEpoch(
        item.transaction.date,
        isUtc: true,
      ).toLocal();
      final dayKey = DateTime(dt.year, dt.month, dt.day);
      map.putIfAbsent(dayKey, () => []).add(item);
    }
    final keys = map.keys.toList()..sort((a, b) => b.compareTo(a));
    return keys.map((k) => _DayGroup(day: k, items: map[k]!)).toList();
  }
}

class _DayGroup {
  const _DayGroup({required this.day, required this.items});
  final DateTime day;
  final List<TransactionWithDetails> items;

  bool get hasCashflow => items.any(
        (e) =>
            e.transaction.type == TransactionType.income ||
            e.transaction.type == TransactionType.expense,
      );

  int get dailyNetFlow {
    var net = 0;
    for (final e in items) {
      if (e.transaction.type == TransactionType.income) {
        net += e.transaction.amount;
      } else if (e.transaction.type == TransactionType.expense) {
        net -= e.transaction.amount;
      }
    }
    return net;
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}
