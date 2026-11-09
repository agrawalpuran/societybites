import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/selling_reach.dart';
import '../../services/api_service.dart';
import '../../services/deep_link_navigation.dart';
import '../../services/deep_link_service.dart';
import '../../services/session_service.dart';
import '../../services/storefront_host.dart';
import '../../widgets/admin_loading_panel.dart';
import '../../widgets/screen_loading_note.dart';

const _kitchenSlugPattern = r'^[a-z0-9](?:[a-z0-9-]{0,28}[a-z0-9])?$';
const _reservedKitchenSlugs = {'www', 'app', 'api', 'admin', 'kitchen'};

/// Admin-facing label for a user's chosen selling reach (read-only).
String adminUserSellingReachLabel(Map<String, dynamic> user) {
  final level = parseSellingReachLevel(user['sellingReachLevel']);
  if (!level.isBeyondSociety) return 'My society';

  final rawKm = user['sellingReachRadiusKm'];
  final km = rawKm is num
      ? rawKm.toDouble()
      : double.tryParse(rawKm?.toString() ?? '');
  if (km != null && km > 0) {
    return 'Up to ${formatReachRadiusKm(km)} km';
  }
  return 'Beyond society';
}

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
  bool _isSuperAdmin = false;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    final role = await SessionService.getRole();
    if (!mounted) return;
    setState(() => _isSuperAdmin = role == 'super_admin');
    await _loadUsers();
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

  bool _isSellerRole(String role) =>
      role == 'seller' || role == 'super_admin';

  String? _kitchenSlugError(String raw) {
    final slug = raw.trim().toLowerCase();
    if (slug.isEmpty) return null;
    if (slug.length < 2) return 'At least 2 characters';
    if (!RegExp(_kitchenSlugPattern).hasMatch(slug)) {
      return 'Lowercase letters, numbers, and hyphens only';
    }
    if (_reservedKitchenSlugs.contains(slug)) return 'Reserved link';
    return null;
  }

  String _kitchenPublicUrl(String slug) {
    final host = StorefrontHost.kitchenPublicHost(slug);
    if (host != null) return 'https://$host';
    return DeepLinkService.kitchenSiteUrl(slug);
  }

  Future<void> _editKitchenLink(Map<String, dynamic> user) async {
    final userId = user['id']?.toString() ?? '';
    if (userId.isEmpty) return;

    final initial = user['storefrontSlug']?.toString().trim() ?? '';
    final controller = TextEditingController(text: initial);
    var saving = false;
    String? fieldError;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final slug = controller.text.trim().toLowerCase();
            final validation = _kitchenSlugError(slug);
            final preview =
                slug.isNotEmpty && validation == null ? _kitchenPublicUrl(slug) : '';

            Future<void> save({required bool clear}) async {
              if (saving) return;
              if (!clear) {
                final error = _kitchenSlugError(controller.text);
                if (error != null) {
                  setDialogState(() => fieldError = error);
                  return;
                }
              }
              setDialogState(() {
                saving = true;
                fieldError = null;
              });
              try {
                await ApiService.updateAdminUser(
                  userId,
                  clearStorefrontSlug: clear,
                  storefrontSlug:
                      clear ? null : controller.text.trim().toLowerCase(),
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                await _loadUsers();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      clear ? 'Kitchen link cleared' : 'Kitchen link saved',
                    ),
                  ),
                );
              } catch (e) {
                if (!ctx.mounted) return;
                setDialogState(() {
                  saving = false;
                  fieldError = e.toString().replaceFirst('Exception: ', '');
                });
              }
            }

            return AlertDialog(
              title: const Text('Kitchen website link'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sets the branded URL slug. Add GoDaddy + Vercel DNS '
                      'for the subdomain until wildcard *.societyeats.com is live.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6A7774),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      autocorrect: false,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9-]')),
                        TextInputFormatter.withFunction(
                          (old, value) =>
                              value.copyWith(text: value.text.toLowerCase()),
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Slug',
                        hintText: 'puran',
                        errorText: fieldError ?? validation,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() => fieldError = null),
                    ),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SelectableText(
                        preview,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0E5A47),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => DeepLinkNavigation.copyLink(
                          ctx,
                          url: preview,
                          successMessage: 'Link copied',
                        ),
                        icon: const Icon(Icons.link_rounded, size: 18),
                        label: const Text('Copy link'),
                      ),
                    ],
                    const SizedBox(height: 8),
                    const Text(
                      'Path-only (no subdomain DNS): …/kitchen/{slug} on main site.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF8A9491)),
                    ),
                  ],
                ),
              ),
              actions: [
                if (initial.isNotEmpty)
                  TextButton(
                    onPressed: saving ? null : () => save(clear: true),
                    child: const Text(
                      'Clear',
                      style: TextStyle(color: Color(0xFFB44D3A)),
                    ),
                  ),
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving || validation != null
                      ? null
                      : () => save(clear: false),
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
  }

  Future<void> _showUserActions(Map<String, dynamic> user) async {
    final userId = user['id']?.toString() ?? '';
    final currentRole = user['role']?.toString() ?? 'buyer';
    final isSuspended = user['suspended'] == true;
    final kitchenSlug = user['storefrontSlug']?.toString().trim() ?? '';
    final showKitchenLink =
        _isSuperAdmin && _isSellerRole(currentRole);

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
              const SizedBox(height: 4),
              Text(
                'Selling reach: ${adminUserSellingReachLabel(user)}',
                style: const TextStyle(color: Color(0xFF6A7774)),
              ),
              if (kitchenSlug.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Kitchen link: $kitchenSlug',
                  style: const TextStyle(
                    color: Color(0xFF0E5A47),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              if (showKitchenLink)
                ListTile(
                  leading: const Icon(
                    Icons.language_rounded,
                    color: Color(0xFF0E5A47),
                  ),
                  title: const Text('Kitchen website link'),
                  subtitle: Text(
                    kitchenSlug.isEmpty
                        ? 'Not set — tap to assign slug'
                        : 'Slug: $kitchenSlug',
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_editKitchenLink(user));
                  },
                ),
              if (showKitchenLink) const Divider(),
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
              ...['buyer', 'seller', 'admin'].map((role) {
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
            children: ['', 'buyer', 'seller', 'admin'].map((role) {
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
      return const ScreenLoadingNote(message: 'Loading users…');
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
            return const ScreenLoadingNote(message: 'Loading more…');
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
          final reach = adminUserSellingReachLabel(user);
          final kitchenSlug = user['storefrontSlug']?.toString().trim() ?? '';

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
                  [
                    if (kitchenSlug.isNotEmpty) 'Kitchen: $kitchenSlug',
                    '$phone • $society • Reach: $reach • Joined ${_formatDate(joinedAt)}',
                  ].join(' • '),
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
