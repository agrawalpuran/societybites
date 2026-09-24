import 'package:flutter/material.dart';

import '../models/data.dart';
import '../models/listing_availability.dart';
import '../services/api_service.dart';
import '../services/my_listings_cache.dart';
import '../services/seller_onboarding.dart';
import '../services/session_service.dart';
import '../widgets/app_header.dart';
import '../widgets/listing_image.dart';
import '../widgets/made_to_order_hint.dart';
import 'add_listing_screen.dart';

class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({
    super.key,
    this.fetchListings,
    this.updateCatalog,
    this.pauseAllListings,
    this.resumeAllListings,
  });

  /// Test seam. Production uses [ApiService.getListings].
  final Future<List<Map<String, dynamic>>> Function()? fetchListings;

  /// Test seam. Production uses [ApiService.updateListingCatalog].
  final Future<void> Function(String listingId, String catalogType)?
      updateCatalog;

  /// Test seam. Production uses [ApiService.pauseAllListings].
  final Future<Map<String, dynamic>> Function()? pauseAllListings;

  /// Test seam. Production uses [ApiService.resumeAllListings].
  final Future<Map<String, dynamic>> Function()? resumeAllListings;

  @override
  MyListingsScreenState createState() => MyListingsScreenState();
}

class MyListingsScreenState extends State<MyListingsScreen>
    with SingleTickerProviderStateMixin {
  List<FoodItem> _listings = [];
  bool _isLoading = true;
  bool _hasSuccessfullyLoaded = false;
  bool _bulkBusy = false;
  String? _error;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (mounted && !_tabController.indexIsChanging) setState(() {});
    });
    if (MyListingsCache.hasSnapshot) {
      _listings = MyListingsCache.listings;
      _isLoading = false;
      _hasSuccessfullyLoaded = true;
    }
    _loadListings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<FoodItem> get _regularReadyNowListings => _listings
      .where((item) => !item.isPreOrderCatalog && !item.isMadeToOrder)
      .toList();

  List<FoodItem> get _madeToOrderListings =>
      _listings.where((item) => item.isMadeToOrder).toList();

  List<FoodItem> get _preorderListings =>
      _listings.where((item) => item.isPreOrderCatalog).toList();

  bool get _isPreorderTab => _tabController.index == 3;
  bool get _isMadeToOrderTab => _tabController.index == 2;

  Future<void> reload() => _loadListings();

  String _cleanError(Object e) {
    var message = e.toString();
    if (message.startsWith('Exception: ')) {
      message = message.substring('Exception: '.length);
    }
    return message;
  }

  Future<void> _loadListings() async {
    if (!_hasSuccessfullyLoaded && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      List<Map<String, dynamic>> raw;
      final fetchListings = widget.fetchListings;
      if (fetchListings != null) {
        raw = await fetchListings();
      } else {
        final societyId = await SessionService.getSocietyId();
        final userId = await SessionService.getUserId();
        if (userId == null) {
          throw Exception('Please log in again.');
        }
        if (societyId == null || societyId.isEmpty) {
          throw Exception('Join your society to manage listings.');
        }

        raw = await ApiService.getListings(
          societyId: societyId,
          sellerId: userId,
          status: 'all',
          catalogType: 'all',
        ).timeout(
          const Duration(seconds: 20),
          onTimeout: () {
            throw Exception('Could not load listings. Please try again.');
          },
        );
      }
      final listings = <FoodItem>[];
      for (final item in raw) {
        try {
          listings.add(FoodItem.fromJson(item));
        } catch (_) {
          // Skip a corrupt row so one bad listing cannot blank the screen.
        }
      }

      MyListingsCache.replace(listings);
      if (!mounted) return;
      setState(() {
        _listings = listings;
        _isLoading = false;
        _hasSuccessfullyLoaded = true;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (!_hasSuccessfullyLoaded) {
        setState(() {
          _error = _cleanError(e);
          _isLoading = false;
        });
      }
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

  Future<void> _renewListing(FoodItem listing) async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => _RenewListingDialog(
        listingName: listing.name,
        initial: listing.availableAt,
      ),
    );

    if (picked == null) return;

    try {
      await ApiService.renewListing(
        listingId: listing.id,
        availableAt: picked,
      );
      await _loadListings();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Listing renewed')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not renew: ${_cleanError(e)}')),
      );
    }
  }

  Future<void> _openEditor([FoodItem? listing]) async {
    if (listing == null) {
      final canList = await SellerOnboarding.ensureCanCreateListing(context);
      if (!canList || !mounted) return;
    }

    final catalogType = listing?.catalogType ??
        (_isPreorderTab ? listingCatalogPreorder : listingCatalogRegular);

    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddListingScreen(
          existingListing: listing,
          catalogType: catalogType,
          initialAvailabilityMode: listing == null && _isMadeToOrderTab
              ? listingAvailabilityMadeToOrder
              : listingAvailabilityReadyNow,
        ),
      ),
    );

    if (changed == true) {
      await _loadListings();
    }
  }

  Future<void> _moveListing(FoodItem listing) async {
    final toPreorder = !listing.isPreOrderCatalog;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          toPreorder
              ? 'Move ${listing.name} to Pre-orders?'
              : 'Move ${listing.name} to Regular Orders?',
        ),
        content: Text(
          toPreorder
              ? 'This item will no longer be available for regular orders. Customers will only be able to order it through your pre-order campaigns.'
              : 'This item will become available for normal daily ordering.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Move'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final catalogType =
          toPreorder ? listingCatalogPreorder : listingCatalogRegular;
      final updateCatalog = widget.updateCatalog;
      if (updateCatalog != null) {
        await updateCatalog(listing.id, catalogType);
      } else {
        await ApiService.updateListingCatalog(
          listingId: listing.id,
          catalogType: catalogType,
        );
      }
      await _loadListings();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            toPreorder
                ? 'Moved to Pre-orders'
                : 'Moved to Regular Orders',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_cleanError(e))),
      );
    }
  }

  Future<void> _pauseAllListings() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pause all listings?'),
        content: const Text(
          'Your kitchen will temporarily stop accepting new orders.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirm-pause-all'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Pause All'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _bulkBusy = true);
    try {
      final pauseAll =
          widget.pauseAllListings ?? ApiService.pauseAllListings;
      final result = await pauseAll();
      await _loadListings();
      if (!mounted) return;
      final count = result['pausedCount'];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count is num && count > 0
                ? 'Paused $count listing${count == 1 ? '' : 's'}.'
                : 'Listings paused.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_cleanError(e))),
      );
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  Future<void> _renewAllListings() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renew all listings?'),
        content: const Text(
          'Eligible paused listings will become available again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirm-renew-all'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Renew All'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _bulkBusy = true);
    try {
      final resumeAll =
          widget.resumeAllListings ?? ApiService.resumeAllListings;
      final result = await resumeAll();
      await _loadListings();
      if (!mounted) return;
      final count = result['resumedCount'];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count is num && count > 0
                ? 'Renewed $count listing${count == 1 ? '' : 's'}.'
                : 'Eligible listings renewed.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_cleanError(e))),
      );
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
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
                    label: Text(
                      _isPreorderTab ? 'Add Pre-order Item' : 'Add Listing',
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF0E5A47),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _bulkBusy ? null : _pauseAllListings,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0E5A47),
                        side: const BorderSide(color: Color(0xFF0E5A47)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'Pause All',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _bulkBusy ? null : _renewAllListings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0E5A47),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'Renew All',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
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
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFFD94F4F),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _loadListings,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0E5A47),
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Try again'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            _buildCatalogTabs(),
                            Expanded(
                              child: TabBarView(
                                controller: _tabController,
                                children: [
                                  _buildCatalogPane(
                                    listings: _listings,
                                    emptyTitle: 'No listings yet',
                                    emptyBody:
                                        'Add food items for regular orders, made to order, or pre-orders.',
                                    addLabel: 'Add Listing',
                                  ),
                                  _buildCatalogPane(
                                    listings: _regularReadyNowListings,
                                    emptyTitle: 'No regular listings yet',
                                    emptyBody:
                                        'Add food items that customers can order anytime.',
                                    addLabel: 'Add Listing',
                                  ),
                                  _buildCatalogPane(
                                    listings: _madeToOrderListings,
                                    emptyTitle: 'No made-to-order listings yet',
                                    emptyBody:
                                        'Add items you will prepare after a buyer places an order.',
                                    addLabel: 'Add Listing',
                                  ),
                                  _buildCatalogPane(
                                    listings: _preorderListings,
                                    emptyTitle: 'No pre-order items yet',
                                    emptyBody:
                                        'Add food items that customers can order through your pre-order campaigns.',
                                    addLabel: 'Add Pre-order Item',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCatalogTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFFF0F2F1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicator: BoxDecoration(
            color: const Color(0xFF0E5A47),
            borderRadius: BorderRadius.circular(12),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerHeight: 0,
          labelColor: Colors.white,
          unselectedLabelColor: const Color(0xFF6A7774),
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          tabs: [
            Tab(text: 'All (${_listings.length})'),
            Tab(text: 'Regular (${_regularReadyNowListings.length})'),
            Tab(text: 'Made to Order (${_madeToOrderListings.length})'),
            Tab(text: 'Pre-orders (${_preorderListings.length})'),
          ],
        ),
      ),
    );
  }

  Widget _buildCatalogPane({
    required List<FoodItem> listings,
    required String emptyTitle,
    required String emptyBody,
    required String addLabel,
  }) {
    if (listings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                emptyTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                emptyBody,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF6A7774),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _openEditor(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0E5A47),
                  foregroundColor: Colors.white,
                ),
                child: Text(addLabel),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF0E5A47),
      onRefresh: _loadListings,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.all(20),
        itemCount: listings.length,
        itemBuilder: (_, index) {
          final listing = listings[index];
          return _SellerListingCard(
            listing: listing,
            onEdit: () => _openEditor(listing),
            onDelete: () => _deleteListing(listing),
            onPause: () => _pauseListing(listing),
            onResume: () => _resumeListing(listing),
            onRenew: () => _renewListing(listing),
            onMove: () => _moveListing(listing),
          );
        },
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
    required this.onRenew,
    required this.onMove,
  });

  final FoodItem listing;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onRenew;
  final VoidCallback onMove;

  @override
  Widget build(BuildContext context) {
    final isPaused = listing.isPaused;
    final isExpired = listing.isExpired;
    final canPause = listing.isActive || listing.status == 'sold_out';
    final canResume = isPaused;
    final canRenew = isExpired;

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
                    const SizedBox(height: 4),
                    Text(
                      listing.isPreOrderCatalog
                          ? 'PRE-ORDER'
                          : listing.isMadeToOrder
                              ? 'MADE TO ORDER'
                              : 'REGULAR',
                      style: const TextStyle(
                        fontSize: 11,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF6A7774),
                      ),
                    ),
                    if (listingSoldCaption(listing.quantitySold).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          listingSoldCaption(listing.quantitySold),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6A7774),
                          ),
                        ),
                      ),
                    if (listing.isMadeToOrder)
                      MadeToOrderHint(food: listing, compact: true),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ListingCardActions(
            listing: listing,
            canPause: canPause,
            canResume: canResume,
            canRenew: canRenew,
            onPause: onPause,
            onResume: onResume,
            onRenew: onRenew,
            onMove: onMove,
            onEdit: onEdit,
            onDelete: onDelete,
          ),
        ],
      ),
    );
  }
}

class _ListingCardActions extends StatelessWidget {
  const _ListingCardActions({
    required this.listing,
    required this.canPause,
    required this.canResume,
    required this.canRenew,
    required this.onPause,
    required this.onResume,
    required this.onRenew,
    required this.onMove,
    required this.onEdit,
    required this.onDelete,
  });

  final FoodItem listing;
  final bool canPause;
  final bool canResume;
  final bool canRenew;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onRenew;
  final VoidCallback onMove;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackEditDelete = constraints.maxWidth < 360;
        final statusButton = canPause
            ? _ListingPillButton(
                icon: Icons.pause_circle_outline,
                label: 'Pause',
                foreground: const Color(0xFFB86A00),
                background: const Color(0xFFFFF3E0),
                onTap: onPause,
              )
            : canResume
                ? _ListingPillButton(
                    icon: Icons.play_circle_outline,
                    label: 'Resume',
                    foreground: const Color(0xFF0E5A47),
                    background: const Color(0xFFE8F5EE),
                    onTap: onResume,
                  )
                : canRenew
                    ? _ListingPillButton(
                        icon: Icons.refresh_rounded,
                        label: 'Renew',
                        foreground: const Color(0xFF3A4644),
                        background: const Color(0xFFF0F2F1),
                        onTap: onRenew,
                      )
                    : null;

        final moveButton = _ListingPillButton(
          icon: Icons.swap_horiz_rounded,
          label: listing.isPreOrderCatalog
              ? 'Move to Regular Orders'
              : 'Move to Pre-orders',
          foreground: const Color(0xFF0E5A47),
          background: const Color(0xFFD6F0E4),
          onTap: onMove,
        );

        final editAction = _ListingIconAction(
          icon: Icons.edit_outlined,
          label: 'Edit',
          color: const Color(0xFF0E5A47),
          onTap: onEdit,
        );
        final deleteAction = _ListingIconAction(
          icon: Icons.delete_outline_rounded,
          label: 'Delete',
          color: const Color(0xFFD94F4F),
          onTap: onDelete,
        );

        if (stackEditDelete) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (statusButton != null)
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                      child: statusButton,
                    ),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                    child: moveButton,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: editAction),
                  Container(
                    width: 1,
                    height: 28,
                    color: const Color(0xFFEAEFED),
                  ),
                  Expanded(child: deleteAction),
                ],
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (statusButton != null) ...[
              Flexible(child: statusButton),
              const SizedBox(width: 8),
            ],
            Flexible(child: moveButton),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Container(
                width: 1,
                height: 32,
                color: const Color(0xFFEAEFED),
              ),
            ),
            editAction,
            deleteAction,
          ],
        );
      },
    );
  }
}

class _ListingPillButton extends StatelessWidget {
  const _ListingPillButton({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: foreground),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 2,
                    softWrap: true,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ListingIconAction extends StatelessWidget {
  const _ListingIconAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
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
      case 'expired':
        label = 'EXPIRED';
        bg = const Color(0xFFEEEEEE);
        fg = const Color(0xFF6A7774);
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

class _RenewListingDialog extends StatefulWidget {
  const _RenewListingDialog({
    required this.listingName,
    this.initial,
  });

  final String listingName;
  final DateTime? initial;

  @override
  State<_RenewListingDialog> createState() => _RenewListingDialogState();
}

class _RenewListingDialogState extends State<_RenewListingDialog> {
  late DateTime _dateTime;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final candidate =
        widget.initial ?? now.add(const Duration(hours: 2));
    _dateTime = candidate.isAfter(now)
        ? candidate
        : now.add(const Duration(hours: 2));
  }

  Future<void> _pickDateTime() async {
    final firstDate = listingAvailableUntilFirstDate();
    final lastDate = listingAvailableUntilLastDate();
    var initialDate =
        _dateTime.isBefore(firstDate) ? firstDate : _dateTime;
    if (initialDate.isAfter(lastDate)) initialDate = lastDate;
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'Available until (up to $listingAvailableUntilMaxDays days)',
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dateTime),
    );
    if (time == null || !mounted) return;

    setState(() {
      _dateTime =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  String get _formatted {
    final d = _dateTime;
    final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}, '
        '${h.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final valid = _dateTime.isAfter(DateTime.now());
    return AlertDialog(
      title: const Text('Renew listing'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Set a new Available Until for "${widget.listingName}".',
            style: const TextStyle(fontSize: 14, color: Color(0xFF3A4644)),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _pickDateTime,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F7F6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE0E5E3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_available_outlined,
                      color: Color(0xFF0E5A47)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _formatted,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF101617),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: !valid ? null : () => Navigator.pop(context, _dateTime),
          child: const Text('Renew'),
        ),
      ],
    );
  }
}
