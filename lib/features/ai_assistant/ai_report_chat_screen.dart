import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:si_hemat/app/providers.dart';
import 'package:si_hemat/app/theme/app_theme.dart';
import 'package:si_hemat/core/utils/date_formatter.dart';

class AiReportChatScreen extends ConsumerStatefulWidget {
  const AiReportChatScreen({
    super.key,
    this.initialPrompt,
  });

  final String? initialPrompt;

  @override
  ConsumerState<AiReportChatScreen> createState() => _AiReportChatScreenState();
}

class _AiReportChatScreenState extends ConsumerState<AiReportChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;
  String? _error;

  static const List<String> _quickPrompts = [
    'Buat evaluasi keuangan keluarga bulan ini dan beri 3 saran hemat praktis.',
    'Pengeluaran paling besar bulan ini di kategori apa saja?',
    'Apakah anggaran bulan ini masih aman atau ada yang over budget?',
    'Bandingkan pengeluaran bulan ini dengan bulan lalu.',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialPrompt != null && widget.initialPrompt!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sendQuestion(widget.initialPrompt!);
      });
    }
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendQuestion(String rawText) async {
    final text = rawText.trim();
    final family = ref.read(activeFamilyProvider).value;
    if (text.isEmpty || family == null || _sending) return;

    _inputCtrl.clear();
    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final month = ref.read(reportMonthProvider);
      final scope = ref.read(scopeFilterProvider);
      await ref.read(aiFinanceServiceProvider).askFinancialQuestion(
            familyId: family.id,
            question: text,
            month: month,
            visibilityFilter: scope,
          );
      _scrollToBottom();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final month = ref.watch(reportMonthProvider);
    final configAsync = ref.watch(aiConfigProvider);
    final messagesAsync = ref.watch(aiChatMessagesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Asisten AI Keuangan'),
            Text(
              'Konteks: ${DateFormatter.formatMonthYear(month)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Bersihkan Riwayat Chat',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () =>
                ref.read(databaseProvider).clearAiChatMessages(),
          ),
          IconButton(
            tooltip: 'Pengaturan AI',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/ai-settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (configAsync.value?.isConfigured == false)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Card(
                color: AppTheme.warningColor.withValues(alpha: 0.14),
                child: ListTile(
                  dense: true,
                  leading: const Icon(
                    Icons.key_off_rounded,
                    color: AppTheme.warningColor,
                  ),
                  title: const Text('Pengaturan AI belum dikonfigurasi'),
                  trailing: TextButton(
                    onPressed: () => context.push('/ai-settings'),
                    child: const Text('Atur'),
                  ),
                ),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Card(
                color: AppTheme.expenseColor.withValues(alpha: 0.12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppTheme.expenseColor),
                  ),
                ),
              ),
            ),
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (messages) {
                if (messages.isEmpty) {
                  return ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      const SizedBox(height: 16),
                      Center(
                        child: CircleAvatar(
                          radius: 32,
                          backgroundColor: colors.primaryContainer,
                          foregroundColor: colors.onPrimaryContainer,
                          child: const Icon(
                            Icons.auto_awesome_rounded,
                            size: 30,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Tanya Kondisi Keuangan Keluarga',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Jawaban dihitung dari angka pasti database SQLite Anda — AI hanya membantu menjelaskan dan memberi saran hemat.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ..._quickPrompts.map(
                        (prompt) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: OutlinedButton(
                            onPressed:
                                _sending ? null : () => _sendQuestion(prompt),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(prompt, textAlign: TextAlign.center),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }

                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length + (_sending ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (i == messages.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 10),
                            Text('Si-Hemat AI sedang menganalisis laporan...'),
                          ],
                        ),
                      );
                    }
                    final msg = messages[i];
                    final isUser = msg.role == 'user';
                    return Align(
                      alignment: isUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(ctx).size.width * 0.84,
                        ),
                        decoration: BoxDecoration(
                          color: isUser
                              ? colors.primary
                              : colors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: SelectableText(
                          msg.content,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isUser ? colors.onPrimary : colors.onSurface,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _sendQuestion,
                      decoration: const InputDecoration(
                        hintText: 'Tanya laporan bulan ini...',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending
                        ? null
                        : () => _sendQuestion(_inputCtrl.text),
                    icon: const Icon(Icons.send_rounded),
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
