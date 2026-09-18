import 'package:flutter/material.dart';

import '../models/data.dart';
import '../models/nearby_seller.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';
import '../widgets/guest_order_auth.dart';
import '../widgets/listing_image.dart';
import '../widgets/one_seller_cart.dart';
import '../widgets/preorder_widgets.dart';
import 'buyer_preorder_detail_screen.dart';
import 'checkout_screen.dart';
import 'food_detail_screen.dart';
import 'home_listing_filter.dart';
import 'login_screen.dart';

class _CachedStorefront {
  const _CachedStorefront({
    required this.products,
    required this.campaigns,
  });

  final List<FoodItem> products;
  final List<PreOrderCampaign> campaigns;
}

/// Session-only in-memory storefront cache, keyed by seller ID.
class SellerStorefrontMemoryCache {
  SellerStorefrontMemoryCache._();

  static final Map<String, _CachedStorefront> _bySellerId = {};

  @visibleForTesting
  static void clear() => _bySellerId.clear();

  static _CachedStorefront? _read(String sellerId) {
    final cached = _bySellerId[sellerId];
    if (cached == null) return null;
    return _CachedStorefront(
      products: List<FoodItem>.from(cached.products),
      campaigns: List<PreOrderCampaign>.from(cached.campaigns),
    );
  }

  static void _write({
    required String sellerId,
    required List<FoodItem> products,
    required List<PreOrderCampaign> campaigns,
  }) {
    _bySellerId[sellerId] = _CachedStorefront(
      products: List<FoodItem>.from(products),
      campaigns: List<PreOrderCampaign>.from(campaigns),
    );
  }
}

class SellerStorefrontScreen extends StatefulWidget {
  const SellerStorefrontScreen({
    super.key,
    required this.seller,
    this.cartItems,
    this.onCartChanged,
    this.fetchListings,
    this.fetchCampaigns,
    this.nearbyContext,
    this.guestBrowse = false,
    this.guestSocietyName,
    this.browseOnly = false,
    this.initialProducts,
    this.foodTypeFilter,
  });

  final Seller seller;
  final List<CartItem>? cartItems;
  final VoidCallback? onCartChanged;

  /// Test seams. Production uses listings and campaign APIs.
  final Future<List<Map<String, dynamic>>> Function()? fetchListings;
  final Future<List<Map<String, dynamic>>> Function()? fetchCampaigns;

  /// Nearby discovery context. Does not enable cross-society ordering.
  final NearbySellerCard? nearbyContext;

  /// Public guest kitchen browse. Add/order requires authentication.
  final bool guestBrowse;
  final String? guestSocietyName;
  final bool browseOnly;
  final List<FoodItem>? initialProducts;

  /// Optional VEG / NON_VEG filter inherited from Home. Null keeps all items.
  final String? foodTypeFilter;

  @override
  SellerStorefrontScreenState createState() => SellerStorefrontScreenState();
}

class SellerStorefrontScreenState extends State<SellerStorefrontScreen> {
  final List<CartItem> _localCart = [];
  List<FoodItem> _products = [];
  List<PreOrderCampaign> _campaigns = [];
  bool _loading = true;
  bool _hasSuccessfullyLoaded = false;
  String? _error;

  List<CartItem> get _cart => widget.cartItems ?? _localCart;

  List<FoodItem> get _visibleProducts => listingsMatchingFoodType(
        _products,
        foodType: widget.foodTypeFilter,
      );

  @override
  void initState() {
    super.initState();
    final cached = SellerStorefrontMemoryCache._read(widget.seller.id);
    final initial = widget.initialProducts;
    if (cached != null) {
      _products = cached.products;
      _campaigns = cached.campaigns;
      _hasSuccessfullyLoaded = true;
      _loading = false;
    } else if (initial != null && initial.isNotEmpty) {
      _products = List<FoodItem>.from(initial);
      _hasSuccessfullyLoaded = true;
      _loading = false;
    }
    _load();
  }

  Future<void> reload() => _load();

  Future<void> _load() async {
    if (!_hasSuccessfullyLoaded) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      late final List<Map<String, dynamic>> listingRaw;
      late final List<Map<String, dynamic>> campaignRaw;
      final fetchListings = widget.fetchListings;
      final fetchCampaigns = widget.fetchCampaigns;
      if (fetchListings != null && fetchCampaigns != null) {
        final responses = await Future.wait([
          fetchListings(),
          fetchCampaigns(),
        ]);
        listingRaw = responses[0];
        campaignRaw = responses[1];
      } else if (widget.guestBrowse) {
        final raw = await ApiService.getGuestKitchenStorefront(widget.seller.id);
        final listings = raw['listings'];
        listingRaw = listings is List
            ? listings
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList()
            : <Map<String, dynamic>>[];
        campaignRaw = const [];
      } else {
        if (widget.nearbyContext != null) {
          final raw = await ApiService.getNearbySellerStorefront(
            widget.seller.id,
          );
          final listings = raw['listings'];
          listingRaw = listings is List
              ? listings
                    .whereType<Map>()
                    .map((item) => Map<String, dynamic>.from(item))
                    .toList()
              : <Map<String, dynamic>>[];
          campaignRaw = const [];
        } else {
          final societyId = await SessionService.getSocietyId();
          if (societyId == null || societyId.isEmpty) {
            if (!mounted) return;
            if (!_hasSuccessfullyLoaded) {
              setState(() {
                _products = [];
                _campaigns = [];
                _loading = false;
                _error = 'Join your society to view this storefront.';
              });
            }
            return;
          }
          final responses = await Future.wait([
            ApiService.getListings(
              societyId: societyId,
              sellerId: widget.seller.id,
              catalogType: 'REGULAR',
            ),
            ApiService.getPreOrderCampaigns(
              societyId: societyId,
              sellerId: widget.seller.id,
              status: 'open',
            ),
          ]);
          listingRaw = responses[0];
          campaignRaw = responses[1];
        }
      }
      final products = listingRaw
          .map(FoodItem.fromJson)
          .where((item) => item.isActive && !item.isPreOrder)
          .toList();
      final now = DateTime.now();
      final campaigns =
          campaignRaw
              .map(PreOrderCampaign.fromJson)
              .where(
                (campaign) =>
                    campaign.status == 'open' &&
                    campaign.products.isNotEmpty &&
                    now.isBefore(campaign.orderCutoffAt),
              )
              .toList()
            ..sort((a, b) => a.orderCutoffAt.compareTo(b.orderCutoffAt));
      SellerStorefrontMemoryCache._write(
        sellerId: widget.seller.id,
        products: products,
        campaigns: campaigns,
      );
      if (!mounted) return;
      setState(() {
        _products = products;
        _campaigns = campaigns;
        _loading = false;
        _hasSuccessfullyLoaded = true;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      if (!_hasSuccessfullyLoaded) {
        setState(() {
          _error = cleanApiError(error);
          _loading = false;
        });
      }
    }
  }

  int _cartQuantity(FoodItem food) {
    final index = _cart.indexWhere((item) => item.food.id == food.id);
    return index == -1 ? 0 : _cart[index].quantity;
  }

  Future<void> _changeCart(FoodItem food, int delta) async {
    if (widget.guestBrowse && delta > 0) {
      await showGuestOrderAuthDialog(context);
      return;
    }
    if (delta > 0 && food.quantity <= 0) {
      _show('${food.name} is sold out.');
      return;
    }
    if (_cart.isNotEmpty && _cart.first.food.sellerId != food.sellerId) {
      final replace = await confirmReplaceSellerCart(
        context,
        currentSellerName: _cart.first.food.sellerName,
      );
      if (!replace || !mounted) return;
      setState(_cart.clear);
    }
    final current = _cartQuantity(food);
    if (delta > 0 && current >= food.quantity) {
      _show('Only ${food.quantity} available for ${food.name}.');
      return;
    }
    setState(() {
      final index = _cart.indexWhere((item) => item.food.id == food.id);
      if (index == -1 && delta > 0) {
        _cart.add(CartItem(food: food));
      } else if (index != -1) {
        _cart[index].quantity += delta;
        if (_cart[index].quantity <= 0) _cart.removeAt(index);
      }
    });
    widget.onCartChanged?.call();
  }

  void _show(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty) return;
    if (!await SessionService.isSignedIn()) {
      if (!context.mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }
    if (!context.mounted) return;
    final placed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(
          cartItems: _cart
              .map((item) => CartItem(food: item.food, quantity: item.quantity))
              .toList(),
          isCrossSociety: widget.nearbyContext != null,
          sellerFulfilment: widget.nearbyContext?.fulfilment,
          sellerSocietyName: widget.nearbyContext?.societyName,
        ),
      ),
    );
    if (placed == true && mounted) {
      setState(_cart.clear);
      widget.onCartChanged?.call();
      await _load();
    }
  }

  double get _rating {
    final reviewCount = _reviewCount;
    if (reviewCount == 0) return widget.seller.rating;
    final productTotal = _products.fold<double>(
      0,
      (sum, item) => sum + item.rating * item.reviewCount,
    );
    final campaignTotal = _campaigns
        .expand((campaign) => campaign.products)
        .fold<double>(0, (sum, item) => sum + item.rating * item.reviewCount);
    return (productTotal + campaignTotal) / reviewCount;
  }

  int get _reviewCount {
    final regular = _products.fold<int>(
      0,
      (sum, item) => sum + item.reviewCount,
    );
    final campaign = _campaigns
        .expand((campaign) => campaign.products)
        .fold<int>(0, (sum, item) => sum + item.reviewCount);
    return regular + campaign;
  }

  String? get _location {
    if (_products.isNotEmpty) return _products.first.locationLabel;
    final block = widget.seller.block.trim();
    return block.isEmpty || block == 'Block ?' ? null : block;
  }

  String _formatCharge(double? amount) {
    final value = amount ?? 0;
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }

  int get _cartCount => _cart.fold<int>(0, (sum, item) => sum + item.quantity);

  double get _cartTotal =>
      _cart.fold<double>(0, (sum, item) => sum + item.total);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: preorderBackground,
      appBar: AppBar(
        backgroundColor: preorderBackground,
        foregroundColor: preorderText,
        elevation: 0,
        title: const Text(
          'Seller Storefront',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: RefreshIndicator(
        color: preorderGreen,
        onRefresh: _load,
        child: _content(),
      ),
      floatingActionButton: widget.browseOnly || _cart.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _checkout,
              backgroundColor: preorderGreen,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.shopping_bag_rounded),
              label: Text(
                '$_cartCount items  •  ${formatMoney(_cartTotal)}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _content() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(),
                if (_error != null && !_hasSuccessfullyLoaded) ...[
                  const SizedBox(height: 18),
                  PreOrderEmptyState(
                    title: 'Unable to load this store',
                    message: _error!,
                    action: OutlinedButton(
                      onPressed: _load,
                      child: const Text('Try again'),
                    ),
                  ),
                ] else if (_loading && !_hasSuccessfullyLoaded) ...[
                  const SizedBox(height: 28),
                  _sectionTitle('PRODUCTS'),
                  const SizedBox(height: 12),
                  _productSkeletonGrid(),
                ] else if (_visibleProducts.isEmpty && _campaigns.isEmpty) ...[
                  const SizedBox(height: 24),
                  const PreOrderEmptyState(
                    title: 'Nothing available right now',
                    message: 'This seller has no items available right now.',
                  ),
                ] else ...[
                  if (_visibleProducts.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    _sectionTitle('PRODUCTS'),
                    const SizedBox(height: 12),
                    _productGrid(),
                  ] else ...[
                    const SizedBox(height: 28),
                    const Text(
                      'No products available',
                      style: TextStyle(
                        color: preorderMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (_campaigns.isNotEmpty && !widget.guestBrowse) ...[
                    const SizedBox(height: 30),
                    _sectionTitle('PRE-ORDERS'),
                    const SizedBox(height: 12),
                    ..._campaigns.map(_campaignCard),
                  ],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _header() {
    final location = _location;
    final reviews = _reviewCount > 0 ? _reviewCount : widget.seller.reviewCount;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: preorderBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: widget.seller.avatarColor,
            child: Icon(
              widget.seller.avatarIcon,
              color: preorderGreen,
              size: 34,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.seller.name,
                  style: const TextStyle(
                    color: preorderText,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (widget.guestBrowse &&
                    (widget.guestSocietyName ?? widget.seller.block)
                        .trim()
                        .isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.guestSocietyName ?? widget.seller.block,
                    style: const TextStyle(color: preorderMuted),
                  ),
                ] else if (widget.nearbyContext != null) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Nearby seller',
                    style: TextStyle(
                      color: preorderGreen,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      widget.nearbyContext!.societyName,
                      if (widget.nearbyContext!.distanceLabel.isNotEmpty)
                        widget.nearbyContext!.distanceLabel,
                    ].join(' • '),
                    style: const TextStyle(color: preorderMuted),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (widget.nearbyContext!.offersDelivery)
                        const Text(
                          '🛵 Seller Delivery',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      if (widget.nearbyContext!.deliveryChargeLabel != null)
                        Text(
                          widget.nearbyContext!.deliveryChargeLabel ==
                                  'Free delivery'
                              ? 'Free delivery'
                              : 'Delivery charge ₹${_formatCharge(widget.nearbyContext!.fulfilment.deliveryCharge)}',
                          style: const TextStyle(color: preorderMuted),
                        ),
                      if (widget.nearbyContext!.offersPickup)
                        const Text(
                          '🏠 Pickup Available',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                    ],
                  ),
                ],
                if (_rating > 0 || reviews > 0) ...[
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 10,
                    runSpacing: 5,
                    children: [
                      if (_rating > 0)
                        Text(
                          '⭐ ${_rating.toStringAsFixed(1)}',
                          style: const TextStyle(
                            color: preorderText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      if (reviews > 0)
                        Text(
                          '$reviews review${reviews == 1 ? '' : 's'}',
                          style: const TextStyle(color: preorderMuted),
                        ),
                    ],
                  ),
                ],
                if (location != null) ...[
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        color: preorderMuted,
                        size: 17,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          location,
                          style: const TextStyle(color: preorderMuted),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _productSkeletonGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 3 : 2;
        return GridView.builder(
          key: const Key('storefront-product-skeletons'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 4,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: constraints.maxWidth >= 720 ? .78 : .72,
          ),
          itemBuilder: (context, index) => const _StorefrontProductSkeleton(),
        );
      },
    );
  }

  Widget _productGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 3 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _visibleProducts.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: constraints.maxWidth >= 720 ? .78 : .72,
          ),
          itemBuilder: (context, index) => _productCard(_visibleProducts[index]),
        );
      },
    );
  }

  Widget _productCard(FoodItem food) {
    final quantity = _cartQuantity(food);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FoodDetailScreen(
                food: food,
                onSellerTap: () => Navigator.pop(context),
                requireAuthToOrder: widget.guestBrowse,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: preorderBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ListingImage(
                  food: food,
                  width: double.infinity,
                  height: double.infinity,
                  borderRadius: 14,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                food.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: preorderText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    formatMoney(food.price),
                    style: const TextStyle(
                      color: preorderGreen,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  if (widget.browseOnly)
                    const SizedBox.shrink()
                  else if (food.quantity <= 0)
                    const Text(
                      'Sold out',
                      style: TextStyle(
                        color: Color(0xFFD94F4F),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  else if (quantity == 0)
                    _smallButton(
                      label: 'Add',
                      onTap: () => _changeCart(food, 1),
                    )
                  else
                    Row(
                      children: [
                        _quantityButton(
                          Icons.remove,
                          () => _changeCart(food, -1),
                        ),
                        SizedBox(
                          width: 28,
                          child: Text(
                            '$quantity',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        _quantityButton(
                          Icons.add,
                          () => _changeCart(food, 1),
                          filled: true,
                        ),
                      ],
                    ),
                ],
              ),
              if (food.quantity > 0) ...[
                const SizedBox(height: 5),
                Text(
                  '${food.quantity} available',
                  style: const TextStyle(color: preorderMuted, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _campaignCard(PreOrderCampaign campaign) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: preorderBorder),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BuyerPreOrderDetailScreen(
                campaignId: campaign.id,
                initialCampaign: campaign,
                regularCartHasItems: _cart.isNotEmpty,
                cartItems: _cart,
                onCartChanged: widget.onCartChanged,
                onSellerTap: () => Navigator.pop(context),
              ),
            ),
          ).then((_) => _load());
        },
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PreOrderCoverImage(
                imageUrl: campaign.coverImageUrl,
                width: 128,
                height: 112,
                borderRadius: 15,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PreOrderBadge(compact: true),
                    const SizedBox(height: 8),
                    Text(
                      campaign.title,
                      style: const TextStyle(
                        color: preorderText,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (campaign.description?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        campaign.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: preorderMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      formatOrderByLabel(campaign.orderCutoffAt),
                      style: const TextStyle(
                        color: preorderMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      formatReadyAt(campaign.fulfilmentAt),
                      style: const TextStyle(
                        color: preorderGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFFADB5B2)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _smallButton({required String label, required VoidCallback onTap}) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: preorderGreen,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: Text(label),
    );
  }

  Widget _quantityButton(
    IconData icon,
    VoidCallback onTap, {
    bool filled = false,
  }) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 17),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 31, height: 31),
      style: IconButton.styleFrom(
        backgroundColor: filled ? preorderGreen : Colors.white,
        foregroundColor: filled ? Colors.white : preorderText,
        side: filled ? null : const BorderSide(color: Color(0xFFD4DBD8)),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: preorderMuted,
        fontSize: 12,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _StorefrontProductSkeleton extends StatelessWidget {
  const _StorefrontProductSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: preorderBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFEAEFED),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            height: 14,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFEAEFED),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 14,
            width: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFEAEFED),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ],
      ),
    );
  }
}
