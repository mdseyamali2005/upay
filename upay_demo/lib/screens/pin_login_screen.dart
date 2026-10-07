import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../data/user_data.dart';
import '../widgets/upay_logo.dart';
import 'main_shell.dart';

class PinLoginScreen extends StatefulWidget {
  const PinLoginScreen({super.key});

  @override
  State<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends State<PinLoginScreen>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  int _attempts = 0;
  bool _isLoading = false;
  bool _showError = false;
  String _errorText = '';
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _onDigitTap(String digit) {
    if (_pin.length >= 4 || _isLoading) return;
    HapticFeedback.lightImpact();
    setState(() {
      _pin += digit;
      _showError = false;
    });
  }

  void _onBackspace() {
    if (_pin.isEmpty || _isLoading) return;
    HapticFeedback.lightImpact();
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _showError = false;
    });
  }

  Future<void> _onSubmit() async {
    if (_pin.length != 4) return;

    setState(() => _isLoading = true);

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 800));

    final valid = await UserData.verifyPin(_pin);

    if (!mounted) return;

    if (valid) {
      await UserData.setLoggedIn(true);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const MainShell(),
          transitionsBuilder: (context, anim, secondaryAnim, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    } else {
      _attempts++;
      if (_attempts >= 3) {
        setState(() {
          _showError = true;
          _errorText = 'অ্যাকাউন্ট লক হয়েছে। পরে চেষ্টা করুন।';
          _isLoading = false;
          _pin = '';
        });
      } else {
        _shakeController.forward().then((_) => _shakeController.reset());
        setState(() {
          _showError = true;
          _errorText = 'ভুল পিন। ${3 - _attempts} বার চেষ্টা বাকি।';
          _isLoading = false;
          _pin = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // uPay logo small
                  const UpayLogo(height: 42),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.primaryBlue),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'English',
                      style: TextStyle(
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // Title
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 30),
              child: Text(
                'আপনার ৪ ডিজিটের\nপিন প্রদান করুন',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.black,
                  height: 1.3,
                ),
              ),
            ),

            const SizedBox(height: 30),

            // PIN dots with shake animation
            AnimatedBuilder(
              animation: _shakeAnimation,
              builder: (context, child) {
                final dx = _shakeAnimation.value *
                    10 *
                    ((_shakeController.value * 10).toInt().isEven ? 1 : -1);
                return Transform.translate(
                  offset: Offset(dx, 0),
                  child: child,
                );
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding:
                    const EdgeInsets.symmetric(horizontal: 30, vertical: 16),
                decoration: BoxDecoration(
                  color: AppColors.lightGrey,
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(4, (i) {
                          final filled = i < _pin.length;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 10),
                            width: filled ? 18 : 14,
                            height: filled ? 18 : 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: filled
                                  ? AppColors.primaryBlue
                                  : AppColors.grey.withValues(alpha: 0.4),
                              boxShadow: filled
                                  ? [
                                      BoxShadow(
                                        color: AppColors.primaryBlue
                                            .withValues(alpha: 0.3),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      )
                                    ]
                                  : null,
                            ),
                          );
                        }),
                      ),
                    ),
                    GestureDetector(
                      onTap: _pin.length == 4 ? _onSubmit : null,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _pin.length == 4
                              ? AppColors.primaryBlue
                              : AppColors.grey.withValues(alpha: 0.3),
                        ),
                        child: Icon(
                          Icons.arrow_forward,
                          color: _pin.length == 4
                              ? AppColors.white
                              : AppColors.grey,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_showError) ...[
              const SizedBox(height: 12),
              Text(
                _errorText,
                style: const TextStyle(
                  color: AppColors.red,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],

            const SizedBox(height: 30),

            // Fingerprint icon
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: AppColors.grey.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.fingerprint,
                    size: 40,
                    color: AppColors.lightBlue.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'ফিঙ্গারপ্রিন্ট/ফেস আইডি',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.black.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            TextButton(
              onPressed: () {},
              child: const Text(
                'পিন ভুলে গিয়েছেন?',
                style: TextStyle(
                  color: AppColors.primaryBlue,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            const Spacer(),

            // Loading indicator
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ),

            // Number pad
            _buildNumberPad(),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberPad() {
    return Container(
      color: AppColors.offWhite,
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
      child: Column(
        children: [
          _buildNumRow(['1', '2', '3']),
          _buildNumRow(['4', '5', '6']),
          _buildNumRow(['7', '8', '9']),
          _buildNumRow(['⌫', '0', '✓']),
        ],
      ),
    );
  }

  Widget _buildNumRow(List<String> keys) {
    return Row(
      children: keys.map((key) {
        return Expanded(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                if (key == '⌫') {
                  _onBackspace();
                } else if (key == '✓') {
                  _onSubmit();
                } else {
                  _onDigitTap(key);
                }
              },
              child: Container(
                height: 65,
                decoration: BoxDecoration(
                  border:
                      Border.all(color: AppColors.lightGrey.withValues(alpha: 0.5)),
                ),
                child: Center(
                  child: key == '⌫'
                      ? const Icon(Icons.backspace_outlined,
                          size: 24, color: AppColors.darkGrey)
                      : key == '✓'
                          ? Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _pin.length == 4
                                    ? AppColors.accentYellow
                                    : AppColors.grey.withValues(alpha: 0.3),
                              ),
                              child: Icon(
                                Icons.check,
                                color: _pin.length == 4
                                    ? AppColors.white
                                    : AppColors.grey,
                                size: 22,
                              ),
                            )
                          : Text(
                              key,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w500,
                                color: AppColors.black,
                              ),
                            ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
