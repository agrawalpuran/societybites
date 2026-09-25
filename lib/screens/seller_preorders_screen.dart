import 'package:flutter/material.dart';

import '../models/data.dart';
import '../services/api_service.dart';
import '../services/seller_onboarding.dart';
import '../services/session_service.dart';
import '../widgets/app_header.dart';
import '../widgets/preorder_widgets.dart';
import 'add_listing_screen.dart';
import 'create_preorder_screen.dart';
import 'preorder_detail_screen.dart';

class SellerPreOrdersScreen extends StatefulWidget {
  const SellerPreOrdersScreen({
    super.key,
    this.fetchCampaigns,
    this.fetchCatalog,
    this.ensureCanCreateListing,
  });

  /// Test seam. Production uses [ApiService.getPreOrderCampaigns].
  final Future<List<Map<String, dynamic>>> Function()? fetchCampaigns;

  /// Test seam. Production loads the seller's PREORDER catalog.
  final Future<List<Map<String, dynamic>>> Function()? fetchCatalog;

  /// Test seam. Production uses [SellerOnboarding.ensureCanCreateListing].
  final Future<bool> Function(BuildContext context)? ensureCanCreateListing;

  @override
  SellerPreOrdersScreenState createState() => SellerPreOrdersScreenState();
}

class SellerPreOrdersScreenState extends State<SellerPreOrdersScreen> {
  List<PreOrderCampaign> _campaigns = [];
  bool _loading = true;
  bool _hasSuccessfullyLoaded = false;
  String? _error;
  bool? _catalogEmpty;

  @override
  void initState() {
    super.initState();
    _load();
    _loadCatalog();
  }

  Future<void> reload() => _load();

  Future<void> _loadCatalog() async {
    try {
      late final List<Map<String, dynamic>> raw;
      final fetchCatalog = widget.fetchCatalog;
      if (fetchCatalog != null) {
        raw = await fetchCatalog();
      } else if (widget.fetchCampaigns != null) {
        return;
      } else {
        final societyId = await SessionService.getSocietyId();
        final sellerId = await SessionService.getUserId();
        if (sellerId == null || societyId == null || societyId.isEmpty) return;
        raw = await ApiService.getListings(
          societyId: societyId,
          sellerId: sellerId,
          status: 'all',
          catalogType: listingCatalogPreorder,
        );
      }
      if (!mounted) return;
      setState(() => _catalogEmpty = raw.isEmpty);
    } catch (_) {}
  }

  Future<void> _load() async {
    if (!_hasSuccessfullyLoaded) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      late final List<Map<String, dynamic>> raw;
      final fetchCampaigns = widget.fetchCampaigns;
      if (fetchCampaigns != null) {
        raw = await fetchCampaigns();
      } else {
        final societyId = await SessionService.getSocietyId();
        final sellerId = await SessionService.getUserId();
        if (sellerId == null) throw Exception('Please log in again.');
        if (societyId == null || societyId.isEmpty) {
          throw Exception('Join your society to manage pre-orders.');
        }
        raw = await ApiService.getPreOrderCampaigns(
          societyId: societyId,
          sellerId: sellerId,
        );
      }
      final campaigns = await Future.wait(
        raw.map((json) async {
          final campaign = PreOrderCampaign.fromJson(json);
          if (fetchCampaigns != null) return campaign;
          try {
            final summaryRaw = await ApiService.getPreOrderSummary(campaign.id);
            final summary = PreOrderSummary.fromJson(summaryRaw);
            return PreOrderCampaign(
              id: campaign.id,
              title: campaign.title,
              description: campaign.description,
              coverImageUrl: campaign.coverImageUrl,
              status: summary.status,
              orderOpenAt: campaign.orderOpenAt,
              orderCutoffAt: campaign.orderCutoffAt,
              fulfilmentAt: campaign.fulfilmentAt,
              offeredFulfilmentMethods: campaign.offeredFulfilmentMethods,
              defaultDeliveryCharge: campaign.defaultDeliveryCharge,
              products: campaign.products,
              totalOrders: summary.totalOrders,
              totalItems: summary.totalItems,
              foodSubtotal: summary.foodSubtotal,
            );
          } catch (_) {
            return campaign;
          }
        }),
      );
      campaigns.sort((a, b) {
        const rank = {'open': 0, 'draft': 1, 'closed': 2, 'cancelled': 3};
        final statusCompare = (rank[campaignDisplayStatus(a)] ?? 4).compareTo(
          rank[campaignDisplayStatus(b)] ?? 4,
        );
        return statusCompare != 0
            ? statusCompare
            : a.fulfilmentAt.compareTo(b.fulfilmentAt);
      });
      if (!mounted) return;
      setState(() {
        _campaigns = campaigns;
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
      }
    }
  }

  Future<void> _create() async {
    if (_catalogEmpty == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'There is nothing in the pre-order catalog. Create the catalog first.',
          ),
        ),
      );
      return;
    }
    final result = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(builder: (_) => const CreatePreOrderScreen()),
    );
    if (!mounted) return;
    if (result is PreOrderCampaignCreated) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PreOrderDetailScreen(
            campaignId: result.campaignId,
            promptToAddProduct: true,
          ),
        ),
      );
      await _load();
      return;
    }
    if (result == true) await _load();
  }

  Future<void> _createCatalog() async {
    final canList = await (widget.ensureCanCreateListing ??
        SellerOnboarding.ensureCanCreateListing)(context);
    if (!canList || !mounted) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const AddListingScreen(
          catalogType: listingCatalogPreorder,
        ),
      ),
    );
    if (mounted) await _loadCatalog();
  }

  Future<void> _open(PreOrderCampaign campaign) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PreOrderDetailScreen(campaignId: campaign.id),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: preorderBackground,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        backgroundColor: preorderGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Create pre-order',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
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
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
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
                              'Plan ahead, track demand, and know exactly what to prepare.',
                              style: TextStyle(
                                color: preorderMuted,
                                height: 1.4,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              key: const Key('create-preorder-catalog'),
                              onPressed: _createCatalog,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: preorderGreen,
                                side: const BorderSide(color: Color(0xFFD4E8DF)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.menu_book_outlined, size: 18),
                              label: const Text(
                                'Create catalog',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                            if (_catalogEmpty == true) ...[
                              const SizedBox(height: 14),
                              CreatePreorderCatalogNudge(
                                onCreateCatalog: _createCatalog,
                              ),
                            ] else if (_catalogEmpty == false) ...[
                              const SizedBox(height: 14),
                              const ExistingPreorderCatalogNote(),
                            ],
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
                            else if (_campaigns.isEmpty && _catalogEmpty != true)
                              PreOrderEmptyState(
                                title: 'No pre-orders yet',
                                message:
                                    'Create a campaign from items already in your pre-order catalog.',
                                action: ElevatedButton.icon(
                                  onPressed: _create,
                                  icon: const Icon(Icons.add_rounded),
                                  label: const Text('Create pre-order'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: preorderGreen,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              )
                            else
                              ..._campaigns.map(
                                (campaign) => PreOrderCampaignCard(
                                  campaign: campaign,
                                  onTap: () => _open(campaign),
                                ),
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
