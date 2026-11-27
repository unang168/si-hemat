import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:si_hemat/app/providers.dart';
import 'package:si_hemat/app/theme/app_theme.dart';
import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/core/utils/category_icons.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final family = ref.watch(activeFamilyProvider).value;
    final categoriesAsync = ref.watch(categoriesProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kelola Kategori'),
          bottom: const TabBar(
            tabs: [
              Tab(
                icon: Icon(Icons.arrow_upward_rounded, size: 18),
                text: 'Pengeluaran',
              ),
              Tab(
                icon: Icon(Icons.arrow_downward_rounded, size: 18),
                text: 'Pemasukan',
              ),
            ],
          ),
        ),
        floatingActionButton: family == null
            ? null
            : Builder(
                builder: (tabCtx) => FloatingActionButton.extended(
                  onPressed: () {
                    final tabIndex =
                        DefaultTabController.of(tabCtx).index;
                    final type = tabIndex == 1
                        ? CategoryType.income
                        : CategoryType.expense;
                    _openCategoryForm(
                      context,
                      familyId: family.id,
                      initialType: type,
                    );
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Kategori Baru'),
                ),
              ),
        body: categoriesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Gagal memuat kategori: $e')),
          data: (all) {
            final expenseCats =
                all.where((c) => c.type == CategoryType.expense).toList();
            final incomeCats =
                all.where((c) => c.type == CategoryType.income).toList();
            return TabBarView(
              children: [
                _CategoryList(
                  categories: expenseCats,
                  familyId: family?.id,
                  type: CategoryType.expense,
                ),
                _CategoryList(
                  categories: incomeCats,
                  familyId: family?.id,
                  type: CategoryType.income,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static Future<void> _openCategoryForm(
    BuildContext context, {
    required String familyId,
    required String initialType,
    Category? existing,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CategoryFormSheet(
        familyId: familyId,
        initialType: initialType,
        existing: existing,
      ),
    );
  }
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({
    required this.categories,
    required this.familyId,
    required this.type,
  });

  final List<Category> categories;
  final String? familyId;
  final String type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (categories.isEmpty) {
      return Center(
        child: Text(
          'Belum ada kategori.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: categories.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final cat = categories[index];
        return Card(
          child: ListTile(
            onTap: familyId == null
                ? null
                : () => CategoriesScreen._openCategoryForm(
                      context,
                      familyId: familyId!,
                      initialType: type,
                      existing: cat,
                    ),
            leading: CircleAvatar(
              backgroundColor: Color(cat.color).withValues(alpha: 0.16),
              foregroundColor: Color(cat.color),
              child: Icon(AppIcons.forCategory(cat.icon)),
            ),
            title: Text(
              cat.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              cat.isDefault ? 'Kategori Bawaan (bisa diubah)' : 'Kategori Kustom',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            trailing: const Icon(Icons.chevron_right_rounded, size: 20),
          ),
        );
      },
    );
  }
}

class _CategoryFormSheet extends ConsumerStatefulWidget {
  const _CategoryFormSheet({
    required this.familyId,
    required this.initialType,
    this.existing,
  });

  final String familyId;
  final String initialType;
  final Category? existing;

  @override
  ConsumerState<_CategoryFormSheet> createState() => _CategoryFormSheetState();
}

class _CategoryFormSheetState extends ConsumerState<_CategoryFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late String _type;
  late String _icon;
  late int _color;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _type = e?.type ?? widget.initialType;
    _icon = e?.icon ?? AppIcons.categoryIconOptions.first.key;
    _color = e?.color ?? AppIcons.categoryColorPalette.first;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final service = ref.read(categoryServiceProvider);
      if (_isEditing) {
        await service.updateCategory(
          categoryId: widget.existing!.id,
          name: _nameCtrl.text,
          icon: _icon,
          color: _color,
        );
      } else {
        await service.createCategory(
          familyId: widget.familyId,
          name: _nameCtrl.text,
          type: _type,
          icon: _icon,
          color: _color,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan kategori: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final existing = widget.existing;
    if (existing == null) return;
    if (existing.isDefault) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Kategori bawaan tidak dapat dihapus agar sinkronisasi tetap konsisten. Anda tetap bisa mengubah nama, ikon, atau warnanya.',
          ),
        ),
      );
      return;
    }

    final txCount = await ref
        .read(databaseProvider)
        .countActiveTransactionsForCategory(existing.id);
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Kategori?'),
        content: Text(
          txCount > 0
              ? 'Kategori "${existing.name}" dipakai di $txCount transaksi. Menghapusnya hanya menyembunyikan kategori dari daftar baru (riwayat tetap aman).'
              : 'Kategori "${existing.name}" akan dihapus dari daftar aktif.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.expenseColor,
              minimumSize: const Size(96, 44),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(categoryServiceProvider).deleteCategory(existing);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, bottomInset + 20),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Color(_color).withValues(alpha: 0.16),
                    foregroundColor: Color(_color),
                    child: Icon(AppIcons.forCategory(_icon)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isEditing ? 'Edit Kategori' : 'Kategori Baru',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_isEditing && !widget.existing!.isDefault)
                    IconButton(
                      tooltip: 'Hapus Kategori',
                      onPressed: _saving ? null : _confirmDelete,
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: AppTheme.expenseColor,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (!_isEditing) ...[
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: CategoryType.expense,
                      label: Text('Pengeluaran'),
                    ),
                    ButtonSegment(
                      value: CategoryType.income,
                      label: Text('Pemasukan'),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => setState(() => _type = s.first),
                ),
                const SizedBox(height: 14),
              ],
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nama Kategori',
                  hintText: 'Contoh: Arisan, Cicilan Motor, Uang Saku',
                  prefixIcon: Icon(Icons.label_outline_rounded),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Nama kategori wajib diisi'
                    : null,
              ),
              const SizedBox(height: 14),
              Text('Pilih Warna', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: AppIcons.categoryColorPalette.map((c) {
                  final selected = c == _color;
                  return InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: selected
                            ? Border.all(
                                color: colors.onSurface,
                                width: 2.5,
                              )
                            : null,
                      ),
                      child: selected
                          ? const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 16,
                            )
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              Text('Pilih Ikon', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AppIcons.categoryIconOptions.map((opt) {
                  final selected = opt.key == _icon;
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _icon = opt.key),
                    child: Tooltip(
                      message: opt.label,
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: selected
                              ? Color(_color).withValues(alpha: 0.2)
                              : colors.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? Color(_color)
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          opt.icon,
                          size: 20,
                          color: selected
                              ? Color(_color)
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(
                  _saving
                      ? 'Menyimpan...'
                      : (_isEditing ? 'Simpan Perubahan' : 'Tambah Kategori'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
