import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/agent_api.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<dynamic> _contacts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() => _isLoading = true);
    final contacts = await AgentApi.fetchContacts();
    if (mounted) {
      setState(() {
        _contacts = contacts ?? [];
        _isLoading = false;
      });
    }
  }

  void _showAddContactDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    bool saving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('নতুন কন্টাক্ট'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'নাম',
                    hintText: 'যেমন: রাকিব',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'মোবাইল নম্বর',
                    hintText: '১১ ডিজিটের নম্বর',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(context),
                child: const Text('ক্যানসেল'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: AppColors.white,
                ),
                onPressed: saving
                    ? null
                    : () async {
                        final name = nameCtrl.text.trim();
                        final phone = phoneCtrl.text.trim();
                        if (name.isEmpty || phone.isEmpty || phone.length != 11) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('সঠিক নাম ও ১১ ডিজিটের নম্বর দিন')),
                          );
                          return;
                        }
                        setStateDialog(() => saving = true);
                        final success = await AgentApi.addContact(name, phone);
                        if (success && mounted) {
                          Navigator.pop(context);
                          _loadContacts();
                        } else if (mounted) {
                          setStateDialog(() => saving = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('কন্টাক্ট সেভ করতে সমস্যা হয়েছে')),
                          );
                        }
                      },
                child: saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white))
                    : const Text('সেভ'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: AppColors.white,
        title: const Text('অ্যাড্রেস বুক', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _contacts.isEmpty
              ? const Center(child: Text('কোনো কন্টাক্ট পাওয়া যায়নি', style: TextStyle(fontSize: 16, color: AppColors.grey)))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _contacts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final c = _contacts[i];
                    return Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.accentYellow,
                          child: Text(
                            c['name'].toString().substring(0, 1).toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.black),
                          ),
                        ),
                        title: Text(c['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(c['phone_number']),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primaryBlue,
        onPressed: _showAddContactDialog,
        child: const Icon(Icons.add, color: AppColors.white),
      ),
    );
  }
}
