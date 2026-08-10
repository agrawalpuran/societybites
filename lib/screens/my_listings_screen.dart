import 'package:flutter/material.dart';

import '../models/data.dart';
import '../services/api_service.dart';
import '../services/seller_onboarding.dart';
import '../services/session_service.dart';
import '../widgets/app_header.dart';
import '../widgets/listing_image.dart';
import 'add_listing_screen.dart';

class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({super.key});

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen> {
  List<FoodItem> _listings = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadListings();
  }

  String _cleanError(Object e) {
    var message = e.toString();
    if (message.startsWith('Exception: ')) {
      message = message.substring('Exception: '.length);
    }
    return message;
  }

  Future<void> _loadListings() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final societyId =
          await SessionService.getSocietyId() ?? SessionService.defaultSocietyId;
      final userId = await SessionService.getUserId();
      if (userId == null) {
        throw Exception('Please log in again.');
      }

      final raw = await ApiService.getListings(
        societyId: societyId,
        sellerId: userId,
        status: 'all',
      );
      final listings = raw.map(FoodItem.fromJson).toList();

      if (!mounted) return;
      setState(() {
        _listings = listings;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _cleanError(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteListing(FoodItem listing) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove listing?'),
        content: Text(
          '"${listing.name}" will be hidden from buyers.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFD94F4F),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ApiService.deleteListing(listing.id);
      await _loadListings();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Listing removed')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove listing: ${_cleanError(e)}')),
      );
    }
  }

  Future<void> _pauseListing(FoodItem listing) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pause listing?'),
        content: Text(
          '"${listing.name}" will be hidden from buyers until you resume it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Pause'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ApiService.pauseListing(listing.id);
      await _loadListings();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Listing paused')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not pause: ${_cleanError(e)}')),
      );
    }
  }

  Future<void> _resumeListing(FoodItem listing) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resume listing?'),
        content: Text(
          '"${listing.name}" will be visible to buyers again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Resume'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ApiService.resumeListing(listing.id);
      await _loadListings();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Listing resumed')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not resume: ${_cleanError(e)}')),
      );
    }
  }

  Future<void> _openEditor([FoodItem? listing]) async {
    if (listing == null) {
      final canList = await SellerOnboarding.ensureCanCreateListing(context);
      if (!canList || !mounted) return;
    }

    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddListingScreen(existingListing: listing),
      ),
    );

    if (changed == true) {
      await _loadListings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppHeader(
              padding: const EdgeInsets.fromLTRB(4, 10, 20, 0),
              leading: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                color: const Color(0xFF3A4644),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'My Listings',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF101617),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _openEditor(),
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text('Add'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF0E5A47),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF0E5A47),
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Color(0xFFD94F4F)),
                            ),
                          ),
                        )
                      : _listings.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'No listings yet',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton(
                                    onPressed: () => _openEditor(),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0E5A47),
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Create first listing'),
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              color: const Color(0xFF0E5A47),
                              onRefresh: _loadListings,
                              child: ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(
                                  parent: BouncingScrollPhysics(),
                                ),
                                padding: const EdgeInsets.all(20),
                                itemCount: _listings.length,
                                itemBuilder: (_, index) {
                                  final listing = _listings[index];
                                  return _SellerListingCard(
                                    listing: listing,
                                    onEdit: () => _openEditor(listing),
                                    onDelete: () => _deleteListing(listing),
                                    onPause: () => _pauseListing(listing),
                                    onResume: () => _resumeListing(listing),
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SellerListingCard extends StatelessWidget {
  const _SellerListingCard({
    required this.listing,
    required this.onEdit,
    required this.onDelete,
    required this.onPause,
    required this.onResume,
  });

  final FoodItem listing;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPause;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final isPaused = listing.isPaused;
    final canPause = listing.isActive || listing.status == 'sold_out';
    final canResume = isPaused;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListingImage(
                food: listing,
                width: 72,
                height: 72,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            listing.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusBadge(status: listing.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₹${listing.price.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Color(0xFF0E5A47),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (canPause)
                TextButton.icon(
                  onPressed: onPause,
                  icon: const Icon(Icons.pause_circle_outline, size: 18),
                  label: const Text('Pause'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFB86A00),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              if (canResume)
                TextButton.icon(
                  onPressed: onResume,
                  icon: const Icon(Icons.play_circle_outline, size: 18),
                  label: const Text('Resume'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF0E5A47),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              const Spacer(),
              IconButton(
                onPressed: onEdit,
                tooltip: 'Edit',
                icon: const Icon(
                  Icons.edit_outlined,
                  color: Color(0xFF0E5A47),
                ),
              ),
              IconButton(
                onPressed: onDelete,
                tooltip: 'Remove',
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFD94F4F),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    late final String label;
    late final Color bg;
    late final Color fg;

    switch (status) {
      case 'paused':
        label = 'PAUSED';
        bg = const Color(0xFFFFF3E0);
        fg = const Color(0xFFB86A00);
        break;
      case 'sold_out':
        label = 'SOLD OUT';
        bg = const Color(0xFFFFEBEE);
        fg = const Color(0xFFC62828);
        break;
      case 'active':
      default:
        label = 'ACTIVE';
        bg = const Color(0xFFE8F5EE);
        fg = const Color(0xFF0E5A47);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
