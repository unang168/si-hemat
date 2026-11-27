import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:si_hemat/app/providers.dart';
import 'package:si_hemat/core/constants/sync_constants.dart';

/// Compact interactive scope bar (`Semua` | `Keluarga` | `Pribadi`) displayed on
/// non-Dashboard tabs so the user always sees and can switch the active scope.
class ScopeIndicatorBar extends ConsumerWidget {
  const ScopeIndicatorBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(scopeFilterProvider);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          Icon(
            scope == 'all'
                ? Icons.layers_outlined
                : (scope == VisibilityScope.shared
                    ? Icons.groups_rounded
                    : Icons.lock_outline_rounded),
            size: 16,
            color: colors.primary,
          ),
          const SizedBox(width: 6),
          Text(
            'Tampilan:',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _ScopePill(
                    label: 'Semua',
                    selected: scope == 'all',
                    onTap: () =>
                        ref.read(scopeFilterProvider.notifier).setScope('all'),
                  ),
                  const SizedBox(width: 6),
                  _ScopePill(
                    label: 'Keluarga',
                    selected: scope == VisibilityScope.shared,
                    onTap: () => ref
                        .read(scopeFilterProvider.notifier)
                        .setScope(VisibilityScope.shared),
                  ),
                  const SizedBox(width: 6),
                  _ScopePill(
                    label: 'Pribadi',
                    selected: scope == VisibilityScope.personal,
                    onTap: () => ref
                        .read(scopeFilterProvider.notifier)
                        .setScope(VisibilityScope.personal),
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

class _ScopePill extends StatelessWidget {
  const _ScopePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? colors.primaryContainer
              : colors.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? colors.primary.withValues(alpha: 0.5)
                : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? colors.onPrimaryContainer
                    : colors.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}
