import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:si_hemat/app/providers.dart';
import 'package:si_hemat/app/theme/app_theme.dart';
import 'package:si_hemat/core/database/app_database.dart';

class SecurityBackupScreen extends ConsumerStatefulWidget {
  const SecurityBackupScreen({super.key});

  @override
  ConsumerState<SecurityBackupScreen> createState() =>
      _SecurityBackupScreenState();
}

class _SecurityBackupScreenState extends ConsumerState<SecurityBackupScreen> {
  bool _busy = false;

  Future<void> _togglePinLock(bool enable) async {
    final lockService = ref.read(appLockServiceProvider);
    if (enable) {
      final pin = await showDialog<String>(
        context: context,
        builder: (_) => const _SetPinDialog(),
      );
      if (pin == null || !mounted) return;
      await lockService.setPin(pin);
      ref.read(isAppUnlockedProvider.notifier).unlock();
      ref.invalidate(appLockStatusProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kunci PIN 6 digit berhasil diaktifkan.')),
      );
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Matikan Kunci Aplikasi?'),
          content: const Text(
            'PIN dan kunci biometrik akan dinonaktifkan pada perangkat ini.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.expenseColor,
                minimumSize: const Size(110, 44),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Nonaktifkan'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await lockService.disableLock();
      ref.invalidate(appLockStatusProvider);
    }
  }

  Future<void> _editFamilyName(Family family) async {
    final updated = await showDialog<String>(
      context: context,
      builder: (_) => _SingleNameEditDialog(
        title: 'Ubah Nama Buku Keluarga',
        label: 'Nama Buku Keluarga',
        initialValue: family.name,
      ),
    );
    if (updated == null || updated == family.name || !mounted) return;
    final deviceId =
        await ref.read(onboardingServiceProvider).getOrCreateDeviceId();
    await ref.read(databaseProvider).updateFamilyName(
          familyId: family.id,
          name: updated,
          deviceId: deviceId,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Nama buku keluarga diubah ke "$updated".')),
    );
  }

  Future<void> _editMemberName(Member member) async {
    final updated = await showDialog<String>(
      context: context,
      builder: (_) => _SingleNameEditDialog(
        title: 'Ubah Nama Anggota',
        label: 'Nama Panggilan',
        initialValue: member.name,
      ),
    );
    if (updated == null || updated == member.name || !mounted) return;
    final deviceId =
        await ref.read(onboardingServiceProvider).getOrCreateDeviceId();
    await ref.read(databaseProvider).updateMemberName(
          memberId: member.id,
          name: updated,
          deviceId: deviceId,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Nama anggota diubah ke "$updated".')),
    );
  }

  Future<void> _exportBackup() async {
    final family = ref.read(activeFamilyProvider).value;
    if (family == null) return;
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _BackupPasswordDialog(
        title: 'Buat Kata Sandi Backup',
        subtitle:
            'File backup (.sihemat) dienkripsi AES-256. Simpan kata sandi ini karena wajib dimasukkan saat pemulihan.',
        confirmPassword: true,
        actionLabel: 'Enkripsi & Bagikan',
      ),
    );
    if (password == null || !mounted) return;

    setState(() => _busy = true);
    ref.read(suppressAutoLockProvider.notifier).setSuppressed(true);
    try {
      await ref.read(backupServiceProvider).exportBackupAndShare(
            familyId: family.id,
            password: password,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'File backup terenkripsi .sihemat siap disimpan ke Drive / penyimpanan Anda.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuat backup: $e')),
      );
    } finally {
      ref.read(suppressAutoLockProvider.notifier).setSuppressed(false);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importBackup() async {
    ref.read(suppressAutoLockProvider.notifier).setSuppressed(true);
    PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(type: FileType.any);
    } finally {
      ref.read(suppressAutoLockProvider.notifier).setSuppressed(false);
    }
    if (picked == null || !mounted) return;

    final String rawContent;
    try {
      rawContent = utf8.decode(await picked.readAsBytes());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membaca file: $e')),
      );
      return;
    }

    if (!mounted) return;
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _BackupPasswordDialog(
        title: 'Masukkan Kata Sandi Backup',
        subtitle:
            'Masukkan kata sandi yang digunakan saat membuat file backup .sihemat ini.',
        confirmPassword: false,
        actionLabel: 'Pulihkan Data',
      ),
    );
    if (password == null || !mounted) return;

    setState(() => _busy = true);
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
            'Berhasil memulihkan "${summary.familyName}": ${summary.walletsCount} dompet, ${summary.transactionsCount} transaksi, ${summary.budgetsCount} anggaran, ${summary.billsCount} tagihan.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _autoLockLabel(int seconds) {
    switch (seconds) {
      case 0:
        return 'Segera saat keluar aplikasi';
      case 30:
        return 'Setelah 30 detik di background';
      case 60:
        return 'Setelah 1 menit di background';
      default:
        return 'Hanya saat aplikasi baru dibuka';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final lockAsync = ref.watch(appLockStatusProvider);
    final themeMode = ref.watch(themeModeProvider);
    final autoLockSec = ref.watch(autoLockSecondsProvider);
    final family = ref.watch(activeFamilyProvider).value;
    final members = ref.watch(familyMembersProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan & Keamanan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
          ],

          // Theme Mode Selector
          Text(
            'Tampilan & Tema',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Mode Tampilan Aplikasi',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto_outlined, size: 18),
                        label: Text('Sistem'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_outlined, size: 18),
                        label: Text('Terang'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_outlined, size: 18),
                        label: Text('Gelap'),
                      ),
                    ],
                    selected: {themeMode},
                    onSelectionChanged: (s) => ref
                        .read(themeModeProvider.notifier)
                        .setThemeMode(s.first),
                  ),
                ],
              ),
            ),
          ),

          // Family & Member Profile section
          if (family != null) ...[
            const SizedBox(height: 20),
            Text(
              'Profil Keluarga & Anggota',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.family_restroom_rounded),
                    title: const Text('Nama Buku Keluarga'),
                    subtitle: Text(family.name),
                    trailing: const Icon(Icons.edit_outlined, size: 20),
                    onTap: () => _editFamilyName(family),
                  ),
                  for (final m in members) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: Color(m.avatarColor),
                        foregroundColor: Colors.white,
                        child: Text(
                          m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      title: Text(m.name),
                      subtitle: Text(
                        m.role == 'admin' ? 'Admin Keluarga' : 'Anggota Keluarga',
                      ),
                      trailing: const Icon(Icons.edit_outlined, size: 20),
                      onTap: () => _editMemberName(m),
                    ),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),
          Text(
            'Keamanan Aplikasi',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          lockAsync.when(
            loading: () => const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (e, _) => Text('Error: $e'),
            data: (status) => Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.pin_outlined),
                    title: const Text('Kunci Aplikasi (PIN 6 Digit)'),
                    subtitle: const Text(
                      'Minta PIN setiap kali Si-Hemat dibuka',
                    ),
                    value: status.lockEnabled,
                    onChanged: _busy ? null : _togglePinLock,
                  ),
                  if (status.lockEnabled) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.password_rounded),
                      title: const Text('Ubah PIN'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _busy ? null : () => _togglePinLock(true),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.timer_outlined),
                      title: const Text('Kunci Otomatis (Background)'),
                      subtitle: Text(_autoLockLabel(autoLockSec)),
                      trailing: DropdownButton<int>(
                        value: [0, 30, 60, -1].contains(autoLockSec)
                            ? autoLockSec
                            : 30,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Langsung')),
                          DropdownMenuItem(value: 30, child: Text('30 dtk')),
                          DropdownMenuItem(value: 60, child: Text('1 mnt')),
                          DropdownMenuItem(value: -1, child: Text('Nonaktif')),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            ref
                                .read(autoLockSecondsProvider.notifier)
                                .setSeconds(v);
                          }
                        },
                      ),
                    ),
                    if (status.biometricAvailable) ...[
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.fingerprint_rounded),
                        title: const Text('Buka dengan Sidik Jari / Biometrik'),
                        value: status.biometricEnabled,
                        onChanged: _busy
                            ? null
                            : (val) async {
                                await ref
                                    .read(appLockServiceProvider)
                                    .setBiometricEnabled(val);
                                ref.invalidate(appLockStatusProvider);
                              },
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          Text(
            'Backup & Pulihkan Data (.sihemat)',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Karena Si-Hemat 100% offline tanpa server cloud, buat backup terenkripsi berkala dan simpan ke Google Drive pribadi atau laptop Anda.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _busy ? null : _exportBackup,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Export Backup Terenkripsi (.sihemat)'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _importBackup,
                    icon: const Icon(Icons.restore_rounded),
                    label: const Text('Pulihkan dari File Backup (.sihemat)'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          Text(
            'Menu Cepat Lainnya',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: const Text('Kelola Kategori'),
                  subtitle: const Text('Tambah atau ubah ikon & nama kategori'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/categories'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: const Text('Kelola Dompet'),
                  subtitle: const Text('Dompet keluarga & dompet pribadi'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/wallets'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('Pengaturan Gemini AI'),
                  subtitle: const Text('API Key gratis Google AI Studio & model'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/ai-settings'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.wifi_rounded),
                  title: const Text('Sync Keluarga (Wi-Fi Lokal)'),
                  subtitle: const Text('Sinkronkan data bersama di Wi-Fi sama'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/wifi-sync'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Si-Hemat v1.0.0 • Offline-First Family Finance + Gemini AI',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SingleNameEditDialog extends StatefulWidget {
  const _SingleNameEditDialog({
    required this.title,
    required this.label,
    required this.initialValue,
  });

  final String title;
  final String label;
  final String initialValue;

  @override
  State<_SingleNameEditDialog> createState() => _SingleNameEditDialogState();
}

class _SingleNameEditDialogState extends State<_SingleNameEditDialog> {
  late final TextEditingController _ctrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final cleaned = _ctrl.text.trim();
    if (cleaned.isEmpty) {
      setState(() => _error = 'Nama tidak boleh kosong.');
      return;
    }
    Navigator.pop(context, cleaned);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        textCapitalization: TextCapitalization.words,
        autofocus: true,
        decoration: InputDecoration(
          labelText: widget.label,
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

class _SetPinDialog extends StatefulWidget {
  const _SetPinDialog();

  @override
  State<_SetPinDialog> createState() => _SetPinDialogState();
}

class _SetPinDialogState extends State<_SetPinDialog> {
  final _pinCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pinCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = _pinCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      setState(() => _error = 'PIN harus tepat 6 digit angka.');
      return;
    }
    if (pin != confirm) {
      setState(() => _error = 'Konfirmasi PIN tidak cocok.');
      return;
    }
    Navigator.pop(context, pin);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Atur PIN 6 Digit'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _pinCtrl,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'PIN Baru (6 angka)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _confirmCtrl,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'Ulangi PIN',
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(
                _error!,
                style: const TextStyle(
                  color: AppTheme.expenseColor,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Simpan PIN'),
        ),
      ],
    );
  }
}

class _BackupPasswordDialog extends StatefulWidget {
  const _BackupPasswordDialog({
    required this.title,
    required this.subtitle,
    required this.confirmPassword,
    required this.actionLabel,
  });

  final String title;
  final String subtitle;
  final bool confirmPassword;
  final String actionLabel;

  @override
  State<_BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}

class _BackupPasswordDialogState extends State<_BackupPasswordDialog> {
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final pass = _passCtrl.text.trim();
    if (pass.length < 6) {
      setState(() => _error = 'Kata sandi minimal 6 karakter.');
      return;
    }
    if (widget.confirmPassword && pass != _confirmCtrl.text.trim()) {
      setState(() => _error = 'Konfirmasi kata sandi tidak cocok.');
      return;
    }
    Navigator.pop(context, pass);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.subtitle,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Kata Sandi Backup',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            if (widget.confirmPassword) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _confirmCtrl,
                obscureText: _obscure,
                decoration: const InputDecoration(
                  labelText: 'Ulangi Kata Sandi',
                ),
                onSubmitted: (_) => _submit(),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(
                  color: AppTheme.expenseColor,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}
