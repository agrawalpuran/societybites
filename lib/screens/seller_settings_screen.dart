import 'package:flutter/material.dart';

import '../models/seller_fulfilment.dart';
import '../models/seller_payment_preference.dart';
import '../models/selling_reach.dart';
import '../web/web_page_frame.dart';
import '../widgets/app_header.dart';
import '../widgets/kitchen_hours_sheet.dart';
import '../widgets/profile_menu_tile.dart';
import '../widgets/seller_first_time_setup_form.dart';
import 'seller_owner_access_screen.dart';

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
    this.saveAndEnableInProgress = false,
    this.upiReadyForEnableSelling = true,
    this.isFirstTimeSetup = false,
    this.upiIdConfirmed = false,
    this.paymentPreference,
    this.onPaymentPreferenceChanged,
    this.upiId,
    this.upiDisplayName,
    this.onUpiDetailsChanged,
    this.onUpiConfirmed,
    this.onUpiConfirmationInvalidated,
    this.sellingReachPreference,
    this.sellingReach,
    this.onSellingReachChanged,
    this.fulfilment,
    this.onFulfilmentChanged,
    this.kitchenOpensAt,
    this.kitchenClosesAt,
    this.kitchenExplicitAlwaysOpen = false,
    this.onKitchenHoursChanged,
    this.hideFlatNumber = false,
    this.hideFlatNumberSaving = false,
    this.onHideFlatNumberChanged,
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
  final bool saveAndEnableInProgress;
  final bool upiReadyForEnableSelling;
  final bool isFirstTimeSetup;
  final bool upiIdConfirmed;

  final SellerPaymentPreference? paymentPreference;
  final ValueChanged<SellerPaymentPreference>? onPaymentPreferenceChanged;
  final String? upiId;
  final String? upiDisplayName;
  final void Function(String upiId, String displayName)? onUpiDetailsChanged;
  final VoidCallback? onUpiConfirmed;
  final VoidCallback? onUpiConfirmationInvalidated;
  final SellerReachPreference? sellingReachPreference;
  final SellingReach? sellingReach;
  final ValueChanged<SellerReachPreference>? onSellingReachChanged;
  final SellerFulfilment? fulfilment;
  final ValueChanged<SellerFulfilment>? onFulfilmentChanged;
  final String? kitchenOpensAt;
  final String? kitchenClosesAt;
  final bool kitchenExplicitAlwaysOpen;
  final ValueChanged<KitchenHoursDraft>? onKitchenHoursChanged;
  final bool hideFlatNumber;
  final bool hideFlatNumberSaving;
  final ValueChanged<bool>? onHideFlatNumberChanged;

  @override
  Widget build(BuildContext context) {
    final inlineSetup = isFirstTimeSetup &&
        paymentPreference != null &&
        onPaymentPreferenceChanged != null &&
        onUpiDetailsChanged != null &&
        sellingReachPreference != null &&
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
                          ? 'Fill in payment methods, UPI, selling reach, fulfilment, and FSSAI so you can start listing.'
                          : 'Manage payments, kitchen hours, fulfilment & FSSAI',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF6A7774),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (inlineSetup) ...[
                      const _SectionLabel('FOOD & COMPLIANCE'),
                      const SizedBox(height: 6),
                      const Text(
                        'FSSAI is required before you can continue. Submit your '
                        'licence, or say you do not have one yet to request assistance.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF6A7774),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ProfileMenuTile(
                        key: const Key('seller-setup-fssai-entry'),
                        icon: Icons.badge_outlined,
                        title: 'FSSAI details *',
                        subtitle: 'Required · $fssaiSubtitle',
                        trailingLabel:
                            fssaiAllowsEnableSelling ? 'Done' : 'Complete',
                        onTap: onEditFssai,
                      ),
                      const SizedBox(height: 20),
                      SellerFirstTimeSetupForm(
                        paymentPreference: paymentPreference!,
                        onPaymentChanged: onPaymentPreferenceChanged!,
                        upiId: upiId,
                        upiDisplayName: upiDisplayName,
                        onUpiChanged: onUpiDetailsChanged!,
                        onUpiConfirmed: onUpiConfirmed,
                        onUpiConfirmationInvalidated:
                            onUpiConfirmationInvalidated,
                        upiIdConfirmed: upiIdConfirmed,
                        sellingReachPreference: sellingReachPreference!,
                        sellingReach: sellingReach!,
                        onReachPreferenceChanged: onSellingReachChanged!,
                        fulfilment: fulfilment!,
                        onFulfilmentChanged: onFulfilmentChanged!,
                        kitchenOpensAt: kitchenOpensAt,
                        kitchenClosesAt: kitchenClosesAt,
                        kitchenExplicitAlwaysOpen: kitchenExplicitAlwaysOpen,
                        onKitchenChanged: onKitchenHoursChanged!,
                      ),
                    ] else ...[
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
                      ProfileMenuTile(
                        icon: Icons.manage_accounts_outlined,
                        title: 'Owner access',
                        subtitle:
                            'Invite someone to view your kitchen (view only)',
                        trailingLabel: 'Manage',
                        onTap: () {
                          Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SellerOwnerAccessScreen(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      const _SectionLabel('PRIVACY'),
                      const SizedBox(height: 6),
                      const Text(
                        'Hide my flat number',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF101617),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _PrivacyFlatRadioGroup(
                        hideFlatNumber: hideFlatNumber,
                        saving: hideFlatNumberSaving,
                        onChanged: onHideFlatNumberChanged,
                      ),
                      const SizedBox(height: 10),
                      const _SectionLabel('FOOD & COMPLIANCE'),
                      const SizedBox(height: 10),
                      ProfileMenuTile(
                        icon: Icons.badge_outlined,
                        title: 'FSSAI details *',
                        subtitle: fssaiRequirementEnabled
                            ? 'Required to receive orders · $fssaiSubtitle'
                            : 'Required for seller setup · $fssaiSubtitle',
                        trailingLabel: 'Update',
                        onTap: onEditFssai,
                      ),
                    ],
                  ],
                ),
              ),
              if (onSaveAndEnable != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: AbsorbPointer(
                    absorbing: saveAndEnableInProgress,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SetupContinueChecklist(
                          fssaiDone: fssaiAllowsEnableSelling,
                          upiDone: upiReadyForEnableSelling,
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            key: const Key('seller-settings-enable'),
                            // Always tappable so we can explain blockers or
                            // show the UPI confirm popup — never a dead button.
                            onPressed:
                                saveAndEnableInProgress ? null : onSaveAndEnable,
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
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (saveAndEnableInProgress) ...[
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                Text(
                                  saveAndEnableInProgress
                                      ? 'Opening next step…'
                                      : (isFirstTimeSetup
                                          ? 'Continue'
                                          : 'Save / Enable Selling'),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
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
      ),
      maxWidth: 720,
    );
  }
}

class _SetupContinueChecklist extends StatelessWidget {
  const _SetupContinueChecklist({
    required this.fssaiDone,
    required this.upiDone,
  });

  final bool fssaiDone;
  final bool upiDone;

  @override
  Widget build(BuildContext context) {
    final allDone = fssaiDone && upiDone;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: allDone ? const Color(0xFFF0F7F4) : const Color(0xFFFFF8F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: allDone ? const Color(0xFFC8E0D6) : const Color(0xFFF0D4CC),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              allDone
                  ? 'Ready — Continue will ask you to confirm your UPI ID.'
                  : 'Still needed before the next step:',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: allDone
                    ? const Color(0xFF0E5A47)
                    : const Color(0xFF9A3412),
              ),
            ),
            const SizedBox(height: 8),
            _ChecklistRow(
              done: fssaiDone,
              label: fssaiDone
                  ? 'FSSAI addressed'
                  : 'FSSAI — submit licence or request assistance',
            ),
            const SizedBox(height: 4),
            _ChecklistRow(
              done: upiDone,
              label: upiDone
                  ? 'UPI ID and display name'
                  : 'UPI ID and display name',
            ),
          ],
        ),
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.done, required this.label});

  final bool done;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          done ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 18,
          color: done ? const Color(0xFF0E5A47) : const Color(0xFFB45309),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              height: 1.3,
              fontWeight: FontWeight.w500,
              color: done ? const Color(0xFF3D524C) : const Color(0xFF7C2D12),
            ),
          ),
        ),
      ],
    );
  }
}

class _PrivacyFlatRadioGroup extends StatelessWidget {
  const _PrivacyFlatRadioGroup({
    required this.hideFlatNumber,
    required this.saving,
    this.onChanged,
  });

  final bool hideFlatNumber;
  final bool saving;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null && !saving;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8E6)),
      ),
      child: Column(
        children: [
          _PrivacyRadioTile(
            key: const Key('hide-flat-number-yes'),
            label: 'Yes',
            subtitle: hideFlatNumber
                ? null
                : 'Hide flat number on public listings and profiles',
            selectedDetail: hideFlatNumber
                ? 'Your flat number will be hidden publicly. It may be '
                    'shown to the relevant buyer only after confirmation of '
                    'an eligible self-pickup order with My Home selected.'
                : null,
            selected: hideFlatNumber,
            enabled: enabled,
            onTap: enabled ? () => onChanged!(true) : null,
          ),
          const Divider(height: 1, color: Color(0xFFE2E8E6)),
          _PrivacyRadioTile(
            key: const Key('hide-flat-number-no'),
            label: 'No',
            subtitle: 'Show flat number as today',
            selected: !hideFlatNumber,
            enabled: enabled,
            onTap: enabled ? () => onChanged!(false) : null,
          ),
          if (saving)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }
}

class _PrivacyRadioTile extends StatelessWidget {
  const _PrivacyRadioTile({
    super.key,
    required this.label,
    this.subtitle,
    this.selectedDetail,
    required this.selected,
    required this.enabled,
    this.onTap,
  });

  final String label;
  final String? subtitle;
  final String? selectedDetail;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: enabled
                  ? (selected ? const Color(0xFF0F766E) : const Color(0xFF9AA8A4))
                  : const Color(0xFFB8C4C0),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: enabled
                          ? const Color(0xFF101617)
                          : const Color(0xFF9AA8A4),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF6A7774),
                        height: 1.3,
                      ),
                    ),
                  ],
                  if (selected && selectedDetail != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      selectedDetail!,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF6A7774),
                        height: 1.4,
                      ),
                    ),
                  ],
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
