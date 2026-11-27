import 'package:intl/intl.dart';

/// Deterministic Indonesian Rupiah currency formatting and parsing helpers.
class CurrencyFormatter {
  CurrencyFormatter._();

  static final NumberFormat _idrFormat = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  static final NumberFormat _numberFormat = NumberFormat.decimalPattern('id_ID');

  static String formatIdr(int amount, {bool hide = false}) {
    if (hide) return 'Rp ••••••';
    return _idrFormat.format(amount);
  }

  static String formatSignedIdr(int amount, {bool hide = false}) {
    if (hide) return 'Rp ••••••';
    final prefix = amount > 0 ? '+' : '';
    return '$prefix${_idrFormat.format(amount)}';
  }

  static String formatCompactIdr(int amount, {bool hide = false}) {
    if (hide) return 'Rp •••';
    final abs = amount.abs();
    final sign = amount < 0 ? '-' : '';
    if (abs >= 1000000000) {
      return '${sign}Rp ${(abs / 1000000000).toStringAsFixed(1).replaceAll('.', ',')} M';
    }
    if (abs >= 1000000) {
      return '${sign}Rp ${(abs / 1000000).toStringAsFixed(1).replaceAll('.', ',')} jt';
    }
    if (abs >= 1000) {
      return '${sign}Rp ${_numberFormat.format(abs ~/ 1000)} rb';
    }
    return _idrFormat.format(amount);
  }

  static String formatNumber(int amount) {
    return _numberFormat.format(amount);
  }

  static String formatShortAxisIdr(double value) {
    final abs = value.abs();
    if (abs <= 0) return '0';
    if (abs >= 1000000000) {
      final v = abs / 1000000000;
      return '${v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1).replaceAll('.0', '').replaceAll('.', ',')} M';
    }
    if (abs >= 1000000) {
      final v = abs / 1000000;
      return '${v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1).replaceAll('.0', '').replaceAll('.', ',')} jt';
    }
    if (abs >= 1000) {
      return '${(abs / 1000).round()} rb';
    }
    return abs.round().toString();
  }

  /// Parses strings like "150.000", "Rp 150.000", or "150000" into integer Rupiah.
  static int? parseIdr(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }
}
