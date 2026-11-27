import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:si_hemat/app/providers.dart';
import 'package:si_hemat/app/theme/app_theme.dart';
import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/utils/currency_formatter.dart';
import 'package:si_hemat/core/utils/date_formatter.dart';
import 'package:si_hemat/core/utils/idr_input_formatter.dart';
import 'package:si_hemat/features/ai_assistant/ai_models.dart';

class AiReceiptScanScreen extends ConsumerStatefulWidget {
  const AiReceiptScanScreen({super.key});

  @override
  ConsumerState<AiReceiptScanScreen> createState() =>
      _AiReceiptScanScreenState();
}

class _AiReceiptScanScreenState extends ConsumerState<AiReceiptScanScreen> {
  final _picker = ImagePicker();
  Uint8List? _compressedBytes;
  bool _scanning = false;
  bool _saving = false;
  String? _reply;
  String? _error;
  AiTransactionDraft? _draft;

  final _amountCtrl = TextEditingController();
  final _merchantCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _amountCtrl.dispose();
    _merchantCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndScan(ImageSource source) async {
    final family = ref.read(activeFamilyProvider).value;
    if (family == null) return;

    ref.read(suppressAutoLockProvider.notifier).setSuppressed(true);
    final XFile? picked;
    try {
      picked = await _picker.pickImage(source: source);
    } finally {
      ref.read(suppressAutoLockProvider.notifier).setSuppressed(false);
    }
    if (picked == null) return;

    setState(() {
      _scanning = true;
      _error = null;
      _reply = null;
      _draft = null;
    });

    try {
      final rawBytes = await picked.readAsBytes();
      final compressed = await FlutterImageCompress.compressWithList(
        rawBytes,
        minWidth: 1280,
        minHeight: 1280,
        quality: 80,
        format: CompressFormat.jpeg,
      );

      if (!mounted) return;
      setState(() => _compressedBytes = compressed);

      final result = await ref.read(aiFinanceServiceProvider).parseReceiptImage(
            familyId: family.id,
            imageBytes: compressed,
          );
      if (!mounted) return;
      setState(() {
        _reply = result.assistantMessage;
        if (result.drafts.isNotEmpty) {
          _draft = result.drafts.first;
          _amountCtrl.text = CurrencyFormatter.formatNumber(_draft!.amount);
          _merchantCtrl.text = _draft!.merchant ?? '';
          _noteCtrl.text = _draft!.note ?? '';
        } else {
          _error = 'Nominal transaksi tidak terbaca jelas pada gambar ini.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _saveDraft() async {
    final family = ref.read(activeFamilyProvider).value;
    final draft = _draft;
    if (family == null || draft == null) return;

    final amount = CurrencyFormatter.parseIdr(_amountCtrl.text) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nominal wajib lebih dari Rp 0.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(aiFinanceServiceProvider).commitDraft(
            familyId: family.id,
            draft: draft.copyWith(
              amount: amount,
              merchant: _merchantCtrl.text,
              note: _noteCtrl.text,
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transaksi dari struk berhasil disimpan!')),
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
    final wallets = (ref.watch(allWalletsWithBalanceProvider).value ?? const [])
        .map((w) => w.wallet)
        .toList();
    final categories = ref.watch(categoriesProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Struk / QRIS (AI)'),
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
                  'Pengaturan AI belum dikonfigurasi',
                  style: TextStyle(fontWeight: FontWeight.w700),
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
                    'Foto Struk Belanja atau Pilih Screenshot QRIS / M-Banking',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _scanning
                              ? null
                              : () => _pickAndScan(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('Kamera'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _scanning
                              ? null
                              : () => _pickAndScan(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Galeri'),
                        ),
                      ),
                    ],
                  ),
                  if (_compressedBytes != null) ...[
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.memory(
                        _compressedBytes!,
                        height: 200,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ],
                  if (_scanning) ...[
                    const SizedBox(height: 14),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 6),
                    Text(
                      'Gemini Vision sedang membaca struk...',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Card(
              color: AppTheme.expenseColor.withValues(alpha: 0.12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppTheme.expenseColor),
                ),
              ),
            ),
          ],
          if (_reply != null) ...[
            const SizedBox(height: 12),
            Card(
              color: colors.primaryContainer.withValues(alpha: 0.45),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(_reply!),
              ),
            ),
          ],
          if (_draft != null) ...[
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Konfirmasi Hasil Scan',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _amountCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: const [IdrInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Total Nominal (Rp)',
                        prefixText: 'Rp ',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _merchantCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Toko / Merchant',
                        prefixIcon: Icon(Icons.storefront_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (categories.isNotEmpty) ...[
                      Builder(
                        builder: (_) {
                          final filteredCats = categories
                              .where(
                                (c) => _draft!.type == TransactionType.income
                                    ? c.type == CategoryType.income
                                    : c.type == CategoryType.expense,
                              )
                              .toList();
                          return DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: filteredCats
                                    .any((c) => c.id == _draft!.categoryId)
                                ? _draft!.categoryId
                                : filteredCats.first.id,
                            decoration: const InputDecoration(
                              labelText: 'Kategori',
                            ),
                            items: filteredCats
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
                            onChanged: (v) {
                              if (v == null) return;
                              final cat =
                                  filteredCats.firstWhere((c) => c.id == v);
                              setState(
                                () => _draft = _draft!.copyWith(
                                  categoryId: cat.id,
                                  categoryName: cat.name,
                                ),
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (wallets.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: wallets.any((w) => w.id == _draft!.walletId)
                            ? _draft!.walletId
                            : wallets.first.id,
                        decoration: const InputDecoration(labelText: 'Dompet'),
                        items: wallets
                            .map(
                              (w) => DropdownMenuItem(
                                value: w.id,
                                child: Text(
                                  w.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          final w = wallets.firstWhere((x) => x.id == v);
                          setState(
                            () => _draft = _draft!.copyWith(
                              walletId: w.id,
                              walletName: w.name,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _noteCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Catatan / Rincian Item',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tanggal struk: ${DateFormatter.formatShortDate(_draft!.date)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _saving ? null : _saveDraft,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(
                        _saving ? 'Menyimpan...' : 'Simpan ke Buku Keuangan',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
