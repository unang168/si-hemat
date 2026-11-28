import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:si_hemat/app/providers.dart';
import 'package:si_hemat/app/theme/app_theme.dart';
import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/core/utils/category_icons.dart';
import 'package:si_hemat/core/utils/currency_formatter.dart';
import 'package:si_hemat/core/utils/idr_input_formatter.dart';
import 'package:si_hemat/features/wallets/wallet_service.dart';

class WalletsScreen extends ConsumerWidget {
  const WalletsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final family = ref.watch(activeFamilyProvider).value;
    final walletsAsync = ref.watch(allWalletsWithBalanceProvider);
    final hints = ref.watch(walletBankHintsProvider).value ?? const {};
    final hideBalance = ref.watch(hideBalanceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelola Dompet'),
      ),
      floatingActionButton: family == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openWalletForm(
                context,
                ref,
                familyId: family.id,
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Dompet Baru'),
            ),
      body: walletsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat dompet: $e')),
        data: (wallets) {
          final sharedWallets = wallets
              .where((w) => w.wallet.visibility == VisibilityScope.shared)
              .toList();
          final personalWallets = wallets
              .where((w) => w.wallet.visibility == VisibilityScope.personal)
              .toList();
          final totalShared =
              sharedWallets.fold<int>(0, (sum, w) => sum + w.balance);
          final totalPersonal =
              personalWallets.fold<int>(0, (sum, w) => sum + w.balance);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              _SectionHeader(
                title: 'Dompet Bersama Keluarga',
                subtitle:
                    'Ikut tersinkronisasi saat Wi-Fi Sync • Total: ${CurrencyFormatter.formatIdr(totalShared, hide: hideBalance)}',
                icon: Icons.groups_rounded,
                color: colors.primary,
              ),
              const SizedBox(height: 10),
              if (sharedWallets.isEmpty)
                const _EmptyWalletCard(
                  text: 'Belum ada dompet bersama keluarga.',
                )
              else
                ...sharedWallets.map(
                  (item) => _WalletCard(
                    item: item,
                    bankHint: hints[item.wallet.id],
                    hideBalance: hideBalance,
                    onTap: () => _openWalletForm(
                      context,
                      ref,
                      familyId: family!.id,
                      existing: item.wallet,
                      existingHint: hints[item.wallet.id],
                    ),
                  ),
                ),
              const SizedBox(height: 22),
              _SectionHeader(
                title: 'Dompet Pribadi',
                subtitle:
                    'Hanya tersimpan di HP ini (tidak di-sync) • Total: ${CurrencyFormatter.formatIdr(totalPersonal, hide: hideBalance)}',
                icon: Icons.lock_outline_rounded,
                color: const Color(0xFF6A1B9A),
              ),
              const SizedBox(height: 10),
              if (personalWallets.isEmpty)
                const _EmptyWalletCard(text: 'Belum ada dompet pribadi.')
              else
                ...personalWallets.map(
                  (item) => _WalletCard(
                    item: item,
                    bankHint: hints[item.wallet.id],
                    hideBalance: hideBalance,
                    onTap: () => _openWalletForm(
                      context,
                      ref,
                      familyId: family!.id,
                      existing: item.wallet,
                      existingHint: hints[item.wallet.id],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openWalletForm(
    BuildContext context,
    WidgetRef ref, {
    required String familyId,
    Wallet? existing,
    WalletBankHint? existingHint,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _WalletFormSheet(
        familyId: familyId,
        existing: existing,
        existingHint: existingHint,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyWalletCard extends StatelessWidget {
  const _EmptyWalletCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({
    required this.item,
    this.bankHint,
    required this.hideBalance,
    required this.onTap,
  });

  final WalletWithBalance item;
  final WalletBankHint? bankHint;
  final bool hideBalance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hintText =
        bankHint != null && !bankHint!.isEmpty ? ' • ${bankHint!.displayLabel}' : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ListTile(
          onTap: onTap,
          leading: CircleAvatar(
            backgroundColor: Color(item.wallet.color).withValues(alpha: 0.14),
            foregroundColor: Color(item.wallet.color),
            child: Icon(AppIcons.forWalletType(item.wallet.type)),
          ),
          title: Text(
            item.wallet.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${WalletType.label(item.wallet.type)}$hintText • Saldo awal ${CurrencyFormatter.formatIdr(item.wallet.initialBalance, hide: hideBalance)}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                CurrencyFormatter.formatIdr(item.balance, hide: hideBalance),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: item.balance >= 0
                      ? AppTheme.incomeColor
                      : AppTheme.expenseColor,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _WalletFormSheet extends ConsumerStatefulWidget {
  const _WalletFormSheet({
    required this.familyId,
    this.existing,
    this.existingHint,
  });

  final String familyId;
  final Wallet? existing;
  final WalletBankHint? existingHint;

  @override
  ConsumerState<_WalletFormSheet> createState() => _WalletFormSheetState();
}

class _WalletFormSheetState extends ConsumerState<_WalletFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _initialBalanceCtrl;
  late final TextEditingController _bankNameCtrl;
  late final TextEditingController _last4Ctrl;
  late String _type;
  late String _visibility;
  late int _color;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _initialBalanceCtrl = TextEditingController(
      text: CurrencyFormatter.formatNumber(e?.initialBalance ?? 0),
    );
    _bankNameCtrl = TextEditingController(
      text: widget.existingHint?.bankName ?? '',
    );
    _last4Ctrl = TextEditingController(
      text: widget.existingHint?.last4 ?? '',
    );
    _type = e?.type ?? WalletType.bank;
    _visibility = e?.visibility ?? VisibilityScope.shared;
    _color = e?.color ?? AppIcons.walletColorPalette.first;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _initialBalanceCtrl.dispose();
    _bankNameCtrl.dispose();
    _last4Ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final balance = CurrencyFormatter.parseIdr(_initialBalanceCtrl.text) ?? 0;
      final service = ref.read(walletServiceProvider);
      final String walletId;
      if (_isEditing) {
        walletId = widget.existing!.id;
        await service.updateWallet(
          walletId: walletId,
          name: _nameCtrl.text,
          type: _type,
          visibility: _visibility,
          initialBalance: balance,
          color: _color,
        );
      } else {
        walletId = await service.createWallet(
          familyId: widget.familyId,
          name: _nameCtrl.text,
          type: _type,
          visibility: _visibility,
          initialBalance: balance,
          color: _color,
        );
      }
      await service.setBankHint(
        walletId: walletId,
        bankName: _type == WalletType.cash ? '' : _bankNameCtrl.text,
        last4: _type == WalletType.cash ? '' : _last4Ctrl.text,
      );
      ref.invalidate(walletBankHintsProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan dompet: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final txCount = await ref
        .read(databaseProvider)
        .countActiveTransactionsForWallet(existing.id);
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Dompet?'),
        content: Text(
          txCount > 0
              ? 'Dompet "${existing.name}" memiliki $txCount transaksi terkait. Dompet akan disembunyikan (soft-delete) agar riwayat tidak rusak.'
              : 'Dompet "${existing.name}" akan dihapus dari daftar aktif.',
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

    if (confirmed != true) return;
    await ref.read(walletServiceProvider).deleteWallet(existing.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final theme = Theme.of(context);

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
                      _isEditing ? 'Edit Dompet' : 'Tambah Dompet Baru',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_isEditing)
                    IconButton(
                      tooltip: 'Hapus Dompet',
                      onPressed: _saving ? null : _confirmDelete,
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: AppTheme.expenseColor,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nama Dompet',
                  hintText: 'Contoh: BCA Keluarga, GoPay, Dana Darurat',
                  prefixIcon: Icon(Icons.label_outline_rounded),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Nama dompet wajib diisi'
                    : null,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _type,
                decoration: const InputDecoration(
                  labelText: 'Jenis Dompet',
                  prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                ),
                items: WalletType.all
                    .map(
                      (t) => DropdownMenuItem<String>(
                        value: t,
                        child: Text(
                          WalletType.label(t),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _type = v);
                },
              ),
              const SizedBox(height: 14),
              Text(
                'Kepemilikan / Sync',
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: VisibilityScope.shared,
                    icon: Icon(Icons.groups_rounded),
                    label: Text('Keluarga (Sync)'),
                  ),
                  ButtonSegment(
                    value: VisibilityScope.personal,
                    icon: Icon(Icons.lock_outline_rounded),
                    label: Text('Pribadi (Lokal)'),
                  ),
                ],
                selected: {_visibility},
                onSelectionChanged: (s) =>
                    setState(() => _visibility = s.first),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _initialBalanceCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: const [IdrInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Saldo Awal (Rp)',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
              ),
              if (_type != WalletType.cash) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _bankNameCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Bank / E-Wallet (opsional)',
                          hintText: 'BCA, Mandiri, OVO',
                          prefixIcon: Icon(Icons.account_balance_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _last4Ctrl,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: '4 Digit Akhir',
                          hintText: '7890',
                          counterText: '',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Opsional (terenkripsi lokal) agar Import Mutasi PDF otomatis mengenali dompet ini.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Text('Warna Dompet', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: AppIcons.walletColorPalette.map((c) {
                  final selected = c == _color;
                  return InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: selected
                            ? Border.all(
                                color: theme.colorScheme.onSurface,
                                width: 2.5,
                              )
                            : null,
                      ),
                      child: selected
                          ? const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 18,
                            )
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(
                  _saving
                      ? 'Menyimpan...'
                      : (_isEditing ? 'Simpan Perubahan' : 'Tambah Dompet'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
