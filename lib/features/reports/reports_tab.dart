import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
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
import 'package:si_hemat/features/transactions/transaction_list_tile.dart';

class ReportsTab extends ConsumerStatefulWidget {
  const ReportsTab({super.key});

  @override
  ConsumerState<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends ConsumerState<ReportsTab> {
  bool _exporting = false;
  int _touchedPieIndex = -1;

  Future<void> _exportReport({required bool asPdf}) async {
    final family = ref.read(activeFamilyProvider).value;
    final report = ref.read(monthlyReportProvider).value;
    final txs = ref.read(reportTransactionsProvider).value ?? const [];
    if (family == null || report == null) return;

    setState(() => _exporting = true);
    ref.read(suppressAutoLockProvider.notifier).setSuppressed(true);
    try {
      final exporter = ref.read(reportExportServiceProvider);
      if (asPdf) {
        await exporter.exportPdfAndShare(
          familyName: family.name,
          report: report,
          transactions: txs,
        );
      } else {
        await exporter.exportCsvAndShare(
          familyName: family.name,
          month: report.month,
          transactions: txs,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal export laporan: $e')),
      );
    } finally {
      ref.read(suppressAutoLockProvider.notifier).setSuppressed(false);
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final incomeColor = AppTheme.incomeOf(context);
    final expenseColor = AppTheme.expenseOf(context);

    final family = ref.watch(activeFamilyProvider).value;
    final scope = ref.watch(scopeFilterProvider);
    final month = ref.watch(reportMonthProvider);
    final monthNotifier = ref.read(reportMonthProvider.notifier);
    final reportAsync = ref.watch(monthlyReportProvider);
    final hideBalance = ref.watch(hideBalanceProvider);
    final isCurrentMonth = DateFormatter.isSameMonth(month, DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan Keuangan'),
        actions: [
          PopupMenuButton<String>(
            enabled: !_exporting,
            tooltip: 'Export Laporan',
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share_rounded),
            onSelected: (value) => _exportReport(asPdf: value == 'pdf'),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'pdf',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.picture_as_pdf_outlined),
                  title: Text('Export Laporan PDF'),
                ),
              ),
              PopupMenuItem(
                value: 'csv',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.table_chart_outlined),
                  title: Text('Export Transaksi CSV'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          const ScopeIndicatorBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded),
                      onPressed: () {
                        setState(() => _touchedPieIndex = -1);
                        monthNotifier.prevMonth();
                      },
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
                              onPressed: () {
                                setState(() => _touchedPieIndex = -1);
                                monthNotifier.goToCurrentMonth();
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded),
                      onPressed: () {
                        setState(() => _touchedPieIndex = -1);
                        monthNotifier.nextMonth();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: reportAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Gagal memuat laporan: $e')),
              data: (report) {
                if (report == null) {
                  return const Center(child: Text('Data belum tersedia.'));
                }
                final touchedCategory = (_touchedPieIndex >= 0 &&
                        _touchedPieIndex < report.expenseByCategory.length)
                    ? report.expenseByCategory[_touchedPieIndex]
                    : null;

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  children: [
                    // Executive Monthly Summary Card
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
                                  'Ringkasan Bulanan',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Chip(
                                  label: Text(
                                    'Saving ${report.summary.savingRatePercent.toStringAsFixed(0)}%',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _SummaryStat(
                                    label: 'Pemasukan',
                                    value: CurrencyFormatter.formatCompactIdr(
                                      report.summary.totalIncome,
                                      hide: hideBalance,
                                    ),
                                    color: incomeColor,
                                  ),
                                ),
                                Expanded(
                                  child: _SummaryStat(
                                    label: 'Pengeluaran',
                                    value: CurrencyFormatter.formatCompactIdr(
                                      report.summary.totalExpense,
                                      hide: hideBalance,
                                    ),
                                    color: expenseColor,
                                  ),
                                ),
                                Expanded(
                                  child: _SummaryStat(
                                    label: 'Selisih',
                                    value: CurrencyFormatter.formatCompactIdr(
                                      report.summary.netCashflow,
                                      hide: hideBalance,
                                    ),
                                    color: report.summary.netCashflow >= 0
                                        ? incomeColor
                                        : expenseColor,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _exporting
                                        ? null
                                        : () => _exportReport(asPdf: true),
                                    icon: const Icon(
                                      Icons.picture_as_pdf_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('PDF'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _exporting
                                        ? null
                                        : () => _exportReport(asPdf: false),
                                    icon: const Icon(
                                      Icons.table_chart_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('CSV'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Gemini AI Report Assistant Card
                    Card(
                      color: colors.primaryContainer.withValues(alpha: 0.45),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.auto_awesome_rounded,
                                  color: colors.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Asisten AI Laporan (Gemini / 9Router)',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Pengaturan AI',
                                  icon: const Icon(
                                    Icons.settings_outlined,
                                    size: 20,
                                  ),
                                  onPressed: () => context.push('/ai-settings'),
                                ),
                              ],
                            ),
                            Text(
                              'Tanya kondisi keuangan bulan ini atau minta evaluasi & saran hemat berdasarkan data SQLite Anda.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () => context.push(
                                      '/ai-report-chat?prompt=${Uri.encodeQueryComponent('Buat evaluasi keuangan keluarga bulan ini dan beri 3 saran hemat praktis.')}',
                                    ),
                                    icon: const Icon(
                                      Icons.summarize_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('Evaluasi AI'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        context.push('/ai-report-chat'),
                                    icon: const Icon(
                                      Icons.chat_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('Tanya AI'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Interactive Donut Chart: Expense by Category
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Komposisi Pengeluaran',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (report.expenseByCategory.isNotEmpty)
                                  Text(
                                    'Sentuh grafik / daftar',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            if (report.expenseByCategory.isEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 20),
                                child: Center(
                                  child: Text(
                                    'Belum ada pengeluaran di bulan ini.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              )
                            else ...[
                              SizedBox(
                                height: 210,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    PieChart(
                                      PieChartData(
                                        centerSpaceRadius: 56,
                                        sectionsSpace: 2,
                                        pieTouchData: PieTouchData(
                                          touchCallback: (event, response) {
                                            if (!event
                                                    .isInterestedForInteractions ||
                                                response == null ||
                                                response.touchedSection ==
                                                    null) {
                                              return;
                                            }
                                            final idx = response.touchedSection!
                                                .touchedSectionIndex;
                                            if (idx != _touchedPieIndex) {
                                              setState(
                                                () => _touchedPieIndex = idx,
                                              );
                                            }
                                          },
                                        ),
                                        sections: List.generate(
                                          report.expenseByCategory.length,
                                          (index) {
                                            final c =
                                                report.expenseByCategory[index];
                                            final isTouched =
                                                index == _touchedPieIndex;
                                            return PieChartSectionData(
                                              value: c.amount.toDouble(),
                                              color: Color(c.color),
                                              radius: isTouched ? 50 : 42,
                                              title: c.percentage >= 8
                                                  ? '${c.percentage.toStringAsFixed(0)}%'
                                                  : '',
                                              titleStyle: TextStyle(
                                                color: Colors.white,
                                                fontSize: isTouched ? 12 : 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 102,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            touchedCategory != null
                                                ? touchedCategory.categoryName
                                                : 'Total Keluar',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                              color: colors.onSurfaceVariant,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            CurrencyFormatter.formatCompactIdr(
                                              touchedCategory != null
                                                  ? touchedCategory.amount
                                                  : report.summary.totalExpense,
                                              hide: hideBalance,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: theme.textTheme.labelLarge
                                                ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          if (touchedCategory != null)
                                            Text(
                                              '${touchedCategory.percentage.toStringAsFixed(0)}%',
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                color: Color(
                                                  touchedCategory.color,
                                                ),
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              ...List.generate(
                                report.expenseByCategory.length,
                                (index) {
                                  final c = report.expenseByCategory[index];
                                  final isTouched = index == _touchedPieIndex;
                                  return InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: family == null
                                        ? null
                                        : () {
                                            setState(
                                              () => _touchedPieIndex = index,
                                            );
                                            showCategoryTransactionsSheet(
                                              context,
                                              familyId: family.id,
                                              categoryId: c.categoryId,
                                              categoryName: c.categoryName,
                                              categoryIcon: c.icon,
                                              categoryColor: c.color,
                                              month: month,
                                              visibilityFilter: scope,
                                              typeFilter:
                                                  TransactionType.expense,
                                            );
                                          },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isTouched
                                            ? Color(c.color)
                                                .withValues(alpha: 0.10)
                                            : null,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 14,
                                            backgroundColor: Color(c.color)
                                                .withValues(alpha: 0.14),
                                            foregroundColor: Color(c.color),
                                            child: Icon(
                                              AppIcons.forCategory(c.icon),
                                              size: 14,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              '${c.categoryName} (${c.transactionCount}x)',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            '${c.percentage.toStringAsFixed(0)}% • ${CurrencyFormatter.formatIdr(c.amount, hide: hideBalance)}',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(width: 2),
                                          Icon(
                                            Icons.chevron_right_rounded,
                                            size: 16,
                                            color: colors.onSurfaceVariant,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Interactive 6-Month Cashflow Bar Chart
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Tren 6 Bulan Terakhir',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Row(
                                  children: [
                                    _LegendDot(
                                      color: incomeColor,
                                      label: 'Masuk',
                                    ),
                                    const SizedBox(width: 10),
                                    _LegendDot(
                                      color: expenseColor,
                                      label: 'Keluar',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              height: 200,
                              child: _SixMonthBarChart(
                                points: report.trend6Months,
                                hideBalance: hideBalance,
                                incomeColor: incomeColor,
                                expenseColor: expenseColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Top 5 Biggest Expenses
                    if (report.topExpenses.isNotEmpty) ...[
                      Text(
                        'Pengeluaran Terbesar Bulan Ini',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Card(
                        child: Column(
                          children: [
                            for (var i = 0;
                                i < report.topExpenses.length;
                                i++) ...[
                              if (i > 0) const Divider(height: 1),
                              TransactionListTile(
                                item: report.topExpenses[i],
                                hideBalance: hideBalance,
                                onTap: () => context.push(
                                  '/transaction/edit',
                                  extra: report.topExpenses[i].transaction,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _SixMonthBarChart extends StatelessWidget {
  const _SixMonthBarChart({
    required this.points,
    required this.hideBalance,
    required this.incomeColor,
    required this.expenseColor,
  });

  final List<MonthlyTrendPoint> points;
  final bool hideBalance;
  final Color incomeColor;
  final Color expenseColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    var maxVal = 0;
    for (final p in points) {
      if (p.income > maxVal) maxVal = p.income;
      if (p.expense > maxVal) maxVal = p.expense;
    }
    final maxY = maxVal <= 0 ? 100000.0 : (maxVal * 1.2);
    final interval = maxY / 4;

    return BarChart(
      BarChartData(
        maxY: maxY,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => colors.inverseSurface,
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              if (groupIndex < 0 || groupIndex >= points.length) return null;
              final point = points[groupIndex];
              final monthLabel = DateFormat('MMM yyyy', 'id_ID').format(
                point.month,
              );
              final isIncome = rodIndex == 0;
              final label = isIncome ? 'Masuk' : 'Keluar';
              final amountStr = CurrencyFormatter.formatIdr(
                isIncome ? point.income : point.expense,
                hide: hideBalance,
              );
              return BarTooltipItem(
                '$monthLabel\n$label: $amountStr',
                TextStyle(
                  color: colors.onInverseSurface,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              );
            },
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: interval,
              getTitlesWidget: (value, meta) {
                if (hideBalance) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    CurrencyFormatter.formatShortAxisIdr(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= points.length) {
                  return const SizedBox.shrink();
                }
                final label = DateFormat('MMM', 'id_ID').format(
                  points[idx].month,
                );
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    label,
                    style: theme.textTheme.labelSmall,
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: List.generate(points.length, (i) {
          final p = points[i];
          return BarChartGroupData(
            x: i,
            barsSpace: 4,
            barRods: [
              BarChartRodData(
                toY: p.income.toDouble(),
                width: 10,
                borderRadius: BorderRadius.circular(4),
                color: incomeColor,
              ),
              BarChartRodData(
                toY: p.expense.toDouble(),
                width: 10,
                borderRadius: BorderRadius.circular(4),
                color: expenseColor,
              ),
            ],
          );
        }),
      ),
    );
  }
}
