import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../data/user_data.dart';
import '../widgets/agent_ai_mark.dart';
import '../widgets/upay_logo.dart';
import 'voice_agent_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  double _balance = UserData.demoBalance;
  bool _showBalance = false;
  int _bannerIndex = 0;
  late PageController _bannerController;
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    _bannerController = PageController();
    _loadBalance();
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_bannerController.hasClients) return;
      final next = (_bannerIndex + 1) % 3;
      _bannerController.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerController.dispose();
    super.dispose();
  }

  Future<void> _loadBalance() async {
    // Try syncing from backend first (gets latest after voice agent transactions)
    await UserData.syncFromBackend();
    final bal = await UserData.getBalance();
    if (mounted) setState(() => _balance = bal);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: CustomScrollView(
        slivers: [
          // Yellow header
          SliverToBoxAdapter(child: _buildHeader()),
          // Service grid
          SliverToBoxAdapter(child: _buildServiceGrid()),
          // Banner carousel
          SliverToBoxAdapter(child: _buildBannerCarousel()),
          // Payment section header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('উপায় পেমেন্ট', style: AppTextStyles.sectionHeader),
            ),
          ),
          // Payment grid
          SliverToBoxAdapter(child: _buildPaymentGrid()),
          // Other services header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child:
                  Text('অন্যান্য সার্ভিস', style: AppTextStyles.sectionHeader),
            ),
          ),
          // Other services grid
          SliverToBoxAdapter(child: _buildOtherServicesGrid()),
          // Bottom cards
          SliverToBoxAdapter(child: _buildBottomCards()),
          // Bottom spacing
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.accentYellow,
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.white,
                  shape: BoxShape.circle,
                ),
                child: const UpayLogo(height: 40),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      UserData.demoName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.black,
                      ),
                    ),
                    Text(
                      UserData.demoPhone,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.darkGrey,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => _showBalance = !_showBalance),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _showBalance ? '৳ ${_balance.toStringAsFixed(0)}' : 'ব্যালেন্স',
                    style: const TextStyle(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: const Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(Icons.notifications_outlined, color: AppColors.black, size: 20),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: AppColors.red, shape: BoxShape.circle),
                        child: SizedBox(width: 7, height: 7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconGrid(List<_ServiceItem> items) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 8,
          crossAxisSpacing: 4,
          childAspectRatio: 0.78,
        ),
        itemBuilder: (context, index) {
          final item = items[index];
          return _TapTile(
            onTap: () {
              if (item.label == 'এজেন্ট' || item.label == 'ভয়েস এজেন্ট') {
                _openAgent();
              } else {
                _showDemoSnackbar(item.label);
              }
            },
            child: Column(
              children: [
                item.label == 'এজেন্ট'
                    ? const AgentAiMark(size: 52)
                    : Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: item.color.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(item.icon, color: item.color, size: 24),
                      ),
                const SizedBox(height: 6),
                Text(
                  item.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.black,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildServiceGrid() {
    final services = [
      _ServiceItem('এজেন্ট', Icons.record_voice_over, AppColors.primaryBlue),
      _ServiceItem('সেন্ড মানি', Icons.send, AppColors.primaryBlue),
      _ServiceItem(
          'মোবাইল রিচার্জ', Icons.phone_android, AppColors.primaryBlue),
      _ServiceItem(
          'ক্যাশ আউট', Icons.account_balance, AppColors.primaryBlue),
      _ServiceItem('পে বিল', Icons.receipt_long, AppColors.primaryBlue),
      _ServiceItem('অ্যাড মানি', Icons.add_card, AppColors.primaryBlue),
      _ServiceItem('সঞ্চয়', Icons.savings, AppColors.goldYellow),
      _ServiceItem(
          'ফান্ড ট্রান্সফার', Icons.swap_horiz, AppColors.primaryBlue),
      _ServiceItem(
          'রিকোয়েস্ট মানি', Icons.request_page, AppColors.primaryBlue),
      _ServiceItem('মেক পেমেন্ট', Icons.qr_code, AppColors.primaryBlue),
      _ServiceItem('রেফার & আর্ন', Icons.group_add, AppColors.green),
      _ServiceItem(
          'এনপিএসবি', Icons.account_balance_wallet, AppColors.primaryBlue),
    ];

    return _buildIconGrid(services);
  }

  Widget _buildBannerCarousel() {
    final banners = [
      _BannerData(
        'আনলিমিটেড ক্যাশব্যাক!',
        'মোবাইল রিচার্জে ৫০ টাকা পর্যন্ত ক্যাশব্যাক পান',
        const [Color(0xFF1A237E), Color(0xFF0D47A1)],
      ),
      _BannerData(
        'ভয়েস এজেন্ট',
        'কথা বলে ব্যালেন্স জানুন ও ক্যাশ আউট করুন',
        const [Color(0xFF4A148C), Color(0xFF7B1FA2)],
      ),
      _BannerData(
        'রেফার করুন, আর্ন করুন!',
        'প্রতিটি রেফারেলে ২০০ টাকা বোনাস পান',
        const [Color(0xFF00695C), Color(0xFF00897B)],
      ),
    ];

    return Column(
      children: [
        SizedBox(
          height: 110,
          child: PageView.builder(
            controller: _bannerController,
            onPageChanged: (i) => setState(() => _bannerIndex = i),
            itemCount: banners.length,
            itemBuilder: (context, index) {
              final banner = banners[index];
              return GestureDetector(
                onTap: index == 1 ? _openAgent : null,
                child: Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    colors: banner.colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: banner.colors.first.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // Decorative circles
                    Positioned(
                      right: -20,
                      top: -20,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.white.withValues(alpha: 0.06),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 20,
                      bottom: -30,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.white.withValues(alpha: 0.04),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            banner.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            banner.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.white.withValues(alpha: 0.85),
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        // Dots indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(banners.length, (i) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: _bannerIndex == i ? 20 : 8,
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: _bannerIndex == i
                    ? AppColors.primaryBlue
                    : AppColors.grey.withValues(alpha: 0.3),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildPaymentGrid() {
    final payments = [
      _ServiceItem('ট্রাফিক ফাইন', Icons.traffic, AppColors.green),
      _ServiceItem('টোল পেমেন্ট', Icons.toll, AppColors.orange),
      _ServiceItem('সরকারি পেমেন্ট', Icons.account_balance, AppColors.red),
      _ServiceItem('এডুকেশন', Icons.school, AppColors.primaryBlue),
      _ServiceItem('এন জি ও', Icons.volunteer_activism, AppColors.orange),
      _ServiceItem('বীমা', Icons.security, AppColors.primaryBlue),
      _ServiceItem('ডোনেশন', Icons.favorite, AppColors.red),
      _ServiceItem('যাকাত পেমেন্ট', Icons.mosque, AppColors.green),
      _ServiceItem(
          'টিকেট', Icons.confirmation_number, AppColors.primaryBlue),
      _ServiceItem('জিপি ফ্লেক্সিপ্ল্যান', Icons.apps, AppColors.green),
      _ServiceItem('হোটেল', Icons.hotel, AppColors.orange),
      _ServiceItem('আবেদন ফি', Icons.description, AppColors.primaryBlue),
      _ServiceItem('Othoba', Icons.shopping_bag, AppColors.primaryBlue),
      _ServiceItem('মেট্রোরেল', Icons.train, AppColors.red),
    ];

    return _buildIconGrid(payments);
  }

  Widget _buildOtherServicesGrid() {
    final others = [
      _ServiceItem('পেওনিয়ার', Icons.circle_outlined, AppColors.orange),
      _ServiceItem('উপায় চাকা', Icons.attractions, AppColors.goldYellow),
      _ServiceItem('মিউজিক', Icons.music_note, AppColors.primaryBlue),
      _ServiceItem('ই-লার্নিং', Icons.laptop_mac, AppColors.green),
      _ServiceItem('গেমস', Icons.sports_esports, AppColors.primaryBlue),
    ];

    return _buildIconGrid(others);
  }

  Widget _buildBottomCards() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'উপায় কার্ড',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.red,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.credit_card, color: AppColors.primaryBlue, size: 26),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'উপায় অফার',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.card_giftcard, color: AppColors.primaryBlue, size: 26),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openAgent() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VoiceAgentScreen()),
    );
    // Reload balance after returning from voice agent
    _loadBalance();
  }

  void _showDemoSnackbar(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label — ডেমো মোড'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: AppColors.primaryBlue,
      ),
    );
  }
}

class _TapTile extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _TapTile({required this.child, required this.onTap});

  @override
  State<_TapTile> createState() => _TapTileState();
}

class _TapTileState extends State<_TapTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class _ServiceItem {
  final String label;
  final IconData icon;
  final Color color;
  _ServiceItem(this.label, this.icon, this.color);
}

class _BannerData {
  final String title;
  final String subtitle;
  final List<Color> colors;
  _BannerData(this.title, this.subtitle, this.colors);
}
