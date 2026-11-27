import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:si_hemat/app/providers.dart';
import 'package:si_hemat/app/theme/app_theme.dart';
import 'package:si_hemat/app/widgets/category_transactions_sheet.dart';
import 'package:si_hemat/app/widgets/scope_indicator_bar.dart';
import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/core/utils/category_icons.dart';
import 'package:si_hemat/core/utils/currency_formatter.dart';
import 'package:si_hemat/core/utils/date_formatter.dart';
import 'package:si_hemat/core/utils/idr_input_formatter.dart';

class BudgetsBillsTab extends ConsumerWidget {
  const BudgetsBillsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(budgetMonthProvider);
    final monthNotifier = ref.read(budgetMonthProvider.notifier);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Anggaran & Tagihan'),
          bottom: const TabBar(
            tabs: [
              Tab(
                icon: Icon(Icons.pie_chart_outline_rounded, size: 18),
                text: 'Anggaran',
              ),
              Tab(
                icon: Icon(Icons.event_repeat_rounded, size: 18),
                text: 'Tagihan Rutin',
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            const ScopeIndicatorBar(),
            // Shared Month Bar for Budgets & Bills
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left_rounded),
                        onPressed: monthNotifier.prevMonth,
                      ),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                DateFormatter.formatMonthYear(month),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (!DateFormatter.isSameMonth(
                              month,
                              DateTime.now(),
                            )) ...[
                              const SizedBox(width: 8),
                              ActionChip(
                                visualDensity: VisualDensity.compact,
                                label: const Text('Bulan Ini'),
                                onPressed: monthNotifier.goToCurrentMonth,
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right_rounded),
                        onPressed: monthNotifier.nextMonth,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Expanded(
              child: TabBarView(
                children: [
                  _BudgetsSubTab(),
                  _BillsSubTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetsSubTab extends ConsumerWidget {
  const _BudgetsSubTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final family = ref.watch(activeFamilyProvider).value;
    final month = ref.watch(budgetMonthProvider);
    final budgetsAsync = ref.watch(budgetsProgressProvider);
    final hideBalance = ref.watch(hideBalanceProvider);

    return budgetsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Gagal memuat anggaran: $e')),
      data: (items) {
        final totalLimit =
            items.fold<int>(0, (sum, i) => sum + i.budget.limitAmount);
        final totalSpent = items.fold<int>(0, (sum, i) => sum + i.spentAmount);
        final totalRatio = totalLimit <= 0 ? 0.0 : totalSpent / totalLimit;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            // Summary & Action buttons
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Realisasi Anggaran',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${(totalRatio * 100).toStringAsFixed(0)}%',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: _statusColor(totalRatio),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: totalRatio.clamp(0.0, 1.0),
                        minHeight: 10,
                        color: _statusColor(totalRatio),
                        backgroundColor: colors.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Terpakai: ${CurrencyFormatter.formatIdr(totalSpent, hide: hideBalance)}',
                          style: theme.textTheme.bodySmall,
                        ),
                        Text(
                          'Batas: ${CurrencyFormatter.formatIdr(totalLimit, hide: hideBalance)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: family == null
                                ? null
                                : () => _openBudgetForm(
                                      context,
                                      familyId: family.id,
                                      month: month,
                                    ),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Atur Anggaran'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.outlined(
                          tooltip: 'Salin Anggaran Bulan Lalu',
                          onPressed: family == null
                              ? null
                              : () async {
                                  final count = await ref
                                      .read(budgetBillServiceProvider)
                                      .copyFromPreviousMonth(
                                        familyId: family.id,
                                        targetMonth: month,
                                      );
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        count > 0
                                            ? '$count anggaran disalin dari bulan lalu.'
                                            : 'Tidak ada anggaran baru untuk disalin dari bulan lalu.',
                                      ),
                                    ),
                                  );
                                },
                          icon: const Icon(Icons.copy_all_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (items.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(
                        Icons.pie_chart_outline_rounded,
                        size: 44,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Belum ada batas anggaran bulan ini',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tetapkan batas bulanan (mis. Makan & Dapur, Hiburan) agar pengeluaran keluarga selalu terkendali.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: family == null
                          ? null
                          : () => showCategoryTransactionsSheet(
                                context,
                                familyId: family.id,
                                categoryId: item.budget.categoryId,
                                categoryName:
                                    item.category?.name ?? 'Kategori',
                                categoryIcon: item.category?.icon,
                                categoryColor:
                                    item.category?.color ?? 0xFF0E7C66,
                                month: month,
                                visibilityFilter: item.budget.visibility,
                                typeFilter: TransactionType.expense,
                                budgetLimitAmount: item.budget.limitAmount,
                                onEditBudget: () => _openBudgetForm(
                                  context,
                                  familyId: family.id,
                                  month: month,
                                  existing: item.budget,
                                ),
                              ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: Color(
                                    item.category?.color ?? 0xFF0E7C66,
                                  ).withValues(alpha: 0.14),
                                  foregroundColor: Color(
                                    item.category?.color ?? 0xFF0E7C66,
                                  ),
                                  child: Icon(
                                    AppIcons.forCategory(item.category?.icon),
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.category?.name ?? 'Kategori',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        item.budget.visibility ==
                                                VisibilityScope.shared
                                            ? 'Anggaran Keluarga • Tap lihat rincian'
                                            : 'Anggaran Pribadi • Tap lihat rincian',
                                        style:
                                            theme.textTheme.labelSmall?.copyWith(
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _statusColor(item.ratio)
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    item.isOverBudget
                                        ? 'Over ${(item.ratio * 100).toStringAsFixed(0)}%'
                                        : '${(item.ratio * 100).toStringAsFixed(0)}%',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: _statusColor(item.ratio),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Edit Batas Anggaran',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                  ),
                                  onPressed: family == null
                                      ? null
                                      : () => _openBudgetForm(
                                            context,
                                            familyId: family.id,
                                            month: month,
                                            existing: item.budget,
                                          ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: item.ratio.clamp(0.0, 1.0),
                                minHeight: 8,
                                color: _statusColor(item.ratio),
                                backgroundColor: colors.surfaceContainerHighest,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${CurrencyFormatter.formatIdr(item.spentAmount, hide: hideBalance)} / ${CurrencyFormatter.formatIdr(item.budget.limitAmount, hide: hideBalance)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  item.remainingAmount >= 0
                                      ? 'Sisa ${CurrencyFormatter.formatCompactIdr(item.remainingAmount, hide: hideBalance)}'
                                      : 'Lebih ${CurrencyFormatter.formatCompactIdr(item.remainingAmount.abs(), hide: hideBalance)}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: _statusColor(item.ratio),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Color _statusColor(double ratio) {
    if (ratio >= 1.0) return AppTheme.expenseColor;
    if (ratio >= 0.8) return AppTheme.warningColor;
    return AppTheme.incomeColor;
  }

  Future<void> _openBudgetForm(
    BuildContext context, {
    required String familyId,
    required DateTime month,
    Budget? existing,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BudgetFormSheet(
        familyId: familyId,
        month: month,
        existing: existing,
      ),
    );
  }
}

class _BudgetFormSheet extends ConsumerStatefulWidget {
  const _BudgetFormSheet({
    required this.familyId,
    required this.month,
    this.existing,
  });

  final String familyId;
  final DateTime month;
  final Budget? existing;

  @override
  ConsumerState<_BudgetFormSheet> createState() => _BudgetFormSheetState();
}

class _BudgetFormSheetState extends ConsumerState<_BudgetFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _limitCtrl;
  String? _categoryId;
  late String _visibility;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _limitCtrl = TextEditingController(
      text: widget.existing != null
          ? CurrencyFormatter.formatNumber(widget.existing!.limitAmount)
          : '',
    );
    _categoryId = widget.existing?.categoryId;
    final activeScope = ref.read(scopeFilterProvider);
    _visibility = widget.existing?.visibility ??
        (activeScope == VisibilityScope.personal
            ? VisibilityScope.personal
            : VisibilityScope.shared);
  }

  @override
  void dispose() {
    _limitCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _categoryId == null) return;
    setState(() => _saving = true);
    try {
      final limit = CurrencyFormatter.parseIdr(_limitCtrl.text) ?? 0;
      await ref.read(budgetBillServiceProvider).saveBudget(
            familyId: widget.familyId,
            categoryId: _categoryId!,
            month: widget.month,
            limitAmount: limit,
            visibility: _visibility,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan anggaran: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final expenseCategories = (ref.watch(categoriesProvider).value ?? const [])
        .where((c) => c.type == CategoryType.expense)
        .toList();
    if (_categoryId == null && expenseCategories.isNotEmpty) {
      _categoryId = expenseCategories.first.id;
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, bottomInset + 20),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.existing != null
                        ? 'Edit Anggaran Bulanan'
                        : 'Atur Anggaran Bulanan',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (widget.existing != null)
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: AppTheme.expenseColor,
                    ),
                    onPressed: () async {
                      await ref
                          .read(budgetBillServiceProvider)
                          .deleteBudget(widget.existing!.id);
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: expenseCategories.any((c) => c.id == _categoryId)
                  ? _categoryId
                  : null,
              decoration: const InputDecoration(
                labelText: 'Kategori Pengeluaran',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: expenseCategories
                  .map(
                    (c) => DropdownMenuItem(
                      value: c.id,
                      child: Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: widget.existing != null
                  ? null
                  : (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _limitCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: const [IdrInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Batas Anggaran per Bulan (Rp)',
                prefixText: 'Rp ',
              ),
              validator: (v) {
                final n = CurrencyFormatter.parseIdr(v ?? '') ?? 0;
                return n <= 0 ? 'Batas anggaran wajib > Rp 0' : null;
              },
            ),
            const SizedBox(height: 14),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: VisibilityScope.shared,
                  label: Text('Keluarga'),
                ),
                ButtonSegment(
                  value: VisibilityScope.personal,
                  label: Text('Pribadi'),
                ),
              ],
              selected: {_visibility},
              onSelectionChanged: widget.existing != null
                  ? null
                  : (s) => setState(() => _visibility = s.first),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Menyimpan...' : 'Simpan Anggaran'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BillsSubTab extends ConsumerWidget {
  const _BillsSubTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final family = ref.watch(activeFamilyProvider).value;
    final month = ref.watch(budgetMonthProvider);
    final billsAsync = ref.watch(recurringBillsProvider);
    final hideBalance = ref.watch(hideBalanceProvider);

    return billsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Gagal memuat tagihan: $e')),
      data: (bills) {
        final totalBills =
            bills.fold<int>(0, (sum, b) => sum + b.bill.amount);
        final paidTotal = bills
            .where((b) => b.isPaidForMonth)
            .fold<int>(0, (sum, b) => sum + b.bill.amount);
        final unpaidTotal = totalBills - paidTotal;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _BillMetric(
                            label: 'Sudah Lunas',
                            value: CurrencyFormatter.formatCompactIdr(
                              paidTotal,
                              hide: hideBalance,
                            ),
                            color: AppTheme.incomeColor,
                          ),
                        ),
                        Expanded(
                          child: _BillMetric(
                            label: 'Belum Dibayar',
                            value: CurrencyFormatter.formatCompactIdr(
                              unpaidTotal,
                              hide: hideBalance,
                            ),
                            color: unpaidTotal > 0
                                ? AppTheme.expenseColor
                                : AppTheme.incomeColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: family == null
                          ? null
                          : () => _openBillForm(
                                context,
                                familyId: family.id,
                                activeMonth: month,
                              ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Tambah Tagihan Rutin'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (bills.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(
                        Icons.event_repeat_rounded,
                        size: 44,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Belum ada tagihan rutin',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Catat tagihan bulanan seperti Listrik, Internet, KPR, SPP, BPJS, atau cicilan agar tidak terlewat.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...bills.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      onTap: family == null
                          ? null
                          : () => _openBillForm(
                                context,
                                familyId: family.id,
                                activeMonth: month,
                                existing: item.bill,
                              ),
                      leading: CircleAvatar(
                        backgroundColor: item.isPaidForMonth
                            ? AppTheme.incomeColor.withValues(alpha: 0.14)
                            : (item.isOverdue
                                    ? AppTheme.expenseColor
                                    : AppTheme.warningColor)
                                .withValues(alpha: 0.14),
                        foregroundColor: item.isPaidForMonth
                            ? AppTheme.incomeColor
                            : (item.isOverdue
                                ? AppTheme.expenseColor
                                : AppTheme.warningColor),
                        child: Icon(
                          item.isPaidForMonth
                              ? Icons.check_circle_rounded
                              : AppIcons.forCategory(item.category?.icon),
                        ),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              item.bill.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                decoration: item.isPaidForMonth
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                          if (item.hasInstallmentPlan) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colors.secondaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${item.installmentNumber}/${item.totalInstallments}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colors.onSecondaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        '${CurrencyFormatter.formatIdr(item.bill.amount, hide: hideBalance)} • ${_dueLabel(item)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: item.isOverdue
                              ? AppTheme.expenseColor
                              : (item.isDueSoon
                                  ? AppTheme.warningColor
                                  : colors.onSurfaceVariant),
                          fontWeight: (item.isOverdue || item.isDueSoon)
                              ? FontWeight.w700
                              : null,
                        ),
                      ),
                      trailing: item.isPaidForMonth
                          ? const Chip(label: Text('Lunas'))
                          : FilledButton.tonal(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(76, 38),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                              ),
                              onPressed: () => _openPayBillSheet(
                                context,
                                item: item,
                                month: month,
                              ),
                              child: const Text('Bayar'),
                            ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  String _dueLabel(RecurringBillWithDetails item) {
    if (item.isPaidForMonth) return 'Sudah dibayar bulan ini';
    if (item.isOverdue) {
      return 'Terlambat ${item.daysUntilDue.abs()} hari (${DateFormatter.formatShortDate(item.dueDateForMonth)})';
    }
    if (item.daysUntilDue == 0) return 'Jatuh tempo Hari Ini!';
    if (item.isDueSoon) return 'Jatuh tempo H-${item.daysUntilDue}';
    return 'Jatuh tempo tgl ${item.bill.dueDay}';
  }

  Future<void> _openBillForm(
    BuildContext context, {
    required String familyId,
    required DateTime activeMonth,
    RecurringBill? existing,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BillFormSheet(
        familyId: familyId,
        activeMonth: activeMonth,
        existing: existing,
      ),
    );
  }

  Future<void> _openPayBillSheet(
    BuildContext context, {
    required RecurringBillWithDetails item,
    required DateTime month,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PayBillSheet(item: item, month: month),
    );
  }
}

class _BillMetric extends StatelessWidget {
  const _BillMetric({
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
      crossAxisAlignment: CrossAxisAlignment.start,
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
          style: theme.textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _BillFormSheet extends ConsumerStatefulWidget {
  const _BillFormSheet({
    required this.familyId,
    required this.activeMonth,
    this.existing,
  });

  final String familyId;
  final DateTime activeMonth;
  final RecurringBill? existing;

  @override
  ConsumerState<_BillFormSheet> createState() => _BillFormSheetState();
}

class _BillFormSheetState extends ConsumerState<_BillFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _tenorCtrl;
  String? _categoryId;
  String? _walletId;
  late int _dueDay;
  late String _visibility;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _amountCtrl = TextEditingController(
      text: e != null ? CurrencyFormatter.formatNumber(e.amount) : '',
    );
    _tenorCtrl = TextEditingController(
      text: _computeExistingTenor(e)?.toString() ?? '',
    );
    _categoryId = e?.categoryId;
    _walletId = e?.walletId;
    _dueDay = e?.dueDay ?? 10;
    final activeScope = ref.read(scopeFilterProvider);
    _visibility = e?.visibility ??
        (activeScope == VisibilityScope.personal
            ? VisibilityScope.personal
            : VisibilityScope.shared);
  }

  int? _computeExistingTenor(RecurringBill? bill) {
    if (bill?.startMonth == null || bill?.endMonth == null) return null;
    final s = bill!.startMonth!.split('-');
    final e = bill.endMonth!.split('-');
    if (s.length != 2 || e.length != 2) return null;
    final sy = int.tryParse(s[0]);
    final sm = int.tryParse(s[1]);
    final ey = int.tryParse(e[0]);
    final em = int.tryParse(e[1]);
    if (sy == null || sm == null || ey == null || em == null) return null;
    final diff = (ey - sy) * 12 + (em - sm) + 1;
    return diff > 0 ? diff : null;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _tenorCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _categoryId == null) return;
    setState(() => _saving = true);
    try {
      final amount = CurrencyFormatter.parseIdr(_amountCtrl.text) ?? 0;
      final tenorText = _tenorCtrl.text.trim();
      final tenor = tenorText.isEmpty ? null : int.tryParse(tenorText);
      final service = ref.read(budgetBillServiceProvider);

      if (widget.existing != null) {
        final existing = widget.existing!;
        await service.updateBill(
          billId: existing.id,
          walletId: _walletId,
          categoryId: _categoryId!,
          name: _nameCtrl.text,
          amount: amount,
          dueDay: _dueDay,
          startMonth: existing.startMonth ??
              DateFormatter.monthKey(widget.activeMonth),
          tenorMonths: tenor,
          existingEndMonth: existing.endMonth,
          clearTenor: tenorText.isEmpty,
          visibility: _visibility,
        );
      } else {
        await service.createBill(
          familyId: widget.familyId,
          walletId: _walletId,
          categoryId: _categoryId!,
          name: _nameCtrl.text,
          amount: amount,
          dueDay: _dueDay,
          startMonth: widget.activeMonth,
          tenorMonths: tenor,
          visibility: _visibility,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan tagihan: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDeleteBill() async {
    final existing = widget.existing;
    if (existing == null) return;

    final monthLabel = DateFormatter.formatMonthYear(widget.activeMonth);
    final prevMonthKey = DateFormatter.monthKey(
      DateTime(widget.activeMonth.year, widget.activeMonth.month - 1, 1),
    );
    final paidSet = AppDatabase.parsePaidMonths(existing);
    final hasPriorHistory = paidSet.any((m) => m.compareTo(prevMonthKey) <= 0) ||
        (existing.startMonth != null &&
            existing.startMonth!.compareTo(prevMonthKey) <= 0);

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus / Hentikan Tagihan'),
        content: Text(
          hasPriorHistory
              ? 'Pilih "Hentikan mulai $monthLabel" agar riwayat lunas bulan-bulan sebelumnya tetap tersimpan (hanya $monthLabel dan seterusnya yang dihapus).'
              : 'Tagihan "${existing.name}" akan dihapus dari daftar tagihan rutin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          if (hasPriorHistory)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'stop_future'),
              child: Text('Hentikan mulai $monthLabel'),
            ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.expenseColor,
            ),
            onPressed: () => Navigator.pop(ctx, 'delete_all'),
            child: Text(hasPriorHistory ? 'Hapus Semua Riwayat' : 'Hapus'),
          ),
        ],
      ),
    );

    if (action == null) return;
    final service = ref.read(budgetBillServiceProvider);
    if (action == 'stop_future') {
      await service.stopBillFromMonth(
        billId: existing.id,
        fromMonth: widget.activeMonth,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '"${existing.name}" dihentikan mulai $monthLabel. Riwayat bulan sebelumnya tetap tersimpan.',
            ),
          ),
        );
      }
    } else if (action == 'delete_all') {
      await service.deleteBill(existing.id);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final expenseCategories = (ref.watch(categoriesProvider).value ?? const [])
        .where((c) => c.type == CategoryType.expense)
        .toList();
    final wallets = ref.watch(allWalletsWithBalanceProvider).value ?? const [];

    if (_categoryId == null && expenseCategories.isNotEmpty) {
      final billsCat = expenseCategories
          .where((c) => c.id.endsWith('_exp_bills'))
          .firstOrNull;
      _categoryId = billsCat?.id ?? expenseCategories.first.id;
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, bottomInset + 20),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.existing != null
                          ? 'Edit Tagihan Rutin'
                          : 'Tambah Tagihan Rutin',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (widget.existing != null)
                    IconButton(
                      tooltip: 'Hapus / Hentikan Tagihan',
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: AppTheme.expenseColor,
                      ),
                      onPressed: _saving ? null : _confirmDeleteBill,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nama Tagihan',
                  hintText: 'Contoh: Listrik PLN, Internet, SPP, KPR',
                  prefixIcon: Icon(Icons.receipt_outlined),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Nama tagihan wajib diisi'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: const [IdrInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Estimasi Nominal (Rp)',
                  prefixText: 'Rp ',
                ),
                validator: (v) {
                  final n = CurrencyFormatter.parseIdr(v ?? '') ?? 0;
                  return n <= 0 ? 'Nominal wajib > Rp 0' : null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: _dueDay.clamp(1, 31),
                decoration: const InputDecoration(
                  labelText: 'Tanggal Jatuh Tempo Tiap Bulan',
                  prefixIcon: Icon(Icons.calendar_today_rounded),
                ),
                items: List.generate(
                  31,
                  (i) => DropdownMenuItem(
                    value: i + 1,
                    child: Text(
                      i + 1 == 31
                          ? 'Akhir bulan (tgl 28/29/30/31)'
                          : 'Setiap tanggal ${i + 1}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                onChanged: (v) {
                  if (v != null) setState(() => _dueDay = v);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tenorCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tenor / Lama Cicilan dalam Bulan (opsional)',
                  hintText: 'Contoh: 12 (kosongkan jika rutin selamanya)',
                  prefixIcon: Icon(Icons.timelapse_rounded),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final n = int.tryParse(v.trim());
                  if (n == null || n <= 0 || n > 360) {
                    return 'Masukkan angka tenor 1–360 bulan';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: expenseCategories.any((c) => c.id == _categoryId)
                    ? _categoryId
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Kategori',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: expenseCategories
                    .map(
                      (c) => DropdownMenuItem(
                        value: c.id,
                        child: Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _categoryId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: wallets.any((w) => w.wallet.id == _walletId)
                    ? _walletId
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Dompet Pembayaran Default (opsional)',
                  prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                ),
                items: wallets
                    .map(
                      (w) => DropdownMenuItem(
                        value: w.wallet.id,
                        child: Text(
                          w.wallet.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _walletId = v),
              ),
              const SizedBox(height: 14),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: VisibilityScope.shared,
                    label: Text('Keluarga'),
                  ),
                  ButtonSegment(
                    value: VisibilityScope.personal,
                    label: Text('Pribadi'),
                  ),
                ],
                selected: {_visibility},
                onSelectionChanged: (s) =>
                    setState(() => _visibility = s.first),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Menyimpan...' : 'Simpan Tagihan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PayBillSheet extends ConsumerStatefulWidget {
  const _PayBillSheet({
    required this.item,
    required this.month,
  });

  final RecurringBillWithDetails item;
  final DateTime month;

  @override
  ConsumerState<_PayBillSheet> createState() => _PayBillSheetState();
}

class _PayBillSheetState extends ConsumerState<_PayBillSheet> {
  late final TextEditingController _amountCtrl;
  String? _walletId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(
      text: CurrencyFormatter.formatNumber(widget.item.bill.amount),
    );
    _walletId = widget.item.bill.walletId;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final wallets = ref.watch(allWalletsWithBalanceProvider).value ?? const [];
    if (_walletId == null && wallets.isNotEmpty) {
      final matchingWallet = wallets
          .where((w) => w.wallet.visibility == widget.item.bill.visibility)
          .firstOrNull;
      _walletId = (matchingWallet ?? wallets.first).wallet.id;
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, bottomInset + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Bayar ${widget.item.bill.name}',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Tindakan ini otomatis menandai tagihan lunas untuk ${DateFormatter.formatMonthYear(widget.month)} sekaligus mencatat pengeluaran pada dompet yang dipilih.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: const [IdrInputFormatter()],
            decoration: const InputDecoration(
              labelText: 'Nominal Aktual Dibayar (Rp)',
              prefixText: 'Rp ',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: wallets.any((w) => w.wallet.id == _walletId)
                ? _walletId
                : null,
            decoration: const InputDecoration(
              labelText: 'Bayar dari Dompet',
              prefixIcon: Icon(Icons.account_balance_wallet_outlined),
            ),
            items: wallets
                .map(
                  (w) => DropdownMenuItem(
                    value: w.wallet.id,
                    child: Text(
                      '${w.wallet.name} (${w.wallet.visibility == VisibilityScope.shared ? 'Keluarga' : 'Pribadi'} • ${CurrencyFormatter.formatCompactIdr(w.balance)})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _walletId = v),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _saving
                ? null
                : () async {
                    final wallet = wallets
                        .where((w) => w.wallet.id == _walletId)
                        .firstOrNull
                        ?.wallet;
                    final amount =
                        CurrencyFormatter.parseIdr(_amountCtrl.text) ?? 0;
                    if (wallet == null || amount <= 0) return;

                    setState(() => _saving = true);
                    try {
                      await ref.read(budgetBillServiceProvider).payBill(
                            bill: widget.item.bill,
                            wallet: wallet,
                            month: widget.month,
                            overrideAmount: amount,
                          );
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${widget.item.bill.name} dicatat lunas (${CurrencyFormatter.formatIdr(amount)}).',
                            ),
                          ),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
            icon: const Icon(Icons.check_rounded),
            label: Text(_saving ? 'Memproses...' : 'Konfirmasi Lunas & Catat'),
          ),
        ],
      ),
    );
  }
}
