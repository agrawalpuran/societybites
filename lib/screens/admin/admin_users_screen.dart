import 'package:flutter/material.dart';

import '../../services/api_service.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _searchController = TextEditingController();
  String _roleFilter = '';
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  String? _error;
  int _page = 1;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers({bool reset = true}) async {
    if (reset) {
      setState(() {
        _page = 1;
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final data = await ApiService.getAdminUsers(
        search: _searchController.text.trim().isNotEmpty
            ? _searchController.text.trim()
            : null,
        role: _roleFilter.isNotEmpty ? _roleFilter : null,
        page: _page,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _users = data;
        } else {
          _users.addAll(data);
        }
        _hasMore = data.length >= 20;
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

  void _loadMore() {
    if (!_hasMore || _isLoading) return;
    _page++;
    _loadUsers(reset: false);
  }

  void _onSearch() {
    _loadUsers();
  }

  void _onRoleChanged(String role) {
    _roleFilter = role;
    _loadUsers();
  }

  Future<void> _showUserActions(Map<String, dynamic> user) async {
    final userId = user['id']?.toString() ?? '';
    final currentRole = user['role']?.toString() ?? 'buyer';
    final isSuspended = user['suspended'] == true;

    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user['name']?.toString() ?? 'User',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF101617),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Role: $currentRole • ${isSuspended ? "Suspended" : "Active"}',
                style: const TextStyle(color: Color(0xFF6A7774)),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Icon(
                  isSuspended ? Icons.check_circle : Icons.block,
                  color: isSuspended ? Colors.green : Colors.red,
                ),
                title: Text(isSuspended ? 'Activate User' : 'Suspend User'),
                onTap: () {
                  Navigator.pop(ctx);
                  _toggleSuspend(userId, !isSuspended);
                },
              ),
              const Divider(),
              const Padding(
                padding: EdgeInsets.only(left: 16, top: 8, bottom: 8),
                child: Text(
                  'Change Role',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF8A9491),
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              ...['buyer', 'seller', 'super_admin'].map((role) {
                return ListTile(
                  leading: Icon(
                    role == currentRole
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: const Color(0xFF0E5A47),
                  ),
                  title: Text(role),
                  onTap: role == currentRole
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          _changeRole(userId, role);
                        },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggleSuspend(String userId, bool suspend) async {
    final action = suspend ? 'suspend' : 'activate';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${suspend ? "Suspend" : "Activate"} user?'),
        content: Text('Are you sure you want to $action this user?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: suspend ? Colors.red : Colors.green,
            ),
            child: Text(suspend ? 'Suspend' : 'Activate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ApiService.updateAdminUser(userId, suspended: suspend);
      _loadUsers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('User ${suspend ? "suspended" : "activated"}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  Future<void> _changeRole(String userId, String newRole) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change role?'),
        content: Text('Change this user\'s role to "$newRole"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF0E5A47),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ApiService.updateAdminUser(userId, role: newRole);
      _loadUsers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Role changed to $newRole')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onSubmitted: (_) => _onSearch(),
                  decoration: InputDecoration(
                    hintText: 'Search by name or phone...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        _onSearch();
                      },
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFEAEFED)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFEAEFED)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: ['', 'buyer', 'seller', 'super_admin'].map((role) {
              final isActive = _roleFilter == role;
              final label =
                  role.isEmpty ? 'All' : role[0].toUpperCase() + role.substring(1);
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  selected: isActive,
                  label: Text(label),
                  selectedColor: const Color(0xFFE8F5EE),
                  checkmarkColor: const Color(0xFF0E5A47),
                  onSelected: (_) => _onRoleChanged(role),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _buildContent(),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading && _users.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF0E5A47)),
      );
    }
    if (_error != null && _users.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Color(0xFF6A7774))),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadUsers, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_users.isEmpty) {
      return const Center(
        child: Text('No users found', style: TextStyle(color: Color(0xFF6A7774))),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF0E5A47),
      onRefresh: _loadUsers,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _users.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _users.length) {
            _loadMore();
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF0E5A47)),
              ),
            );
          }

          final user = _users[index];
          final name = user['name']?.toString() ?? 'Unknown';
          final phone = user['phone']?.toString() ?? '';
          final role = user['role']?.toString() ?? 'buyer';
          final society =
              (user['society'] as Map<String, dynamic>?)?['name']?.toString() ??
                  '—';
          final joinedAt = user['createdAt']?.toString() ?? '';
          final isSuspended = user['suspended'] == true;

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
            color: isSuspended ? const Color(0xFFFFF3F3) : Colors.white,
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              onTap: () => _showUserActions(user),
              leading: CircleAvatar(
                backgroundColor: isSuspended
                    ? const Color(0xFFFFCDD2)
                    : const Color(0xFFE8F5EE),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isSuspended
                        ? const Color(0xFFC62828)
                        : const Color(0xFF0E5A47),
                  ),
                ),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F2F1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      role,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0E5A47),
                      ),
                    ),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '$phone • $society • Joined ${_formatDate(joinedAt)}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6A7774)),
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded,
                  color: Color(0xFFADB5B2)),
            ),
          );
        },
      ),
    );
  }

  String _formatDate(String iso) {
    if (iso.isEmpty) return '—';
    try {
      final d = DateTime.parse(iso);
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) {
      return iso;
    }
  }
}
