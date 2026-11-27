import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/core/security/secure_storage_service.dart';
import 'package:si_hemat/core/utils/currency_formatter.dart';
import 'package:si_hemat/core/utils/date_formatter.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

enum BillReminderKind {
  twoDaysBefore, // H-2
  dueToday, // Hari-H
}

class PlannedBillReminder {
  const PlannedBillReminder({
    required this.notificationId,
    required this.billId,
    required this.billName,
    required this.monthKey,
    required this.kind,
    required this.scheduledAt,
    required this.dueDate,
    required this.title,
    required this.body,
  });

  final int notificationId;
  final String billId;
  final String billName;
  final String monthKey;
  final BillReminderKind kind;
  final DateTime scheduledAt;
  final DateTime dueDate;
  final String title;
  final String body;
}

class BillNotificationSettings {
  const BillNotificationSettings({
    required this.enabled,
    required this.hour,
    this.exactAlarmAllowed = true,
  });

  final bool enabled;
  final int hour;
  final bool exactAlarmAllowed;
}

/// Pure, deterministic scheduler logic for H-2 and Hari-H recurring bill reminders.
class BillNotificationPlanner {
  BillNotificationPlanner._();

  /// Computes all upcoming H-2 (2 days before due date) and Hari-H (due date)
  /// reminders across the current month and next month for active, unpaid bills.
  static List<PlannedBillReminder> planReminders({
    required List<RecurringBill> bills,
    required DateTime now,
    int reminderHour = 8,
    int reminderMinute = 0,
  }) {
    final planned = <PlannedBillReminder>[];
    final clampedHour = reminderHour.clamp(0, 23);
    final clampedMin = reminderMinute.clamp(0, 59);
    final targetMonths = [
      DateTime(now.year, now.month, 1),
      DateTime(now.year, now.month + 1, 1),
    ];

    for (final bill in bills) {
      if (bill.isDeleted || !bill.isActive) continue;
      final paidSet = AppDatabase.parsePaidMonths(bill);

      for (final monthStart in targetMonths) {
        final mKey = DateFormatter.monthKey(monthStart);
        if (bill.startMonth != null &&
            bill.startMonth!.isNotEmpty &&
            mKey.compareTo(bill.startMonth!) < 0) {
          continue;
        }
        if (bill.endMonth != null &&
            bill.endMonth!.isNotEmpty &&
            mKey.compareTo(bill.endMonth!) > 0) {
          continue;
        }
        if (paidSet.contains(mKey)) continue;

        final lastDay = DateTime(monthStart.year, monthStart.month + 1, 0).day;
        final dueDate = DateTime(
          monthStart.year,
          monthStart.month,
          bill.dueDay.clamp(1, lastDay),
        );

        final h2Date = dueDate.subtract(const Duration(days: 2));
        final h2Time = DateTime(
          h2Date.year,
          h2Date.month,
          h2Date.day,
          clampedHour,
          clampedMin,
        );
        if (h2Time.isAfter(now)) {
          planned.add(
            PlannedBillReminder(
              notificationId: stableNotificationId(
                billId: bill.id,
                monthKey: mKey,
                kind: BillReminderKind.twoDaysBefore,
              ),
              billId: bill.id,
              billName: bill.name,
              monthKey: mKey,
              kind: BillReminderKind.twoDaysBefore,
              scheduledAt: h2Time,
              dueDate: dueDate,
              title: 'Pengingat Tagihan (H-2): ${bill.name}',
              body:
                  'Jatuh tempo 2 hari lagi (${DateFormatter.formatShortDate(dueDate)}) • ${CurrencyFormatter.formatIdr(bill.amount)}.',
            ),
          );
        }

        final dueTime = DateTime(
          dueDate.year,
          dueDate.month,
          dueDate.day,
          clampedHour,
          clampedMin,
        );
        if (dueTime.isAfter(now)) {
          planned.add(
            PlannedBillReminder(
              notificationId: stableNotificationId(
                billId: bill.id,
                monthKey: mKey,
                kind: BillReminderKind.dueToday,
              ),
              billId: bill.id,
              billName: bill.name,
              monthKey: mKey,
              kind: BillReminderKind.dueToday,
              scheduledAt: dueTime,
              dueDate: dueDate,
              title: 'Jatuh Tempo Hari Ini: ${bill.name}',
              body:
                  'Tagihan ${bill.name} (${CurrencyFormatter.formatIdr(bill.amount)}) jatuh tempo hari ini. Tap untuk catat lunas.',
            ),
          );
        }
      }
    }

    planned.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return planned;
  }

  /// Generates a deterministic positive 31-bit integer ID for Android NotificationManager.
  static int stableNotificationId({
    required String billId,
    required String monthKey,
    required BillReminderKind kind,
  }) {
    final input = utf8.encode('$billId|$monthKey|${kind.name}');
    var hash = 0x811c9dc5;
    for (final b in input) {
      hash ^= b;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }
}

/// Manages 100% offline Android scheduled local notifications for recurring bills
/// (fires even when the app is closed and survives phone reboots).
class BillNotificationService {
  BillNotificationService({
    required this.db,
    required this.keyStore,
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final AppDatabase db;
  final SecureKeyStore keyStore;
  final FlutterLocalNotificationsPlugin _plugin;

  bool _initialized = false;
  String _iconName = 'ic_stat_sihemat';
  String? _lastInitError;
  static bool _tzInitialized = false;

  static const String _channelId = 'si_hemat_bill_reminders';
  static const String _channelName = 'Pengingat Tagihan Rutin';
  static const String _channelDesc =
      'Notifikasi pengingat tagihan H-2 (2 hari sebelum) dan Hari-H jatuh tempo.';

  Future<bool> initialize() async {
    if (_initialized) return true;
    _ensureTimezoneConfigured();
    _lastInitError = null;

    // Try dedicated monochrome status bar icon first; gracefully fall back to @mipmap/ic_launcher.
    for (final candidateIcon in const ['ic_stat_sihemat', '@mipmap/ic_launcher']) {
      try {
        final androidSettings = AndroidInitializationSettings(candidateIcon);
        final initSettings = InitializationSettings(android: androidSettings);
        await _plugin.initialize(settings: initSettings);

        final androidImpl = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        await androidImpl?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDesc,
            importance: Importance.high,
            playSound: true,
            enableVibration: true,
          ),
        );

        _iconName = candidateIcon;
        _initialized = true;
        return true;
      } on MissingPluginException catch (e) {
        // Expected in headless unit/widget tests.
        _lastInitError = e.message;
        return false;
      } catch (e) {
        _lastInitError = e.toString();
      }
    }
    return false;
  }

  void _ensureTimezoneConfigured() {
    if (_tzInitialized) return;
    try {
      tz_data.initializeTimeZones();
      final localOffset = DateTime.now().timeZoneOffset;
      tz.Location? matched;

      // Prefer exact Indonesian zones for WIB/WITA/WIT before general offset search.
      const preferredZones = [
        'Asia/Jakarta',
        'Asia/Makassar',
        'Asia/Jayapura',
      ];
      for (final name in preferredZones) {
        final loc = tz.timeZoneDatabase.locations[name];
        if (loc != null && loc.currentTimeZone.offset == localOffset) {
          matched = loc;
          break;
        }
      }
      matched ??= tz.timeZoneDatabase.locations.values
          .where((loc) => loc.currentTimeZone.offset == localOffset)
          .firstOrNull;
      if (matched != null) {
        tz.setLocalLocation(matched);
      }
      _tzInitialized = true;
    } catch (_) {}
  }

  Future<BillNotificationSettings> loadSettings() async {
    final enabledRaw =
        await keyStore.read(SecureStorageKeys.billNotificationsEnabled);
    final hourRaw =
        await keyStore.read(SecureStorageKeys.billNotificationHour);
    final enabled = enabledRaw != 'false'; // Enabled by default
    final hour = int.tryParse(hourRaw ?? '') ?? 8;
    final exactAllowed = await canScheduleExactAlarms();
    return BillNotificationSettings(
      enabled: enabled,
      hour: hour.clamp(0, 23),
      exactAlarmAllowed: exactAllowed,
    );
  }

  Future<bool> canScheduleExactAlarms() async {
    try {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await androidImpl?.canScheduleExactNotifications() ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<bool> requestPermissions() async {
    final ok = await initialize();
    if (!ok) return false;
    try {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final notifGranted =
          await androidImpl?.requestNotificationsPermission() ?? true;
      return notifGranted;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestExactAlarmPermission() async {
    await initialize();
    try {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await androidImpl?.requestExactAlarmsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setEnabled({
    required bool enabled,
    String? familyId,
  }) async {
    await keyStore.write(
      SecureStorageKeys.billNotificationsEnabled,
      enabled ? 'true' : 'false',
    );
    if (enabled) {
      await requestPermissions();
      if (familyId != null) {
        await rescheduleAllForFamily(familyId);
      }
    } else {
      await cancelAllScheduled();
    }
  }

  Future<void> setReminderHour({
    required int hour,
    String? familyId,
  }) async {
    await keyStore.write(
      SecureStorageKeys.billNotificationHour,
      hour.clamp(0, 23).toString(),
    );
    if (familyId != null) {
      await rescheduleAllForFamily(familyId);
    }
  }

  Future<void> cancelAllScheduled() async {
    final ok = await initialize();
    if (!ok) return;
    try {
      await _plugin.cancelAllPendingNotifications();
    } catch (_) {}
  }

  NotificationDetails _buildNotificationDetails() {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        icon: _iconName,
        playSound: true,
        enableVibration: true,
      ),
    );
  }

  /// Recomputes and reschedules all upcoming H-2 and Hari-H reminders for [familyId].
  /// Returns the number of scheduled reminders.
  Future<int> rescheduleAllForFamily(String familyId) async {
    final settings = await loadSettings();
    final ok = await initialize();
    if (!ok) return 0;

    try {
      await _plugin.cancelAllPendingNotifications();
    } catch (_) {
      return 0;
    }
    if (!settings.enabled) return 0;

    final allBills = await (db.select(db.recurringBills)
          ..where((b) => b.familyId.equals(familyId)))
        .get();
    final reminders = BillNotificationPlanner.planReminders(
      bills: allBills,
      now: DateTime.now(),
      reminderHour: settings.hour,
    );

    var scheduleMode = settings.exactAlarmAllowed
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
    final details = _buildNotificationDetails();

    var scheduledCount = 0;
    for (final r in reminders) {
      try {
        final tzDate = tz.TZDateTime.from(r.scheduledAt.toUtc(), tz.local);
        await _plugin.zonedSchedule(
          id: r.notificationId,
          title: r.title,
          body: r.body,
          scheduledDate: tzDate,
          notificationDetails: details,
          androidScheduleMode: scheduleMode,
          payload: 'bill:${r.billId}:${r.monthKey}',
        );
        scheduledCount++;
      } catch (_) {
        if (scheduleMode != AndroidScheduleMode.inexactAllowWhileIdle) {
          scheduleMode = AndroidScheduleMode.inexactAllowWhileIdle;
          try {
            final tzDate = tz.TZDateTime.from(r.scheduledAt.toUtc(), tz.local);
            await _plugin.zonedSchedule(
              id: r.notificationId,
              title: r.title,
              body: r.body,
              scheduledDate: tzDate,
              notificationDetails: details,
              androidScheduleMode: scheduleMode,
              payload: 'bill:${r.billId}:${r.monthKey}',
            );
            scheduledCount++;
          } catch (_) {}
        }
      }
    }
    return scheduledCount;
  }

  /// Returns the planned upcoming H-2 & Hari-H reminders for UI display.
  Future<List<PlannedBillReminder>> previewUpcomingReminders(
    String familyId,
  ) async {
    final settings = await loadSettings();
    if (!settings.enabled) return const [];
    final allBills = await (db.select(db.recurringBills)
          ..where((b) => b.familyId.equals(familyId)))
        .get();
    return BillNotificationPlanner.planReminders(
      bills: allBills,
      now: DateTime.now(),
      reminderHour: settings.hour,
    );
  }

  /// Schedules a real AlarmManager background test notification [seconds] from now
  /// using the exact same `zonedSchedule` pipeline as H-2 & Hari-H bill reminders.
  Future<({DateTime scheduledAt, bool exact})> scheduleTestNotificationInSeconds({
    int seconds = 15,
  }) async {
    final granted = await requestPermissions();
    if (!_initialized) {
      throw StateError(
        'Layanan notifikasi gagal diinisialisasi${_lastInitError != null ? ': $_lastInitError' : '.'}',
      );
    }
    if (!granted) {
      throw StateError(
        'Izin notifikasi HP belum diaktifkan. Aktifkan izin Notifikasi untuk Si-Hemat di Setelan Aplikasi HP Anda.',
      );
    }

    final exactAllowed = await canScheduleExactAlarms();
    final target = DateTime.now().add(Duration(seconds: seconds));
    final tzDate = tz.TZDateTime.from(target.toUtc(), tz.local);
    final details = _buildNotificationDetails();

    var usedExact = exactAllowed;
    try {
      await _plugin.zonedSchedule(
        id: 999902,
        title: 'Tes Alarm Background Si-Hemat Berhasil!',
        body:
            'Alarm terjadwal bekerja normal meski aplikasi tertutup. Pengingat H-2 & Hari-H akan muncul tepat waktu.',
        scheduledDate: tzDate,
        notificationDetails: details,
        androidScheduleMode: exactAllowed
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'test_scheduled',
      );
    } catch (_) {
      usedExact = false;
      await _plugin.zonedSchedule(
        id: 999902,
        title: 'Tes Alarm Background Si-Hemat Berhasil!',
        body:
            'Alarm terjadwal bekerja normal meski aplikasi tertutup. Pengingat H-2 & Hari-H akan muncul tepat waktu.',
        scheduledDate: tzDate,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'test_scheduled',
      );
    }
    return (scheduledAt: target, exact: usedExact);
  }

  /// Sends an immediate test notification AND throws a descriptive error if
  /// initialization or permission failed so the UI never fails silently.
  Future<void> sendTestNotification() async {
    final granted = await requestPermissions();
    if (!_initialized) {
      throw StateError(
        'Layanan notifikasi gagal diinisialisasi${_lastInitError != null ? ': $_lastInitError' : '.'}',
      );
    }
    if (!granted) {
      throw StateError(
        'Izin notifikasi HP belum diaktifkan. Aktifkan izin Notifikasi untuk Si-Hemat di Setelan Aplikasi HP Anda.',
      );
    }
    await _plugin.show(
      id: 999901,
      title: 'Pengingat Tagihan Si-Hemat Aktif',
      body:
          'Notifikasi H-2 (2 hari sebelum) & Hari-H jatuh tempo siap mengingatkan Anda meski aplikasi tertutup.',
      notificationDetails: _buildNotificationDetails(),
      payload: 'test',
    );
  }
}
