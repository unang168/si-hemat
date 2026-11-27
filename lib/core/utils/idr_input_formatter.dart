import 'package:flutter/services.dart';
import 'package:si_hemat/core/utils/currency_formatter.dart';

/// Live thousand-separator formatter for Indonesian Rupiah numeric TextFields
/// (e.g. typing `1500000` displays `1.500.000` smoothly while keeping cursor intuitive).
class IdrInputFormatter extends TextInputFormatter {
  const IdrInputFormatter({this.maxDigits = 15});

  final int maxDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final rawDigits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (rawDigits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // Limit digits to avoid int overflow (15 digits = up to 999 Triliun).
    final capped = rawDigits.length > maxDigits
        ? rawDigits.substring(0, maxDigits)
        : rawDigits;

    // Count how many digits existed before the user's cursor in newValue.
    final selectionEnd = newValue.selection.end.clamp(0, newValue.text.length);
    var digitsBeforeCursor = newValue.text
        .substring(0, selectionEnd)
        .replaceAll(RegExp(r'[^0-9]'), '')
        .length;

    // Strip leading zeros except when value is simply "0".
    final parsed = int.tryParse(capped) ?? 0;
    final formatted = CurrencyFormatter.formatNumber(parsed);

    if (parsed == 0) {
      return const TextEditingValue(
        text: '0',
        selection: TextSelection.collapsed(offset: 1),
      );
    }

    // Adjust cursor offset for stripped leading zeros.
    final leadingZeros = capped.length - parsed.toString().length;
    digitsBeforeCursor = (digitsBeforeCursor - leadingZeros).clamp(
      0,
      parsed.toString().length,
    );

    // Map digit index back into formatted string index (skipping '.' separators).
    var cursorOffset = 0;
    var seenDigits = 0;
    while (cursorOffset < formatted.length && seenDigits < digitsBeforeCursor) {
      if (formatted.codeUnitAt(cursorOffset) >= 48 &&
          formatted.codeUnitAt(cursorOffset) <= 57) {
        seenDigits++;
      }
      cursorOffset++;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: cursorOffset),
    );
  }
}
