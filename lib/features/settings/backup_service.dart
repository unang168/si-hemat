import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/database/app_database.dart';
import 'package:si_hemat/core/security/secure_storage_service.dart';
import 'package:si_hemat/features/onboarding/onboarding_service.dart';

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;

  @override
  String toString() => message;
}

class BackupRestoreSummary {
  const BackupRestoreSummary({
    required this.familyName,
    required this.walletsCount,
    required this.transactionsCount,
    required this.budgetsCount,
    required this.billsCount,
  });

  final String familyName;
  final int walletsCount;
  final int transactionsCount;
  final int budgetsCount;
  final int billsCount;
}

/// Password-protected, AES-256-GCM + PBKDF2-HMAC-SHA256 encrypted full backup & restore
/// (`.sihemat`) for complete offline data portability including personal & shared records.
class BackupService {
  BackupService({
    required this.db,
    required this.keyStore,
    required this.onboarding,
  });

  final AppDatabase db;
  final SecureKeyStore keyStore;
  final OnboardingService onboarding;

  static const int _pbkdf2Iterations = 100000;
  static final AesGcm _aesGcm = AesGcm.with256bits();

  Future<SecretKey> _derivePasswordKey({
    required String password,
    required List<int> salt,
    int iterations = _pbkdf2Iterations,
  }) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return pbkdf2.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
  }

  /// Creates an encrypted `.sihemat` backup JSON string containing all family & personal
  /// SQLite records plus `family_secret` (protected by [password]).
  Future<String> createEncryptedBackupString({
    required String familyId,
    required String password,
  }) async {
    if (password.trim().length < 6) {
      throw const BackupException(
        'Kata sandi backup minimal 6 karakter agar data Anda aman.',
      );
    }

    final family = await (db.select(db.families)
          ..where((f) => f.id.equals(familyId))
          ..limit(1))
        .getSingleOrNull();
    if (family == null) {
      throw const BackupException('Data buku keluarga tidak ditemukan.');
    }

    final members = await (db.select(db.members)
          ..where((m) => m.familyId.equals(familyId)))
        .get();
    final categories = await (db.select(db.categories)
          ..where((c) => c.familyId.equals(familyId)))
        .get();
    final wallets = await (db.select(db.wallets)
          ..where((w) => w.familyId.equals(familyId)))
        .get();
    final budgets = await (db.select(db.budgets)
          ..where((b) => b.familyId.equals(familyId)))
        .get();
    final bills = await (db.select(db.recurringBills)
          ..where((b) => b.familyId.equals(familyId)))
        .get();
    final transactions = await (db.select(db.transactions)
          ..where((t) => t.familyId.equals(familyId)))
        .get();

    final familySecret = await keyStore.read(SecureStorageKeys.familySecret);
    final memberId = await keyStore.read(SecureStorageKeys.memberId);

    final clearPayload = <String, dynamic>{
      'family_secret': familySecret,
      'owner_member_id': memberId,
      'family': {
        'id': family.id,
        'name': family.name,
        'payday_day': family.paydayDay,
        'currency': family.currency,
        'created_at': family.createdAt,
        'updated_at': family.updatedAt,
        'updated_by_device_id': family.updatedByDeviceId,
        'is_deleted': family.isDeleted,
      },
      'members': members
          .map(
            (m) => {
              'id': m.id,
              'family_id': m.familyId,
              'device_id': m.deviceId,
              'name': m.name,
              'role': m.role,
              'avatar_color': m.avatarColor,
              'created_at': m.createdAt,
              'updated_at': m.updatedAt,
              'updated_by_device_id': m.updatedByDeviceId,
              'is_deleted': m.isDeleted,
            },
          )
          .toList(),
      'categories': categories
          .map(
            (c) => {
              'id': c.id,
              'family_id': c.familyId,
              'name': c.name,
              'type': c.type,
              'icon': c.icon,
              'color': c.color,
              'is_default': c.isDefault,
              'created_at': c.createdAt,
              'updated_at': c.updatedAt,
              'updated_by_device_id': c.updatedByDeviceId,
              'is_deleted': c.isDeleted,
            },
          )
          .toList(),
      'wallets': wallets
          .map(
            (w) => {
              'id': w.id,
              'family_id': w.familyId,
              'owner_member_id': w.ownerMemberId,
              'name': w.name,
              'type': w.type,
              'visibility': w.visibility,
              'initial_balance': w.initialBalance,
              'icon': w.icon,
              'color': w.color,
              'created_at': w.createdAt,
              'updated_at': w.updatedAt,
              'updated_by_device_id': w.updatedByDeviceId,
              'is_deleted': w.isDeleted,
            },
          )
          .toList(),
      'budgets': budgets
          .map(
            (b) => {
              'id': b.id,
              'family_id': b.familyId,
              'category_id': b.categoryId,
              'month_key': b.monthKey,
              'limit_amount': b.limitAmount,
              'visibility': b.visibility,
              'created_at': b.createdAt,
              'updated_at': b.updatedAt,
              'updated_by_device_id': b.updatedByDeviceId,
              'is_deleted': b.isDeleted,
            },
          )
          .toList(),
      'recurring_bills': bills
          .map(
            (b) => {
              'id': b.id,
              'family_id': b.familyId,
              'wallet_id': b.walletId,
              'category_id': b.categoryId,
              'name': b.name,
              'amount': b.amount,
              'due_day': b.dueDay,
              'start_month': b.startMonth,
              'end_month': b.endMonth,
              'last_paid_month': b.lastPaidMonth,
              'paid_months': b.paidMonths,
              'is_active': b.isActive,
              'visibility': b.visibility,
              'created_at': b.createdAt,
              'updated_at': b.updatedAt,
              'updated_by_device_id': b.updatedByDeviceId,
              'is_deleted': b.isDeleted,
            },
          )
          .toList(),
      'transactions': transactions
          .map(
            (t) => {
              'id': t.id,
              'family_id': t.familyId,
              'member_id': t.memberId,
              'wallet_id': t.walletId,
              'to_wallet_id': t.toWalletId,
              'category_id': t.categoryId,
              'type': t.type,
              'amount': t.amount,
              'date': t.date,
              'merchant': t.merchant,
              'note': t.note,
              'receipt_hash': t.receiptHash,
              'source': t.source,
              'visibility': t.visibility,
              'created_at': t.createdAt,
              'updated_at': t.updatedAt,
              'updated_by_device_id': t.updatedByDeviceId,
              'is_deleted': t.isDeleted,
            },
          )
          .toList(),
    };

    final rng = Random.secure();
    final salt = List<int>.generate(16, (_) => rng.nextInt(256));
    final key = await _derivePasswordKey(password: password, salt: salt);
    final box = await _aesGcm.encrypt(
      utf8.encode(jsonEncode(clearPayload)),
      secretKey: key,
    );

    final envelope = <String, dynamic>{
      'app': 'si_hemat_backup',
      'v': 1,
      'created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      'family_name': family.name,
      'kdf': 'pbkdf2-hmac-sha256',
      'iterations': _pbkdf2Iterations,
      'salt': base64UrlEncode(salt),
      'nonce': base64UrlEncode(box.nonce),
      'ciphertext': base64UrlEncode(box.cipherText),
      'mac': base64UrlEncode(box.mac.bytes),
    };
    return jsonEncode(envelope);
  }

  /// Writes the encrypted `.sihemat` backup file and opens Android's share sheet.
  Future<File> exportBackupAndShare({
    required String familyId,
    required String password,
  }) async {
    final encrypted = await createEncryptedBackupString(
      familyId: familyId,
      password: password,
    );
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'si_hemat_backup_$stamp.sihemat'));
    await file.writeAsString(encrypted, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/octet-stream')],
        subject: 'Backup Terenkripsi Si-Hemat ($stamp)',
      ),
    );
    return file;
  }

  /// Decrypts and atomically restores a `.sihemat` encrypted backup into local SQLite.
  Future<BackupRestoreSummary> restoreFromEncryptedBackupString({
    required String rawBackupContent,
    required String password,
  }) async {
    final Map<String, dynamic> envelope;
    try {
      final decoded = jsonDecode(rawBackupContent.trim());
      if (decoded is! Map<String, dynamic> ||
          decoded['app'] != 'si_hemat_backup') {
        throw const BackupException(
          'File bukan format backup Si-Hemat (.sihemat) yang valid.',
        );
      }
      envelope = decoded;
    } on BackupException {
      rethrow;
    } catch (_) {
      throw const BackupException('File backup rusak atau tidak terbaca.');
    }

    final Map<String, dynamic> payload;
    try {
      final salt = base64Url.decode(
        base64Url.normalize(envelope['salt'] as String),
      );
      final nonce = base64Url.decode(
        base64Url.normalize(envelope['nonce'] as String),
      );
      final cipherText = base64Url.decode(
        base64Url.normalize(envelope['ciphertext'] as String),
      );
      final macBytes = base64Url.decode(
        base64Url.normalize(envelope['mac'] as String),
      );
      final iterations = (envelope['iterations'] as int?) ?? _pbkdf2Iterations;
      final key = await _derivePasswordKey(
        password: password,
        salt: salt,
        iterations: iterations,
      );
      final clear = await _aesGcm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
        secretKey: key,
      );
      payload = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    } catch (_) {
      throw const BackupException(
        'Kata sandi backup salah atau file telah dimodifikasi.',
      );
    }

    final rawFamily = payload['family'] as Map<String, dynamic>;
    final membersList = _listOfMaps(payload['members']);
    final categoriesList = _listOfMaps(payload['categories']);
    final walletsList = _listOfMaps(payload['wallets']);
    final budgetsList = _listOfMaps(payload['budgets']);
    final billsList = _listOfMaps(payload['recurring_bills']);
    final txList = _listOfMaps(payload['transactions']);

    await db.transaction(() async {
      // Full snapshot restore: clear any existing local workspace rows atomically
      // so restoring a backup onto a device with a placeholder family switches cleanly.
      await db.delete(db.transactions).go();
      await db.delete(db.recurringBills).go();
      await db.delete(db.budgets).go();
      await db.delete(db.wallets).go();
      await db.delete(db.categories).go();
      await db.delete(db.members).go();
      await db.delete(db.families).go();
      await db.delete(db.syncPeers).go();

      await db.into(db.families).insertOnConflictUpdate(
            FamiliesCompanion.insert(
              id: rawFamily['id'] as String,
              name: rawFamily['name'] as String,
              paydayDay: Value(rawFamily['payday_day'] as int? ?? 25),
              currency: Value(rawFamily['currency'] as String? ?? 'IDR'),
              createdAt: rawFamily['created_at'] as int,
              updatedAt: rawFamily['updated_at'] as int,
              updatedByDeviceId: rawFamily['updated_by_device_id'] as String,
              isDeleted: Value(rawFamily['is_deleted'] as bool? ?? false),
            ),
          );

      for (final m in membersList) {
        await db.into(db.members).insertOnConflictUpdate(
              MembersCompanion.insert(
                id: m['id'] as String,
                familyId: m['family_id'] as String,
                deviceId: m['device_id'] as String,
                name: m['name'] as String,
                role: Value(m['role'] as String? ?? MemberRole.member),
                avatarColor: Value(m['avatar_color'] as int? ?? 0xFF0E7C66),
                createdAt: m['created_at'] as int,
                updatedAt: m['updated_at'] as int,
                updatedByDeviceId: m['updated_by_device_id'] as String,
                isDeleted: Value(m['is_deleted'] as bool? ?? false),
              ),
            );
      }

      for (final c in categoriesList) {
        await db.into(db.categories).insertOnConflictUpdate(
              CategoriesCompanion.insert(
                id: c['id'] as String,
                familyId: c['family_id'] as String,
                name: c['name'] as String,
                type: c['type'] as String,
                icon: c['icon'] as String,
                color: c['color'] as int,
                isDefault: Value(c['is_default'] as bool? ?? false),
                createdAt: c['created_at'] as int,
                updatedAt: c['updated_at'] as int,
                updatedByDeviceId: c['updated_by_device_id'] as String,
                isDeleted: Value(c['is_deleted'] as bool? ?? false),
              ),
            );
      }

      for (final w in walletsList) {
        await db.into(db.wallets).insertOnConflictUpdate(
              WalletsCompanion.insert(
                id: w['id'] as String,
                familyId: w['family_id'] as String,
                ownerMemberId: Value(w['owner_member_id'] as String?),
                name: w['name'] as String,
                type: w['type'] as String,
                visibility:
                    Value(w['visibility'] as String? ?? VisibilityScope.shared),
                initialBalance: Value(w['initial_balance'] as int? ?? 0),
                icon: Value(
                  w['icon'] as String? ?? 'account_balance_wallet',
                ),
                color: Value(w['color'] as int? ?? 0xFF0E7C66),
                createdAt: w['created_at'] as int,
                updatedAt: w['updated_at'] as int,
                updatedByDeviceId: w['updated_by_device_id'] as String,
                isDeleted: Value(w['is_deleted'] as bool? ?? false),
              ),
            );
      }

      for (final b in budgetsList) {
        await db.into(db.budgets).insertOnConflictUpdate(
              BudgetsCompanion.insert(
                id: b['id'] as String,
                familyId: b['family_id'] as String,
                categoryId: b['category_id'] as String,
                monthKey: b['month_key'] as String,
                limitAmount: b['limit_amount'] as int,
                visibility:
                    Value(b['visibility'] as String? ?? VisibilityScope.shared),
                createdAt: b['created_at'] as int,
                updatedAt: b['updated_at'] as int,
                updatedByDeviceId: b['updated_by_device_id'] as String,
                isDeleted: Value(b['is_deleted'] as bool? ?? false),
              ),
            );
      }

      for (final b in billsList) {
        await db.into(db.recurringBills).insertOnConflictUpdate(
              RecurringBillsCompanion.insert(
                id: b['id'] as String,
                familyId: b['family_id'] as String,
                walletId: Value(b['wallet_id'] as String?),
                categoryId: b['category_id'] as String,
                name: b['name'] as String,
                amount: b['amount'] as int,
                dueDay: b['due_day'] as int,
                startMonth: Value(b['start_month'] as String?),
                endMonth: Value(b['end_month'] as String?),
                lastPaidMonth: Value(b['last_paid_month'] as String?),
                paidMonths: Value(b['paid_months'] as String? ?? ''),
                isActive: Value(b['is_active'] as bool? ?? true),
                visibility:
                    Value(b['visibility'] as String? ?? VisibilityScope.shared),
                createdAt: b['created_at'] as int,
                updatedAt: b['updated_at'] as int,
                updatedByDeviceId: b['updated_by_device_id'] as String,
                isDeleted: Value(b['is_deleted'] as bool? ?? false),
              ),
            );
      }

      for (final t in txList) {
        await db.into(db.transactions).insertOnConflictUpdate(
              TransactionsCompanion.insert(
                id: t['id'] as String,
                familyId: t['family_id'] as String,
                memberId: t['member_id'] as String,
                walletId: t['wallet_id'] as String,
                toWalletId: Value(t['to_wallet_id'] as String?),
                categoryId: Value(t['category_id'] as String?),
                type: t['type'] as String,
                amount: t['amount'] as int,
                date: t['date'] as int,
                merchant: Value(t['merchant'] as String?),
                note: Value(t['note'] as String?),
                receiptHash: Value(t['receipt_hash'] as String?),
                source: Value(
                  t['source'] as String? ?? TransactionSource.manual,
                ),
                visibility:
                    Value(t['visibility'] as String? ?? VisibilityScope.shared),
                createdAt: t['created_at'] as int,
                updatedAt: t['updated_at'] as int,
                updatedByDeviceId: t['updated_by_device_id'] as String,
                isDeleted: Value(t['is_deleted'] as bool? ?? false),
              ),
            );
      }
    });

    await onboarding.getOrCreateDeviceId();
    await keyStore.write(
      SecureStorageKeys.familyId,
      rawFamily['id'] as String,
    );
    final ownerMemberId = payload['owner_member_id'] as String?;
    if (ownerMemberId != null && ownerMemberId.isNotEmpty) {
      await keyStore.write(SecureStorageKeys.memberId, ownerMemberId);
    }
    final familySecret = payload['family_secret'] as String?;
    if (familySecret != null && familySecret.isNotEmpty) {
      await keyStore.write(SecureStorageKeys.familySecret, familySecret);
    }

    return BackupRestoreSummary(
      familyName: rawFamily['name'] as String,
      walletsCount: walletsList.where((w) => w['is_deleted'] != true).length,
      transactionsCount: txList.where((t) => t['is_deleted'] != true).length,
      budgetsCount: budgetsList.where((b) => b['is_deleted'] != true).length,
      billsCount: billsList.where((b) => b['is_deleted'] != true).length,
    );
  }

  List<Map<String, dynamic>> _listOfMaps(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList();
  }
}
