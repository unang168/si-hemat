import 'package:drift/drift.dart';

/// Offline-first, sync-ready SQLite schema for Si-Hemat.
/// Every synced table uses UUID text primary keys, integer Rupiah amounts,
/// UTC epoch millisecond timestamps, and soft-delete flags (`isDeleted`).

class Families extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get paydayDay => integer().withDefault(const Constant(25))();
  TextColumn get currency => text().withDefault(const Constant('IDR'))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  TextColumn get updatedByDeviceId => text()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Members extends Table {
  TextColumn get id => text()();
  TextColumn get familyId => text().references(Families, #id)();
  TextColumn get deviceId => text()();
  TextColumn get name => text()();
  TextColumn get role => text().withDefault(const Constant('member'))();
  IntColumn get avatarColor => integer().withDefault(const Constant(0xFF0E7C66))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  TextColumn get updatedByDeviceId => text()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Wallets extends Table {
  TextColumn get id => text()();
  TextColumn get familyId => text().references(Families, #id)();
  TextColumn get ownerMemberId => text().nullable().references(Members, #id)();
  TextColumn get name => text()();
  TextColumn get type => text()(); // cash | bank | ewallet | credit
  TextColumn get visibility => text().withDefault(const Constant('shared'))(); // shared | personal
  IntColumn get initialBalance => integer().withDefault(const Constant(0))();
  TextColumn get icon => text().withDefault(const Constant('account_balance_wallet'))();
  IntColumn get color => integer().withDefault(const Constant(0xFF0E7C66))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  TextColumn get updatedByDeviceId => text()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get familyId => text().references(Families, #id)();
  TextColumn get name => text()();
  TextColumn get type => text()(); // income | expense
  TextColumn get icon => text()();
  IntColumn get color => integer()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  TextColumn get updatedByDeviceId => text()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get familyId => text().references(Families, #id)();
  TextColumn get memberId => text().references(Members, #id)();
  TextColumn get walletId => text().references(Wallets, #id)();
  TextColumn get toWalletId => text().nullable().references(Wallets, #id)();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get type => text()(); // income | expense | transfer
  IntColumn get amount => integer()();
  IntColumn get date => integer()(); // UTC epoch ms
  TextColumn get merchant => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get receiptPath => text().nullable()();
  TextColumn get receiptHash => text().nullable()();
  TextColumn get source => text().withDefault(const Constant('manual'))(); // manual | ai_chat | ai_receipt | recurring
  TextColumn get visibility => text().withDefault(const Constant('shared'))(); // shared | personal
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  TextColumn get updatedByDeviceId => text()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Budgets extends Table {
  TextColumn get id => text()();
  TextColumn get familyId => text().references(Families, #id)();
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get monthKey => text()(); // YYYY-MM
  IntColumn get limitAmount => integer()();
  TextColumn get visibility => text().withDefault(const Constant('shared'))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  TextColumn get updatedByDeviceId => text()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class RecurringBills extends Table {
  TextColumn get id => text()();
  TextColumn get familyId => text().references(Families, #id)();
  TextColumn get walletId => text().nullable().references(Wallets, #id)();
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get name => text()();
  IntColumn get amount => integer()();
  IntColumn get dueDay => integer()(); // 1..31
  TextColumn get startMonth => text().nullable()(); // YYYY-MM (inclusive)
  TextColumn get endMonth => text().nullable()(); // YYYY-MM (inclusive)
  TextColumn get lastPaidMonth => text().nullable()(); // YYYY-MM
  TextColumn get paidMonths => text().withDefault(const Constant(''))(); // comma-separated YYYY-MM
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get visibility => text().withDefault(const Constant('shared'))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  TextColumn get updatedByDeviceId => text()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Local-only table (not synced): tracks known family peer devices on Wi-Fi LAN.
class SyncPeers extends Table {
  TextColumn get peerDeviceId => text()();
  TextColumn get peerName => text()();
  IntColumn get lastSyncedAt => integer().withDefault(const Constant(0))();
  TextColumn get lastIp => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {peerDeviceId};
}

/// Local-only table (not synced): stores AI assistant conversation history.
class AiChatMessages extends Table {
  TextColumn get id => text()();
  TextColumn get role => text()(); // user | assistant
  TextColumn get content => text()();
  TextColumn get draftJson => text().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
