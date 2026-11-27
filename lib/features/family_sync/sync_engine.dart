import 'package:drift/drift.dart';
import 'package:si_hemat/core/constants/sync_constants.dart';
import 'package:si_hemat/core/database/app_database.dart';

class SyncMergeStats {
  const SyncMergeStats({
    required this.applied,
    required this.skipped,
  });

  final int applied;
  final int skipped;
}

class SyncPayloadSummary {
  const SyncPayloadSummary({
    required this.payload,
    required this.recordCount,
  });

  final Map<String, dynamic> payload;
  final int recordCount;
}

/// Offline-first Delta Export & Conflict-Free Last-Write-Wins (LWW) Merge Engine.
/// Strictly exports ONLY `visibility = shared` wallets, transactions, budgets, and bills;
/// personal data never leaves the owner's device.
class SyncEngine {
  SyncEngine(this.db);

  final AppDatabase db;

  /// Exports all shared records for [familyId] with `updatedAt > sinceTimestamp`.
  Future<SyncPayloadSummary> exportSharedDelta({
    required String familyId,
    required int sinceTimestamp,
  }) async {
    final family = await (db.select(db.families)
          ..where((f) => f.id.equals(familyId))
          ..limit(1))
        .getSingleOrNull();

    final members = await (db.select(db.members)
          ..where(
            (m) =>
                m.familyId.equals(familyId) &
                m.updatedAt.isBiggerThanValue(sinceTimestamp),
          ))
        .get();

    final categories = await (db.select(db.categories)
          ..where(
            (c) =>
                c.familyId.equals(familyId) &
                c.updatedAt.isBiggerThanValue(sinceTimestamp),
          ))
        .get();

    final wallets = await (db.select(db.wallets)
          ..where(
            (w) =>
                w.familyId.equals(familyId) &
                w.visibility.equals(VisibilityScope.shared) &
                w.updatedAt.isBiggerThanValue(sinceTimestamp),
          ))
        .get();

    final budgets = await (db.select(db.budgets)
          ..where(
            (b) =>
                b.familyId.equals(familyId) &
                b.visibility.equals(VisibilityScope.shared) &
                b.updatedAt.isBiggerThanValue(sinceTimestamp),
          ))
        .get();

    final bills = await (db.select(db.recurringBills)
          ..where(
            (b) =>
                b.familyId.equals(familyId) &
                b.visibility.equals(VisibilityScope.shared) &
                b.updatedAt.isBiggerThanValue(sinceTimestamp),
          ))
        .get();

    final transactions = await (db.select(db.transactions)
          ..where(
            (t) =>
                t.familyId.equals(familyId) &
                t.visibility.equals(VisibilityScope.shared) &
                t.updatedAt.isBiggerThanValue(sinceTimestamp),
          ))
        .get();

    final includeFamily = family != null && family.updatedAt > sinceTimestamp;
    final totalCount = (includeFamily ? 1 : 0) +
        members.length +
        categories.length +
        wallets.length +
        budgets.length +
        bills.length +
        transactions.length;

    final payload = <String, dynamic>{
      'v': SyncConstants.protocolVersion,
      'family_id': familyId,
      'exported_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      'family': includeFamily ? _encodeFamily(family) : null,
      'members': members.map(_encodeMember).toList(),
      'categories': categories.map(_encodeCategory).toList(),
      'wallets': wallets.map(_encodeWallet).toList(),
      'budgets': budgets.map(_encodeBudget).toList(),
      'recurring_bills': bills.map(_encodeBill).toList(),
      'transactions': transactions.map(_encodeTransaction).toList(),
    };

    return SyncPayloadSummary(payload: payload, recordCount: totalCount);
  }

  /// Atomically merges an incoming decrypted delta payload into local SQLite using
  /// Last-Write-Wins (`updatedAt` + deterministic `updatedByDeviceId` tie-breaker)
  /// and set-union merging for `recurring_bills.paidMonths`.
  Future<SyncMergeStats> mergeSharedDelta({
    required String expectedFamilyId,
    required Map<String, dynamic> payload,
  }) async {
    if (payload['family_id'] != expectedFamilyId) {
      throw ArgumentError('family_id pada payload tidak cocok.');
    }

    var applied = 0;
    var skipped = 0;

    await db.transaction(() async {
      // 1. Family metadata
      final rawFamily = payload['family'];
      if (rawFamily is Map<String, dynamic>) {
        final local = await (db.select(db.families)
              ..where((f) => f.id.equals(rawFamily['id'] as String))
              ..limit(1))
            .getSingleOrNull();
        if (local == null ||
            _incomingWins(
              incomingTs: rawFamily['updated_at'] as int,
              incomingDevice: rawFamily['updated_by_device_id'] as String,
              localTs: local.updatedAt,
              localDevice: local.updatedByDeviceId,
            )) {
          await db.into(db.families).insertOnConflictUpdate(
                FamiliesCompanion.insert(
                  id: rawFamily['id'] as String,
                  name: rawFamily['name'] as String,
                  paydayDay: Value(rawFamily['payday_day'] as int),
                  currency: Value(rawFamily['currency'] as String? ?? 'IDR'),
                  createdAt: rawFamily['created_at'] as int,
                  updatedAt: rawFamily['updated_at'] as int,
                  updatedByDeviceId: rawFamily['updated_by_device_id'] as String,
                  isDeleted: Value(rawFamily['is_deleted'] as bool? ?? false),
                ),
              );
          applied++;
        } else {
          skipped++;
        }
      }

      // 2. Members
      for (final raw in _listOfMaps(payload['members'])) {
        final id = raw['id'] as String;
        final local = await (db.select(db.members)
              ..where((m) => m.id.equals(id))
              ..limit(1))
            .getSingleOrNull();
        if (local == null ||
            _incomingWins(
              incomingTs: raw['updated_at'] as int,
              incomingDevice: raw['updated_by_device_id'] as String,
              localTs: local.updatedAt,
              localDevice: local.updatedByDeviceId,
            )) {
          await db.into(db.members).insertOnConflictUpdate(
                MembersCompanion.insert(
                  id: id,
                  familyId: raw['family_id'] as String,
                  deviceId: raw['device_id'] as String,
                  name: raw['name'] as String,
                  role: Value(raw['role'] as String? ?? MemberRole.member),
                  avatarColor: Value(raw['avatar_color'] as int? ?? 0xFF0E7C66),
                  createdAt: raw['created_at'] as int,
                  updatedAt: raw['updated_at'] as int,
                  updatedByDeviceId: raw['updated_by_device_id'] as String,
                  isDeleted: Value(raw['is_deleted'] as bool? ?? false),
                ),
              );
          applied++;
        } else {
          skipped++;
        }
      }

      // 3. Categories
      for (final raw in _listOfMaps(payload['categories'])) {
        final id = raw['id'] as String;
        final local = await (db.select(db.categories)
              ..where((c) => c.id.equals(id))
              ..limit(1))
            .getSingleOrNull();
        if (local == null ||
            _incomingWins(
              incomingTs: raw['updated_at'] as int,
              incomingDevice: raw['updated_by_device_id'] as String,
              localTs: local.updatedAt,
              localDevice: local.updatedByDeviceId,
            )) {
          await db.into(db.categories).insertOnConflictUpdate(
                CategoriesCompanion.insert(
                  id: id,
                  familyId: raw['family_id'] as String,
                  name: raw['name'] as String,
                  type: raw['type'] as String,
                  icon: raw['icon'] as String,
                  color: raw['color'] as int,
                  isDefault: Value(raw['is_default'] as bool? ?? false),
                  createdAt: raw['created_at'] as int,
                  updatedAt: raw['updated_at'] as int,
                  updatedByDeviceId: raw['updated_by_device_id'] as String,
                  isDeleted: Value(raw['is_deleted'] as bool? ?? false),
                ),
              );
          applied++;
        } else {
          skipped++;
        }
      }

      // 4. Shared Wallets only
      for (final raw in _listOfMaps(payload['wallets'])) {
        if (raw['visibility'] != VisibilityScope.shared) continue;
        final id = raw['id'] as String;
        final local = await (db.select(db.wallets)
              ..where((w) => w.id.equals(id))
              ..limit(1))
            .getSingleOrNull();
        if (local == null ||
            _incomingWins(
              incomingTs: raw['updated_at'] as int,
              incomingDevice: raw['updated_by_device_id'] as String,
              localTs: local.updatedAt,
              localDevice: local.updatedByDeviceId,
            )) {
          await db.into(db.wallets).insertOnConflictUpdate(
                WalletsCompanion.insert(
                  id: id,
                  familyId: raw['family_id'] as String,
                  ownerMemberId: Value(raw['owner_member_id'] as String?),
                  name: raw['name'] as String,
                  type: raw['type'] as String,
                  visibility: const Value(VisibilityScope.shared),
                  initialBalance: Value(raw['initial_balance'] as int? ?? 0),
                  icon: Value(
                    raw['icon'] as String? ?? 'account_balance_wallet',
                  ),
                  color: Value(raw['color'] as int? ?? 0xFF0E7C66),
                  createdAt: raw['created_at'] as int,
                  updatedAt: raw['updated_at'] as int,
                  updatedByDeviceId: raw['updated_by_device_id'] as String,
                  isDeleted: Value(raw['is_deleted'] as bool? ?? false),
                ),
              );
          applied++;
        } else {
          skipped++;
        }
      }

      // 5. Shared Budgets
      for (final raw in _listOfMaps(payload['budgets'])) {
        if (raw['visibility'] != VisibilityScope.shared) continue;
        final id = raw['id'] as String;
        final local = await (db.select(db.budgets)
              ..where((b) => b.id.equals(id))
              ..limit(1))
            .getSingleOrNull();
        if (local == null ||
            _incomingWins(
              incomingTs: raw['updated_at'] as int,
              incomingDevice: raw['updated_by_device_id'] as String,
              localTs: local.updatedAt,
              localDevice: local.updatedByDeviceId,
            )) {
          await db.into(db.budgets).insertOnConflictUpdate(
                BudgetsCompanion.insert(
                  id: id,
                  familyId: raw['family_id'] as String,
                  categoryId: raw['category_id'] as String,
                  monthKey: raw['month_key'] as String,
                  limitAmount: raw['limit_amount'] as int,
                  visibility: const Value(VisibilityScope.shared),
                  createdAt: raw['created_at'] as int,
                  updatedAt: raw['updated_at'] as int,
                  updatedByDeviceId: raw['updated_by_device_id'] as String,
                  isDeleted: Value(raw['is_deleted'] as bool? ?? false),
                ),
              );
          applied++;
        } else {
          skipped++;
        }
      }

      // 6. Shared Recurring Bills (with union merge on paidMonths!)
      for (final raw in _listOfMaps(payload['recurring_bills'])) {
        if (raw['visibility'] != VisibilityScope.shared) continue;
        final id = raw['id'] as String;
        final local = await (db.select(db.recurringBills)
              ..where((b) => b.id.equals(id))
              ..limit(1))
            .getSingleOrNull();

        final incomingPaid = _parsePaidString(
          raw['paid_months'] as String? ?? '',
          raw['last_paid_month'] as String?,
        );
        final localPaid =
            local != null ? AppDatabase.parsePaidMonths(local) : <String>{};
        final unionPaid = {...localPaid, ...incomingPaid}.toList()..sort();
        final mergedPaidStr = unionPaid.join(',');
        final mergedLastPaid = unionPaid.isNotEmpty ? unionPaid.last : null;

        final wins = local == null ||
            _incomingWins(
              incomingTs: raw['updated_at'] as int,
              incomingDevice: raw['updated_by_device_id'] as String,
              localTs: local.updatedAt,
              localDevice: local.updatedByDeviceId,
            );

        if (wins) {
          await db.into(db.recurringBills).insertOnConflictUpdate(
                RecurringBillsCompanion.insert(
                  id: id,
                  familyId: raw['family_id'] as String,
                  walletId: Value(raw['wallet_id'] as String?),
                  categoryId: raw['category_id'] as String,
                  name: raw['name'] as String,
                  amount: raw['amount'] as int,
                  dueDay: raw['due_day'] as int,
                  startMonth: Value(raw['start_month'] as String?),
                  endMonth: Value(raw['end_month'] as String?),
                  lastPaidMonth: Value(mergedLastPaid),
                  paidMonths: Value(mergedPaidStr),
                  isActive: Value(raw['is_active'] as bool? ?? true),
                  visibility: const Value(VisibilityScope.shared),
                  createdAt: raw['created_at'] as int,
                  updatedAt: raw['updated_at'] as int,
                  updatedByDeviceId: raw['updated_by_device_id'] as String,
                  isDeleted: Value(raw['is_deleted'] as bool? ?? false),
                ),
              );
          applied++;
        } else if (mergedPaidStr != local.paidMonths) {
          // Even if local metadata is newer, never lose paid months reported by peer
          await (db.update(db.recurringBills)..where((b) => b.id.equals(id)))
              .write(
            RecurringBillsCompanion(
              paidMonths: Value(mergedPaidStr),
              lastPaidMonth: Value(mergedLastPaid),
            ),
          );
          applied++;
        } else {
          skipped++;
        }
      }

      // 7. Shared Transactions
      for (final raw in _listOfMaps(payload['transactions'])) {
        if (raw['visibility'] != VisibilityScope.shared) continue;
        final id = raw['id'] as String;
        final local = await (db.select(db.transactions)
              ..where((t) => t.id.equals(id))
              ..limit(1))
            .getSingleOrNull();
        if (local == null ||
            _incomingWins(
              incomingTs: raw['updated_at'] as int,
              incomingDevice: raw['updated_by_device_id'] as String,
              localTs: local.updatedAt,
              localDevice: local.updatedByDeviceId,
            )) {
          await db.into(db.transactions).insertOnConflictUpdate(
                TransactionsCompanion.insert(
                  id: id,
                  familyId: raw['family_id'] as String,
                  memberId: raw['member_id'] as String,
                  walletId: raw['wallet_id'] as String,
                  toWalletId: Value(raw['to_wallet_id'] as String?),
                  categoryId: Value(raw['category_id'] as String?),
                  type: raw['type'] as String,
                  amount: raw['amount'] as int,
                  date: raw['date'] as int,
                  merchant: Value(raw['merchant'] as String?),
                  note: Value(raw['note'] as String?),
                  receiptHash: Value(raw['receipt_hash'] as String?),
                  source: Value(
                    raw['source'] as String? ?? TransactionSource.manual,
                  ),
                  visibility: const Value(VisibilityScope.shared),
                  createdAt: raw['created_at'] as int,
                  updatedAt: raw['updated_at'] as int,
                  updatedByDeviceId: raw['updated_by_device_id'] as String,
                  isDeleted: Value(raw['is_deleted'] as bool? ?? false),
                ),
              );
          applied++;
        } else {
          skipped++;
        }
      }
    });

    return SyncMergeStats(applied: applied, skipped: skipped);
  }

  bool _incomingWins({
    required int incomingTs,
    required String incomingDevice,
    required int localTs,
    required String localDevice,
  }) {
    if (incomingTs > localTs) return true;
    if (incomingTs < localTs) return false;
    return incomingDevice.compareTo(localDevice) > 0;
  }

  Set<String> _parsePaidString(String paidMonths, String? lastPaid) {
    final set = <String>{};
    if (paidMonths.isNotEmpty) {
      for (final p in paidMonths.split(',')) {
        final t = p.trim();
        if (t.isNotEmpty) set.add(t);
      }
    }
    if (lastPaid != null && lastPaid.isNotEmpty) set.add(lastPaid);
    return set;
  }

  List<Map<String, dynamic>> _listOfMaps(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList();
  }

  Map<String, dynamic> _encodeFamily(Family f) => {
        'id': f.id,
        'name': f.name,
        'payday_day': f.paydayDay,
        'currency': f.currency,
        'created_at': f.createdAt,
        'updated_at': f.updatedAt,
        'updated_by_device_id': f.updatedByDeviceId,
        'is_deleted': f.isDeleted,
      };

  Map<String, dynamic> _encodeMember(Member m) => {
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
      };

  Map<String, dynamic> _encodeCategory(Category c) => {
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
      };

  Map<String, dynamic> _encodeWallet(Wallet w) => {
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
      };

  Map<String, dynamic> _encodeBudget(Budget b) => {
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
      };

  Map<String, dynamic> _encodeBill(RecurringBill b) => {
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
      };

  Map<String, dynamic> _encodeTransaction(Transaction t) => {
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
      };
}
