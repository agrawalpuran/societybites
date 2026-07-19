import 'package:flutter/material.dart';

import '../../services/api_service.dart';

class AdminSocietiesScreen extends StatefulWidget {
  const AdminSocietiesScreen({super.key});

  @override
  State<AdminSocietiesScreen> createState() => _AdminSocietiesScreenState();
}

class _AdminSocietiesScreenState extends State<AdminSocietiesScreen> {
  List<Map<String, dynamic>> _societies = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSocieties();
  }

  Future<void> _loadSocieties() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getAdminSocieties();
      if (!mounted) return;
      setState(() {
        _societies = data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _showCreateDialog() async {
    final nameController = TextEditingController();
    final cityController = TextEditingController();
    final codeController = TextEditingController();
    final addressController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Society'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildField(nameController, 'Society Name'),
              const SizedBox(height: 12),
              _buildField(cityController, 'City'),
              const SizedBox(height: 12),
              _buildField(codeController, 'Invite Code'),
              const SizedBox(height: 12),
              _buildField(addressController, 'Address (optional)'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0E5A47),
              foregroundColor: Colors.white,
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result != true) return;

    if (nameController.text.trim().isEmpty ||
        cityController.text.trim().isEmpty ||
        codeController.text.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name, City, and Invite Code are required')),
      );
      return;
    }

    try {
      await ApiService.createAdminSociety(
        name: nameController.text.trim(),
        city: cityController.text.trim(),
        inviteCode: codeController.text.trim(),
        address: addressController.text.trim().isNotEmpty
            ? addressController.text.trim()
            : null,
      );
      _loadSocieties();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Society created')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  Future<void> _showEditDialog(Map<String, dynamic> society) async {
    final id = society['id']?.toString() ?? '';
    final nameController =
        TextEditingController(text: society['name']?.toString() ?? '');
    final cityController =
        TextEditingController(text: society['city']?.toString() ?? '');
    final addressController =
        TextEditingController(text: society['address']?.toString() ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Society'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildField(nameController, 'Society Name'),
              const SizedBox(height: 12),
              _buildField(cityController, 'City'),
              const SizedBox(height: 12),
              _buildField(addressController, 'Address'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0E5A47),
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != true) return;

    try {
      await ApiService.updateAdminSociety(
        id,
        name: nameController.text.trim(),
        city: cityController.text.trim(),
        address: addressController.text.trim().isNotEmpty
            ? addressController.text.trim()
            : null,
      );
      _loadSocieties();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Society updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  Future<void> _regenerateCode(Map<String, dynamic> society) async {
    final id = society['id']?.toString() ?? '';
    final name = society['name']?.toString() ?? 'this society';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Regenerate Invite Code?'),
        content: Text(
          'This will invalidate the current invite code for "$name". '
          'Members who haven\'t joined yet will need the new code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Regenerate'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final result = await ApiService.regenerateInviteCode(id);
      _loadSocieties();
      if (!mounted) return;
      final newCode = result['inviteCode']?.toString() ?? 'updated';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('New invite code: $newCode')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  Widget _buildField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF5F7F6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFEAEFED)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFEAEFED)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF0E5A47)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        backgroundColor: const Color(0xFF0E5A47),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Society'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF0E5A47)),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Color(0xFF6A7774))),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadSocieties, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_societies.isEmpty) {
      return const Center(
        child: Text('No societies', style: TextStyle(color: Color(0xFF6A7774))),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF0E5A47),
      onRefresh: _loadSocieties,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _societies.length,
        itemBuilder: (context, index) {
          final s = _societies[index];
          final name = s['name']?.toString() ?? 'Unknown';
          final inviteCode = s['inviteCode']?.toString() ?? '—';
          final memberCount = s['memberCount'] ?? s['_count']?['members'] ?? 0;
          final listingCount =
              s['listingCount'] ?? s['_count']?['listings'] ?? 0;
          final city = s['city']?.toString() ?? '';

          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF101617),
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (val) {
                          if (val == 'edit') _showEditDialog(s);
                          if (val == 'regen') _regenerateCode(s);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit'),
                          ),
                          const PopupMenuItem(
                            value: 'regen',
                            child: Text('Regenerate Code'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      _InfoChip(
                          icon: Icons.vpn_key_rounded, label: inviteCode),
                      if (city.isNotEmpty)
                        _InfoChip(
                            icon: Icons.location_city_rounded, label: city),
                      _InfoChip(
                          icon: Icons.people_rounded,
                          label: '$memberCount members'),
                      _InfoChip(
                          icon: Icons.fastfood_rounded,
                          label: '$listingCount listings'),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: const Color(0xFF8A9491)),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF6A7774),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
