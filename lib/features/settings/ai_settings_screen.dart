import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:si_hemat/app/providers.dart';
import 'package:si_hemat/app/theme/app_theme.dart';
import 'package:si_hemat/features/ai_assistant/ai_models.dart';
import 'package:si_hemat/features/ai_assistant/gemini_client.dart';
import 'package:si_hemat/features/ai_assistant/nine_router_client.dart';

class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  final _geminiKeyCtrl = TextEditingController();
  final _nrUrlCtrl = TextEditingController();
  final _nrKeyCtrl = TextEditingController();
  final _nrModelCtrl = TextEditingController();

  String _provider = AiProviderType.gemini;
  String _selectedGeminiModel = GeminiModels.hydrogen;
  List<String> _fetchedNrModels = const [];

  bool _obscureKey = true;
  bool _loading = true;
  bool _testing = false;
  bool _loadingModels = false;
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
      _provider = config.provider;
      _geminiKeyCtrl.text = config.apiKey;
      _selectedGeminiModel = config.model;
      _nrUrlCtrl.text = config.nineRouterBaseUrl;
      _nrKeyCtrl.text = config.nineRouterApiKey;
      _nrModelCtrl.text = config.nineRouterModel;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _geminiKeyCtrl.dispose();
    _nrUrlCtrl.dispose();
    _nrKeyCtrl.dispose();
    _nrModelCtrl.dispose();
    super.dispose();
  }

  Future<void> _persistConfig() async {
    await ref.read(aiFinanceServiceProvider).saveConfig(
          provider: _provider,
          apiKey: _geminiKeyCtrl.text,
          model: _selectedGeminiModel,
          nineRouterBaseUrl: _nrUrlCtrl.text,
          nineRouterApiKey: _nrKeyCtrl.text,
          nineRouterModel: _nrModelCtrl.text,
        );
    ref.invalidate(aiConfigProvider);
  }

  Future<void> _saveOnly() async {
    await _persistConfig();
    if (!mounted) return;
    setState(() {
      _statusMessage =
          'Pengaturan AI (${_provider == AiProviderType.nineRouter ? '9Router' : 'Gemini'}) tersimpan aman di perangkat Anda.';
      _statusIsError = false;
    });
  }

  Future<void> _fetchNineRouterModels() async {
    final url = _nrUrlCtrl.text.trim();
    if (url.isEmpty) {
      setState(() {
        _statusMessage = 'Masukkan Base URL 9Router terlebih dahulu.';
        _statusIsError = true;
      });
      return;
    }

    setState(() {
      _loadingModels = true;
      _statusMessage = null;
    });
    try {
      final models = await ref
          .read(aiFinanceServiceProvider)
          .fetchNineRouterModels(
            baseUrl: url,
            apiKey: _nrKeyCtrl.text,
          );
      if (!mounted) return;
      setState(() {
        _fetchedNrModels = models;
        if (models.isNotEmpty && _nrModelCtrl.text.trim().isEmpty) {
          _nrModelCtrl.text = models.first;
        }
        _statusMessage = models.isEmpty
            ? 'Terhubung ke 9Router, namun daftar model kosong. Ketik nama model/combo secara manual.'
            : 'Berhasil memuat ${models.length} model / combo dari 9Router!';
        _statusIsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = e.toString();
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  Future<void> _saveAndTest() async {
    if (_provider == AiProviderType.gemini) {
      final key = _geminiKeyCtrl.text.trim();
      if (key.isEmpty) {
        setState(() {
          _statusMessage = 'Masukkan Gemini API Key terlebih dahulu.';
          _statusIsError = true;
        });
        return;
      }
    } else {
      if (_nrUrlCtrl.text.trim().isEmpty) {
        setState(() {
          _statusMessage = 'Masukkan Base URL server 9Router terlebih dahulu.';
          _statusIsError = true;
        });
        return;
      }
      if (_nrModelCtrl.text.trim().isEmpty) {
        setState(() {
          _statusMessage =
              'Masukkan atau pilih nama Model / Combo 9Router terlebih dahulu.';
          _statusIsError = true;
        });
        return;
      }
    }

    setState(() {
      _testing = true;
      _statusMessage = null;
    });

    try {
      await _persistConfig();
      final service = ref.read(aiFinanceServiceProvider);
      final String reply;
      final String label;
      if (_provider == AiProviderType.nineRouter) {
        label = '9Router (${_nrModelCtrl.text.trim()})';
        reply = await service.testNineRouter(
          baseUrl: _nrUrlCtrl.text,
          apiKey: _nrKeyCtrl.text,
          model: _nrModelCtrl.text,
        );
      } else {
        label = _selectedGeminiModel;
        reply = await service.testApiKey(
          apiKey: _geminiKeyCtrl.text,
          model: _selectedGeminiModel,
        );
      }
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Terhubung ke $label! Respons: "$reply"';
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
    final isNineRouter = _provider == AiProviderType.nineRouter;

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan AI (BYOK)')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Pilih Penyedia AI',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: AiProviderType.gemini,
                      icon: Icon(Icons.auto_awesome_outlined, size: 18),
                      label: Text('Gemini (Gratis)'),
                    ),
                    ButtonSegment(
                      value: AiProviderType.nineRouter,
                      icon: Icon(Icons.hub_outlined, size: 18),
                      label: Text('9Router (OpenAI)'),
                    ),
                  ],
                  selected: {_provider},
                  onSelectionChanged: (s) => setState(() {
                    _provider = s.first;
                    _statusMessage = null;
                  }),
                ),
                const SizedBox(height: 14),

                // Guide Card per provider
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
                              isNineRouter
                                  ? Icons.hub_rounded
                                  : Icons.auto_awesome_rounded,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                isNineRouter
                                    ? 'Cara Menghubungkan 9Router'
                                    : 'Cara Mendapatkan API Key Gratis',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isNineRouter
                              ? '1. Jalankan 9Router di PC/server Anda (default port 20128).\n'
                                  '2. Untuk HP di Wi-Fi sama, pakai IP LAN PC (contoh: http://192.168.1.10:20128/v1) atau domain HTTPS Anda (jangan pakai localhost di HP).\n'
                                  '3. Tempel Master API Key (sk-...) dari dashboard 9Router lalu tekan "Muat Daftar Model" atau ketik nama Model / Combo Anda.'
                              : '1. Buka aistudio.google.com lalu login dengan akun Google Anda.\n'
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

                // Form Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!isNineRouter) ...[
                          TextField(
                            controller: _geminiKeyCtrl,
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
                            groupValue: _selectedGeminiModel,
                            onChanged: (v) {
                              if (v != null) {
                                setState(() => _selectedGeminiModel = v);
                              }
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
                        ] else ...[
                          TextField(
                            controller: _nrUrlCtrl,
                            keyboardType: TextInputType.url,
                            decoration: const InputDecoration(
                              labelText: 'Base URL 9Router',
                              hintText: NineRouterClient.defaultBaseUrl,
                              helperText:
                                  'Otomatis dinormalisasi ke .../v1 (OpenAI-compatible)',
                              prefixIcon: Icon(Icons.link_rounded),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _nrKeyCtrl,
                            obscureText: _obscureKey,
                            decoration: InputDecoration(
                              labelText: '9Router API Key',
                              hintText: 'sk-...',
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
                          const SizedBox(height: 14),
                          TextField(
                            controller: _nrModelCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Model ID atau Nama Combo',
                              hintText:
                                  'Contoh: gemini/gemini-2.5-flash atau my-combo',
                              helperText:
                                  'Untuk Scan Struk, pilih model/combo yang mendukung Vision (gambar).',
                              prefixIcon: Icon(Icons.smart_toy_outlined),
                            ),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _loadingModels || _testing
                                ? null
                                : _fetchNineRouterModels,
                            icon: _loadingModels
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh_rounded, size: 18),
                            label: Text(
                              _loadingModels
                                  ? 'Memuat Model dari 9Router...'
                                  : 'Muat Daftar Model / Combo (/v1/models)',
                            ),
                          ),
                          if (_fetchedNrModels.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Pilih dari ${_fetchedNrModels.length} Model Tersedia:',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: _fetchedNrModels.take(24).map((id) {
                                final selected = _nrModelCtrl.text.trim() == id;
                                return ChoiceChip(
                                  label: Text(
                                    id,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  selected: selected,
                                  onSelected: (_) =>
                                      setState(() => _nrModelCtrl.text = id),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                        const SizedBox(height: 18),
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
                            ? AppTheme.expenseOf(context)
                            : AppTheme.incomeOf(context))
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
                                ? AppTheme.expenseOf(context)
                                : AppTheme.incomeOf(context),
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
                            isNineRouter
                                ? 'Privasi: Permintaan AI dikirim langsung dari HP Anda ke endpoint 9Router milik Anda sendiri; tidak melewati server pengembang Si-Hemat.'
                                : 'Privasi: Permintaan ke Gemini API menggunakan mode store: false (tidak disimpan di server Google) dan hanya mengirim ringkasan angka saat tanya laporan.',
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
