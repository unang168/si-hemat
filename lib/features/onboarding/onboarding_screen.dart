import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:si_hemat/app/providers.dart';
import 'package:si_hemat/core/utils/currency_formatter.dart';
import 'package:si_hemat/core/utils/date_formatter.dart';
import 'package:si_hemat/core/utils/idr_input_formatter.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  bool _isJoiningMode = false;
  bool _isSubmitting = false;

  // Create family controllers
  final _createFormKey = GlobalKey<FormState>();
  final _familyNameCtrl = TextEditingController(text: 'Keluarga Kami');
  final _adminNameCtrl = TextEditingController();
  final _initialCashCtrl = TextEditingController(text: '0');
  final _initialBankCtrl = TextEditingController(text: '0');
  int _paydayDay = 25;

  // Join family controllers
  final _joinFormKey = GlobalKey<FormState>();
  final _memberNameCtrl = TextEditingController();
  final _qrPayloadCtrl = TextEditingController();

  @override
  void dispose() {
    _familyNameCtrl.dispose();
    _adminNameCtrl.dispose();
    _initialCashCtrl.dispose();
    _initialBankCtrl.dispose();
    _memberNameCtrl.dispose();
    _qrPayloadCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitCreateFamily() async {
    if (!_createFormKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      await ref.read(onboardingServiceProvider).createNewFamily(
            familyName: _familyNameCtrl.text,
            adminName: _adminNameCtrl.text,
            paydayDay: _paydayDay,
            initialCashBalance:
                CurrencyFormatter.parseIdr(_initialCashCtrl.text) ?? 0,
            initialBankBalance:
                CurrencyFormatter.parseIdr(_initialBankCtrl.text) ?? 0,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuat buku keluarga: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _restoreFromBackupFile() async {
    final picked = await FilePicker.pickFile(type: FileType.any);
    if (picked == null || !mounted) return;
    final String rawContent;
    try {
      rawContent = utf8.decode(await picked.readAsBytes());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membaca file backup: $e')),
      );
      return;
    }

    if (!mounted) return;
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _OnboardingRestorePassDialog(),
    );
    if (password == null || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      final summary = await ref
          .read(backupServiceProvider)
          .restoreFromEncryptedBackupString(
            rawBackupContent: rawContent,
            password: password,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pulih "${summary.familyName}": ${summary.walletsCount} dompet & ${summary.transactionsCount} transaksi.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _submitJoinFamily() async {
    if (!_joinFormKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      await ref.read(onboardingServiceProvider).joinFamilyFromQr(
            qrPayloadRaw: _qrPayloadCtrl.text,
            memberName: _memberNameCtrl.text,
          );
      ref.invalidate(aiConfigProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('FormatException: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.savings_rounded,
                      size: 28,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Si-Hemat',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        Text(
                          'Asisten Keuangan Keluarga Offline & AI',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: false,
                    icon: Icon(Icons.home_rounded),
                    label: Text('Buat Keluarga'),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    icon: Icon(Icons.qr_code_2_rounded),
                    label: Text('Gabung Keluarga'),
                  ),
                ],
                selected: {_isJoiningMode},
                onSelectionChanged: _isSubmitting
                    ? null
                    : (selection) {
                        setState(() => _isJoiningMode = selection.first);
                      },
              ),
              const SizedBox(height: 20),
              if (!_isJoiningMode)
                _buildCreateCard(theme, colors)
              else
                _buildJoinCard(theme, colors),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _isSubmitting ? null : _restoreFromBackupFile,
                icon: const Icon(Icons.restore_rounded),
                label: const Text('Pulihkan dari File Backup (.sihemat)'),
              ),
              const SizedBox(height: 14),
              Card(
                color: colors.secondaryContainer.withValues(alpha: 0.45),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        color: colors.onSecondaryContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Data tersimpan 100% lokal di HP Anda. Sinkronisasi pasangan dilakukan terenkripsi lewat Wi-Fi rumah yang sama.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreateCard(ThemeData theme, ColorScheme colors) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _createFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Siapkan Buku Keluarga',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Dompet Kas Keluarga, Rekening Keluarga, Dompet Pribadi, dan 15 kategori harian akan langsung disiapkan otomatis.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _familyNameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nama Buku Keluarga',
                  hintText: 'Contoh: Keluarga Erwin',
                  prefixIcon: Icon(Icons.family_restroom_rounded),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Nama keluarga wajib diisi'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _adminNameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nama Panggilan Anda',
                  hintText: 'Contoh: Ayah / Erwin',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Nama panggilan wajib diisi'
                    : null,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: _paydayDay,
                decoration: const InputDecoration(
                  labelText: 'Tanggal Gajian (untuk hitung Safe-to-Spend)',
                  helperText:
                      'Jika jatuh di Sabtu/Minggu, otomatis maju ke hari Jumat.',
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
                  if (v != null) setState(() => _paydayDay = v);
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _initialCashCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: const [IdrInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Saldo Awal Kas Keluarga (Rp, opsional)',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _initialBankCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: const [IdrInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Saldo Awal Rekening Keluarga (Rp, opsional)',
                  prefixIcon: Icon(Icons.account_balance_outlined),
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _isSubmitting ? null : _submitCreateFamily,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_forward_rounded),
                label: Text(
                  _isSubmitting ? 'Menyiapkan...' : 'Mulai Gunakan Si-Hemat',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildJoinCard(ThemeData theme, ColorScheme colors) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _joinFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Gabung Buku Keluarga',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Scan QR Code dari HP Admin (menu Undang Keluarga) atau tempel kode undangan di bawah.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _isSubmitting
                    ? null
                    : () async {
                        final scanned = await context.push<String>('/qr-scanner');
                        if (scanned != null && scanned.isNotEmpty && mounted) {
                          setState(() => _qrPayloadCtrl.text = scanned);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'QR Undangan terbaca! Isi nama panggilan lalu klik Gabung Sekarang.',
                              ),
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Scan QR Code (Kamera)'),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _memberNameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nama Panggilan Anda',
                  hintText: 'Contoh: Ibu / Pasangan',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Nama panggilan wajib diisi'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _qrPayloadCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Tempel Kode Undangan Keluarga',
                  hintText: '{"v":1,"app":"si_hemat",...}',
                  alignLabelWithHint: true,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Kode undangan wajib diisi'
                    : null,
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _isSubmitting ? null : _submitJoinFamily,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.group_add_rounded),
                label: Text(
                  _isSubmitting ? 'Menghubungkan...' : 'Gabung Sekarang',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingRestorePassDialog extends StatefulWidget {
  const _OnboardingRestorePassDialog();

  @override
  State<_OnboardingRestorePassDialog> createState() =>
      _OnboardingRestorePassDialogState();
}

class _OnboardingRestorePassDialogState
    extends State<_OnboardingRestorePassDialog> {
  final _passCtrl = TextEditingController();

  @override
  void dispose() {
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Kata Sandi Backup'),
      content: TextField(
        controller: _passCtrl,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: 'Masukkan kata sandi file .sihemat',
        ),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _passCtrl.text.trim()),
          child: const Text('Pulihkan'),
        ),
      ],
    );
  }
}
