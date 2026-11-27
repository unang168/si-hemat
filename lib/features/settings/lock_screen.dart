import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:si_hemat/app/providers.dart';
import 'package:si_hemat/app/theme/app_theme.dart';

class PinLockScreen extends ConsumerStatefulWidget {
  const PinLockScreen({
    super.key,
    required this.biometricEnabled,
    required this.onUnlocked,
  });

  final bool biometricEnabled;
  final VoidCallback onUnlocked;

  @override
  ConsumerState<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends ConsumerState<PinLockScreen> {
  String _pin = '';
  String? _errorText;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    if (widget.biometricEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
    }
  }

  Future<void> _tryBiometric() async {
    final ok =
        await ref.read(appLockServiceProvider).authenticateWithBiometrics();
    if (ok && mounted) {
      widget.onUnlocked();
    }
  }

  Future<void> _onDigitTap(String digit) async {
    if (_verifying || _pin.length >= 6) return;
    setState(() {
      _pin += digit;
      _errorText = null;
    });

    if (_pin.length == 6) {
      setState(() => _verifying = true);
      final valid = await ref.read(appLockServiceProvider).verifyPin(_pin);
      if (!mounted) return;
      if (valid) {
        widget.onUnlocked();
      } else {
        setState(() {
          _pin = '';
          _verifying = false;
          _errorText = 'PIN salah. Silakan coba lagi.';
        });
      }
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty || _verifying) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _errorText = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            children: [
              const Spacer(),
              CircleAvatar(
                radius: 34,
                backgroundColor: colors.primaryContainer,
                foregroundColor: colors.onPrimaryContainer,
                child: const Icon(Icons.lock_rounded, size: 32),
              ),
              const SizedBox(height: 16),
              Text(
                'Si-Hemat Terkunci',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Masukkan 6 digit PIN Anda untuk membuka buku keuangan.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (index) {
                  final filled = index < _pin.length;
                  return Container(
                    width: 18,
                    height: 18,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled ? colors.primary : Colors.transparent,
                      border: Border.all(
                        color: filled ? colors.primary : colors.outline,
                        width: 2,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 22,
                child: _errorText != null
                    ? Text(
                        _errorText!,
                        style: const TextStyle(
                          color: AppTheme.expenseColor,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : null,
              ),
              const Spacer(),
              _buildKeypadRow(['1', '2', '3']),
              const SizedBox(height: 12),
              _buildKeypadRow(['4', '5', '6']),
              const SizedBox(height: 12),
              _buildKeypadRow(['7', '8', '9']),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  SizedBox(
                    width: 72,
                    height: 60,
                    child: widget.biometricEnabled
                        ? IconButton(
                            tooltip: 'Buka dengan Biometrik',
                            onPressed: _tryBiometric,
                            icon: Icon(
                              Icons.fingerprint_rounded,
                              size: 32,
                              color: colors.primary,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  _KeypadButton(
                    label: '0',
                    onTap: () => _onDigitTap('0'),
                  ),
                  SizedBox(
                    width: 72,
                    height: 60,
                    child: IconButton(
                      tooltip: 'Hapus',
                      onPressed: _onBackspace,
                      icon: const Icon(Icons.backspace_outlined, size: 24),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeypadRow(List<String> digits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: digits
          .map((d) => _KeypadButton(label: d, onTap: () => _onDigitTap(d)))
          .toList(),
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 72,
      height: 60,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
