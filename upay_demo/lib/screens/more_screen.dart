import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../theme/app_theme.dart';
import '../widgets/agent_ai_mark.dart';
import '../data/user_data.dart';
import 'pin_login_screen.dart';
import 'voice_agent_screen.dart';
import 'contacts_screen.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  bool _voiceAgentEnabled = false;
  double _transactionLimit = UserData.defaultLimit;
  bool _isLoadingLimit = false;
  final TextEditingController _limitController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final enabled = await UserData.isVoiceAgentEnabled();
    final limit = await UserData.getTransactionLimit();
    if (mounted) {
      setState(() {
        _voiceAgentEnabled = enabled;
        _transactionLimit = limit;
        _limitController.text = limit.toStringAsFixed(0);
      });
    }
  }

  Future<void> _toggleVoiceAgent(bool value) async {
    await UserData.setVoiceAgentEnabled(value);
    setState(() => _voiceAgentEnabled = value);

    if (value) {
      // Show info snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('ভয়েস এজেন্ট সক্রিয় হয়েছে!'),
            backgroundColor: AppColors.green,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  Future<void> _updateLimit() async {
    final newLimit = double.tryParse(_limitController.text);
    if (newLimit == null || newLimit <= 0) {
      _showError('সঠিক পরিমাণ দিন');
      return;
    }
    if (newLimit > 25000) {
      _showError('সর্বোচ্চ লিমিট ২৫,০০০ টাকা');
      return;
    }

    setState(() => _isLoadingLimit = true);

    try {
      // Try to update the backend limit via PUT API
      final uri =
          Uri.parse('https://upay-voice-guard.onrender.com/limit');
      final response = await http.put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'limit': newLimit.toInt()}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        await UserData.setTransactionLimit(newLimit);
        setState(() {
          _transactionLimit = newLimit;
          _isLoadingLimit = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'লিমিট আপডেট হয়েছে: ৳${newLimit.toStringAsFixed(0)}'),
              backgroundColor: AppColors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      } else {
        // Still save locally even if backend fails
        await UserData.setTransactionLimit(newLimit);
        setState(() {
          _transactionLimit = newLimit;
          _isLoadingLimit = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'লিমিট লোকালি সেভ হয়েছে (সার্ভার অফলাইন)'),
              backgroundColor: AppColors.orange,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    } catch (e) {
      // Save locally on timeout/error
      await UserData.setTransactionLimit(newLimit);
      setState(() {
        _transactionLimit = newLimit;
        _isLoadingLimit = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'লিমিট লোকালি সেভ হয়েছে (সার্ভার অফলাইন)'),
            backgroundColor: AppColors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('লগ আউট'),
        content: const Text('আপনি কি লগ আউট করতে চান?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('না'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child:
                const Text('হ্যাঁ', style: TextStyle(color: AppColors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await UserData.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const PinLoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Container(
                color: AppColors.white,
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: const Text(
                  'আরো',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ),
              const Divider(
                  height: 1,
                  color: AppColors.primaryBlue,
                  thickness: 2),

              // ─── VOICE AGENT SECTION (NEW!) ───
              const SizedBox(height: 8),
              _buildSectionHeader('ভয়েস এজেন্ট'),
              _buildVoiceAgentSection(),

              // Settings
              _buildSectionHeader('সেটিংস'),
              _buildSettingsSection(),

              // Support
              _buildSectionHeader('উপায় সাপোর্ট'),
              _buildSupportSection(),

              // Account Services
              _buildSectionHeader('অ্যাকাউন্ট সার্ভিস'),
              _buildAccountServiceSection(),

              // Policies
              _buildSectionHeader('নীতিমালা'),
              _buildPoliciesSection(),

              // Logout
              _buildLogoutButton(),

              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      width: double.infinity,
      color: AppColors.lightGrey.withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.grey,
        ),
      ),
    );
  }

  // ─── THE VOICE AGENT SECTION ───
  Widget _buildVoiceAgentSection() {
    return Material(
      color: AppColors.white,
      child: Column(
        children: [
          ListTile(
            leading: const AgentAiMark(size: 40),
            title: const Text(
              'এজেন্ট কল করুন',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'অ্যাপের ভেতরে বাংলায় কথা বলুন',
              style: TextStyle(fontSize: 12, color: AppColors.grey),
            ),
            trailing: const Icon(Icons.chevron_right, color: AppColors.grey),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const VoiceAgentScreen()),
              );
            },
          ),
          const Divider(height: 1, indent: 72),
          // Voice Agent Toggle
          ListTile(
            leading: const AgentAiMark(size: 40),
            title: const Text(
              'ভয়েস এজেন্ট',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              _voiceAgentEnabled ? 'সক্রিয়' : 'নিষ্ক্রিয়',
              style: TextStyle(
                fontSize: 12,
                color: _voiceAgentEnabled ? AppColors.green : AppColors.grey,
              ),
            ),
            trailing: Switch(
              value: _voiceAgentEnabled,
              onChanged: _toggleVoiceAgent,
              activeThumbColor: AppColors.green,
              activeTrackColor: AppColors.green.withValues(alpha: 0.3),
            ),
          ),

          // If voice agent enabled — show settings
          if (_voiceAgentEnabled) ...[
            const Divider(height: 1, indent: 72),

            // Transaction limit setting
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.security,
                        color: AppColors.orange, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ট্রানজেকশন লিমিট',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'প্রতি লেনদেনে সর্বোচ্চ পরিমাণ',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Limit input
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 8, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.offWhite,
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: AppColors.lightGrey),
                      ),
                      child: TextField(
                        controller: _limitController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          prefixText: '৳ ',
                          prefixStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.black,
                          ),
                          hintText: 'পরিমাণ দিন',
                          hintStyle: TextStyle(
                            color: AppColors.grey,
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isLoadingLimit ? null : _updateLimit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: AppColors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                    child: _isLoadingLimit
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.white,
                            ),
                          )
                        : const Text(
                            'সেভ',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ],
              ),
            ),

            // Current limit display
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 4, 20, 8),
              child: Text(
                'বর্তমান লিমিট: ৳${_transactionLimit.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.green,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            // Quick limit presets
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 0, 20, 12),
              child: Wrap(
                spacing: 8,
                children: [1000, 2000, 5000, 10000].map((amount) {
                  final isSelected = _transactionLimit == amount.toDouble();
                  return GestureDetector(
                    onTap: () {
                      _limitController.text = amount.toString();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primaryBlue
                            : AppColors.offWhite,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primaryBlue
                              : AppColors.lightGrey,
                        ),
                      ),
                      child: Text(
                        '৳$amount',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? AppColors.white
                              : AppColors.darkGrey,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

          ],
        ],
      ),
    );
  }

  Widget _buildSettingsSection() {
    return Material(
      color: AppColors.white,
      child: Column(
        children: [
          _buildMenuItem(
            icon: Icons.lock_outline,
            iconColor: AppColors.accentYellow,
            bgColor: AppColors.accentYellow.withValues(alpha: 0.12),
            title: 'পিন পরিবর্তন',
          ),
          _buildMenuItem(
            icon: Icons.language,
            iconColor: AppColors.green,
            bgColor: AppColors.green.withValues(alpha: 0.12),
            title: 'ভাষা পরিবর্তন',
          ),
          _buildMenuItem(
            icon: Icons.admin_panel_settings,
            iconColor: AppColors.primaryBlue,
            bgColor: AppColors.primaryBlue.withValues(alpha: 0.12),
            title: 'অনুমতি পরিবর্তন',
          ),
        ],
      ),
    );
  }

  Widget _buildSupportSection() {
    return Material(
      color: AppColors.white,
      child: Column(
        children: [
          _buildMenuItem(
            icon: Icons.support_agent,
            iconColor: AppColors.orange,
            bgColor: AppColors.orange.withValues(alpha: 0.12),
            title: '২৪x৭ সেবা',
          ),
          _buildMenuItem(
            icon: Icons.question_answer_outlined,
            iconColor: AppColors.orange,
            bgColor: AppColors.orange.withValues(alpha: 0.12),
            title: 'বহুল জিজ্ঞাসিত প্রশ্ন',
          ),
        ],
      ),
    );
  }

  Widget _buildAccountServiceSection() {
    return Material(
      color: AppColors.white,
      child: Column(
        children: [
          _buildMenuItem(
            icon: Icons.contacts,
            iconColor: AppColors.green,
            bgColor: AppColors.green.withValues(alpha: 0.12),
            title: 'অ্যাড্রেস বুক',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ContactsScreen()),
              );
            },
          ),
          _buildMenuItem(
            icon: Icons.info_outline,
            iconColor: AppColors.primaryBlue,
            bgColor: AppColors.primaryBlue.withValues(alpha: 0.12),
            title: 'MNP তথ্য আপডেট',
          ),
          _buildMenuItem(
            icon: Icons.settings,
            iconColor: AppColors.goldYellow,
            bgColor: AppColors.goldYellow.withValues(alpha: 0.12),
            title: 'উপায় চাকা',
          ),
          _buildMenuItem(
            icon: Icons.fingerprint,
            iconColor: AppColors.primaryBlue,
            bgColor: AppColors.primaryBlue.withValues(alpha: 0.12),
            title: 'ফিঙ্গারপ্রিন্ট/ফেস আইডি বন্ধ করুন',
          ),
          _buildMenuItem(
            icon: Icons.group,
            iconColor: AppColors.primaryBlue,
            bgColor: AppColors.primaryBlue.withValues(alpha: 0.12),
            title: 'রেফার উপায়',
          ),
        ],
      ),
    );
  }

  Widget _buildPoliciesSection() {
    return Material(
      color: AppColors.white,
      child: Column(
        children: [
          _buildMenuItem(
            icon: Icons.description_outlined,
            iconColor: AppColors.orange,
            bgColor: AppColors.orange.withValues(alpha: 0.12),
            title: 'শর্তাবলী',
          ),
          _buildMenuItem(
            icon: Icons.privacy_tip_outlined,
            iconColor: AppColors.green,
            bgColor: AppColors.green.withValues(alpha: 0.12),
            title: 'গোপনীয়তা নীতিমালা',
          ),
          _buildMenuItem(
            icon: Icons.info,
            iconColor: AppColors.primaryBlue,
            bgColor: AppColors.primaryBlue.withValues(alpha: 0.12),
            title: 'অ্যাপ-এর তথ্য',
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Material(
      color: AppColors.white,
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.red.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.logout, color: AppColors.red, size: 22),
        ),
        title: const Text(
          'লগ আউট',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.red,
          ),
        ),
        onTap: _logout,
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String title,
    VoidCallback? onTap,
  }) {
    return Column(
      children: [
        ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          trailing:
              const Icon(Icons.chevron_right, color: AppColors.grey),
          onTap: onTap ??
              () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$title — ডেমো মোড'),
                    duration: const Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    backgroundColor: AppColors.primaryBlue,
                  ),
                );
              },
        ),
        const Divider(height: 1, indent: 72),
      ],
    );
  }
}
