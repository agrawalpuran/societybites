import 'package:flutter/material.dart';

import '../../services/api_service.dart';

class AdminListingsScreen extends StatefulWidget {
  const AdminListingsScreen({super.key});

  @override
  State<AdminListingsScreen> createState() => _AdminListingsScreenState();
}

class _AdminListingsScreenState extends State<AdminListingsScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _listings = [];
  bool _isLoading = true;
  String? _error;
  int _page = 1;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadListings();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadListings({bool reset = true}) async {
    if (reset) {
      setState(() {
        _page = 1;
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final data = await ApiService.getAdminListings(
        search: _searchController.text.trim().isNotEmpty
            ? _searchController.text.trim()
            : null,
        page: _page,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _listings = data;
        } else {
          _listings.addAll(data);
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
    _loadListings(reset: false);
  }

  void _onSearch() {
    _loadListings();
  }

  Future<void> _toggleStatus(Map<String, dynamic> listing) async {
    final id = listing['id']?.toString() ?? '';
    final currentStatus = listing['status']?.toString() ?? 'active';
    final newStatus = currentStatus == 'active' ? 'disabled' : 'active';
    final action = newStatus == 'disabled' ? 'Disable' : 'Enable';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$action listing?'),
        content: Text(
          '$action "${listing['name'] ?? 'this listing'}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor:
                  newStatus == 'disabled' ? Colors.red : Colors.green,
            ),
            child: Text(action),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ApiService.updateAdminListing(id, status: newStatus);
      _loadListings();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Listing ${newStatus == "disabled" ? "disabled" : "enabled"}')),
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
          child: TextField(
            controller: _searchController,
            onSubmitted: (_) => _onSearch(),
            decoration: InputDecoration(
              hintText: 'Search listings...',
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
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading && _listings.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF0E5A47)),
      );
    }
    if (_error != null && _listings.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Color(0xFF6A7774))),
            const SizedBox(height: 12),
            ElevatedButton(
                onPressed: _loadListings, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_listings.isEmpty) {
      return const Center(
        child: Text('No listings found',
            style: TextStyle(color: Color(0xFF6A7774))),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF0E5A47),
      onRefresh: _loadListings,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _listings.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _listings.length) {
            _loadMore();
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF0E5A47)),
              ),
            );
          }

          final listing = _listings[index];
          final name = listing['name']?.toString() ?? 'Unnamed';
          final seller =
              (listing['seller'] as Map<String, dynamic>?)?['name']?.toString() ??
                  '—';
          final price = listing['price'] ?? 0;
          final status = listing['status']?.toString() ?? 'active';
          final society = (listing['society'] as Map<String, dynamic>?)
                  ?['name']
                  ?.toString() ??
              '—';
          final isDisabled = status == 'disabled';

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
            color: isDisabled ? const Color(0xFFFFF8F0) : Colors.white,
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isDisabled
                      ? const Color(0xFFFFE0B2)
                      : const Color(0xFFE8F5EE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.fastfood_rounded,
                  size: 20,
                  color: isDisabled
                      ? const Color(0xFFE65100)
                      : const Color(0xFF0E5A47),
                ),
              ),
              title: Text(
                name,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14),
              ),
              subtitle: Text(
                '$seller • ₹$price • $society',
                style:
                    const TextStyle(fontSize: 12, color: Color(0xFF6A7774)),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDisabled
                          ? const Color(0xFFFFE0B2)
                          : const Color(0xFFE8F5EE),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDisabled
                            ? const Color(0xFFE65100)
                            : const Color(0xFF2E7D32),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      isDisabled
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      size: 20,
                      color: const Color(0xFF8A9491),
                    ),
                    tooltip: isDisabled ? 'Enable' : 'Disable',
                    onPressed: () => _toggleStatus(listing),
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
