import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:si_hemat/app/providers.dart';

class FamilyQrScreen extends ConsumerStatefulWidget {
  const FamilyQrScreen({super.key});

  @override
  ConsumerState<FamilyQrScreen> createState() => _FamilyQrScreenState();
}

class _FamilyQrScreenState extends ConsumerState<FamilyQrScreen> {
  bool _includeApiKey = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final inviteAsync = ref.watch(familyInvitePayloadProvider(_includeApiKey));
    final membersAsync = ref.watch(familyMembersProvider);
    final hashAsync = ref.watch(familyHashProvider);
    final aiConfigured = ref.watch(aiConfigProvider).value?.isConfigured ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Undang Keluarga (QR)'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (aiConfigured) ...[
            Card(
              child: SwitchListTile(
                value: _includeApiKey,
                onChanged: (v) => setState(() => _includeApiKey = v),
                title: const Text('Sertakan Gemini API Key dalam QR'),
                subtitle: const Text(
                  'Agar pasangan langsung bisa memakai fitur AI tanpa mengetik API Key manual.',
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          inviteAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Gagal memuat kode QR: $e'),
              ),
            ),
            data: (payload) {
              if (payload == null) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Data keluarga belum tersedia.'),
                  ),
                );
              }
              final qrString = payload.toQrString();
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        payload.familyName,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Scan QR ini dari HP pasangan untuk berbagi buku keluarga & kunci enkripsi Wi-Fi lokal.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: colors.outlineVariant),
                        ),
                        child: QrImageView(
                          data: qrString,
                          version: QrVersions.auto,
                          size: 220,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (hashAsync.value != null)
                        Chip(
                          avatar:
                              const Icon(Icons.fingerprint_rounded, size: 18),
                          label: Text('ID Sync: ${hashAsync.value}'),
                        ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: qrString),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Kode undangan disalin (jaga kerahasiaannya, hanya kirim ke anggota keluarga).',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded),
                        label: const Text('Salin Kode Undangan'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Text(
            'Anggota Terdaftar',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          membersAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Error: $e'),
            data: (members) => Card(
              child: Column(
                children: members
                    .map(
                      (m) => ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Color(m.avatarColor),
                          foregroundColor: Colors.white,
                          child: Text(
                            m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                          ),
                        ),
                        title: Text(
                          m.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          m.role == 'admin' ? 'Admin Keluarga' : 'Anggota',
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
