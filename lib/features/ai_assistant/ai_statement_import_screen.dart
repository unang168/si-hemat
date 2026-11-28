import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:si_hemat/app/providers.dart';
import 'package:si_hemat/app/theme/app_theme.dart';
import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/core/utils/currency_formatter.dart';
import 'package:si_hemat/core/utils/date_formatter.dart';
import 'package:si_hemat/core/utils/idr_input_formatter.dart';
import 'package:si_hemat/features/ai_assistant/ai_models.dart';
import 'package:si_hemat/features/ai_assistant/pdf_statement_renderer.dart';
import 'package:si_hemat/features/ai_assistant/statement_import_service.dart';

class AiStatementImportScreen extends ConsumerStatefulWidget {
  const AiStatementImportScreen({
    super.key,
    this.initialDrafts,
  });

  /// Optional pre-parsed drafts handed off from single-receipt scan when >1 row is detected.
  final List<AiTransactionDraft>? initialDrafts;

  @override
  ConsumerState<AiStatementImportScreen> createState() =>
      _AiStatementImportScreenState();
}

class _AiStatementImportScreenState
    extends ConsumerState<AiStatementImportScreen> {
  final _imagePicker = ImagePicker();

  String? _selectedWalletId;
  bool _processing = false;
  bool _cancelled = false;
  bool _saving = false;
  StatementImportProgress? _progress;
  String? _error;
  String? _sourceLabel;

  StatementImportResult? _result;
  List<StatementDraftItem> _items = const [];
  bool _rememberAccountHint = true;
  bool _dismissedMismatchBanner = false;
  bool _hydratedInitialDrafts = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureDefaultWalletAndHydrate();
  }

  void _ensureDefaultWalletAndHydrate() {
    final wallets = (ref.read(allWalletsWithBalanceProvider).value ?? const [])
        .map((w) => w.wallet)
        .toList();
    if (wallets.isEmpty) return;

    if (_selectedWalletId == null ||
        !wallets.any((w) => w.id == _selectedWalletId)) {
      final preferred = wallets
              .where(
                (w) =>
                    w.type == WalletType.bank || w.type == WalletType.ewallet,
              )
              .firstOrNull ??
          wallets.first;
      _selectedWalletId = preferred.id;
    }

    if (!_hydratedInitialDrafts &&
        widget.initialDrafts != null &&
        widget.initialDrafts!.isNotEmpty) {
      _hydratedInitialDrafts = true;
      final family = ref.read(activeFamilyProvider).value;
      if (family != null && _selectedWalletId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final res = await ref
              .read(statementImportServiceProvider)
              .fromAiDrafts(
                familyId: family.id,
                walletId: _selectedWalletId!,
                drafts: widget.initialDrafts!,
              );
          if (!mounted) return;
          setState(() {
            _result = res;
            _items = res.items;
            _sourceLabel = 'Dari Scan Struk / Screenshot';
          });
        });
      }
    }
  }

  Future<void> _pickPdfAndImport() async {
    final family = ref.read(activeFamilyProvider).value;
    final walletId = _selectedWalletId;
    if (family == null || walletId == null) return;

    ref.read(suppressAutoLockProvider.notifier).setSuppressed(true);
    PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
    } finally {
      ref.read(suppressAutoLockProvider.notifier).setSuppressed(false);
    }
    if (picked == null || !mounted) return;

    setState(() {
      _processing = true;
      _cancelled = false;
      _error = null;
      _result = null;
      _items = const [];
      _dismissedMismatchBanner = false;
      _sourceLabel = 'PDF: ${picked!.name}';
      _progress = const StatementImportProgress(
        currentPage: 0,
        totalPages: 1,
        foundCount: 0,
        statusText: 'Membuka file PDF secara lokal di HP...',
      );
    });

    try {
      final pdfBytes = await picked.readAsBytes();
      var passwordAttempt = 0;

      final pageJpegs = await PdfStatementRenderer.renderPdfToJpegs(
        pdfBytes: pdfBytes,
        fileName: picked.name,
        passwordProvider: () async {
          if (!mounted) return null;
          passwordAttempt++;
          return showDialog<String>(
            context: context,
            barrierDismissible: false,
            builder: (_) => _PdfPasswordDialog(
              fileName: picked!.name,
              isRetry: passwordAttempt > 1,
            ),
          );
        },
        onProgress: (rendered, total) {
          if (!mounted) return;
          setState(() {
            _progress = StatementImportProgress(
              currentPage: rendered,
              totalPages: total,
              foundCount: 0,
              statusText: 'Menyiapkan halaman PDF $rendered dari $total...',
            );
          });
        },
      );

      if (!mounted) return;
      await _processPageImages(
        familyId: family.id,
        walletId: walletId,
        pageImages: pageJpegs,
      );
    } on PdfStatementException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.isCancelled ? null : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _processing = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _pickScreenshotsAndImport({bool fromCamera = false}) async {
    final family = ref.read(activeFamilyProvider).value;
    final walletId = _selectedWalletId;
    if (family == null || walletId == null) return;

    ref.read(suppressAutoLockProvider.notifier).setSuppressed(true);
    final List<XFile> pickedFiles;
    try {
      if (fromCamera) {
        final single = await _imagePicker.pickImage(source: ImageSource.camera);
        pickedFiles = single != null ? [single] : const [];
      } else {
        pickedFiles = await _imagePicker.pickMultiImage(limit: 10);
      }
    } finally {
      ref.read(suppressAutoLockProvider.notifier).setSuppressed(false);
    }
    if (pickedFiles.isEmpty || !mounted) return;

    setState(() {
      _processing = true;
      _cancelled = false;
      _error = null;
      _result = null;
      _items = const [];
      _dismissedMismatchBanner = false;
      _sourceLabel = fromCamera
          ? 'Foto Kamera (1 gambar)'
          : 'Screenshot Mutasi (${pickedFiles.length} gambar)';
      _progress = StatementImportProgress(
        currentPage: 0,
        totalPages: pickedFiles.length,
        foundCount: 0,
        statusText: 'Mengompresi ${pickedFiles.length} gambar mutasi...',
      );
    });

    try {
      final compressedPages = <Uint8List>[];
      for (var i = 0; i < pickedFiles.length; i++) {
        if (_cancelled) break;
        final raw = await pickedFiles[i].readAsBytes();
        final jpeg = await PdfStatementRenderer.compressStatementImage(raw);
        compressedPages.add(jpeg);
      }
      if (!mounted || _cancelled) return;
      await _processPageImages(
        familyId: family.id,
        walletId: walletId,
        pageImages: compressedPages,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _processing = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _processPageImages({
    required String familyId,
    required String walletId,
    required List<Uint8List> pageImages,
  }) async {
    final res = await ref.read(statementImportServiceProvider).parseStatementPages(
          familyId: familyId,
          selectedWalletId: walletId,
          pageImages: pageImages,
          isCancelled: () => _cancelled,
          onProgress: (p) {
            if (!mounted) return;
            setState(() => _progress = p);
          },
        );
    if (!mounted) return;
    setState(() {
      _result = res;
      _items = res.items;
      _rememberAccountHint =
          res.hasDetectedAccount && res.suggestedWalletId == null;
    });
  }

  Future<void> _changeTargetWallet(String newWalletId) async {
    final family = ref.read(activeFamilyProvider).value;
    setState(() {
      _selectedWalletId = newWalletId;
      _dismissedMismatchBanner = false;
    });
    if (family != null && _items.isNotEmpty) {
      final rechecked =
          await ref.read(statementImportServiceProvider).applyDeduplication(
                familyId: family.id,
                walletId: newWalletId,
                items: _items,
              );
      if (!mounted) return;
      setState(() => _items = rechecked);
    }
  }

  Future<void> _saveSelected() async {
    final family = ref.read(activeFamilyProvider).value;
    final wallets = (ref.read(allWalletsWithBalanceProvider).value ?? const [])
        .map((w) => w.wallet)
        .toList();
    final categories = ref.read(categoriesProvider).value ?? const [];
    final targetWallet =
        wallets.where((w) => w.id == _selectedWalletId).firstOrNull;
    if (family == null || targetWallet == null) return;

    final selectedCount = _items.where((e) => e.selected).length;
    if (selectedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Centang minimal 1 transaksi sebelum menyimpan.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final saved =
          await ref.read(statementImportServiceProvider).commitSelectedItems(
                familyId: family.id,
                targetWallet: targetWallet,
                allWallets: wallets,
                allCategories: categories,
                items: _items,
                rememberAccountHint:
                    _rememberAccountHint && (_result?.hasDetectedAccount ?? false),
                detectedBank: _result?.detectedBank,
                detectedAccountLast4: _result?.detectedAccountLast4,
              );
      ref.invalidate(walletBankHintsProvider);
      if (!mounted) return;
      final scopeLabel = targetWallet.visibility == VisibilityScope.shared
          ? 'Keluarga'
          : 'Pribadi';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$saved transaksi berhasil disimpan ke ${targetWallet.name} ($scopeLabel)!',
          ),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan mutasi: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editItem(
    int index,
    List<Wallet> wallets,
    List<Category> categories,
  ) async {
    final updated = await showModalBottomSheet<StatementDraftItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditStatementItemSheet(
        item: _items[index],
        sourceWalletId: _selectedWalletId ?? '',
        wallets: wallets,
        categories: categories,
      ),
    );
    if (updated == null || !mounted) return;
    setState(() {
      final next = List<StatementDraftItem>.from(_items);
      next[index] = updated;
      _items = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final incomeColor = AppTheme.incomeOf(context);
    final expenseColor = AppTheme.expenseOf(context);
    final warningColor = AppTheme.warningOf(context);
    final transferColor = AppTheme.transferOf(context);

    final config = ref.watch(aiConfigProvider).value;
    final wallets = (ref.watch(allWalletsWithBalanceProvider).value ?? const [])
        .map((w) => w.wallet)
        .toList();
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final hints = ref.watch(walletBankHintsProvider).value ?? const {};

    if (_selectedWalletId == null && wallets.isNotEmpty) {
      _ensureDefaultWalletAndHydrate();
    }

    final selectedWallet =
        wallets.where((w) => w.id == _selectedWalletId).firstOrNull;
    final suggestedWallet = _result?.suggestedWalletId != null
        ? wallets.where((w) => w.id == _result!.suggestedWalletId).firstOrNull
        : null;
    final showMismatchBanner = !_dismissedMismatchBanner &&
        suggestedWallet != null &&
        suggestedWallet.id != _selectedWalletId;
    final showRememberCheckbox = (_result?.hasDetectedAccount ?? false) &&
        suggestedWallet == null &&
        selectedWallet != null;

    final selectedItems = _items.where((e) => e.selected).toList();
    final duplicateCount = _items.where((e) => e.isDuplicate).length;
    final totalIn = selectedItems
        .where((e) => e.type == TransactionType.income)
        .fold<int>(0, (s, e) => s + e.amount);
    final totalOut = selectedItems
        .where((e) => e.type == TransactionType.expense)
        .fold<int>(0, (s, e) => s + e.amount);
    final totalTransfer = selectedItems
        .where((e) => e.type == TransactionType.transfer)
        .fold<int>(0, (s, e) => s + e.amount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Mutasi (PDF / Gambar)'),
        actions: [
          IconButton(
            tooltip: 'Pengaturan AI',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/ai-settings'),
          ),
        ],
      ),
      bottomNavigationBar: _items.isEmpty
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  border: Border(
                    top: BorderSide(color: colors.outlineVariant),
                  ),
                ),
                child: FilledButton.icon(
                  onPressed:
                      (_saving || selectedItems.isEmpty) ? null : _saveSelected,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline_rounded),
                  label: Text(
                    _saving
                        ? 'Menyimpan...'
                        : 'Simpan ${selectedItems.length} Transaksi ke ${selectedWallet?.name ?? 'Dompet'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (config != null && !config.isConfigured) ...[
            Card(
              color: warningColor.withValues(alpha: 0.14),
              child: ListTile(
                leading: Icon(Icons.key_off_rounded, color: warningColor),
                title: const Text(
                  'Pengaturan AI belum dikonfigurasi',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'Atur Gemini Free Tier atau 9Router untuk membaca mutasi PDF/gambar.',
                ),
                trailing: TextButton(
                  onPressed: () => context.push('/ai-settings'),
                  child: const Text('Atur'),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Step 1: Target Wallet Selector (Shared vs Personal badge clearly visible)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 13,
                        backgroundColor: colors.primaryContainer,
                        foregroundColor: colors.onPrimaryContainer,
                        child: const Text(
                          '1',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Pilih Dompet / Rekening Tujuan',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (wallets.isEmpty)
                    const Text('Belum ada dompet. Buat dompet terlebih dahulu.')
                  else
                    DropdownButtonFormField<String>(
                      key: ValueKey(_selectedWalletId),
                      isExpanded: true,
                      initialValue: selectedWallet?.id,
                      decoration: const InputDecoration(
                        labelText: 'Dompet Tujuan Mutasi',
                        prefixIcon:
                            Icon(Icons.account_balance_wallet_outlined),
                      ),
                      items: wallets.map((w) {
                        final scope = w.visibility == VisibilityScope.shared
                            ? 'Keluarga'
                            : 'Pribadi';
                        final hint = hints[w.id];
                        final suffix = hint != null && !hint.isEmpty
                            ? ' • ${hint.displayLabel}'
                            : '';
                        return DropdownMenuItem<String>(
                          value: w.id,
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: Color(w.color),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${w.name} [$scope]$suffix',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: _processing
                          ? null
                          : (v) {
                              if (v != null) _changeTargetWallet(v);
                            },
                    ),
                  if (selectedWallet != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          selectedWallet.visibility == VisibilityScope.shared
                              ? Icons.groups_rounded
                              : Icons.lock_outline_rounded,
                          size: 16,
                          color: selectedWallet.visibility ==
                                  VisibilityScope.shared
                              ? colors.primary
                              : const Color(0xFF7B1FA2),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            selectedWallet.visibility == VisibilityScope.shared
                                ? 'Dompet Keluarga • Transaksi yang disimpan akan ikut tersinkronisasi saat Wi-Fi Sync.'
                                : 'Dompet Pribadi • Transaksi hanya tersimpan lokal di HP ini (tidak di-sync ke pasangan).',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Step 2: Upload PDF (1 month, password/non-password) OR Multi-Screenshot (weekly/daily)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 13,
                        backgroundColor: colors.primaryContainer,
                        foregroundColor: colors.onPrimaryContainer,
                        child: const Text(
                          '2',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Unggah Mutasi PDF atau Screenshot',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Mendukung e-Statement PDF 1 bulan (terkunci password maupun tidak) dan 1–10 screenshot m-banking mingguan/harian.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed:
                        (_processing || wallets.isEmpty) ? null : _pickPdfAndImport,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Upload PDF Mutasi (1 Bulan)'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: (_processing || wallets.isEmpty)
                              ? null
                              : () => _pickScreenshotsAndImport(),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Screenshot (1–10)'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: (_processing || wallets.isEmpty)
                            ? null
                            : () => _pickScreenshotsAndImport(fromCamera: true),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Foto'),
                      ),
                    ],
                  ),
                  if (_processing && _progress != null) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: _progress!.currentPage > 0
                          ? _progress!.fraction.clamp(0.05, 1.0)
                          : null,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_progress!.statusText}${_progress!.foundCount > 0 ? ' (${_progress!.foundCount} transaksi)' : ''}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _cancelled = true),
                          child: const Text('Hentikan'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    'Privasi: Password PDF dibuka 100% lokal di HP. Halaman mutasi hanya dikirim ke provider AI pilihan Anda (${config?.activeProviderLabel ?? 'Gemini / 9Router'}).',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Card(
              color: expenseColor.withValues(alpha: 0.12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _error!,
                  style: TextStyle(color: expenseColor),
                ),
              ),
            ),
          ],

          // Smart Auto-Detect Banner (Mismatch protection)
          if (showMismatchBanner) ...[
            const SizedBox(height: 12),
            Card(
              color: warningColor.withValues(alpha: 0.14),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.swap_horiz_rounded,
                          color: warningColor,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Mutasi ini terdeteksi berasal dari ${_result!.detectedAccountLabel}, cocok dengan dompet "${suggestedWallet.name}" [${suggestedWallet.visibility == VisibilityScope.shared ? 'Keluarga' : 'Pribadi'}].',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () =>
                              setState(() => _dismissedMismatchBanner = true),
                          child: const Text('Tetap di Dompet Ini'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () =>
                              _changeTargetWallet(suggestedWallet.id),
                          child: Text('Pindahkan ke ${suggestedWallet.name}'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Remember newly detected account hint on this wallet
          if (showRememberCheckbox) ...[
            const SizedBox(height: 10),
            Card(
              color: colors.primaryContainer.withValues(alpha: 0.35),
              child: CheckboxListTile(
                value: _rememberAccountHint,
                onChanged: (v) =>
                    setState(() => _rememberAccountHint = v ?? false),
                title: Text(
                  'Ingat ${_result!.detectedAccountLabel} untuk "${selectedWallet.name}"',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: const Text(
                  'Agar upload bulan berikutnya langsung terdeteksi otomatis ke dompet ini.',
                ),
              ),
            ),
          ],

          // Result Summary & Batch Review Checklist
          if (_result != null) ...[
            const SizedBox(height: 14),
            Card(
              color: colors.secondaryContainer.withValues(alpha: 0.4),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_sourceLabel != null)
                      Text(
                        _sourceLabel!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      _result!.summaryReply,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_result!.detectedPeriod != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Periode terbaca: ${_result!.detectedPeriod}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],

          if (_items.isNotEmpty) ...[
            const SizedBox(height: 12),
            // Sanity Check Totals Strip + Bulk Selection Chips
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Review Transaksi (${selectedItems.length}/${_items.length} dipilih)',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            final allSelected =
                                selectedItems.length == _items.length;
                            setState(() {
                              _items = _items
                                  .map(
                                    (e) => e.copyWith(selected: !allSelected),
                                  )
                                  .toList();
                            });
                          },
                          child: Text(
                            selectedItems.length == _items.length
                                ? 'Batal Semua'
                                : 'Pilih Semua',
                          ),
                        ),
                        if (duplicateCount > 0)
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _items = _items
                                    .map(
                                      (e) => e.copyWith(
                                        selected: !e.isDuplicate,
                                      ),
                                    )
                                    .toList();
                              });
                            },
                            child: const Text('Hanya Baru'),
                          ),
                      ],
                    ),
                    const Divider(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _TotalPill(
                            label: 'Total Masuk',
                            value: CurrencyFormatter.formatIdr(totalIn),
                            color: incomeColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _TotalPill(
                            label: 'Total Keluar',
                            value: CurrencyFormatter.formatIdr(totalOut),
                            color: expenseColor,
                          ),
                        ),
                        if (totalTransfer > 0) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: _TotalPill(
                              label: 'Transfer',
                              value: CurrencyFormatter.formatIdr(totalTransfer),
                              color: transferColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Ketuk baris transaksi untuk mengubah kategori, nominal, tanggal, atau tipe Transfer.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Draft Rows
            for (var i = 0; i < _items.length; i++) ...[
              _StatementDraftCard(
                item: _items[i],
                incomeColor: incomeColor,
                expenseColor: expenseColor,
                transferColor: transferColor,
                warningColor: warningColor,
                onToggleSelected: (checked) {
                  setState(() {
                    final next = List<StatementDraftItem>.from(_items);
                    next[i] = next[i].copyWith(selected: checked);
                    _items = next;
                  });
                },
                onTapEdit: () => _editItem(i, wallets, categories),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

class _TotalPill extends StatelessWidget {
  const _TotalPill({
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
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
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatementDraftCard extends StatelessWidget {
  const _StatementDraftCard({
    required this.item,
    required this.incomeColor,
    required this.expenseColor,
    required this.transferColor,
    required this.warningColor,
    required this.onToggleSelected,
    required this.onTapEdit,
  });

  final StatementDraftItem item;
  final Color incomeColor;
  final Color expenseColor;
  final Color transferColor;
  final Color warningColor;
  final ValueChanged<bool> onToggleSelected;
  final VoidCallback onTapEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final amountColor = item.type == TransactionType.income
        ? incomeColor
        : (item.type == TransactionType.transfer
            ? transferColor
            : expenseColor);
    final prefix = item.type == TransactionType.income
        ? '+'
        : (item.type == TransactionType.expense ? '-' : '');
    final subtitleText = item.type == TransactionType.transfer
        ? 'Transfer → ${item.toWalletName ?? 'Dompet Lain'}'
        : (item.categoryName ?? 'Tanpa Kategori');

    return Card(
      color: item.isDuplicate && !item.selected
          ? colors.surfaceContainerLow
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTapEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 14, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: item.selected,
                onChanged: (v) => onToggleSelected(v ?? false),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.merchant,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              decoration: !item.selected
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: !item.selected
                                  ? colors.onSurfaceVariant
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$prefix${CurrencyFormatter.formatIdr(item.amount)}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: item.selected
                                ? amountColor
                                : colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          DateFormatter.formatShortDate(item.date),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '• $subtitleText',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '• Hal ${item.pageNumber}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    if (item.isDuplicate && item.duplicateReason != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: warningColor.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '⚠ ${item.duplicateReason}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: warningColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PdfPasswordDialog extends StatefulWidget {
  const _PdfPasswordDialog({
    required this.fileName,
    required this.isRetry,
  });

  final String fileName;
  final bool isRetry;

  @override
  State<_PdfPasswordDialog> createState() => _PdfPasswordDialogState();
}

class _PdfPasswordDialogState extends State<_PdfPasswordDialog> {
  final _ctrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('PDF Terkunci Password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.isRetry
                ? 'Password salah untuk "${widget.fileName}". Silakan coba lagi.'
                : 'File "${widget.fileName}" dilindungi password (umumnya tanggal lahir DDMMYYYY). Password hanya dipakai lokal di HP.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            obscureText: _obscure,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Password PDF',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: const Text('Buka PDF'),
        ),
      ],
    );
  }
}

class _EditStatementItemSheet extends StatefulWidget {
  const _EditStatementItemSheet({
    required this.item,
    required this.sourceWalletId,
    required this.wallets,
    required this.categories,
  });

  final StatementDraftItem item;
  final String sourceWalletId;
  final List<Wallet> wallets;
  final List<Category> categories;

  @override
  State<_EditStatementItemSheet> createState() =>
      _EditStatementItemSheetState();
}

class _EditStatementItemSheetState extends State<_EditStatementItemSheet> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _merchantCtrl;
  late final TextEditingController _noteCtrl;
  late String _type;
  late DateTime _date;
  String? _categoryId;
  String? _toWalletId;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(
      text: CurrencyFormatter.formatNumber(widget.item.amount),
    );
    _merchantCtrl = TextEditingController(text: widget.item.merchant);
    _noteCtrl = TextEditingController(text: widget.item.note ?? '');
    _type = widget.item.type;
    _date = widget.item.date;
    _categoryId = widget.item.categoryId;
    _toWalletId = widget.item.toWalletId;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _merchantCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _apply() {
    final amount = CurrencyFormatter.parseIdr(_amountCtrl.text) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nominal harus lebih dari Rp 0.')),
      );
      return;
    }

    final targetWallets =
        widget.wallets.where((w) => w.id != widget.sourceWalletId).toList();
    String? resolvedToWalletId;
    String? resolvedToWalletName;
    String? resolvedCategoryId;
    String? resolvedCategoryName;

    if (_type == TransactionType.transfer) {
      final tw = targetWallets.where((w) => w.id == _toWalletId).firstOrNull ??
          targetWallets.firstOrNull;
      if (tw == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Butuh minimal 2 dompet untuk mencatat Transfer.'),
          ),
        );
        return;
      }
      resolvedToWalletId = tw.id;
      resolvedToWalletName = tw.name;
    } else {
      final cats = widget.categories
          .where(
            (c) => _type == TransactionType.income
                ? c.type == CategoryType.income
                : c.type == CategoryType.expense,
          )
          .toList();
      final cat =
          cats.where((c) => c.id == _categoryId).firstOrNull ?? cats.firstOrNull;
      resolvedCategoryId = cat?.id;
      resolvedCategoryName = cat?.name;
    }

    Navigator.pop(
      context,
      widget.item.copyWith(
        type: _type,
        amount: amount,
        date: _date,
        merchant: _merchantCtrl.text.trim().isNotEmpty
            ? _merchantCtrl.text.trim()
            : widget.item.merchant,
        note: _noteCtrl.text.trim(),
        categoryId: resolvedCategoryId,
        categoryName: resolvedCategoryName,
        toWalletId: resolvedToWalletId,
        toWalletName: resolvedToWalletName,
        clearToWallet: _type != TransactionType.transfer,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final targetWallets =
        widget.wallets.where((w) => w.id != widget.sourceWalletId).toList();
    final filteredCats = widget.categories
        .where(
          (c) => _type == TransactionType.income
              ? c.type == CategoryType.income
              : c.type == CategoryType.expense,
        )
        .toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, bottomInset + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ubah Detail Draft Transaksi',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 14),
            SegmentedButton<String>(
              segments: [
                const ButtonSegment(
                  value: TransactionType.expense,
                  label: Text('Keluar'),
                ),
                const ButtonSegment(
                  value: TransactionType.income,
                  label: Text('Masuk'),
                ),
                if (targetWallets.isNotEmpty)
                  const ButtonSegment(
                    value: TransactionType.transfer,
                    label: Text('Transfer'),
                  ),
              ],
              selected: {_type},
              onSelectionChanged: (s) {
                setState(() {
                  _type = s.first;
                  if (_type == TransactionType.transfer &&
                      _toWalletId == null &&
                      targetWallets.isNotEmpty) {
                    _toWalletId = targetWallets.first.id;
                  }
                });
              },
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: const [IdrInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Nominal (Rp)',
                prefixText: 'Rp ',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _merchantCtrl,
              decoration: const InputDecoration(
                labelText: 'Merchant / Keterangan',
                prefixIcon: Icon(Icons.storefront_outlined),
              ),
            ),
            const SizedBox(height: 12),
            if (_type == TransactionType.transfer && targetWallets.isNotEmpty)
              DropdownButtonFormField<String>(
                key: ValueKey('tw_${_toWalletId ?? targetWallets.first.id}'),
                isExpanded: true,
                initialValue: targetWallets.any((w) => w.id == _toWalletId)
                    ? _toWalletId
                    : targetWallets.first.id,
                decoration: const InputDecoration(
                  labelText: 'Dompet Tujuan Transfer',
                ),
                items: targetWallets
                    .map(
                      (w) => DropdownMenuItem(
                        value: w.id,
                        child: Text(
                          '${w.name} [${w.visibility == VisibilityScope.shared ? 'Keluarga' : 'Pribadi'}]',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _toWalletId = v),
              )
            else if (filteredCats.isNotEmpty)
              DropdownButtonFormField<String>(
                key: ValueKey('cat_${_type}_${_categoryId ?? ''}'),
                isExpanded: true,
                initialValue: filteredCats.any((c) => c.id == _categoryId)
                    ? _categoryId
                    : filteredCats.first.id,
                decoration: const InputDecoration(labelText: 'Kategori'),
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
                onChanged: (v) => setState(() => _categoryId = v),
              ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(
                'Tanggal: ${DateFormatter.formatShortDate(_date)}',
              ),
              trailing: const Text('Ubah'),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null && mounted) {
                  setState(() => _date = picked);
                }
              },
            ),
            TextField(
              controller: _noteCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _apply,
              child: const Text('Terapkan Perubahan'),
            ),
          ],
        ),
      ),
    );
  }
}
