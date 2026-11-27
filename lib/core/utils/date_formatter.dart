import 'package:intl/intl.dart';

class DateFormatter {
  DateFormatter._();

  static const int endOfMonthPayday = 31;

  static String monthKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$y-$m';
  }

  static String formatShortDate(DateTime date) {
    return DateFormat('d MMM yyyy', 'id_ID').format(date);
  }

  static String formatPaydayShort(DateTime date) {
    return DateFormat('EEE, d MMM', 'id_ID').format(date);
  }

  static String formatMonthYear(DateTime date) {
    return DateFormat('MMMM yyyy', 'id_ID').format(date);
  }

  static String formatDayHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = today.difference(target).inDays;
    if (diff == 0) return 'Hari Ini';
    if (diff == 1) return 'Kemarin';
    return DateFormat('EEEE, d MMM yyyy', 'id_ID').format(date);
  }

  static bool isSameMonth(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month;
  }

  static String formatRelativeTime(int epochMs, {DateTime? now}) {
    if (epochMs <= 0) return 'Belum pernah';
    final current = now ?? DateTime.now();
    final target =
        DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true).toLocal();
    final diff = current.difference(target);
    if (diff.inSeconds < 60) return 'Baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
    if (diff.inHours < 24) return '${diff.inHours} jam lalu';
    if (diff.inDays < 7) return '${diff.inDays} hari lalu';
    return DateFormat('d MMM yyyy, HH:mm', 'id_ID').format(target);
  }

  static String paydayOptionLabel(int day) {
    if (day >= endOfMonthPayday) {
      return 'Akhir bulan (tgl 28/29/30/31)';
    }
    return 'Setiap tanggal $day';
  }

  /// Returns the effective payday date for a specific [year] and [month].
  /// - [paydayDay] accepts 1..31 (31 = end of month, automatically clamped to 28/29/30/31).
  /// - If the date falls on Saturday or Sunday, it shifts earlier to Friday.
  static DateTime effectivePaydayForMonth(
    int year,
    int month,
    int paydayDay, {
    bool adjustWeekendToFriday = true,
  }) {
    final lastDayOfMonth = DateTime(year, month + 1, 0).day;
    final day = paydayDay.clamp(1, lastDayOfMonth);
    var payday = DateTime(year, month, day);

    if (adjustWeekendToFriday) {
      if (payday.weekday == DateTime.saturday) {
        payday = payday.subtract(const Duration(days: 1));
      } else if (payday.weekday == DateTime.sunday) {
        payday = payday.subtract(const Duration(days: 2));
      }
    }
    return payday;
  }

  /// Finds the next strictly future payday date after [now]'s calendar date.
  static DateTime nextPaydayDate(
    DateTime now,
    int paydayDay, {
    bool adjustWeekendToFriday = true,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    for (var monthOffset = 0; monthOffset <= 2; monthOffset++) {
      final candidate = effectivePaydayForMonth(
        today.year,
        today.month + monthOffset,
        paydayDay,
        adjustWeekendToFriday: adjustWeekendToFriday,
      );
      if (candidate.isAfter(today)) {
        return candidate;
      }
    }
    return effectivePaydayForMonth(
      today.year,
      today.month + 1,
      paydayDay,
      adjustWeekendToFriday: adjustWeekendToFriday,
    );
  }

  /// Calculates remaining days (at least 1) until the next effective payday.
  static int daysUntilNextPayday(
    DateTime now,
    int paydayDay, {
    bool adjustWeekendToFriday = true,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final next = nextPaydayDate(
      today,
      paydayDay,
      adjustWeekendToFriday: adjustWeekendToFriday,
    );
    final days = next.difference(today).inDays;
    return days < 1 ? 1 : days;
  }
}
