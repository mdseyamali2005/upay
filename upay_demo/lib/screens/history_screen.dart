import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../data/user_data.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedFilter = 'সব';

  final List<String> _filters = [
    'সব',
    'সেন্ড মানি',
    'রিসিভড মানি',
    'মোবাইল রিচার্জ',
    'ক্যাশ আউট',
  ];

  List<Map<String, dynamic>> _allTransactions =
      UserData.getDemoTransactions();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _syncAndRefresh();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Sync from backend and refresh the transaction list.
  Future<void> _syncAndRefresh() async {
    await UserData.syncFromBackend();
    if (mounted) {
      setState(() {
        _allTransactions = UserData.getDemoTransactions();
      });
    }
  }

  List<Map<String, dynamic>> get _filteredTransactions {
    if (_selectedFilter == 'সব') return _allTransactions;
    return _allTransactions
        .where((txn) => txn['label'] == _selectedFilter)
        .toList();
  }

  IconData _getIcon(String type) {
    switch (type) {
      case 'send_money':
        return Icons.arrow_upward_rounded;
      case 'received_money':
        return Icons.arrow_downward_rounded;
      case 'mobile_recharge':
        return Icons.phone_android;
      case 'cash_out':
        return Icons.account_balance;
      case 'pay_bill':
        return Icons.receipt_long;
      case 'add_money':
        return Icons.add_circle_outline;
      default:
        return Icons.swap_horiz;
    }
  }

  Color _getIconColor(String type) {
    switch (type) {
      case 'send_money':
        return AppColors.red;
      case 'received_money':
        return AppColors.green;
      case 'mobile_recharge':
        return AppColors.primaryBlue;
      case 'cash_out':
        return AppColors.orange;
      case 'pay_bill':
        return const Color(0xFF7C4DFF);
      case 'add_money':
        return AppColors.green;
      default:
        return AppColors.primaryBlue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Text(
                'হিস্টরি',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.black,
                ),
              ),
            ),
            const Divider(color: AppColors.lightGrey),

            // Tabs
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.lightGrey,
                borderRadius: BorderRadius.circular(28),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: AppColors.accentYellow,
                  borderRadius: BorderRadius.circular(28),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: AppColors.black,
                unselectedLabelColor: AppColors.darkGrey,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
                labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: 'লেনদেন বিবরণী'),
                  Tab(text: 'সারসংক্ষেপ'),
                ],
              ),
            ),

            // Filter chips
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _filters.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final filter = _filters[index];
                  final isSelected = filter == _selectedFilter;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedFilter = filter),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.accentYellow
                            : AppColors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.accentYellow
                              : AppColors.lightGrey,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          filter,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: AppColors.black,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 8),

            // Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTransactionList(),
                  _buildSummaryView(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionList() {
    final transactions = _filteredTransactions;
    if (transactions.isEmpty) {
      return _buildEmptyState();
    }

    // Group by date
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final txn in transactions) {
      final date = txn['date'] as String;
      grouped.putIfAbsent(date, () => []).add(txn);
    }

    final dates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: dates.length,
      itemBuilder: (context, index) {
        final date = dates[index];
        final txns = grouped[date]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _formatDate(date),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.grey,
                ),
              ),
            ),
            ...txns.map((txn) => _buildTransactionTile(txn)),
            if (index < dates.length - 1)
              const Divider(color: AppColors.lightGrey),
          ],
        );
      },
    );
  }

  Widget _buildTransactionTile(Map<String, dynamic> txn) {
    final type = txn['type'] as String;
    final amount = txn['amount'] as double;
    final isCredit = amount > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          // Icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _getIconColor(type).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _getIcon(type),
              color: _getIconColor(type),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  txn['label'] as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.black,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  txn['counterparty'] as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.grey,
                  ),
                ),
              ],
            ),
          ),
          // Amount
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isCredit ? '+' : ''}৳${amount.abs().toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isCredit ? AppColors.green : AppColors.red,
                ),
              ),
              Text(
                txn['txnId'] as String,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryView() {
    // Calculate summary
    double totalSent = 0;
    double totalReceived = 0;
    double totalRecharge = 0;
    double totalCashOut = 0;
    double totalBill = 0;

    for (final txn in _allTransactions) {
      final amount = (txn['amount'] as double).abs();
      switch (txn['type']) {
        case 'send_money':
          totalSent += amount;
          break;
        case 'received_money':
        case 'add_money':
          totalReceived += amount;
          break;
        case 'mobile_recharge':
          totalRecharge += amount;
          break;
        case 'cash_out':
          totalCashOut += amount;
          break;
        case 'pay_bill':
          totalBill += amount;
          break;
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Total card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1B3A6B), Color(0xFF0D47A1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text(
                  'মোট খরচ (এই মাস)',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '৳${(totalSent + totalRecharge + totalCashOut + totalBill).toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Category breakdown
          _buildSummaryRow(
              'সেন্ড মানি', totalSent, AppColors.red, Icons.arrow_upward_rounded),
          _buildSummaryRow('রিসিভড / অ্যাড মানি', totalReceived,
              AppColors.green, Icons.arrow_downward_rounded),
          _buildSummaryRow('মোবাইল রিচার্জ', totalRecharge,
              AppColors.primaryBlue, Icons.phone_android),
          _buildSummaryRow('ক্যাশ আউট', totalCashOut, AppColors.orange,
              Icons.account_balance),
          _buildSummaryRow(
              'পে বিল', totalBill, const Color(0xFF7C4DFF), Icons.receipt_long),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
      String label, double amount, Color color, IconData icon) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            '৳${amount.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    final parts = dateStr.split('-');
    final months = [
      '',
      'জানুয়ারি',
      'ফেব্রুয়ারি',
      'মার্চ',
      'এপ্রিল',
      'মে',
      'জুন',
      'জুলাই',
      'আগস্ট',
      'সেপ্টেম্বর',
      'অক্টোবর',
      'নভেম্বর',
      'ডিসেম্বর'
    ];
    final day = int.parse(parts[2]);
    final month = int.parse(parts[1]);
    return '$day ${months[month]}, ${parts[0]}';
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              color: AppColors.accentYellow.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.phone_android,
                    size: 60,
                    color: AppColors.primaryBlue.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 8),
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 40,
                    color: AppColors.goldYellow.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'আপনার এখনো কোনো ট্রানজেকশন রেকর্ড\nনেই।',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.darkGrey,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
