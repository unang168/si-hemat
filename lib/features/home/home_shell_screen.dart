import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:si_hemat/app/providers.dart';
import 'package:si_hemat/app/theme/app_theme.dart';
import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/features/budgets/budgets_bills_tab.dart';
import 'package:si_hemat/features/dashboard/dashboard_tab.dart';
import 'package:si_hemat/features/reports/reports_tab.dart';
import 'package:si_hemat/features/transactions/transactions_tab.dart';

class HomeShellScreen extends ConsumerStatefulWidget {
  const HomeShellScreen({super.key});

  @override
  ConsumerState<HomeShellScreen> createState() => _HomeShellScreenState();
}

class _HomeShellScreenState extends ConsumerState<HomeShellScreen> {
  int _selectedIndex = 0;

  void _openQuickAddSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        final theme = Theme.of(sheetCtx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Catat Transaksi Cepat',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        AppTheme.expenseColor.withValues(alpha: 0.14),
                    foregroundColor: AppTheme.expenseColor,
                    child: const Icon(Icons.edit_note_rounded),
                  ),
                  title: const Text('Catat Pengeluaran / Pemasukan'),
                  subtitle:
                      const Text('Input cepat manual dengan shortcut nominal'),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    context.push(
                      '/transaction/new?type=${TransactionType.expense}',
                    );
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        AppTheme.transferColor.withValues(alpha: 0.14),
                    foregroundColor: AppTheme.transferColor,
                    child: const Icon(Icons.swap_horiz_rounded),
                  ),
                  title: const Text('Transfer Antar Dompet'),
                  subtitle: const Text(
                    'Tarik tunai atau top-up e-wallet tanpa terhitung dobel',
                  ),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    context.push(
                      '/transaction/new?type=${TransactionType.transfer}',
                    );
                  },
                ),
                const Divider(height: 16),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        Theme.of(sheetCtx).colorScheme.primaryContainer,
                    foregroundColor:
                        Theme.of(sheetCtx).colorScheme.onPrimaryContainer,
                    child: const Icon(Icons.chat_bubble_outline_rounded),
                  ),
                  title: const Text('Catat via Chat AI (Gemini)'),
                  subtitle: const Text(
                    'Ketik santai, otomatis pecah jadi draft transaksi',
                  ),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    context.push('/ai-chat-input');
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        Theme.of(sheetCtx).colorScheme.secondaryContainer,
                    foregroundColor:
                        Theme.of(sheetCtx).colorScheme.onSecondaryContainer,
                    child: const Icon(Icons.document_scanner_outlined),
                  ),
                  title: const Text('Scan Struk / Screenshot QRIS'),
                  subtitle: const Text(
                    'Foto struk atau pilih screenshot bukti bayar via Gemini Vision',
                  ),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    context.push('/ai-receipt-scan');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardTab(
        onSeeAllTransactions: () => setState(() => _selectedIndex = 1),
        onOpenBudgetsBills: () => setState(() => _selectedIndex = 2),
        onOpenWalletTransactions: (walletId) {
          ref.read(transactionFilterProvider.notifier).setWallet(walletId);
          setState(() => _selectedIndex = 1);
        },
      ),
      const TransactionsTab(),
      const BudgetsBillsTab(),
      const ReportsTab(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openQuickAddSheet,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Catat'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Beranda',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Transaksi',
          ),
          NavigationDestination(
            icon: Icon(Icons.pie_chart_outline_rounded),
            selectedIcon: Icon(Icons.pie_chart_rounded),
            label: 'Anggaran',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights_rounded),
            label: 'Laporan',
          ),
        ],
      ),
    );
  }
}
