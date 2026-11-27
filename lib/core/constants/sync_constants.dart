/// Domain enums and shared constants used across Si-Hemat database, UI, and sync.
class VisibilityScope {
  static const String shared = 'shared';
  static const String personal = 'personal';
}

class MemberRole {
  static const String admin = 'admin';
  static const String member = 'member';
}

class WalletType {
  static const String cash = 'cash';
  static const String bank = 'bank';
  static const String ewallet = 'ewallet';
  static const String credit = 'credit';

  static const List<String> all = [cash, bank, ewallet, credit];

  static String label(String type) {
    switch (type) {
      case cash:
        return 'Tunai';
      case bank:
        return 'Rekening Bank';
      case ewallet:
        return 'E-Wallet';
      case credit:
        return 'Kartu Kredit';
      default:
        return 'Lainnya';
    }
  }
}

class CategoryType {
  static const String income = 'income';
  static const String expense = 'expense';
}

class TransactionType {
  static const String income = 'income';
  static const String expense = 'expense';
  static const String transfer = 'transfer';
}

class TransactionSource {
  static const String manual = 'manual';
  static const String aiChat = 'ai_chat';
  static const String aiReceipt = 'ai_receipt';
  static const String recurring = 'recurring';
}

class SyncConstants {
  static const String mdnsServiceType = '_sihemat._tcp';
  static const int protocolVersion = 1;
}
