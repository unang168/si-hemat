import 'package:material_ui/material_ui.dart';
import 'package:si_hemat/core/constants/sync_constants.dart';

class CategoryIconOption {
  const CategoryIconOption({
    required this.key,
    required this.label,
    required this.icon,
  });

  final String key;
  final String label;
  final IconData icon;
}

class AppIcons {
  AppIcons._();

  static const List<CategoryIconOption> categoryIconOptions = [
    CategoryIconOption(
      key: 'restaurant',
      label: 'Makan',
      icon: Icons.restaurant_rounded,
    ),
    CategoryIconOption(
      key: 'local_grocery_store',
      label: 'Belanja Dapur',
      icon: Icons.local_grocery_store_rounded,
    ),
    CategoryIconOption(
      key: 'coffee',
      label: 'Kopi & Jajan',
      icon: Icons.coffee_rounded,
    ),
    CategoryIconOption(
      key: 'directions_car',
      label: 'Transportasi',
      icon: Icons.directions_car_rounded,
    ),
    CategoryIconOption(
      key: 'two_wheeler',
      label: 'Motor',
      icon: Icons.two_wheeler_rounded,
    ),
    CategoryIconOption(
      key: 'local_gas_station',
      label: 'BBM',
      icon: Icons.local_gas_station_rounded,
    ),
    CategoryIconOption(
      key: 'receipt_long',
      label: 'Tagihan',
      icon: Icons.receipt_long_rounded,
    ),
    CategoryIconOption(
      key: 'bolt',
      label: 'Listrik/Air',
      icon: Icons.bolt_rounded,
    ),
    CategoryIconOption(
      key: 'wifi',
      label: 'Internet/Pulsa',
      icon: Icons.wifi_rounded,
    ),
    CategoryIconOption(
      key: 'home',
      label: 'Rumah/KPR',
      icon: Icons.home_rounded,
    ),
    CategoryIconOption(
      key: 'school',
      label: 'Pendidikan',
      icon: Icons.school_rounded,
    ),
    CategoryIconOption(
      key: 'child_care',
      label: 'Anak',
      icon: Icons.child_care_rounded,
    ),
    CategoryIconOption(
      key: 'local_hospital',
      label: 'Kesehatan',
      icon: Icons.local_hospital_rounded,
    ),
    CategoryIconOption(
      key: 'shopping_bag',
      label: 'Belanja',
      icon: Icons.shopping_bag_rounded,
    ),
    CategoryIconOption(
      key: 'credit_card',
      label: 'Cicilan/KK',
      icon: Icons.credit_card_rounded,
    ),
    CategoryIconOption(
      key: 'savings',
      label: 'Tabungan/Arisan',
      icon: Icons.savings_rounded,
    ),
    CategoryIconOption(
      key: 'volunteer_activism',
      label: 'Sosial/Zakat',
      icon: Icons.volunteer_activism_rounded,
    ),
    CategoryIconOption(
      key: 'flight',
      label: 'Liburan',
      icon: Icons.flight_rounded,
    ),
    CategoryIconOption(
      key: 'pets',
      label: 'Hewan',
      icon: Icons.pets_rounded,
    ),
    CategoryIconOption(
      key: 'payments',
      label: 'Gaji',
      icon: Icons.payments_rounded,
    ),
    CategoryIconOption(
      key: 'storefront',
      label: 'Usaha',
      icon: Icons.storefront_rounded,
    ),
    CategoryIconOption(
      key: 'card_giftcard',
      label: 'Bonus/Hadiah',
      icon: Icons.card_giftcard_rounded,
    ),
    CategoryIconOption(
      key: 'trending_up',
      label: 'Investasi',
      icon: Icons.trending_up_rounded,
    ),
    CategoryIconOption(
      key: 'more_horiz',
      label: 'Lainnya',
      icon: Icons.category_rounded,
    ),
  ];

  static IconData forCategory(String? iconName) {
    switch (iconName) {
      case 'restaurant':
        return Icons.restaurant_rounded;
      case 'local_grocery_store':
        return Icons.local_grocery_store_rounded;
      case 'directions_car':
        return Icons.directions_car_rounded;
      case 'two_wheeler':
        return Icons.two_wheeler_rounded;
      case 'local_gas_station':
        return Icons.local_gas_station_rounded;
      case 'receipt_long':
        return Icons.receipt_long_rounded;
      case 'bolt':
        return Icons.bolt_rounded;
      case 'wifi':
        return Icons.wifi_rounded;
      case 'home':
        return Icons.home_rounded;
      case 'school':
        return Icons.school_rounded;
      case 'child_care':
        return Icons.child_care_rounded;
      case 'local_hospital':
        return Icons.local_hospital_rounded;
      case 'shopping_bag':
        return Icons.shopping_bag_rounded;
      case 'coffee':
        return Icons.coffee_rounded;
      case 'credit_card':
        return Icons.credit_card_rounded;
      case 'savings':
        return Icons.savings_rounded;
      case 'volunteer_activism':
        return Icons.volunteer_activism_rounded;
      case 'flight':
        return Icons.flight_rounded;
      case 'pets':
        return Icons.pets_rounded;
      case 'payments':
        return Icons.payments_rounded;
      case 'storefront':
        return Icons.storefront_rounded;
      case 'card_giftcard':
        return Icons.card_giftcard_rounded;
      case 'trending_up':
        return Icons.trending_up_rounded;
      case 'add_circle_outline':
        return Icons.add_circle_outline_rounded;
      case 'more_horiz':
      default:
        return Icons.category_rounded;
    }
  }

  static IconData forWalletType(String type) {
    switch (type) {
      case WalletType.cash:
        return Icons.payments_outlined;
      case WalletType.bank:
        return Icons.account_balance_outlined;
      case WalletType.ewallet:
        return Icons.account_balance_wallet_outlined;
      case WalletType.credit:
        return Icons.credit_card_outlined;
      default:
        return Icons.wallet_outlined;
    }
  }

  static const List<int> walletColorPalette = [
    0xFF0E7C66,
    0xFF1565C0,
    0xFF6A1B9A,
    0xFFE67E22,
    0xFF2E7D32,
    0xFFC0392B,
    0xFF00838F,
    0xFF455A64,
  ];

  static const List<int> categoryColorPalette = [
    0xFF0E7C66,
    0xFFE67E22,
    0xFF2980B9,
    0xFF8E44AD,
    0xFF16A085,
    0xFFE74C3C,
    0xFFD35400,
    0xFFC0392B,
    0xFF27AE60,
    0xFF1ABC9C,
    0xFF2E86C1,
    0xFF5D6D7E,
  ];
}
