import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:si_hemat/app/providers.dart';
import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/core/utils/category_icons.dart';
import 'package:si_hemat/core/utils/currency_formatter.dart';
import 'package:si_hemat/core/utils/date_formatter.dart';
import 'package:si_hemat/features/transactions/transaction_list_tile.dart';

/// Opens a drill-down modal listing all transactions for a specific [categoryId]
/// in [month], respecting [visibilityFilter] (`all` | `shared` | `personal`).
/// Optionally displays an [onEditBudget] button when opened from a Budget card.
Future<void> showCategoryTransactionsSheet(
  BuildContext context, {
  required String familyId,
  required String categoryId,
  required String categoryName,
  required String? categoryIcon,
  required int categoryColor,
  required DateTime month,
  required String visibilityFilter,
  required String typeFilter,
  int? budgetLimitAmount,
  VoidCallback? onEditBudget,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CategoryTransactionsSheet(
      familyId: familyId,
      categoryId: categoryId,
      categoryName: categoryName,
      categoryIcon: categoryIcon,
      categoryColor: categoryColor,
      month: month,
      visibilityFilter: visibilityFilter,
      typeFilter: typeFilter,
      budgetLimitAmount: budgetLimitAmount,
      onEditBudget: onEditBudget,
    ),
  );
}

class _CategoryTransactionsSheet extends ConsumerWidget {
  const _CategoryTransactionsSheet({
    required this.familyId,
    required this.categoryId,
    required this.categoryName,
    required this.categoryIcon,
    required this.categoryColor,
    required this.month,
    required this.visibilityFilter,
    required this.typeFilter,
    this.budgetLimitAmount,
    this.onEditBudget,
  });

  final String familyId;
  final String categoryId;
  final String categoryName;
  final String? categoryIcon;
  final int categoryColor;
  final DateTime month;
  final String visibilityFilter;
  final String typeFilter;
  final int? budgetLimitAmount;
  final VoidCallback? onEditBudget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hideBalance = ref.watch(hideBalanceProvider);
    final db = ref.watch(databaseProvider);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.78,
        ),
        child: StreamBuilder<List<TransactionWithDetails>>(
          stream: db.watchTransactionsDetailed(
            familyId,
            month: month,
            visibilityFilter: visibilityFilter,
            typeFilter: typeFilter,
            categoryIdFilter: categoryId,
          ),
          builder: (context, snapshot) {
            final items = snapshot.data ?? const [];
            final total = items.fold<int>(
              0,
              (sum, e) => sum + e.transaction.amount,
            );

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor:
                            Color(categoryColor).withValues(alpha: 0.16),
                        foregroundColor: Color(categoryColor),
                        child: Icon(AppIcons.forCategory(categoryIcon)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              categoryName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${DateFormatter.formatMonthYear(month)} • ${items.length} transaksi • ${CurrencyFormatter.formatIdr(total, hide: hideBalance)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (onEditBudget != null)
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            onEditBudget!();
                          },
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Edit Batas'),
                        ),
                    ],
                  ),
                ),
                if (budgetLimitAmount != null && budgetLimitAmount! > 0) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: (total / budgetLimitAmount!).clamp(0.0, 1.0),
                            minHeight: 8,
                            color: total > budgetLimitAmount!
                                ? colors.error
                                : colors.primary,
                            backgroundColor: colors.surfaceContainerHighest,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Terpakai ${CurrencyFormatter.formatIdr(total, hide: hideBalance)} dari batas ${CurrencyFormatter.formatIdr(budgetLimitAmount!, hide: hideBalance)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Divider(height: 1),
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      'Belum ada transaksi pada kategori ini di ${DateFormatter.formatMonthYear(month)}.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return TransactionListTile(
                          item: item,
                          hideBalance: hideBalance,
                          onTap: () {
                            Navigator.pop(context);
                            context.push(
                              '/transaction/edit',
                              extra: item.transaction,
                            );
                          },
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
