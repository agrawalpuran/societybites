import 'package:flutter/material.dart';

import '../models/data.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';
import '../widgets/app_header.dart';
import '../widgets/preorder_widgets.dart';
import 'buyer_preorder_detail_screen.dart';
import 'seller_storefront_screen.dart';

class BuyerPreOrdersScreen extends StatefulWidget {
  const BuyerPreOrdersScreen({
    super.key,
    this.hasRegularCart = false,
    this.cartItems,
    this.onCartChanged,
  });

  final bool hasRegularCart;
  final List<CartItem>? cartItems;
  final VoidCallback? onCartChanged;

  @override
  State<BuyerPreOrdersScreen> createState() => _BuyerPreOrdersScreenState();
}

class _BuyerPreOrdersScreenState extends State<BuyerPreOrdersScreen> {
  List<PreOrderCampaign> _campaigns = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final societyId =
          await SessionService.getSocietyId() ??
          SessionService.defaultSocietyId;
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
            ..sort((a, b) => a.orderCutoffAt.compareTo(b.orderCutoffAt));
      if (!mounted) return;
      setState(() {
        _campaigns = campaigns;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = cleanApiError(e);
        _loading = false;
      });
    }
  }

  Future<void> _open(PreOrderCampaign campaign) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BuyerPreOrderDetailScreen(
          campaignId: campaign.id,
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

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<PreOrderCampaign>>{};
    for (final campaign in _campaigns) {
      grouped.putIfAbsent(campaign.sellerName, () => []).add(campaign);
    }

    return Scaffold(
      backgroundColor: preorderBackground,
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              padding: const EdgeInsets.fromLTRB(4, 10, 20, 0),
              leading: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: preorderGreen,
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Pre-orders',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: preorderText,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Order ahead from your neighborhood cooks.',
                              style: TextStyle(
                                color: preorderMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 22),
                            if (_loading)
                              const Padding(
                                padding: EdgeInsets.all(48),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: preorderGreen,
                                  ),
                                ),
                              )
                            else if (_error != null)
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
                              ...grouped.entries.expand(
                                (entry) => [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      2,
                                      8,
                                      2,
                                      10,
                                    ),
                                    child: InkWell(
                                      onTap: () =>
                                          _openSeller(entry.value.first),
                                      borderRadius: BorderRadius.circular(6),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 3,
                                        ),
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
                          ],
                        ),
                      ),
                    ),
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
