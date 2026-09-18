import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../widgets/listing_image.dart';
import '../widgets/app_header.dart';
import '../models/data.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';
import '../widgets/preorder_widgets.dart';
import 'buyer_preorder_detail_screen.dart';
import 'buyer_preorders_screen.dart';
import 'checkout_screen.dart';
import 'food_detail_screen.dart';
import 'explore_nearby_screen.dart';
import 'login_screen.dart';
import 'seller_list_screen.dart';
import 'seller_storefront_screen.dart';
import 'tab_preload.dart';
import '../services/seller_onboarding.dart';
import 'home_listing_filter.dart';
import '../widgets/food_type_selector.dart';
import '../widgets/one_seller_cart.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.onInitialLoadSuccess,
    this.fetchListings,
    this.onStartSelling,
    this.onExploreNearby,
    this.initialCategory,
  });

  /// Fired once after the first successful listings load so MainShell can
  /// start conservative background preload of other tabs.
  final VoidCallback? onInitialLoadSuccess;

  /// Test seam. Production uses [ApiService.getListings].
  final Future<List<Map<String, dynamic>>> Function()? fetchListings;

  final VoidCallback? onStartSelling;
  final VoidCallback? onExploreNearby;
  final String? initialCategory;

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final List<CartItem> _cart = [];
  final TextEditingController _searchController = TextEditingController();

  List<FoodItem> _listings = [];
  List<PreOrderCampaign> _preOrderCampaigns = [];
  bool _preOrdersLoading = true;
  bool _isLoading = true;
  bool _hasSuccessfullyLoaded = false;
  String? _error;
  String _searchQuery = '';
  String? _selectedCategory;
  String? _selectedFoodType;
  bool _didNotifyInitialSuccess = false;

  bool get isLoadInProgress => _isLoading;
  bool get hasSuccessfullyLoaded => _hasSuccessfullyLoaded;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
    debugPreloadLog('HOME INITIAL LOAD');
    _searchController.addListener(_onSearchChanged);
    _loadListings();
    _loadPreOrders();
  }

  /// Called by MainShell on failed first-load retry, app resume, and FCM.
  void refresh() {
    _loadListings();
    _loadPreOrders();
  }

  Future<void> _refreshHome() async {
    await Future.wait([_loadListings(), _loadPreOrders()]);
  }

  Future<void> _loadPreOrders() async {
    try {
      final societyId = await SessionService.getSocietyId();
      if (societyId == null || societyId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _preOrderCampaigns = [];
          _preOrdersLoading = false;
        });
        return;
      }
      final userId = await SessionService.getUserId();
      final raw = await ApiService.getPreOrderCampaigns(
        societyId: societyId,
        status: 'open',
      );
      final now = DateTime.now();
      final campaigns =
          raw
              .map(PreOrderCampaign.fromJson)
              .where(
                (campaign) =>
                    campaign.sellerId != userId &&
                    campaign.products.isNotEmpty &&
                    campaign.status == 'open' &&
                    now.isBefore(campaign.orderCutoffAt),
              )
              .toList()
            ..sort((a, b) => a.fulfilmentAt.compareTo(b.fulfilmentAt));
      if (!mounted) return;
      setState(() {
        _preOrderCampaigns = campaigns.take(3).toList();
        _preOrdersLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _preOrdersLoading = false);
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() => _searchQuery = _searchController.text.trim());
  }

  List<FoodItem> get _filteredListings {
    return applyHomeListingFilters(
      _listings,
      category: _selectedCategory,
      searchQuery: _searchQuery,
      foodType: _selectedFoodType,
    );
  }

  List<Seller> get _sellers => sellersFromListings(_filteredListings);

  Future<void> _loadListings() async {
    final showSpinner = !_hasSuccessfullyLoaded;
    if (showSpinner) {
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
        if (societyId == null || societyId.isEmpty) {
          if (!mounted) return;
          if (!_hasSuccessfullyLoaded) {
            setState(() {
              _listings = [];
              _error = 'Join your society to see listings.';
              _isLoading = false;
            });
          }
          return;
        }
        raw = await ApiService.getListings(
          societyId: societyId,
          catalogType: 'REGULAR',
        );
      }
      final listings = raw.map(FoodItem.fromJson).toList();

      if (!mounted) return;

      setState(() {
        _listings = listings;
        _isLoading = false;
        _hasSuccessfullyLoaded = true;
        _error = null;
      });
      _notifyInitialLoadSuccess();
    } catch (e) {
      if (!mounted) return;
      if (!_hasSuccessfullyLoaded) {
        setState(() {
          _listings = [];
          _error = 'Unable to load sellers right now.';
          _isLoading = false;
        });
      }
    }
  }

  void _notifyInitialLoadSuccess() {
    if (_didNotifyInitialSuccess) return;
    _didNotifyInitialSuccess = true;
    final callback = widget.onInitialLoadSuccess;
    if (callback == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) callback();
    });
  }

  List<FoodItem> get _specials => _filteredListings.take(3).toList();

  List<FoodItem> get _available {
    final filtered = _filteredListings;
    return filtered.length > 3 ? filtered.sublist(3) : filtered;
  }

  Future<void> _addToCart(FoodItem food) async {
    if (food.quantity <= 0) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${food.name} is sold out'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: const Color(0xFFD94F4F),
        ),
      );
      return;
    }

    if (_cart.isNotEmpty) {
      final cartSellerId = _cart.first.food.sellerId;
      if (food.sellerId != cartSellerId) {
        final replace = await confirmReplaceSellerCart(
          context,
          currentSellerName: _cart.first.food.sellerName,
        );
        if (!replace || !mounted) return;
        setState(_cart.clear);
      }
    }

    final currentInCart = _cart
        .where((c) => c.food.id == food.id)
        .fold<int>(0, (sum, c) => sum + c.quantity);
    if (currentInCart >= food.quantity) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Only ${food.quantity} available for ${food.name}'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: const Color(0xFFD94F4F),
        ),
      );
      return;
    }
    setState(() {
      final existing = _cart.indexWhere((c) => c.food.id == food.id);
      if (existing != -1) {
        _cart[existing].quantity++;
      } else {
        _cart.add(CartItem(food: food));
      }
    });
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${food.name} added to cart'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _removeFromCart(FoodItem food) {
    setState(() {
      final existing = _cart.indexWhere((c) => c.food.id == food.id);
      if (existing != -1) {
        if (_cart[existing].quantity > 1) {
          _cart[existing].quantity--;
        } else {
          _cart.removeAt(existing);
        }
      }
    });
  }

  int _cartQtyFor(FoodItem food) {
    final idx = _cart.indexWhere((c) => c.food.id == food.id);
    return idx != -1 ? _cart[idx].quantity : 0;
  }

  void _openDetail(FoodItem food) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FoodDetailScreen(
          food: food,
          onSellerTap: () => _openSeller(sellerFromListing(food)),
        ),
      ),
    );
  }

  void _openSeller(Seller seller) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SellerStorefrontScreen(
          seller: seller,
          cartItems: _cart,
          onCartChanged: () {
            if (mounted) setState(() {});
          },
          foodTypeFilter: _selectedFoodType,
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF0E5A47)),
            )
          : SafeArea(
              child: RefreshIndicator(
                color: const Color(0xFF0E5A47),
                onRefresh: _refreshHome,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader()),
                    if (_showEmptySocietyState) ...[
                      SliverToBoxAdapter(child: _buildEmptySocietyState()),
                    ] else ...[
                    if (_error != null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF0F0),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFE8B4B4),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Live data unavailable',
                                  style: TextStyle(
                                    color: Color(0xFFB42318),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: Color(0xFF7A271A),
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextButton.icon(
                                  onPressed: _loadListings,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    SliverToBoxAdapter(child: _buildSearchBar()),
                    SliverToBoxAdapter(child: _buildCategoryChips()),
                    SliverToBoxAdapter(child: _buildPreOrdersSection()),
                    if (_sellers.isNotEmpty)
                      SliverToBoxAdapter(child: _buildSellersSection()),
                    if (_specials.isNotEmpty)
                      SliverToBoxAdapter(child: _buildSpecialsSection()),
                    SliverToBoxAdapter(child: _buildAvailableHeader()),
                    _buildAvailableList(),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                  ],
                ),
              ),
            ),
      floatingActionButton: _cart.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () async {
                final signedIn = await SessionService.isSignedIn();
                if (!context.mounted) return;
                if (!signedIn) {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                  return;
                }
                final placed = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CheckoutScreen(cartItems: List.from(_cart)),
                  ),
                );

                if (placed == true && mounted) {
                  setState(() => _cart.clear());
                  _loadListings();
                }
              },
              backgroundColor: const Color(0xFF0E5A47),
              foregroundColor: Colors.white,
              icon: const Icon(
                Icons.shopping_bag_rounded,
                size: 20,
                color: Colors.white,
              ),
              label: Text(
                '${_cart.fold<int>(0, (sum, c) => sum + c.quantity)} items  •  ₹${_cart.fold<double>(0, (sum, c) => sum + c.total).toStringAsFixed(0)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildPreOrdersSection() {
    if (_preOrdersLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              color: preorderGreen,
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }
    if (_preOrderCampaigns.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 8, 10),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Pre-orders',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: preorderText,
                  ),
                ),
              ),
              TextButton(
                onPressed: _openBuyerPreOrders,
                child: const Text(
                  'See all →',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0E5A47),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: HomePreOrderCampaignCard.cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _preOrderCampaigns.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final campaign = _preOrderCampaigns[index];
              return HomePreOrderCampaignCard(
                campaign: campaign,
                onTap: () => _openBuyerPreOrderDetail(campaign),
              );
            },
          ),
        ),
      ],
    );
  }

  void _openBuyerPreOrders() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BuyerPreOrdersScreen(
          hasRegularCart: _cart.isNotEmpty,
          cartItems: _cart,
          initialCampaigns: List<PreOrderCampaign>.from(_preOrderCampaigns),
          onCartChanged: () {
            if (mounted) setState(() {});
          },
        ),
      ),
    ).then((_) => _loadPreOrders());
  }

  Future<void> _openBuyerPreOrderDetail(PreOrderCampaign campaign) async {
    final placed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BuyerPreOrderDetailScreen(
          campaignId: campaign.id,
          initialCampaign: campaign,
          regularCartHasItems: _cart.isNotEmpty,
          cartItems: _cart,
          onCartChanged: () {
            if (mounted) setState(() {});
          },
        ),
      ),
    );
    if (placed == true) {
      _loadPreOrders();
    }
  }

  bool get _showEmptySocietyState {
    return _hasSuccessfullyLoaded &&
        _error == null &&
        _listings.isEmpty &&
        _preOrderCampaigns.isEmpty &&
        !_preOrdersLoading &&
        _searchQuery.isEmpty &&
        _selectedCategory == null;
  }

  Future<void> _startSellingFromHome() async {
    if (widget.onStartSelling != null) {
      widget.onStartSelling!();
      return;
    }
    try {
      final enabled = await SellerOnboarding.startSelling(context);
      if (!enabled || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selling enabled — add a listing from Dashboard'),
          backgroundColor: Color(0xFF0E5A47),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not enable selling: $error')),
      );
    }
  }

  void _openExploreNearby() {
    if (widget.onExploreNearby != null) {
      widget.onExploreNearby!();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ExploreNearbyScreen()),
    );
  }

  Widget _buildEmptySocietyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE6EBE9)),
        ),
        child: Column(
          children: [
            const Text(
              'No sellers available yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF101617),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Be the first one to share homemade food in your community.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF3A4644),
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Discover home food from nearby societies',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF6A7774)),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _startSellingFromHome,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0E5A47),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Start Selling'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _openExploreNearby,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0E5A47),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Explore Nearby'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return const AppHeader();
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE6EBE9)),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  const Icon(
                    Icons.search_rounded,
                    color: Color(0xFF8A9491),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: 'Search meals, sellers, blocks…',
                        hintStyle: TextStyle(
                          color: Color(0xFFADB5B2),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      style: const TextStyle(
                        color: Color(0xFF223531),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (_searchQuery.isNotEmpty)
                    IconButton(
                      onPressed: () {
                        _searchController.clear();
                      },
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Color(0xFF8A9491),
                        size: 20,
                      ),
                    )
                  else
                    Container(
                      width: 38,
                      height: 38,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F7F6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.tune_rounded,
                        color: Color(0xFF3A4644),
                        size: 20,
                      ),
                    ),
                ],
              ),
            ),
          ),
          FoodTypeFilterChips(
            selectedFoodType: _selectedFoodType,
            onChanged: (value) {
              setState(() => _selectedFoodType = value);
            },
          ),
        ],
      ),
    );
  }

  static const _categories = [
    'All',
    'Breakfast',
    'Lunch',
    'Dinner',
    'Snacks',
    'Desserts',
    'Beverages',
    'Healthy',
    'Jain',
    'Kids',
    'Homemade Specials',
  ];

  Widget _buildCategoryChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      child: SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: _categories.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final cat = _categories[i];
            final isSelected =
                (_selectedCategory == null && cat == 'All') ||
                _selectedCategory == cat;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedCategory = cat == 'All' ? null : cat;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF0E5A47)
                      : const Color(0xFFF5F7F6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF0E5A47)
                        : const Color(0xFFE0E5E3),
                  ),
                ),
                child: Text(
                  cat,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : const Color(0xFF3A4644),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSellersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
          child: Row(
            children: [
              const Text(
                'Top Rated Sellers',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF101617),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SellerListScreen(
                        sellers: _sellers,
                        onSellerTap: _openSeller,
                      ),
                    ),
                  );
                },
                child: const Text(
                  'SEE ALL',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0E5A47),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _sellers.length,
            separatorBuilder: (context, index) => const SizedBox(width: 16),
            itemBuilder: (_, i) => _SellerChip(
              seller: _sellers[i],
              onTap: () => _openSeller(_sellers[i]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSpecialsSection() {
    return _TodaysSpecialsSection(
      specials: _specials,
      cartQtyFor: _cartQtyFor,
      onAdd: _addToCart,
      onRemove: _removeFromCart,
      onTap: _openDetail,
      onSellerTap: (food) => _openSeller(sellerFromListing(food)),
    );
  }

  Widget _buildAvailableHeader() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 24, 20, 14),
      child: Text(
        'Available Now',
        style: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w800,
          color: Color(0xFF101617),
        ),
      ),
    );
  }

  Widget _buildAvailableList() {
    if (_filteredListings.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Text(
            _searchQuery.isNotEmpty
                ? 'No listings match "$_searchQuery".'
                : _selectedCategory != null
                ? 'No listings in $_selectedCategory yet.'
                : 'No listings yet. Be the first to add food from the seller dashboard.',
            style: const TextStyle(
              color: Color(0xFF6A7774),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) => _AvailableItemTile(
          food: _available[i],
          cartQty: _cartQtyFor(_available[i]),
          onAdd: () => _addToCart(_available[i]),
          onRemove: () => _removeFromCart(_available[i]),
          onTap: () => _openDetail(_available[i]),
          onSellerTap: () => _openSeller(sellerFromListing(_available[i])),
        ),
        childCount: _available.length,
      ),
    );
  }
}

class _SellerChip extends StatelessWidget {
  const _SellerChip({required this.seller, required this.onTap});
  final Seller seller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: seller.avatarColor,
              border: Border.all(color: const Color(0xFF0E5A47), width: 2.4),
            ),
            child: Icon(
              seller.avatarIcon,
              color: const Color(0xFF3A4644),
              size: 28,
            ),
          ),
          SizedBox(height: isIos ? 4 : 8),
          SizedBox(
            width: 72,
            height: isIos ? 32 : null,
            child: Text(
              seller.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF3A4644),
                height: isIos ? 1.1 : 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Today's Specials carousel with scroll-synced pagination dots.
/// Page count is derived from scroll extent vs card stride (not one-dot-per-item).
class _TodaysSpecialsSection extends StatefulWidget {
  const _TodaysSpecialsSection({
    required this.specials,
    required this.cartQtyFor,
    required this.onAdd,
    required this.onRemove,
    required this.onTap,
    required this.onSellerTap,
  });

  final List<FoodItem> specials;
  final int Function(FoodItem food) cartQtyFor;
  final void Function(FoodItem food) onAdd;
  final void Function(FoodItem food) onRemove;
  final void Function(FoodItem food) onTap;
  final void Function(FoodItem food) onSellerTap;

  @override
  State<_TodaysSpecialsSection> createState() => _TodaysSpecialsSectionState();
}

class _TodaysSpecialsSectionState extends State<_TodaysSpecialsSection> {
  static const double _cardWidth = 190;
  static const double _gap = 14;
  static const double _stride = _cardWidth + _gap;

  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<_SpecialsPageInfo> _pageInfo = ValueNotifier(
    const _SpecialsPageInfo(activePage: 0, pageCount: 1),
  );

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_syncPageFromScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPageFromScroll());
  }

  @override
  void didUpdateWidget(covariant _TodaysSpecialsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.specials.length != widget.specials.length) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _syncPageFromScroll(),
      );
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_syncPageFromScroll);
    _scrollController.dispose();
    _pageInfo.dispose();
    super.dispose();
  }

  void _syncPageFromScroll() {
    if (!_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final pageCount = maxScroll <= 0 ? 1 : (maxScroll / _stride).ceil() + 1;
    final offset = _scrollController.offset.clamp(0.0, maxScroll);
    final activePage = (pageCount <= 1 || maxScroll <= 0)
        ? 0
        : ((offset / maxScroll) * (pageCount - 1)).round().clamp(
            0,
            pageCount - 1,
          );

    final next = _SpecialsPageInfo(
      activePage: activePage,
      pageCount: pageCount,
    );
    if (_pageInfo.value != next) {
      _pageInfo.value = next;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 2),
          child: Row(
            children: [
              const Text(
                "Today's Specials",
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF101617),
                ),
              ),
              const Spacer(),
              ValueListenableBuilder<_SpecialsPageInfo>(
                valueListenable: _pageInfo,
                builder: (context, info, _) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      info.pageCount,
                      (i) => Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(left: 5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == info.activePage
                              ? const Color(0xFF0E5A47)
                              : const Color(0xFFD4DBD8),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 268,
          child: ListView.separated(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: widget.specials.length,
            separatorBuilder: (context, index) => const SizedBox(width: _gap),
            itemBuilder: (_, i) {
              final food = widget.specials[i];
              return _SpecialCard(
                food: food,
                cartQty: widget.cartQtyFor(food),
                onAdd: () => widget.onAdd(food),
                onRemove: () => widget.onRemove(food),
                onTap: () => widget.onTap(food),
                onSellerTap: () => widget.onSellerTap(food),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SpecialsPageInfo {
  const _SpecialsPageInfo({required this.activePage, required this.pageCount});

  final int activePage;
  final int pageCount;

  @override
  bool operator ==(Object other) =>
      other is _SpecialsPageInfo &&
      other.activePage == activePage &&
      other.pageCount == pageCount;

  @override
  int get hashCode => Object.hash(activePage, pageCount);
}

class _SpecialCard extends StatelessWidget {
  const _SpecialCard({
    required this.food,
    required this.cartQty,
    required this.onAdd,
    required this.onRemove,
    required this.onTap,
    required this.onSellerTap,
  });

  final FoodItem food;
  final int cartQty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onTap;
  final VoidCallback onSellerTap;

  @override
  Widget build(BuildContext context) {
    final isDark = food.bgColor.computeLuminance() < 0.4;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 190,
        decoration: BoxDecoration(
          color: food.bgColor,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(isDark ? 50 : 220),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.star_rounded,
                      size: 14,
                      color: isDark ? Colors.amber : Colors.amber.shade700,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      food.rating > 0 ? food.rating.toString() : 'New',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF3A4644),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: ListingImage(
                  food: food,
                  width: 120,
                  height: 120,
                  borderRadius: 0,
                  iconSize: 64,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
              child: Text(
                food.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF101617),
                  height: 1.2,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 2),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: onSellerTap,
                    child: Text(
                      'By ${food.sellerName}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white : const Color(0xFF0E5A47),
                        decoration: TextDecoration.underline,
                        decorationColor: isDark
                            ? Colors.white
                            : const Color(0xFF0E5A47),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      ' • ${food.locationLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.white70
                            : const Color(0xFF6A7774),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 10, 14),
              child: Row(
                children: [
                  Text(
                    '₹${food.price.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF101617),
                    ),
                  ),
                  if (food.quantity > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${food.quantity} left',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Colors.white70
                            : const Color(0xFF6A7774),
                      ),
                    ),
                  ],
                  const Spacer(),
                  food.quantity <= 0
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD94F4F),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'SOLD OUT',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        )
                      : cartQty == 0
                      ? GestureDetector(
                          onTap: onAdd,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0E5A47),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Add',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0E5A47),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: onRemove,
                                child: const Icon(
                                  Icons.remove,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Text(
                                  '$cartQty',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: onAdd,
                                child: const Icon(
                                  Icons.add,
                                  size: 18,
                                  color: Colors.white,
                                ),
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
}

class _AvailableItemTile extends StatelessWidget {
  const _AvailableItemTile({
    required this.food,
    required this.cartQty,
    required this.onAdd,
    required this.onRemove,
    required this.onTap,
    required this.onSellerTap,
  });

  final FoodItem food;
  final int cartQty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onTap;
  final VoidCallback onSellerTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFEAEFED)),
        ),
        child: Row(
          children: [
            ListingImage(food: food, width: 72, height: 72, iconSize: 36),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          food.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF101617),
                          ),
                        ),
                      ),
                      Text(
                        '₹${food.price.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0E5A47),
                        ),
                      ),
                      if (food.quantity > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${food.quantity} left',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6A7774),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: GestureDetector(
                          onTap: onSellerTap,
                          child: Text(
                            food.sellerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF0E5A47),
                              decoration: TextDecoration.underline,
                              decorationColor: Color(0xFF0E5A47),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      Flexible(
                        child: Text(
                          ', ${food.locationLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF6A7774),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: Colors.amber,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        food.rating > 0 ? food.rating.toString() : 'New',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF3A4644),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5EE),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.schedule_rounded,
                              size: 13,
                              color: Color(0xFF0E5A47),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${food.pickupTime} pickup',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF0E5A47),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      food.quantity <= 0
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD94F4F),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'SOLD OUT',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            )
                          : cartQty == 0
                          ? GestureDetector(
                              onTap: onAdd,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0E5A47),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  'Add',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0E5A47),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GestureDetector(
                                    onTap: onRemove,
                                    child: const Icon(
                                      Icons.remove,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    child: Text(
                                      '$cartQty',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: onAdd,
                                    child: const Icon(
                                      Icons.add,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
