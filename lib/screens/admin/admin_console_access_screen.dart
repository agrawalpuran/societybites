import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../../widgets/admin_loading_panel.dart';

class AdminConsoleAccessScreen extends StatefulWidget {
  const AdminConsoleAccessScreen({super.key});

  @override
  State<AdminConsoleAccessScreen> createState() =>
      _AdminConsoleAccessScreenState();
}

class _AdminConsoleAccessScreenState extends State<AdminConsoleAccessScreen> {
  final _phoneController = TextEditingController();
  List<Map<String, dynamic>> _admins = [];
  bool _loading = true;
  bool _assigning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAdmins();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadAdmins() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final admins = await ApiService.getAdminConsoleAdmins();
      if (!mounted) return;
      setState(() {
        _admins = admins;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiService.userFacingError(e);
        _loading = false;
      });
    }
  }

  Future<void> _assignByPhone() async {
    final raw = _phoneController.text.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a mobile number')),
      );
      return;
    }

    setState(() => _assigning = true);
    try {
      final result = await ApiService.grantAdminConsoleAccess(raw);
      if (!mounted) return;
      _phoneController.clear();
      await _loadAdmins();
      final already = result['alreadyAdmin'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            already
                ? 'User already has view-only console access'
                : 'Console admin access granted',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiService.userFacingError(e))),
      );
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  Future<void> _revoke(String userId, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke console access?'),
        content: Text(
          '$label will lose view-only admin portal access and return to buyer role.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ApiService.revokeAdminConsoleAccess(userId);
      await _loadAdmins();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Console access revoked')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiService.userFacingError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AdminLoadingPanel(message: 'Loading console admins…');
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        const Text(
          'Console admins',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF101617),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Grant view-only access to the admin portal by mobile number. '
          'Console admins can browse data but cannot change settings.',
          style: TextStyle(color: Color(0xFF6A7774), height: 1.4),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          decoration: InputDecoration(
            labelText: 'Mobile number',
            hintText: '10-digit Indian mobile',
            prefixText: '+91 ',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE6EBE9)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _assigning ? null : _assignByPhone,
          icon: _assigning
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.person_add_alt_1_rounded, size: 20),
          label: const Text('Grant console access'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0E5A47),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 28),
        const Text(
          'Active console admins',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF223531),
          ),
        ),
        const SizedBox(height: 12),
        if (_admins.isEmpty)
          const Text(
            'No console admins yet.',
            style: TextStyle(color: Color(0xFF8A9491)),
          )
        else
          ..._admins.map((admin) {
            final name = admin['name']?.toString().trim();
            final phone = admin['phone']?.toString() ?? '';
            final id = admin['id']?.toString() ?? '';
            final society =
                admin['society'] is Map
                    ? admin['society']['name']?.toString()
                    : null;
            final label = (name != null && name.isNotEmpty) ? name : phone;
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                title: Text(label),
                subtitle: Text(
                  [
                    phone,
                    if (society != null && society.isNotEmpty) society,
                  ].join(' • '),
                ),
                trailing: IconButton(
                  tooltip: 'Revoke access',
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                  onPressed: id.isEmpty ? null : () => _revoke(id, label),
                ),
              ),
            );
          }),
      ],
    );
  }
}
