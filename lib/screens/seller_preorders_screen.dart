import 'package:flutter/material.dart';

import '../models/data.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';
import '../widgets/app_header.dart';
import '../widgets/preorder_widgets.dart';
import 'create_preorder_screen.dart';
import 'preorder_detail_screen.dart';

class SellerPreOrdersScreen extends StatefulWidget {
  const SellerPreOrdersScreen({super.key});

  @override
  State<SellerPreOrdersScreen> createState() => _SellerPreOrdersScreenState();
}

class _SellerPreOrdersScreenState extends State<SellerPreOrdersScreen> {
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
      final societyId = await SessionService.getSocietyId();
      final sellerId = await SessionService.getUserId();
      if (sellerId == null) throw Exception('Please log in again.');
      if (societyId == null || societyId.isEmpty) {
        throw Exception('Join your society to manage pre-orders.');
      }
      final raw = await ApiService.getPreOrderCampaigns(
        societyId: societyId,
        sellerId: sellerId,
      );
      final campaigns = await Future.wait(
        raw.map((json) async {
          final campaign = PreOrderCampaign.fromJson(json);
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
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = cleanApiError(e);
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CreatePreOrderScreen()),
    );
    if (changed == true) await _load();
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
                              PreOrderEmptyState(
                                title: 'No pre-orders yet',
                                message:
                                    'Create a campaign, add products, and collect demand before you cook.',
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
