import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:si_hemat/app/providers.dart';
import 'package:si_hemat/app/theme/app_theme.dart';
import 'package:si_hemat/core/utils/date_formatter.dart';
import 'package:si_hemat/features/family_sync/sync_transport.dart';

class WifiSyncScreen extends ConsumerStatefulWidget {
  const WifiSyncScreen({super.key});

  @override
  ConsumerState<WifiSyncScreen> createState() => _WifiSyncScreenState();
}

class _WifiSyncScreenState extends ConsumerState<WifiSyncScreen> {
  bool _starting = true;
  bool _syncing = false;
  String? _error;
  String? _lastResultBanner;
  List<SyncPeerInfo> _discovered = const [];
  StreamSubscription<List<SyncPeerInfo>>? _peersSub;
  StreamSubscription<SyncRunResult>? _incomingSub;

  @override
  void initState() {
    super.initState();
    _startSyncHost();
  }

  Future<void> _startSyncHost() async {
    final service = ref.read(wifiLanSyncServiceProvider);
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      _peersSub = service.discoveredPeers.listen((list) {
        if (mounted) setState(() => _discovered = list);
      });
      _incomingSub = service.incomingSyncEvents.listen((res) {
        final fam = ref.read(activeFamilyProvider).value;
        if (fam != null) {
          ref
              .read(billNotificationServiceProvider)
              .rescheduleAllForFamily(fam.id);
        }
        if (!mounted) return;
        setState(() {
          _lastResultBanner =
              'Menerima sync dari ${res.peerName}: ${res.receivedApplied} data diperbarui, ${res.sentRecords} dikirim.';
        });
      });
      await service.startHostAndDiscovery();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  void dispose() {
    _peersSub?.cancel();
    _incomingSub?.cancel();
    ref.read(wifiLanSyncServiceProvider).stopAll();
    super.dispose();
  }

  Future<void> _runSync(SyncPeerInfo peer) async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _error = null;
    });
    try {
      final res =
          await ref.read(wifiLanSyncServiceProvider).syncWithPeer(peer);
      final fam = ref.read(activeFamilyProvider).value;
      if (fam != null) {
        await ref
            .read(billNotificationServiceProvider)
            .rescheduleAllForFamily(fam.id);
      }
      if (!mounted) return;
      setState(() {
        _lastResultBanner =
            'Sync selesai dengan ${res.peerName}! Kirim ${res.sentRecords} data, terima ${res.receivedApplied} pembaruan.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_lastResultBanner!)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _openManualConnectDialog() async {
    final result = await showDialog<({String host, int port})>(
      context: context,
      builder: (_) => const _ManualSyncDialog(),
    );
    if (result == null || !mounted) return;

    setState(() {
      _syncing = true;
      _error = null;
    });
    try {
      final service = ref.read(wifiLanSyncServiceProvider);
      final peer = await service.probeManualPeer(
        host: result.host,
        port: result.port,
      );
      final res = await service.syncWithPeer(peer);
      final fam = ref.read(activeFamilyProvider).value;
      if (fam != null) {
        await ref
            .read(billNotificationServiceProvider)
            .rescheduleAllForFamily(fam.id);
      }
      if (!mounted) return;
      setState(() {
        _lastResultBanner =
            'Sync manual berhasil dengan ${res.peerName}! Kirim ${res.sentRecords}, terima ${res.receivedApplied} pembaruan.';
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final service = ref.watch(wifiLanSyncServiceProvider);
    final historyAsync = ref.watch(syncPeersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Keluarga (Wi-Fi)'),
        actions: [
          IconButton(
            tooltip: 'QR Undang Keluarga',
            icon: const Icon(Icons.qr_code_2_rounded),
            onPressed: () => context.push('/family-qr'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Host Status Card
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
                        _starting ? Icons.wifi_find_rounded : Icons.wifi_rounded,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _starting
                              ? 'Menyalakan layanan Sync Wi-Fi...'
                              : 'Siap Sync (Terenkripsi AES-256)',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Buka halaman ini di kedua HP pada Wi-Fi rumah atau hotspot yang sama. Hanya data Keluarga (Shared) yang disinkronkan; Dompet & transaksi Pribadi tetap privat di HP masing-masing.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  if (!_starting && service.boundPort != null) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          avatar: const Icon(Icons.lan_outlined, size: 16),
                          label: Text(
                            'IP: ${service.localIpv4 ?? 'Wi-Fi'} : ${service.boundPort}',
                          ),
                        ),
                        if (service.activeFamilyHash != null)
                          Chip(
                            avatar: const Icon(
                              Icons.fingerprint_rounded,
                              size: 16,
                            ),
                            label: Text('ID: ${service.activeFamilyHash}'),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          if (_lastResultBanner != null) ...[
            const SizedBox(height: 12),
            Card(
              color: AppTheme.incomeColor.withValues(alpha: 0.12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline_rounded,
                      color: AppTheme.incomeColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_lastResultBanner!)),
                  ],
                ),
              ),
            ),
          ],

          if (_error != null) ...[
            const SizedBox(height: 12),
            Card(
              color: AppTheme.expenseColor.withValues(alpha: 0.12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: AppTheme.expenseColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: AppTheme.expenseColor),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'HP Keluarga Terdeteksi (${_discovered.length})',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextButton.icon(
                onPressed: _syncing ? null : _openManualConnectDialog,
                icon: const Icon(Icons.link_rounded, size: 18),
                label: const Text('IP Manual'),
              ),
            ],
          ),
          const SizedBox(height: 6),

          if (_discovered.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Mencari HP keluarga di Wi-Fi yang sama...',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pastikan HP pasangan sudah bergabung memakai QR Keluarga Anda dan sedang membuka halaman Sync ini. Jika router memblokir mDNS, gunakan tombol "IP Manual" di atas.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._discovered.map(
              (peer) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: colors.primaryContainer,
                      foregroundColor: colors.onPrimaryContainer,
                      child: const Icon(Icons.smartphone_rounded),
                    ),
                    title: Text(
                      peer.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text('${peer.host}:${peer.port}'),
                    trailing: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(96, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      onPressed: _syncing ? null : () => _runSync(peer),
                      icon: _syncing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync_rounded, size: 18),
                      label: const Text('Sync'),
                    ),
                  ),
                ),
              ),
            ),

          const SizedBox(height: 18),
          Text(
            'Riwayat Sinkronisasi',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          historyAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Error: $e'),
            data: (peers) {
              if (peers.isEmpty) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      'Belum ada riwayat sync dengan anggota keluarga.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }
              return Card(
                child: Column(
                  children: peers.map((p) {
                    final dt = DateTime.fromMillisecondsSinceEpoch(
                      p.lastSyncedAt,
                      isUtc: true,
                    ).toLocal();
                    final hh = dt.hour.toString().padLeft(2, '0');
                    final mm = dt.minute.toString().padLeft(2, '0');
                    return ListTile(
                      leading: const Icon(Icons.history_rounded),
                      title: Text(
                        p.peerName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Terakhir sync: ${DateFormatter.formatShortDate(dt)} $hh:$mm${p.lastIp != null ? ' (${p.lastIp})' : ''}',
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ManualSyncDialog extends StatefulWidget {
  const _ManualSyncDialog();

  @override
  State<_ManualSyncDialog> createState() => _ManualSyncDialogState();
}

class _ManualSyncDialogState extends State<_ManualSyncDialog> {
  final _ipCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _ipCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final host = _ipCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 0;
    if (host.isEmpty || port <= 0 || port > 65535) {
      setState(() {
        _validationError = 'Masukkan Alamat IP dan Port (1–65535) yang valid.';
      });
      return;
    }
    Navigator.pop(context, (host: host, port: port));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sync Manual via IP Wi-Fi'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Lihat Alamat IP & Port pada layar Sync Wi-Fi di HP pasangan (jika pakai Emulator, masukkan IP HP fisik karena Emulator memakai jaringan NAT).',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ipCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Alamat IP',
                hintText: 'Contoh: 172.10.23.14',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _portCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: 'Contoh: 54321',
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_validationError != null) ...[
              const SizedBox(height: 8),
              Text(
                _validationError!,
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
          child: const Text('Sambungkan & Sync'),
        ),
      ],
    );
  }
}
