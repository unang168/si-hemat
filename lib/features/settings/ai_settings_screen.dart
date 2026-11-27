import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:si_hemat/app/providers.dart';
import 'package:si_hemat/app/theme/app_theme.dart';
import 'package:si_hemat/features/ai_assistant/gemini_client.dart';

class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  final _apiKeyCtrl = TextEditingController();
  String _selectedModel = GeminiModels.hydrogen;
  bool _obscureKey = true;
  bool _loading = true;
  bool _testing = false;
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    final config = await ref.read(aiFinanceServiceProvider).loadConfig();
    if (!mounted) return;
    setState(() {
      _apiKeyCtrl.text = config.apiKey;
      _selectedModel = config.model;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveOnly() async {
    await ref.read(aiFinanceServiceProvider).saveConfig(
          apiKey: _apiKeyCtrl.text,
          model: _selectedModel,
        );
    ref.invalidate(aiConfigProvider);
    if (!mounted) return;
    setState(() {
      _statusMessage = 'Pengaturan AI tersimpan aman di perangkat Anda.';
      _statusIsError = false;
    });
  }

  Future<void> _saveAndTest() async {
    final key = _apiKeyCtrl.text.trim();
    if (key.isEmpty) {
      setState(() {
        _statusMessage = 'Masukkan Gemini API Key terlebih dahulu.';
        _statusIsError = true;
      });
      return;
    }

    setState(() {
      _testing = true;
      _statusMessage = null;
    });

    try {
      await ref.read(aiFinanceServiceProvider).saveConfig(
            apiKey: key,
            model: _selectedModel,
          );
      ref.invalidate(aiConfigProvider);

      final reply = await ref.read(aiFinanceServiceProvider).testApiKey(
            apiKey: key,
            model: _selectedModel,
          );
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Terhubung ke $_selectedModel! Respons: "$reply"';
        _statusIsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = e.toString();
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan Gemini AI')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: colors.primaryContainer.withValues(alpha: 0.45),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Cara Mendapatkan API Key Gratis',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '1. Buka aistudio.google.com lalu login dengan akun Google Anda.\n'
                          '2. Klik "Get API key" → buat key baru (tersedia kuota gratis & klaim kredit Google AI Pro).\n'
                          '3. Tempel API Key di bawah ini. Key disimpan terenkripsi di Android Keystore.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _apiKeyCtrl,
                          obscureText: _obscureKey,
                          decoration: InputDecoration(
                            labelText: 'Gemini API Key',
                            hintText: 'AIzaSy...',
                            prefixIcon: const Icon(Icons.key_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureKey
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () =>
                                  setState(() => _obscureKey = !_obscureKey),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Pilih Model Gemini',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        RadioGroup<String>(
                          groupValue: _selectedModel,
                          onChanged: (v) {
                            if (v != null) setState(() => _selectedModel = v);
                          },
                          child: Column(
                            children: GeminiModels.available
                                .map(
                                  (m) => RadioListTile<String>(
                                    contentPadding: EdgeInsets.zero,
                                    value: m.id,
                                    title: Text(
                                      m.label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      m.subtitle,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _testing ? null : _saveAndTest,
                          icon: _testing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.verified_outlined),
                          label: Text(
                            _testing
                                ? 'Menguji Koneksi...'
                                : 'Simpan & Tes Koneksi',
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: _testing ? null : _saveOnly,
                          child: const Text('Simpan Tanpa Tes'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_statusMessage != null) ...[
                  const SizedBox(height: 14),
                  Card(
                    color: (_statusIsError
                            ? AppTheme.expenseColor
                            : AppTheme.incomeColor)
                        .withValues(alpha: 0.12),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(
                            _statusIsError
                                ? Icons.error_outline_rounded
                                : Icons.check_circle_outline_rounded,
                            color: _statusIsError
                                ? AppTheme.expenseColor
                                : AppTheme.incomeColor,
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(_statusMessage!)),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(Icons.privacy_tip_outlined, color: colors.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Privasi: Permintaan ke Gemini API menggunakan mode store: false (tidak disimpan di server Google) dan hanya mengirim ringkasan angka saat tanya laporan.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
