import 'package:flutter/material.dart';

import '../widgets/app_header.dart';
import '../widgets/profile_menu_tile.dart';

/// Navigation container for existing seller settings. Save behaviour stays
/// on Profile — this screen only groups the current entry points.
class SellerSettingsScreen extends StatelessWidget {
  const SellerSettingsScreen({
    super.key,
    required this.photoUrl,
    required this.displayName,
    required this.savingPhoto,
    required this.upiSubtitle,
    required this.paymentTitle,
    required this.sellingReachSubtitle,
    required this.fulfilmentTitle,
    required this.fulfilmentSubtitle,
    required this.fssaiSubtitle,
    required this.onChangePhoto,
    this.onRemovePhoto,
    required this.onEditUpi,
    required this.onChangePaymentPreference,
    required this.onChangeSellingReach,
    required this.onChangeFulfilment,
    required this.onEditFssai,
  });

  final String? photoUrl;
  final String displayName;
  final bool savingPhoto;
  final String upiSubtitle;
  final String paymentTitle;
  final String sellingReachSubtitle;
  final String fulfilmentTitle;
  final String fulfilmentSubtitle;
  final String fssaiSubtitle;
  final VoidCallback onChangePhoto;
  final VoidCallback? onRemovePhoto;
  final VoidCallback onEditUpi;
  final VoidCallback onChangePaymentPreference;
  final VoidCallback onChangeSellingReach;
  final VoidCallback onChangeFulfilment;
  final VoidCallback onEditFssai;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(
              showCart: false,
              leading: BackButton(color: Color(0xFF101617)),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  const Text(
                    'Seller Settings',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF101617),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Manage payments, fulfilment, profile & FSSAI',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF6A7774),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _SectionLabel('PAYMENTS'),
                  const SizedBox(height: 6),
                  const Text(
                    'Manage UPI and Cash on Delivery',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF6A7774),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ProfileMenuTile(
                    icon: Icons.payments_outlined,
                    title: 'Payment Methods',
                    subtitle: paymentTitle,
                    trailingLabel: 'Change',
                    onTap: onChangePaymentPreference,
                  ),
                  ProfileMenuTile(
                    icon: Icons.account_balance_wallet_rounded,
                    title: 'UPI for Payments',
                    subtitle: upiSubtitle,
                    onTap: onEditUpi,
                  ),
                  const SizedBox(height: 10),
                  const _SectionLabel('SELLER PROFILE'),
                  const SizedBox(height: 10),
                  ProfilePhotoSection(
                    photoUrl: photoUrl,
                    name: displayName,
                    saving: savingPhoto,
                    onChangePhoto: onChangePhoto,
                    onRemovePhoto: onRemovePhoto,
                  ),
                  const SizedBox(height: 20),
                  const _SectionLabel('SELLING'),
                  const SizedBox(height: 10),
                  ProfileMenuTile(
                    icon: Icons.social_distance_rounded,
                    title: 'Selling Reach',
                    subtitle: sellingReachSubtitle,
                    trailingLabel: 'Change',
                    onTap: onChangeSellingReach,
                  ),
                  ProfileMenuTile(
                    icon: Icons.local_shipping_outlined,
                    title: fulfilmentTitle,
                    subtitle: fulfilmentSubtitle,
                    trailingLabel: 'Change',
                    onTap: onChangeFulfilment,
                  ),
                  const SizedBox(height: 10),
                  const _SectionLabel('FOOD & COMPLIANCE'),
                  const SizedBox(height: 10),
                  ProfileMenuTile(
                    icon: Icons.badge_outlined,
                    title: 'FSSAI details',
                    subtitle: fssaiSubtitle,
                    trailingLabel: 'Update',
                    onTap: onEditFssai,
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w700,
        color: Color(0xFF8A9491),
      ),
    );
  }
}
