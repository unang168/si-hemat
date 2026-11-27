import 'package:material_ui/material_ui.dart';
import 'package:si_hemat/app/theme/app_theme.dart';
import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/core/utils/category_icons.dart';
import 'package:si_hemat/core/utils/currency_formatter.dart';

class TransactionListTile extends StatelessWidget {
  const TransactionListTile({
    super.key,
    required this.item,
    required this.hideBalance,
    this.onTap,
  });

  final TransactionWithDetails item;
  final bool hideBalance;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tx = item.transaction;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isTransfer = tx.type == TransactionType.transfer;
    final isIncome = tx.type == TransactionType.income;

    final incomeColor = AppTheme.incomeOf(context);
    final expenseColor = AppTheme.expenseOf(context);
    final transferColor = AppTheme.transferOf(context);

    final Color accentColor;
    final IconData iconData;
    final String title;
    final String amountText;

    if (isTransfer) {
      accentColor = transferColor;
      iconData = Icons.swap_horiz_rounded;
      title =
          '${item.wallet?.name ?? 'Dompet'} → ${item.toWallet?.name ?? 'Dompet'}';
      amountText = CurrencyFormatter.formatIdr(tx.amount, hide: hideBalance);
    } else if (isIncome) {
      accentColor = incomeColor;
      iconData = AppIcons.forCategory(item.category?.icon);
      title = tx.merchant ?? item.category?.name ?? 'Pemasukan';
      amountText =
          CurrencyFormatter.formatSignedIdr(tx.amount, hide: hideBalance);
    } else {
      accentColor = item.category != null
          ? Color(item.category!.color)
          : expenseColor;
      iconData = AppIcons.forCategory(item.category?.icon);
      title = tx.merchant ?? item.category?.name ?? 'Pengeluaran';
      amountText =
          CurrencyFormatter.formatSignedIdr(-tx.amount, hide: hideBalance);
    }

    final subtitleParts = <String>[
      if (!isTransfer && tx.merchant != null && item.category != null)
        item.category!.name,
      if (!isTransfer && item.wallet != null) item.wallet!.name,
      if (item.member != null) item.member!.name,
      if (tx.visibility == VisibilityScope.personal) 'Pribadi',
      if (tx.note != null && tx.note!.isNotEmpty) tx.note!,
    ];

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: CircleAvatar(
        backgroundColor: accentColor.withValues(alpha: 0.14),
        foregroundColor: accentColor,
        child: Icon(iconData, size: 20),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitleParts.join(' • '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
      trailing: Text(
        amountText,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: isTransfer
              ? transferColor
              : (isIncome ? incomeColor : expenseColor),
        ),
      ),
    );
  }
}
