import 'package:flutter/material.dart';

import '../models/seller_fulfilment.dart';
import '../models/seller_payment_preference.dart';
import '../models/selling_reach.dart';
import '../web/web_page_frame.dart';
import '../widgets/app_header.dart';
import '../widgets/kitchen_hours_sheet.dart';
import '../widgets/profile_menu_tile.dart';
import '../widgets/seller_first_time_setup_form.dart';

/// Navigation container for seller settings. Save behaviour stays on Profile —
/// this screen groups entry points (existing sellers) or inline setup (first time).
class SellerSettingsScreen extends StatelessWidget {
  const SellerSettingsScreen({
    super.key,
    required this.upiSubtitle,
    required this.paymentTitle,
    required this.sellingReachSubtitle,
    required this.fulfilmentTitle,
    required this.fulfilmentSubtitle,
    required this.kitchenHoursSubtitle,
    required this.fssaiSubtitle,
    this.fssaiRequirementEnabled = false,
    this.fssaiAllowsEnableSelling = true,
    required this.onEditUpi,
    required this.onChangePaymentPreference,
    required this.onChangeSellingReach,
    required this.onChangeFulfilment,
    required this.onChangeKitchenHours,
    required this.onEditFssai,
    this.onSaveAndEnable,
    this.isFirstTimeSetup = false,
    this.paymentPreference,
    this.onPaymentPreferenceChanged,
    this.upiId,
    this.upiDisplayName,
    this.onUpiDetailsChanged,
    this.sellingReachLevel,
    this.sellingReach,
    this.onSellingReachChanged,
    this.fulfilment,
    this.onFulfilmentChanged,
    this.kitchenOpensAt,
    this.kitchenClosesAt,
    this.onKitchenHoursChanged,
  });

  final String upiSubtitle;
  final String paymentTitle;
  final String sellingReachSubtitle;
  final String fulfilmentTitle;
  final String fulfilmentSubtitle;
  final String kitchenHoursSubtitle;
  final String fssaiSubtitle;
  final bool fssaiRequirementEnabled;
  final bool fssaiAllowsEnableSelling;
  final VoidCallback onEditUpi;
  final VoidCallback onChangePaymentPreference;
  final VoidCallback onChangeSellingReach;
  final VoidCallback onChangeFulfilment;
  final VoidCallback onChangeKitchenHours;
  final VoidCallback onEditFssai;
  final VoidCallback? onSaveAndEnable;
  final bool isFirstTimeSetup;

  final SellerPaymentPreference? paymentPreference;
  final ValueChanged<SellerPaymentPreference>? onPaymentPreferenceChanged;
  final String? upiId;
  final String? upiDisplayName;
  final void Function(String upiId, String displayName)? onUpiDetailsChanged;
  final SellingReachLevel? sellingReachLevel;
  final SellingReach? sellingReach;
  final ValueChanged<SellingReachLevel>? onSellingReachChanged;
  final SellerFulfilment? fulfilment;
  final ValueChanged<SellerFulfilment>? onFulfilmentChanged;
  final String? kitchenOpensAt;
  final String? kitchenClosesAt;
  final ValueChanged<KitchenHoursDraft>? onKitchenHoursChanged;

  @override
  Widget build(BuildContext context) {
    final inlineSetup = isFirstTimeSetup &&
        paymentPreference != null &&
        onPaymentPreferenceChanged != null &&
        onUpiDetailsChanged != null &&
        sellingReachLevel != null &&
        sellingReach != null &&
        onSellingReachChanged != null &&
        fulfilment != null &&
        onFulfilmentChanged != null &&
        onKitchenHoursChanged != null;

    return centerOnWeb(
      context,
      Scaffold(
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
                    Text(
                      isFirstTimeSetup
                          ? (fssaiRequirementEnabled
                              ? 'Fill in payment methods, UPI, selling reach, fulfilment, and FSSAI so you can start listing.'
                              : 'Fill in payment methods, UPI, selling reach, and fulfilment. You can add FSSAI details when ready.')
                          : 'Manage payments, kitchen hours, fulfilment & FSSAI',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF6A7774),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (inlineSetup)
                      SellerFirstTimeSetupForm(
                        paymentPreference: paymentPreference!,
                        onPaymentChanged: onPaymentPreferenceChanged!,
                        upiId: upiId,
                        upiDisplayName: upiDisplayName,
                        onUpiChanged: onUpiDetailsChanged!,
                        sellingReachLevel: sellingReachLevel!,
                        sellingReach: sellingReach!,
                        onReachChanged: onSellingReachChanged!,
                        fulfilment: fulfilment!,
                        onFulfilmentChanged: onFulfilmentChanged!,
                        kitchenOpensAt: kitchenOpensAt,
                        kitchenClosesAt: kitchenClosesAt,
                        onKitchenChanged: onKitchenHoursChanged!,
                        fssaiSubtitle: fssaiSubtitle,
                        fssaiRequirementEnabled: fssaiRequirementEnabled,
                        fssaiAllowsEnableSelling: fssaiAllowsEnableSelling,
                        onOpenFssai: onEditFssai,
                      )
                    else ...[
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
                      ProfileMenuTile(
                        icon: Icons.schedule_rounded,
                        title: 'Kitchen hours',
                        subtitle: kitchenHoursSubtitle,
                        trailingLabel: 'Change',
                        onTap: onChangeKitchenHours,
                      ),
                      const SizedBox(height: 10),
                      const _SectionLabel('FOOD & COMPLIANCE'),
                      const SizedBox(height: 10),
                      ProfileMenuTile(
                        icon: Icons.badge_outlined,
                        title: 'FSSAI details',
                        subtitle: fssaiRequirementEnabled
                            ? 'Required on platform · $fssaiSubtitle'
                            : 'Optional on platform · $fssaiSubtitle',
                        trailingLabel:
                            fssaiRequirementEnabled ? 'Update' : 'Fill',
                        onTap: onEditFssai,
                      ),
                    ],
                  ],
                ),
              ),
              if (onSaveAndEnable != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (fssaiRequirementEnabled && !fssaiAllowsEnableSelling)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: Text(
                            'Submit your FSSAI details for review before you can enable selling.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF6A7774),
                            ),
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          key: const Key('seller-settings-enable'),
                          onPressed:
                              fssaiAllowsEnableSelling ? onSaveAndEnable : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0E5A47),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFFB8C4C0),
                            disabledForegroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Save / Enable Selling',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      maxWidth: 720,
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
