import 'package:flutter/material.dart';
import '../data/user_data.dart';
import '../theme/app_theme.dart';
import '../widgets/agent_ai_mark.dart';
import 'home_screen.dart';
import 'account_screen.dart';
import 'history_screen.dart';
import 'more_screen.dart';
import 'voice_agent_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  bool _agentOn = false;
  late final AnimationController _pulse;

  final List<Widget> _screens = const [
    HomeScreen(),
    AccountScreen(),
    SizedBox(), // Placeholder for BanglaQR (center FAB)
    HistoryScreen(),
    MoreScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _loadAgent();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _loadAgent() async {
    final on = await UserData.isVoiceAgentEnabled();
    if (mounted) setState(() => _agentOn = on);
  }

  void _openAgent() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VoiceAgentScreen()));
    // Trigger rebuild so child screens pick up synced data
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex == 2 ? 0 : _currentIndex,
            children: _screens,
          ),
          if (_agentOn && _currentIndex == 0)
            Positioned(
              right: 16,
              bottom: 18,
              child: ScaleTransition(
                scale: Tween<double>(begin: 1, end: 1.06).animate(
                  CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                ),
                child: Material(
                  color: AppColors.white,
                  elevation: 6,
                  shadowColor: AppColors.primaryBlue.withValues(alpha: 0.35),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _openAgent,
                    child: const AgentAiMark(size: 84),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: SizedBox(
        width: 68,
        height: 68,
        child: FloatingActionButton(
          onPressed: () => _showBanglaQRSheet(context),
          elevation: 4,
          backgroundColor: AppColors.white,
          shape: CircleBorder(
            side: BorderSide(color: AppColors.primaryBlue, width: 3),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.qr_code_2, color: AppColors.primaryBlue, size: 22),
              Text(
                'BANGLA',
                style: TextStyle(
                  fontSize: 7,
                  height: 1.1,
                  fontWeight: FontWeight.w900,
                  color: AppColors.red,
                  letterSpacing: 0.4,
                ),
              ),
              Text(
                'QR',
                style: TextStyle(
                  fontSize: 8,
                  height: 1.1,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primaryBlue,
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        color: AppColors.white,
        elevation: 12,
        padding: EdgeInsets.zero,
        height: 68,
        child: Row(
          children: [
            _buildNavItem(0, Icons.home_rounded, 'হোম'),
            _buildNavItem(1, Icons.account_balance_wallet_outlined, 'অ্যাকাউন্ট'),
            const SizedBox(width: 72),
            _buildNavItem(3, Icons.history_rounded, 'হিস্টরি'),
            _buildNavItem(4, Icons.more_horiz_rounded, 'আরো'),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isActive = _currentIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _currentIndex = index);
          if (index == 0 || index == 4) _loadAgent();
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: isActive ? 1.08 : 1,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: Icon(
                icon,
                color: isActive ? AppColors.primaryBlue : AppColors.grey,
                size: 22,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? AppColors.primaryBlue : AppColors.grey,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _showBanglaQRSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primaryBlue, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.qr_code_2,
                size: 120,
                color: AppColors.primaryBlue,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Bangla QR স্ক্যান করুন',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'ডেমো মোড — স্ক্যানার উপলব্ধ নয়',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.grey,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
