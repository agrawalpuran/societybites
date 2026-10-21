import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../web/web_page_frame.dart';
import '../widgets/app_header.dart';
import '../widgets/status_banner.dart';

/// Manager invites an owner (view-only). No revoke in MVP.
class SellerOwnerAccessScreen extends StatefulWidget {
  const SellerOwnerAccessScreen({super.key});

  @override
  State<SellerOwnerAccessScreen> createState() =>
      _SellerOwnerAccessScreenState();
}

class _SellerOwnerAccessScreenState extends State<SellerOwnerAccessScreen> {
  final _phoneController = TextEditingController();
  List<Map<String, dynamic>> _owners = [];
  bool _loading = true;
  bool _inviting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final owners = await ApiService.listSellerStaffOwners();
      if (!mounted) return;
      setState(() {
        _owners = owners;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _invite() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the owner mobile number')),
      );
      return;
    }
    setState(() => _inviting = true);
    try {
      await ApiService.inviteSellerStaffOwner(phone: phone);
      if (!mounted) return;
      _phoneController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Owner invited. They can view your kitchen after login.'),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _inviting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return centerOnWeb(
      context,
      Scaffold(
        backgroundColor: const Color(0xFFF8FAF9),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppHeader(
                showCart: false,
                padding: const EdgeInsets.fromLTRB(4, 10, 20, 0),
                leading: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                color: const Color(0xFF3A4644),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Text(
                'Owner access',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF101617),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: Text(
                'Invite the business owner to view this kitchen. They cannot accept orders or change listings.',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6A7774),
                  height: 1.35,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d+\s-]')),
                      ],
                      decoration: InputDecoration(
                        hintText: 'Owner mobile number',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFFE0E5E3)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFFE0E5E3)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _inviting ? null : _invite,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0E5A47),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _inviting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Invite'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF0E5A47)),
                    )
                  : _error != null
                      ? StatusBanner(
                          message: _error!,
                          action: TextButton(
                            onPressed: _load,
                            child: const Text('Retry'),
                          ),
                        )
                      : RefreshIndicator(
                          color: const Color(0xFF0E5A47),
                          onRefresh: _load,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                            children: [
                              if (_owners.isEmpty)
                                const StatusBanner(
                                  padding: EdgeInsets.zero,
                                  message:
                                      'No owner invited yet. Add their mobile number above.',
                                )
                              else ...[
                                const Text(
                                  'OWNERS WITH ACCESS',
                                  style: TextStyle(
                                    fontSize: 11,
                                    letterSpacing: 1,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF6A7774),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                for (final owner in _owners)
                                  _OwnerRow(owner: owner),
                              ],
                            ],
                          ),
                        ),
            ),
            ],
          ),
        ),
      ),
      maxWidth: 720,
    );
  }
}

class _OwnerRow extends StatelessWidget {
  const _OwnerRow({required this.owner});

  final Map<String, dynamic> owner;

  @override
  Widget build(BuildContext context) {
    final name = (owner['staffName'] as String?)?.trim();
    final phone = (owner['staffPhone'] as String?)?.trim() ?? '';
    final title = (name != null && name.isNotEmpty) ? name : phone;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: Row(
        children: [
          const Icon(Icons.visibility_outlined, color: Color(0xFF0E5A47)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.isEmpty ? 'Owner' : title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                if (name != null && name.isNotEmpty && phone.isNotEmpty)
                  Text(
                    phone,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6A7774),
                    ),
                  ),
                const SizedBox(height: 2),
                const Text(
                  'View only',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF9A6B00),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
