import 'package:flutter/material.dart';

import '../models/listing_availability.dart';
import '../widgets/app_header.dart';
import 'add_listing_screen.dart';
import 'create_preorder_screen.dart';
import 'preorder_detail_screen.dart';

enum AddListingOrderType { availableNow, madeToOrder, preOrder }

/// Seller entry for + Add Listing. Routes to existing listing or campaign flows.
class AddListingTypeScreen extends StatefulWidget {
  const AddListingTypeScreen({super.key});

  @override
  State<AddListingTypeScreen> createState() => _AddListingTypeScreenState();
}

class _AddListingTypeScreenState extends State<AddListingTypeScreen> {
  AddListingOrderType _selected = AddListingOrderType.availableNow;

  Future<void> _continue() async {
    final created = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(
        builder: (_) => switch (_selected) {
          AddListingOrderType.availableNow => const AddListingScreen(
              initialAvailabilityMode: listingAvailabilityReadyNow,
            ),
          AddListingOrderType.madeToOrder => const AddListingScreen(
              initialAvailabilityMode: listingAvailabilityMadeToOrder,
            ),
          AddListingOrderType.preOrder => const CreatePreOrderScreen(),
        },
      ),
    );
    if (!mounted) return;
    if (created is PreOrderCampaignCreated) {
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PreOrderDetailScreen(
            campaignId: created.campaignId,
            promptToAddProduct: true,
          ),
        ),
      );
      return;
    }
    if (created == true) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              padding: const EdgeInsets.fromLTRB(4, 10, 20, 0),
              leading: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                color: const Color(0xFF3A4644),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Add Listing',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0E5A47),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                children: [
                  const Text(
                    'What type of order is this?',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF101617),
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Choose how buyers can order this item.',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF6A7774),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _TypeCard(
                    key: const Key('listing-type-available-now'),
                    selected: _selected == AddListingOrderType.availableNow,
                    asset: 'assets/images/available_now.jpg',
                    title: 'Available Now',
                    subtitle: 'Ready to sell today',
                    description:
                        'You have this item available and buyers can order it now.',
                    examples: 'e.g. Samosa, Biryani, Pickle, Prepared Cakes',
                    onTap: () => setState(
                      () => _selected = AddListingOrderType.availableNow,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _TypeCard(
                    key: const Key('listing-type-made-to-order'),
                    selected: _selected == AddListingOrderType.madeToOrder,
                    asset: 'assets/images/made_to_order.jpg',
                    title: 'Made to Order',
                    subtitle: 'Prepare after the buyer orders',
                    description:
                        'You make this item only when someone places an order.',
                    examples: 'e.g. Cakes, Dosa Batter, Thepla, Fresh Snacks',
                    onTap: () => setState(
                      () => _selected = AddListingOrderType.madeToOrder,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _TypeCard(
                    key: const Key('listing-type-pre-order'),
                    selected: _selected == AddListingOrderType.preOrder,
                    asset: 'assets/images/pre_order.jpg',
                    title: 'Pre-Order',
                    subtitle: 'Take orders for a future date',
                    description:
                        'Collect orders during a fixed time period and prepare them together on a planned date.',
                    examples:
                        'e.g. Diwali Sweets, Sunday Specials, Festival Menus',
                    onTap: () => setState(
                      () => _selected = AddListingOrderType.preOrder,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const _HelpCard(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  key: const Key('listing-type-continue'),
                  onPressed: _continue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0E5A47),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    super.key,
    required this.selected,
    required this.asset,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.examples,
    required this.onTap,
  });

  final bool selected;
  final String asset;
  final String title;
  final String subtitle;
  final String description;
  final String examples;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFE8F5EE) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? const Color(0xFF0E5A47)
                  : const Color(0xFFE0E5E3),
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: ClipOval(
                  child: Image.asset(
                    asset,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ColoredBox(
                      color: Color(0xFFE8F5EE),
                      child: Icon(
                        Icons.restaurant_rounded,
                        color: Color(0xFF0E5A47),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF101617),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? const Color(0xFF0E5A47)
                            : const Color(0xFF6A7774),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: Color(0xFF3A4644),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      examples,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: Color(0xFF8A9491),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                size: 22,
                color: selected
                    ? const Color(0xFF0E5A47)
                    : const Color(0xFFC5CDC9),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HelpCard extends StatelessWidget {
  const _HelpCard();

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Material(
        color: const Color(0xFFF0F2F1),
        borderRadius: BorderRadius.circular(16),
        child: const ExpansionTile(
          tilePadding: EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: EdgeInsets.fromLTRB(14, 0, 14, 14),
          iconColor: Color(0xFF8A9491),
          collapsedIconColor: Color(0xFF8A9491),
          title: Text(
            'Not sure which to choose?',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6A7774),
            ),
          ),
          children: [
            _HelpLine(
              title: 'Available Now',
              body: 'Already prepared and ready to sell.',
            ),
            SizedBox(height: 8),
            _HelpLine(
              title: 'Made to Order',
              body: 'Prepare after someone orders.',
            ),
            SizedBox(height: 8),
            _HelpLine(
              title: 'Pre-Order',
              body: 'Take orders for a future date.',
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpLine extends StatelessWidget {
  const _HelpLine({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$title\n',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: Color(0xFF3A4644),
              ),
            ),
            TextSpan(
              text: body,
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: Color(0xFF6A7774),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
