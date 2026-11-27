import 'package:si_hemat/core/constants/sync_constants.dart';

class DefaultCategorySeed {
  const DefaultCategorySeed({
    required this.key,
    required this.name,
    required this.type,
    required this.iconName,
    required this.colorValue,
  });

  final String key;
  final String name;
  final String type;
  final String iconName;
  final int colorValue;
}

/// Curated Indonesian household default categories seeded on family creation.
const List<DefaultCategorySeed> kDefaultCategories = [
  // Pengeluaran (Expense)
  DefaultCategorySeed(
    key: 'exp_food',
    name: 'Makan & Dapur',
    type: CategoryType.expense,
    iconName: 'restaurant',
    colorValue: 0xFFE67E22,
  ),
  DefaultCategorySeed(
    key: 'exp_transport',
    name: 'Transportasi',
    type: CategoryType.expense,
    iconName: 'directions_car',
    colorValue: 0xFF2980B9,
  ),
  DefaultCategorySeed(
    key: 'exp_bills',
    name: 'Tagihan Rumah',
    type: CategoryType.expense,
    iconName: 'receipt_long',
    colorValue: 0xFF8E44AD,
  ),
  DefaultCategorySeed(
    key: 'exp_kids',
    name: 'Anak & Pendidikan',
    type: CategoryType.expense,
    iconName: 'school',
    colorValue: 0xFF16A085,
  ),
  DefaultCategorySeed(
    key: 'exp_health',
    name: 'Kesehatan',
    type: CategoryType.expense,
    iconName: 'local_hospital',
    colorValue: 0xFFE74C3C,
  ),
  DefaultCategorySeed(
    key: 'exp_shopping',
    name: 'Belanja & Rumah Tangga',
    type: CategoryType.expense,
    iconName: 'shopping_bag',
    colorValue: 0xFFD35400,
  ),
  DefaultCategorySeed(
    key: 'exp_leisure',
    name: 'Hiburan & Jajan',
    type: CategoryType.expense,
    iconName: 'coffee',
    colorValue: 0xFFF39C12,
  ),
  DefaultCategorySeed(
    key: 'exp_debt',
    name: 'Cicilan & Utang',
    type: CategoryType.expense,
    iconName: 'credit_card',
    colorValue: 0xFFC0392B,
  ),
  DefaultCategorySeed(
    key: 'exp_social',
    name: 'Sosial & Sedekah',
    type: CategoryType.expense,
    iconName: 'volunteer_activism',
    colorValue: 0xFF27AE60,
  ),
  DefaultCategorySeed(
    key: 'exp_other',
    name: 'Pengeluaran Lainnya',
    type: CategoryType.expense,
    iconName: 'more_horiz',
    colorValue: 0xFF7F8C8D,
  ),

  // Pemasukan (Income)
  DefaultCategorySeed(
    key: 'inc_salary',
    name: 'Gaji',
    type: CategoryType.income,
    iconName: 'payments',
    colorValue: 0xFF0F9D58,
  ),
  DefaultCategorySeed(
    key: 'inc_business',
    name: 'Usaha & Sampingan',
    type: CategoryType.income,
    iconName: 'storefront',
    colorValue: 0xFF00897B,
  ),
  DefaultCategorySeed(
    key: 'inc_bonus',
    name: 'Bonus & THR',
    type: CategoryType.income,
    iconName: 'card_giftcard',
    colorValue: 0xFF2E7D32,
  ),
  DefaultCategorySeed(
    key: 'inc_invest',
    name: 'Hasil Investasi',
    type: CategoryType.income,
    iconName: 'trending_up',
    colorValue: 0xFF1565C0,
  ),
  DefaultCategorySeed(
    key: 'inc_other',
    name: 'Pemasukan Lainnya',
    type: CategoryType.income,
    iconName: 'add_circle_outline',
    colorValue: 0xFF546E7A,
  ),
];
