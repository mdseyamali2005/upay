import 'package:shared_preferences/shared_preferences.dart';
import '../services/agent_api.dart';

class UserData {
  // Demo user data (matches memory.md)
  static const String demoPin = '1234';
  static const String demoName = 'MD. SEYAM ALI';
  static const String demoPhone = '01307339929';
  static const double demoBalance = 25000.0;
  static const double defaultLimit = 5000.0;

  // SharedPreferences keys
  static const String _keyLoggedIn = 'is_logged_in';
  static const String _keyVoiceAgentEnabled = 'voice_agent_enabled';
  static const String _keyTransactionLimit = 'transaction_limit';
  static const String _keyBalance = 'balance';

  /// In-memory transaction list (synced from backend).
  /// Starts with demo data, gets replaced when syncFromBackend() is called.
  static List<Map<String, dynamic>> _transactions = _defaultDemoTransactions();
  static bool _synced = false;

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyLoggedIn) ?? false;
  }

  static Future<void> setLoggedIn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyLoggedIn, value);
  }

  static Future<bool> verifyPin(String pin) async {
    return pin == demoPin;
  }

  static Future<bool> isVoiceAgentEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyVoiceAgentEnabled) ?? false;
  }

  static Future<void> setVoiceAgentEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyVoiceAgentEnabled, value);
  }

  static Future<double> getTransactionLimit() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyTransactionLimit) ?? defaultLimit;
  }

  static Future<void> setTransactionLimit(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyTransactionLimit, value);
    // Also update the backend
    _updateBackendLimit(value);
  }

  static Future<double> getBalance() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_keyBalance) ?? demoBalance;
  }

  static Future<void> setBalance(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyBalance, value);
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyLoggedIn, false);
  }

  static Future<void> _updateBackendLimit(double limit) async {
    try {
      // In production, this would call the deployed API to update the limit
      // e.g. PUT https://upay-voice-guard.onrender.com/limit
    } catch (_) {
      // Silently fail — demo mode
    }
  }

  // ── Sync from backend ──

  /// Pull latest balance + transactions from the Voice Guard backend.
  /// Call after voice agent session ends or when navigating to history/account.
  static Future<bool> syncFromBackend() async {
    try {
      final info = await AgentApi.fetchUserInfo();
      if (info == null) return false;

      // Update balance
      final bal = (info['balance'] as num).toDouble();
      await setBalance(bal);

      // Convert backend transactions to Flutter format
      final backendTxns = info['transactions'] as List<dynamic>? ?? [];
      _transactions = backendTxns.map((t) {
        final kind = t['kind'] as String;
        final amount = (t['amount'] as num).toDouble();
        final isCredit = kind == 'add_money' || kind == 'received_money';
        return <String, dynamic>{
          'type': kind,
          'label': _labelFor(kind),
          'counterparty': _maskNumber(t['counterparty'] as String),
          'amount': isCredit ? amount : -amount,
          'date': t['ts'] as String,
          'txnId': 'TXN${(t['ts'] as String).replaceAll('-', '')}${t['id'].toString().padLeft(3, '0')}',
        };
      }).toList();
      _synced = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _labelFor(String kind) {
    switch (kind) {
      case 'send_money':
        return 'সেন্ড মানি';
      case 'received_money':
        return 'রিসিভড মানি';
      case 'mobile_recharge':
        return 'মোবাইল রিচার্জ';
      case 'cash_out':
        return 'ক্যাশ আউট';
      case 'pay_bill':
        return 'পে বিল';
      case 'add_money':
        return 'অ্যাড মানি';
      default:
        return kind;
    }
  }

  static String _maskNumber(String number) {
    if (number.length == 11 && number.startsWith('01')) {
      return '${number.substring(0, 5)}XXXXX';
    }
    // Non-phone counterparty (e.g. 'bank', 'DESCO') — return as-is with Bangla fallback
    if (number == 'bank') return 'ব্যাংক';
    return number;
  }

  /// Demo transaction data for the history screen.
  /// After syncFromBackend() is called, this returns synced data.
  static List<Map<String, dynamic>> getDemoTransactions() {
    return List.unmodifiable(_transactions);
  }

  /// Whether a backend sync has been performed at least once.
  static bool get isSynced => _synced;

  static List<Map<String, dynamic>> _defaultDemoTransactions() {
    return [
      {
        'type': 'send_money',
        'label': 'সেন্ড মানি',
        'counterparty': '01711XXXXX',
        'amount': -500.0,
        'date': '2026-10-03',
        'txnId': 'TXN20261003001',
      },
      {
        'type': 'mobile_recharge',
        'label': 'মোবাইল রিচার্জ',
        'counterparty': '01307339929',
        'amount': -100.0,
        'date': '2026-10-03',
        'txnId': 'TXN20261003002',
      },
      {
        'type': 'received_money',
        'label': 'রিসিভড মানি',
        'counterparty': '01811XXXXX',
        'amount': 2000.0,
        'date': '2026-10-02',
        'txnId': 'TXN20261002001',
      },
      {
        'type': 'cash_out',
        'label': 'ক্যাশ আউট',
        'counterparty': '01911111111',
        'amount': -1500.0,
        'date': '2026-10-02',
        'txnId': 'TXN20261002002',
      },
      {
        'type': 'pay_bill',
        'label': 'পে বিল',
        'counterparty': 'DESCO',
        'amount': -750.0,
        'date': '2026-10-01',
        'txnId': 'TXN20261001001',
      },
      {
        'type': 'add_money',
        'label': 'অ্যাড মানি',
        'counterparty': 'ব্যাংক',
        'amount': 5000.0,
        'date': '2026-10-01',
        'txnId': 'TXN20261001002',
      },
      {
        'type': 'send_money',
        'label': 'সেন্ড মানি',
        'counterparty': '01612XXXXX',
        'amount': -300.0,
        'date': '2026-09-30',
        'txnId': 'TXN20260930001',
      },
      {
        'type': 'mobile_recharge',
        'label': 'মোবাইল রিচার্জ',
        'counterparty': '01307339929',
        'amount': -49.0,
        'date': '2026-09-29',
        'txnId': 'TXN20260929001',
      },
    ];
  }
}

