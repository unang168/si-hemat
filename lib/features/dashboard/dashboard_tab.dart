import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:si_hemat/app/providers.dart';
import 'package:si_hemat/app/theme/app_theme.dart';
import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/utils/category_icons.dart';
import 'package:si_hemat/core/utils/currency_formatter.dart';
import 'package:si_hemat/core/utils/date_formatter.dart';
import 'package:si_hemat/features/transactions/transaction_list_tile.dart';

class DashboardTab extends ConsumerWidget {
  const DashboardTab({
    super.key,
    this.onSeeAllTransactions,
    this.onOpenBudgetsBills,
    this.onOpenWalletTransactions,
  });

  final VoidCallback? onSeeAllTransactions;
  final VoidCallback? onOpenBudgetsBills;
  final ValueChanged<String>? onOpenWalletTransactions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final incomeColor = AppTheme.incomeOf(context);
    final expenseColor = AppTheme.expenseOf(context);
    final warningColor = AppTheme.warningOf(context);

    final family = ref.watch(activeFamilyProvider).value;
    final members = ref.watch(familyMembersProvider).value ?? const [];
    final walletsAsync = ref.watch(walletsWithBalanceProvider);
    final summaryAsync = ref.watch(currentMonthSummaryProvider);
    final recentTxAsync = ref.watch(recentTransactionsProvider);
    final dueBills = ref.watch(dueBillsAlertProvider).value ?? const [];
    final syncPeers = ref.watch(syncPeersProvider).value ?? const [];
    final hideBalance = ref.watch(hideBalanceProvider);
    final scope = ref.watch(scopeFilterProvider);

    if (family == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final now = DateTime.now();
    final nextPayday = DateFormatter.nextPaydayDate(now, family.paydayDay);
    final daysLeft = DateFormatter.daysUntilNextPayday(now, family.paydayDay);
    final lastSyncedAt = syncPeers.isNotEmpty ? syncPeers.first.lastSyncedAt : 0;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          floating: true,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(family.name),
              Text(
                'Si-Hemat • Offline-First',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: hideBalance ? 'Tampilkan Saldo' : 'Sembunyikan Saldo',
              icon: Icon(
                hideBalance
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: () => ref.read(hideBalanceProvider.notifier).toggle(),
            ),
            IconButton(
              tooltip: 'Pengaturan Gemini AI',
              icon: const Icon(Icons.auto_awesome_outlined),
              onPressed: () => context.push('/ai-settings'),
            ),
            IconButton(
              tooltip: 'Pengaturan Keamanan & Backup',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => context.push('/security-backup'),
            ),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // Scope filter: Semua | Keluarga | Pribadi
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'all', label: Text('Semua')),
                  ButtonSegment(
                    value: VisibilityScope.shared,
                    label: Text('Keluarga'),
                  ),
                  ButtonSegment(
                    value: VisibilityScope.personal,
                    label: Text('Pribadi'),
                  ),
                ],
                selected: {scope},
                onSelectionChanged: (s) =>
                    ref.read(scopeFilterProvider.notifier).setScope(s.first),
              ),
              const SizedBox(height: 16),

              // Due Bills Alert Banner (Overdue or H-3)
              if (dueBills.isNotEmpty) ...[
                Card(
                  color: warningColor.withValues(alpha: 0.12),
                  child: ListTile(
                    onTap: onOpenBudgetsBills,
                    leading: Icon(
                      Icons.notifications_active_rounded,
                      color: warningColor,
                    ),
                    title: Text(
                      '${dueBills.length} Tagihan Segera / Jatuh Tempo',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      dueBills.map((b) => b.bill.name).take(3).join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Hero Balance & Safe-to-Spend Card
              walletsAsync.when(
                loading: () => const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
                error: (e, _) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Gagal memuat saldo: $e'),
                  ),
                ),
                data: (wallets) {
                  final totalBalance = wallets.fold<int>(
                    0,
                    (sum, item) => sum + item.balance,
                  );
                  final safePerDay =
                      totalBalance > 0 ? totalBalance ~/ daysLeft : 0;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF0A6653),
                              Color(0xFF138F76),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              scope == 'all'
                                  ? 'Total Saldo Bersih'
                                  : scope == VisibilityScope.shared
                                      ? 'Saldo Bersama Keluarga'
                                      : 'Saldo Pribadi Anda',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              CurrencyFormatter.formatIdr(
                                totalBalance,
                                hide: hideBalance,
                              ),
                              style: theme.textTheme.headlineMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 16),
                            InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => _showEditPaydaySheet(
                                context,
                                ref,
                                family.id,
                                family.paydayDay,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.shield_outlined,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Safe-to-Spend: ${CurrencyFormatter.formatIdr(safePerDay, hide: hideBalance)}/hari ($daysLeft hari menuju gajian ${DateFormatter.formatPaydayShort(nextPayday)})',
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.edit_calendar_outlined,
                                      color:
                                          Colors.white.withValues(alpha: 0.9),
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Quick Actions Row (1-tap access to Manual, Chat AI, Scan Struk, Sync Wi-Fi)
                      Row(
                        children: [
                          Expanded(
                            child: _QuickActionButton(
                              icon: Icons.edit_note_rounded,
                              label: 'Catat',
                              color: expenseColor,
                              onTap: () => context.push(
                                '/transaction/new?type=${TransactionType.expense}',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _QuickActionButton(
                              icon: Icons.auto_awesome_rounded,
                              label: 'Chat AI',
                              color: colors.primary,
                              onTap: () => context.push('/ai-chat-input'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _QuickActionButton(
                              icon: Icons.document_scanner_outlined,
                              label: 'Scan Struk',
                              color: AppTheme.transferOf(context),
                              onTap: () => context.push('/ai-receipt-scan'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _QuickActionButton(
                              icon: Icons.wifi_rounded,
                              label: 'Sync Wi-Fi',
                              color: incomeColor,
                              onTap: () => context.push('/wifi-sync'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Monthly Cashflow Summary Card
                      summaryAsync.when(
                        loading: () => const SizedBox.shrink(),
                        error: (_, _) => const SizedBox.shrink(),
                        data: (summary) => Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Arus Kas ${DateFormatter.formatMonthYear(now)}',
                                      style:
                                          theme.textTheme.labelLarge?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (summary.totalIncome > 0 && !hideBalance)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: (summary.savingRatePercent >= 0
                                                  ? incomeColor
                                                  : expenseColor)
                                              .withValues(alpha: 0.14),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          'Saving ${summary.savingRatePercent.toStringAsFixed(0)}%',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color:
                                                summary.savingRatePercent >= 0
                                                    ? incomeColor
                                                    : expenseColor,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _CashflowBox(
                                        icon: Icons.arrow_downward_rounded,
                                        label: 'Pemasukan',
                                        amount: CurrencyFormatter.formatIdr(
                                          summary.totalIncome,
                                          hide: hideBalance,
                                        ),
                                        color: incomeColor,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _CashflowBox(
                                        icon: Icons.arrow_upward_rounded,
                                        label: 'Pengeluaran',
                                        amount: CurrencyFormatter.formatIdr(
                                          summary.totalExpense,
                                          hide: hideBalance,
                                        ),
                                        color: expenseColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Wallets section
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Dompet Aktif (${wallets.length})',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => context.push('/wallets'),
                            icon: const Icon(Icons.tune_rounded, size: 18),
                            label: const Text('Kelola'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (wallets.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('Belum ada dompet di filter ini.'),
                          ),
                        )
                      else
                        ...wallets.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Card(
                              child: ListTile(
                                onTap: () {
                                  if (onOpenWalletTransactions != null) {
                                    onOpenWalletTransactions!(item.wallet.id);
                                  } else {
                                    context.push('/wallets');
                                  }
                                },
                                leading: CircleAvatar(
                                  backgroundColor: Color(item.wallet.color)
                                      .withValues(alpha: 0.14),
                                  foregroundColor: Color(item.wallet.color),
                                  child: Icon(
                                    AppIcons.forWalletType(item.wallet.type),
                                  ),
                                ),
                                title: Text(
                                  item.wallet.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  '${WalletType.label(item.wallet.type)} • ${item.wallet.visibility == VisibilityScope.shared ? 'Keluarga' : 'Pribadi'}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      CurrencyFormatter.formatIdr(
                                        item.balance,
                                        hide: hideBalance,
                                      ),
                                      style:
                                          theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: item.balance >= 0
                                            ? incomeColor
                                            : expenseColor,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      size: 18,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 12),

              // Recent Transactions section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Transaksi Terbaru',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextButton(
                    onPressed: onSeeAllTransactions,
                    child: const Text('Lihat Semua'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              recentTxAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Gagal memuat transaksi: $e'),
                data: (items) {
                  if (items.isEmpty) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(
                              Icons.edit_note_rounded,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Belum ada transaksi. Tekan tombol "+ Catat" untuk mulai mencatat.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < items.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          TransactionListTile(
                            item: items[i],
                            hideBalance: hideBalance,
                            onTap: () => context.push(
                              '/transaction/edit',
                              extra: items[i].transaction,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 16),

              // Family members & Wi-Fi Sync preview card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.wifi_rounded, color: colors.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Keluarga (${members.length})',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  lastSyncedAt > 0
                                      ? 'Terakhir sync: ${DateFormatter.formatRelativeTime(lastSyncedAt)}'
                                      : 'Belum pernah sync Wi-Fi',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => context.push('/wifi-sync'),
                            icon: const Icon(Icons.sync_rounded, size: 18),
                            label: const Text('Sync'),
                          ),
                          TextButton.icon(
                            onPressed: () => context.push('/family-qr'),
                            icon: const Icon(Icons.qr_code_rounded, size: 18),
                            label: const Text('QR'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: members
                            .map(
                              (m) => Chip(
                                avatar: CircleAvatar(
                                  backgroundColor: Color(m.avatarColor),
                                  foregroundColor: Colors.white,
                                  child: Text(
                                    m.name.isNotEmpty
                                        ? m.name[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                label: Text(m.name),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Future<void> _showEditPaydaySheet(
    BuildContext context,
    WidgetRef ref,
    String familyId,
    int currentPayday,
  ) async {
    var selected = currentPayday.clamp(1, 31);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final previewDate = DateFormatter.nextPaydayDate(
              DateTime.now(),
              selected,
            );
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Ubah Tanggal Gajian',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Jika jatuh di hari Sabtu/Minggu, tanggal gajian otomatis maju ke hari Jumat.',
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      initialValue: selected,
                      decoration: const InputDecoration(
                        labelText: 'Tanggal Gajian',
                        prefixIcon: Icon(Icons.calendar_today_rounded),
                      ),
                      items: List.generate(
                        31,
                        (i) => DropdownMenuItem<int>(
                          value: i + 1,
                          child: Text(
                            DateFormatter.paydayOptionLabel(i + 1),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      onChanged: (v) {
                        if (v != null) setSheetState(() => selected = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Gajian berikutnya: ${DateFormatter.formatPaydayShort(previewDate)}',
                      style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(ctx).colorScheme.primary,
                          ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: () async {
                        final deviceId = await ref
                            .read(onboardingServiceProvider)
                            .getOrCreateDeviceId();
                        await ref.read(databaseProvider).updateFamilyPayday(
                              familyId: familyId,
                              paydayDay: selected,
                              deviceId: deviceId,
                            );
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: const Text('Simpan Tanggal Gajian'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: color.withValues(alpha: 0.14),
                foregroundColor: color,
                child: Icon(icon, size: 18),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CashflowBox extends StatelessWidget {
  const _CashflowBox({
    required this.icon,
    required this.label,
    required this.amount,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  amount,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
