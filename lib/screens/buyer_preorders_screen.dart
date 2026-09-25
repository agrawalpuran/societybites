import 'package:flutter/material.dart';

import '../models/data.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';
import '../widgets/preorder_widgets.dart';
import 'buyer_preorder_detail_screen.dart';
import 'home_listing_filter.dart';
import 'seller_storefront_screen.dart';

class BuyerPreOrdersScreen extends StatefulWidget {
  const BuyerPreOrdersScreen({
    super.key,
    this.hasRegularCart = false,
    this.cartItems,
    this.onCartChanged,
    this.initialCampaigns = const [],
  });

  final bool hasRegularCart;
  final List<CartItem>? cartItems;
  final VoidCallback? onCartChanged;
  final List<PreOrderCampaign> initialCampaigns;

  @override
  State<BuyerPreOrdersScreen> createState() => _BuyerPreOrdersScreenState();
}

class _BuyerPreOrdersScreenState extends State<BuyerPreOrdersScreen> {
  late List<PreOrderCampaign> _campaigns;
  late bool _loading;
  late bool _hasSuccessfullyLoaded;
  String? _error;
  String? _buyerSocietyId;
  String? _viewerUserId;

  @override
  void initState() {
    super.initState();
    _campaigns = List<PreOrderCampaign>.from(widget.initialCampaigns);
    _hasSuccessfullyLoaded = _campaigns.isNotEmpty;
    _loading = !_hasSuccessfullyLoaded;
    _load();
  }

  Future<void> _load() async {
    final blockOnSpinner = !_hasSuccessfullyLoaded;
    if (blockOnSpinner && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final societyId = await SessionService.getSocietyId();
      if (societyId == null || societyId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          if (!_hasSuccessfullyLoaded) {
            _error = 'Join your society to see pre-orders.';
          }
        });
        return;
      }
      final userId = await SessionService.getUserId();
      final raw = await ApiService.getPreOrderCampaigns(
        societyId: societyId,
      );
      final campaigns = filterBuyerDiscoverableCampaigns(
        raw.map(PreOrderCampaign.fromJson),
        viewerUserId: userId,
      );
      if (!mounted) return;
      setState(() {
        _campaigns = campaigns;
        _buyerSocietyId = societyId;
        _viewerUserId = userId;
        _loading = false;
        _hasSuccessfullyLoaded = true;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (!_hasSuccessfullyLoaded) {
        setState(() {
          _error = cleanApiError(e);
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open(PreOrderCampaign campaign) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BuyerPreOrderDetailScreen(
          campaignId: campaign.id,
          initialCampaign: campaign,
          regularCartHasItems: widget.hasRegularCart,
          cartItems: widget.cartItems,
          onCartChanged: widget.onCartChanged,
        ),
      ),
    );
    await _load();
  }

  void _openSeller(PreOrderCampaign campaign) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SellerStorefrontScreen(
          seller: sellerFromPreOrderCampaign(campaign),
          cartItems: widget.cartItems,
          onCartChanged: widget.onCartChanged,
        ),
      ),
    );
  }

  List<PreOrderCampaign> _forReach(HomeListingReach reach) {
    return campaignsForHomeReach(
      _campaigns,
      reach: reach,
      buyerSocietyId: _buyerSocietyId,
      viewerUserId: _viewerUserId,
    );
  }

  List<Widget> _reachBlocks() {
    return [
      ..._reachBlock('In your society', _forReach(HomeListingReach.inSociety)),
      ..._reachBlock('Nearby', _forReach(HomeListingReach.nearby)),
      ..._reachBlock('Around you', _forReach(HomeListingReach.extended)),
    ];
  }

  List<Widget> _reachBlock(String title, List<PreOrderCampaign> campaigns) {
    if (campaigns.isEmpty) return const [];
    final grouped = <String, List<PreOrderCampaign>>{};
    for (final campaign in campaigns) {
      grouped.putIfAbsent(campaign.sellerName, () => []).add(campaign);
    }
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 6),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: preorderText,
          ),
        ),
      ),
      ...grouped.entries.expand(
        (entry) => [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 8, 2, 10),
            child: InkWell(
              onTap: () => _openSeller(entry.value.first),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  entry.key,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: preorderGreen,
                  ),
                ),
              ),
            ),
          ),
          ...entry.value.map(
            (campaign) => BuyerPreOrderCampaignCard(
              campaign: campaign,
              onTap: () => _open(campaign),
              onSellerTap: () => _openSeller(campaign),
            ),
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: preorderBackground,
      appBar: AppBar(
        backgroundColor: preorderBackground,
        foregroundColor: preorderText,
        elevation: 0,
        title: const Text(
          'Pre-orders',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: RefreshIndicator(
        color: preorderGreen,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Order ahead from your neighborhood cooks.',
                      style: TextStyle(
                        color: preorderMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 22),
                    if (_loading && !_hasSuccessfullyLoaded)
                      const Padding(
                        padding: EdgeInsets.all(48),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: preorderGreen,
                          ),
                        ),
                      )
                    else if (_error != null && !_hasSuccessfullyLoaded)
                      PreOrderEmptyState(
                        title: 'Could not load pre-orders',
                        message: _error!,
                        action: OutlinedButton(
                          onPressed: _load,
                          child: const Text('Try again'),
                        ),
                      )
                    else if (_campaigns.isEmpty)
                      const PreOrderEmptyState(
                        title: 'No upcoming pre-orders',
                        message:
                            'New pre-order menus from your neighbors will appear here.',
                      )
                    else
                      ..._reachBlocks(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
